#!/usr/bin/env python3
"""Rights-first, fixed-category Wikimedia Commons intake for Camera Coach.

Only metadata and receipts belong in the repository.  Raw thumbnails are
written below the caller-selected external data root and remain
``research_only``; this tool does not create Camera Coach human gold or grant
release clearance.
"""

from __future__ import annotations

import argparse
from email.utils import parsedate_to_datetime
import hashlib
from html.parser import HTMLParser
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import ssl
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any, Callable, Iterable, Mapping, Sequence
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit, urlunsplit
from urllib.request import HTTPSHandler, HTTPRedirectHandler, Request, build_opener


ROOT = Path(__file__).resolve().parents[2]
INTAKE_SCRIPT = ROOT / "tools" / "dataset" / "camera_source_intake.py"
SOURCE_ID = "wikimedia_commons_api"
API_HOST = "commons.wikimedia.org"
MEDIA_HOST = "upload.wikimedia.org"
DEFAULT_CONTACT = "https://github.com/rustemd02/shafinMultitool"
CHUNK_SIZE = 1024 * 1024
MAX_ATTEMPTS = 5
MAX_CONTINUATIONS = 1000
SHA1_RE = re.compile(r"^[0-9a-fA-F]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ALLOWED_MIME = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
RETRYABLE_HTTP = {429, 500, 502, 503, 504}
STALE_PART_SECONDS = 24 * 60 * 60

CANONICAL_CC0_URL = "https://creativecommons.org/publicdomain/zero/1.0"
CANONICAL_CC_BY_URL = "https://creativecommons.org/licenses/by/4.0"
CANONICAL_ACCEPTED_TUPLES = (
    (
        ("license", "cc0"),
        ("license_short_name", "CC0 1.0"),
        ("license_url", CANONICAL_CC0_URL),
        ("attribution_required", False),
        ("clearance_candidate", False),
    ),
    (
        ("license", "cc-by-4.0"),
        ("license_short_name", "CC BY 4.0"),
        ("license_url", CANONICAL_CC_BY_URL),
        ("attribution_required", True),
        ("artist_required", True),
        ("clearance_candidate", False),
    ),
    (
        ("license", "pd"),
        ("license_short_name", "Public domain"),
        ("copyrighted", False),
        ("attribution_required", False),
        ("restrictions", ""),
        ("clearance_candidate", True),
    ),
)
FIXED_CATEGORIES = (
    ("people", "Category:Portraits", 0.25),
    ("landscape", "Category:Landscape photography", 0.20),
    ("architecture_streets", "Category:Architecture", 0.20),
    ("interiors", "Category:Interiors", 0.15),
    ("objects_details", "Category:Quality images of objects", 0.15),
    ("historical_cinematic", "Category:Black and white photographs", 0.05),
)


def _canonical_rights_tuples() -> list[dict[str, Any]]:
    return [dict(fields) for fields in CANONICAL_ACCEPTED_TUPLES]


class CommonsError(ValueError):
    """Fail-closed, user-facing adapter error."""


class DownloadError(CommonsError):
    """An individual media object could not be safely admitted."""


def _json_line(value: Any) -> str:
    return json.dumps(value, allow_nan=False, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _canonical_bytes(value: Any) -> bytes:
    return (_json_line(value) + "\n").encode("utf-8")


def _canonical_hash(value: Any) -> str:
    return hashlib.sha256(_canonical_bytes(value)).hexdigest()


def _sha256_file(path: Path) -> str:
    try:
        info = path.lstat()
    except OSError as exc:
        raise CommonsError(f"cannot inspect file: {path.name}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise CommonsError(f"file is not a regular file: {path.name}")
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            while chunk := stream.read(CHUNK_SIZE):
                digest.update(chunk)
    except OSError as exc:
        raise CommonsError(f"cannot read file: {path.name}") from exc
    return digest.hexdigest()


def _safe_unlink(path: Path) -> None:
    if path.is_symlink():
        raise CommonsError(f"refusing to remove symlink: {path.name}")
    if path.exists():
        if not path.is_file():
            raise CommonsError(f"refusing to remove non-file: {path.name}")
        path.unlink()


def _ensure_directory(path: Path) -> Path:
    missing: list[Path] = []
    current = path
    while True:
        try:
            info = current.lstat()
        except FileNotFoundError:
            missing.append(current)
            parent = current.parent
            if parent == current:
                raise CommonsError(f"cannot find directory parent: {path}")
            current = parent
            continue
        except OSError as exc:
            raise CommonsError(f"cannot inspect directory: {current}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise CommonsError(f"directory path uses a symlink: {current}")
        if not stat.S_ISDIR(info.st_mode):
            raise CommonsError(f"directory path is not a directory: {current}")
        break
    for directory in reversed(missing):
        try:
            directory.mkdir()
            info = directory.lstat()
        except OSError as exc:
            raise CommonsError(f"cannot create directory: {directory}") from exc
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise CommonsError(f"created path is not a safe directory: {directory}")
    return path


def _external_root(value: Path, *, create: bool = True) -> Path:
    candidate = Path(value).expanduser()
    if candidate.exists() and candidate.is_symlink():
        raise CommonsError("data root must not be a symlink")
    root = candidate.resolve()
    repository = ROOT.resolve()
    if root == repository or repository in root.parents or root in repository.parents:
        raise CommonsError("data root must be outside the repository and its ancestors")
    if create:
        _ensure_directory(root)
    if root.is_symlink() or not root.is_dir():
        raise CommonsError("data root must be a regular directory")
    return root


def _safe_relative(root: Path, value: str) -> Path:
    if not isinstance(value, str) or not value or "\x00" in value:
        raise CommonsError("path must be a non-empty string")
    normalized = value.replace("\\", "/")
    path = PurePosixPath(normalized)
    parts = path.parts
    if path.is_absolute() or not parts or any(part in ("", ".", "..") for part in parts):
        raise CommonsError("path is not safely relative")
    if ":" in parts[0]:
        raise CommonsError("path has a drive prefix")
    current = root
    for part in parts[:-1]:
        current /= part
        if current.is_symlink():
            raise CommonsError("path uses a symlink parent")
    return root.joinpath(*parts)


def _fixed_directory(root: Path, relative: str, *, create: bool = False, allow_missing: bool = False) -> Path:
    path = _safe_relative(root, relative)
    if path.is_symlink():
        raise CommonsError(f"fixed directory is a symlink: {relative}")
    if not path.exists():
        if create:
            _ensure_directory(path)
        elif not allow_missing:
            raise CommonsError(f"fixed directory is missing: {relative}")
        return path
    try:
        info = path.lstat()
    except OSError as exc:
        raise CommonsError(f"cannot inspect fixed directory: {relative}") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise CommonsError(f"fixed path is not a regular directory: {relative}")
    return path


def _fixed_file(root: Path, relative: str, *, create_parent: bool = False) -> Path:
    path = _safe_relative(root, relative)
    parent = PurePosixPath(relative.replace("\\", "/")).parent
    if str(parent) not in ("", "."):
        _fixed_directory(root, parent.as_posix(), create=create_parent)
    if path.is_symlink():
        raise CommonsError(f"fixed file is a symlink: {relative}")
    if path.exists() and not path.is_file():
        raise CommonsError(f"fixed path is not a regular file: {relative}")
    return path


def _atomic_write(path: Path, text: str) -> str:
    _ensure_directory(path.parent)
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise CommonsError(f"output is not a regular file: {path.name}")
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".part", dir=path.parent)
        temporary = Path(name)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except (OSError, UnicodeError) as exc:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
        raise CommonsError(f"cannot atomically write {path.name}") from exc
    return _sha256_file(path)


def _atomic_jsonl(path: Path, rows: Iterable[Mapping[str, Any]]) -> tuple[str, int]:
    materialized = [dict(row) for row in rows]
    text = "".join(_json_line(row) + "\n" for row in materialized)
    return _atomic_write(path, text), len(materialized)


def _atomic_json(path: Path, value: Mapping[str, Any]) -> str:
    return _atomic_write(path, _json_line(dict(value)) + "\n")


def _reject_nonfinite(constant: str) -> Any:
    raise CommonsError(f"non-finite JSON number: {constant}")


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), parse_constant=_reject_nonfinite)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise CommonsError(f"cannot read JSON: {path.name}") from exc


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    try:
        with path.open("r", encoding="utf-8", newline="") as stream:
            lines = stream.read().split("\n")
    except (OSError, UnicodeError) as exc:
        raise CommonsError(f"cannot read JSONL: {path.name}") from exc
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(lines, 1):
        if line.endswith("\r"):
            line = line[:-1]
        if "\r" in line:
            raise CommonsError(f"JSONL line {line_number} contains unexpected CR")
        if not line.strip():
            continue
        try:
            value = json.loads(line, parse_constant=_reject_nonfinite)
        except (json.JSONDecodeError, CommonsError) as exc:
            raise CommonsError(f"JSONL line {line_number} is malformed") from exc
        if not isinstance(value, dict):
            raise CommonsError(f"JSONL line {line_number} is not an object")
        rows.append(value)
    return rows


def _load_spec(path: Path) -> tuple[dict[str, Any], str]:
    value = _read_json(path)
    if not isinstance(value, dict) or value.get("schema_id") != "camera-commons-source-spec-v1":
        raise CommonsError("spec schema_id is not camera-commons-source-spec-v1")
    if value.get("source_id") != SOURCE_ID:
        raise CommonsError("spec source_id is not Wikimedia Commons")
    contact = value.get("contact_default", DEFAULT_CONTACT)
    if not isinstance(contact, str) or not contact.strip() or any(ord(ch) < 32 for ch in contact):
        raise CommonsError("spec contact_default is invalid")
    api = value.get("api")
    if not isinstance(api, dict):
        raise CommonsError("spec api block is missing")
    if api.get("endpoint") != f"https://{API_HOST}/w/api.php" or api.get("host") != API_HOST:
        raise CommonsError("spec API endpoint is not the fixed Commons API")
    if api.get("media_hosts") != [MEDIA_HOST] or api.get("namespace") != 6 or api.get("maxlag") != 5:
        raise CommonsError("spec API host, namespace, or maxlag is invalid")
    batch_size = api.get("batch_size")
    interval = api.get("request_interval_seconds")
    if not isinstance(batch_size, int) or isinstance(batch_size, bool) or not 1 <= batch_size <= 50:
        raise CommonsError("spec batch_size must be between 1 and 50")
    if not isinstance(interval, (int, float)) or isinstance(interval, bool) or interval < 0:
        raise CommonsError("spec request_interval_seconds is invalid")
    categories = value.get("categories")
    if not isinstance(categories, list) or not categories:
        raise CommonsError("spec categories are missing")
    total = 0.0
    ids: set[str] = set()
    titles: set[str] = set()
    category_shape: list[tuple[str, str, float]] = []
    for category in categories:
        if not isinstance(category, dict):
            raise CommonsError("spec category entry is invalid")
        identifier, title, fraction = category.get("id"), category.get("title"), category.get("quota_fraction")
        if (
            not isinstance(identifier, str)
            or not re.fullmatch(r"[a-z][a-z0-9_]*", identifier)
            or identifier in ids
            or not isinstance(title, str)
            or not title.startswith("Category:")
            or title in titles
            or not isinstance(fraction, (int, float))
            or isinstance(fraction, bool)
            or fraction <= 0
        ):
            raise CommonsError("spec category entry is invalid")
        multiplier = category.get("candidate_multiplier", 1)
        if not isinstance(multiplier, int) or isinstance(multiplier, bool) or multiplier < 1 or multiplier > 20:
            raise CommonsError("spec candidate_multiplier is invalid")
        ids.add(identifier)
        titles.add(title)
        total += float(fraction)
        category_shape.append((identifier, title, float(fraction)))
    if abs(total - 1.0) > 1e-9:
        raise CommonsError("spec category quotas must sum to 1")
    if category_shape != list(FIXED_CATEGORIES):
        raise CommonsError("spec categories or quotas are not the fixed allowlist")
    download = value.get("download")
    if not isinstance(download, dict) or download.get("thumbnail_width") != 1600:
        raise CommonsError("spec thumbnail width must be 1600")
    max_bytes = download.get("max_bytes")
    max_pixels = download.get("max_pixels")
    mime = download.get("allowed_mime")
    if (
        not isinstance(max_bytes, int)
        or isinstance(max_bytes, bool)
        or max_bytes <= 0
        or not isinstance(max_pixels, int)
        or isinstance(max_pixels, bool)
        or max_pixels <= 0
        or mime != sorted(ALLOWED_MIME)
    ):
        raise CommonsError("spec download policy is invalid")
    rights = value.get("rights_policy")
    if not isinstance(rights, dict) or rights.get("accepted_tuples") != _canonical_rights_tuples():
        raise CommonsError("spec rights policy is missing")
    output = value.get("output")
    if not isinstance(output, dict):
        raise CommonsError("spec output policy is missing")
    output_keys = ("raw_manifest", "candidates", "accepted_rights_receipt", "quarantined", "inventory", "receipt", "image_directory")
    if any(key not in output or not isinstance(output[key], str) for key in output_keys):
        raise CommonsError("spec output policy is incomplete")
    def safe_config_path(raw: str) -> str:
        normalized = raw.replace("\\", "/")
        parts = PurePosixPath(normalized).parts
        if not parts or PurePosixPath(normalized).is_absolute() or any(part in ("", ".", "..") for part in parts) or ":" in parts[0]:
            raise CommonsError("spec output path is not safely relative")
        return PurePosixPath(normalized).as_posix()
    fixed_paths = [safe_config_path(str(output[key])) for key in output_keys[:-1]]
    image_directory = safe_config_path(str(output["image_directory"]))
    if len(set(fixed_paths)) != len(fixed_paths) or any(path == image_directory or path.startswith(image_directory + "/") for path in fixed_paths):
        raise CommonsError("spec output paths are not unique")
    digest = _canonical_hash(value)
    return value, digest


def _validate_contact(contact: str) -> str:
    if not isinstance(contact, str) or not contact.strip() or any(ord(ch) < 32 for ch in contact):
        raise CommonsError("contact must be a non-empty URL without control characters")
    parts = urlsplit(contact.strip())
    if parts.scheme not in {"http", "https"} or not parts.hostname or parts.username or parts.password:
        raise CommonsError("contact must be an HTTP(S) URL")
    return contact.strip()


def _validate_url(url: Any, allowed_hosts: set[str], *, label: str) -> str:
    if not isinstance(url, str) or not url.strip() or any(ord(ch) < 32 for ch in url):
        raise CommonsError(f"{label} is not a valid URL")
    value = url.strip()
    parts = urlsplit(value)
    try:
        port = parts.port
    except ValueError as exc:
        raise CommonsError(f"{label} has an invalid port") from exc
    if (
        parts.scheme != "https"
        or parts.hostname is None
        or parts.hostname.casefold() not in allowed_hosts
        or parts.username
        or parts.password
        or port not in (None, 443)
        or parts.fragment
    ):
        raise CommonsError(f"{label} host or scheme is not allowlisted")
    return value


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req: Request, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> None:
        raise CommonsError(f"redirect rejected: {newurl}")


def _ssl_context() -> ssl.SSLContext:
    system_ca = Path("/etc/ssl/cert.pem")
    if system_ca.is_file():
        return ssl.create_default_context(cafile=str(system_ca))
    return ssl.create_default_context()


def _default_opener() -> Any:
    return build_opener(_NoRedirect(), HTTPSHandler(context=_ssl_context()))


def _response_url(response: Any, requested: str) -> str:
    try:
        value = response.geturl()
    except AttributeError:
        value = requested
    return value if isinstance(value, str) else requested


def _retry_after(headers: Any, *, now: Callable[[], float] = time.time) -> float | None:
    try:
        value = headers.get("Retry-After")
    except AttributeError:
        value = None
    if value is None:
        return None
    try:
        seconds = float(str(value).strip())
        if seconds >= 0:
            return min(seconds, 30.0)
    except ValueError:
        pass
    try:
        seconds = (parsedate_to_datetime(str(value)).timestamp() - now())
    except (TypeError, ValueError, OverflowError):
        return None
    return min(max(0.0, seconds), 30.0)


class _RateLimiter:
    def __init__(self, interval: float, *, clock: Callable[[], float] = time.monotonic, sleeper: Callable[[float], None] = time.sleep) -> None:
        self.interval = max(0.0, float(interval))
        self.clock = clock
        self.sleeper = sleeper
        self.next_allowed = 0.0

    def wait(self) -> None:
        delay = self.next_allowed - self.clock()
        if delay > 0:
            self.sleeper(delay)
        self.next_allowed = self.clock() + self.interval


def _open_request(opener: Any, request: Request, timeout: float) -> Any:
    if opener is None:
        opener = _default_opener()
    if hasattr(opener, "open"):
        return opener.open(request, timeout=timeout)
    return opener(request, timeout=timeout)


def _request_json(
    url: str,
    params: Mapping[str, Any],
    *,
    headers: Mapping[str, str],
    allowed_host: str,
    opener: Any = None,
    limiter: _RateLimiter | None = None,
    sleeper: Callable[[float], None] = time.sleep,
    timeout: float = 30.0,
) -> tuple[dict[str, Any], str]:
    _validate_url(url, {allowed_host}, label="request URL")
    query = urlencode([(key, str(value)) for key, value in params.items()])
    request_url = f"{url}?{query}"
    _validate_url(request_url, {allowed_host}, label="request URL")
    limiter = limiter or _RateLimiter(0.0)
    for attempt in range(MAX_ATTEMPTS):
        limiter.wait()
        request = Request(request_url, headers=dict(headers), method="GET")
        try:
            response = _open_request(opener, request, timeout)
            final_url = _response_url(response, request_url)
            _validate_url(final_url, {allowed_host}, label="response URL")
            status = int(getattr(response, "status", getattr(response, "code", 200)))
            if 300 <= status < 400:
                raise CommonsError("redirect rejected")
            if status >= 400:
                raise HTTPError(request_url, status, f"HTTP {status}", getattr(response, "headers", {}), None)
            response_headers = getattr(response, "headers", {})
            with response:
                body = response.read(20 * 1024 * 1024 + 1)
            if len(body) > 20 * 1024 * 1024:
                raise CommonsError("API response exceeds byte ceiling")
            try:
                value = json.loads(body.decode("utf-8"), parse_constant=_reject_nonfinite)
            except (UnicodeError, json.JSONDecodeError, CommonsError) as exc:
                raise CommonsError("API response is not valid JSON") from exc
            if not isinstance(value, dict):
                raise CommonsError("API response is not a JSON object")
            api_error = value.get("error")
            if api_error is not None:
                if not isinstance(api_error, dict):
                    raise CommonsError("API response error is malformed")
                code = api_error.get("code")
                if code == "maxlag" and attempt + 1 < MAX_ATTEMPTS:
                    delay = _retry_after(response_headers)
                    sleeper(delay if delay is not None else min(30.0, float(2**attempt)))
                    continue
                raise CommonsError(f"API response error: {code if isinstance(code, str) else 'unknown'}")
            return value, _canonical_hash(value)
        except HTTPError as exc:
            if exc.code not in RETRYABLE_HTTP or attempt + 1 >= MAX_ATTEMPTS:
                raise CommonsError(f"API request failed with HTTP {exc.code}") from exc
            delay = _retry_after(exc.headers)
            sleeper(delay if delay is not None else min(30.0, float(2**attempt)))
        except (URLError, TimeoutError, OSError) as exc:
            if attempt + 1 >= MAX_ATTEMPTS:
                raise CommonsError("API request failed after bounded retries") from exc
            sleeper(min(30.0, float(2**attempt)))
    raise CommonsError("API request failed")


def _api_request(
    spec: Mapping[str, Any],
    params: Mapping[str, Any],
    *,
    contact: str,
    limiter: _RateLimiter,
    opener: Any = None,
    sleeper: Callable[[float], None] = time.sleep,
) -> tuple[dict[str, Any], str]:
    api = spec["api"]
    full = dict(params)
    full.update({"format": "json", "formatversion": 2, "maxlag": api["maxlag"]})
    user_agent = f"{api['user_agent']} (+{contact})"
    return _request_json(
        str(api["endpoint"]),
        full,
        headers={"User-Agent": user_agent, "Accept": "application/json"},
        allowed_host=API_HOST,
        opener=opener,
        limiter=limiter,
        sleeper=sleeper,
    )


def _quota_counts(categories: Sequence[Mapping[str, Any]], limit: int) -> list[int]:
    floors = [int(limit * float(category["quota_fraction"])) for category in categories]
    remaining = limit - sum(floors)
    ranked = sorted(
        range(len(categories)),
        key=lambda index: (
            -(limit * float(categories[index]["quota_fraction"]) - floors[index]),
            index,
        ),
    )
    for index in ranked[:remaining]:
        floors[index] += 1
    return floors


def _html_text(value: Any) -> str:
    if not isinstance(value, str):
        return ""

    class TextParser(HTMLParser):
        def __init__(self) -> None:
            super().__init__(convert_charrefs=True)
            self.parts: list[str] = []

        def handle_data(self, data: str) -> None:
            self.parts.append(data)

        def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
            if tag.lower() in {"br", "p", "div", "li"}:
                self.parts.append("\n")

        def handle_endtag(self, tag: str) -> None:
            if tag.lower() in {"p", "div", "li"}:
                self.parts.append("\n")

    parser = TextParser()
    try:
        parser.feed(value)
        parser.close()
    except Exception:
        return ""
    return re.sub(r"\s+", " ", "".join(parser.parts).replace("\n", " ")).strip()


def _ext_value(extmetadata: Mapping[str, Any], key: str, *, required: bool = False) -> Any:
    if key not in extmetadata:
        if required:
            raise CommonsError(f"missing extmetadata field: {key}")
        return None
    entry = extmetadata[key]
    if not isinstance(entry, dict) or "value" not in entry:
        raise CommonsError(f"malformed extmetadata field: {key}")
    return entry["value"]


def _boolean(value: Any, *, key: str, required: bool = True, default: bool = False) -> bool:
    if value is None and not required:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().casefold()
        if normalized == "true":
            return True
        if normalized == "false":
            return False
    raise CommonsError(f"{key} must be a boolean")


def _normalize_license_url(value: Any) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or any(ord(ch) < 32 for ch in value):
        raise CommonsError("LicenseUrl is malformed")
    value = value.strip()
    if not value:
        return None
    parts = urlsplit(value)
    if parts.scheme not in {"http", "https"} or not parts.hostname or parts.fragment:
        raise CommonsError("LicenseUrl is malformed")
    # Only normalize the documented presentation difference; preserve all other raw fields.
    return value[:-1] if value.endswith("/") and len(value) > len(f"{parts.scheme}://{parts.hostname}/") else value


def _classify_rights(extmetadata: Mapping[str, Any]) -> dict[str, Any]:
    if not isinstance(extmetadata, dict) or not extmetadata:
        raise CommonsError("extmetadata is missing")
    for key, value in extmetadata.items():
        if not isinstance(key, str) or not isinstance(value, dict) or "value" not in value:
            raise CommonsError(f"malformed extmetadata field: {key}")
    license_value = _ext_value(extmetadata, "License", required=True)
    short_value = _ext_value(extmetadata, "LicenseShortName", required=True)
    if not isinstance(license_value, str) or not isinstance(short_value, str):
        raise CommonsError("license metadata values must be strings")
    license_value = license_value.strip()
    short_value = short_value.strip()
    artist_raw = _ext_value(extmetadata, "Artist", required=False)
    credit_raw = _ext_value(extmetadata, "Credit", required=False)
    if artist_raw is not None and not isinstance(artist_raw, str):
        raise CommonsError("Artist metadata value must be a string")
    if credit_raw is not None and not isinstance(credit_raw, str):
        raise CommonsError("Credit metadata value must be a string")
    artist_text = _html_text(artist_raw)
    restrictions_value = _ext_value(extmetadata, "Restrictions", required=True)
    if isinstance(restrictions_value, str):
        restrictions = restrictions_value.strip()
    else:
        raise CommonsError("Restrictions metadata value must be a string")
    attribution_raw = _ext_value(extmetadata, "AttributionRequired", required=True)
    copyrighted_raw = _ext_value(extmetadata, "Copyrighted", required=False)
    attribution = _boolean(attribution_raw, key="AttributionRequired", required=False, default=False)
    copyrighted = None if copyrighted_raw is None else _boolean(copyrighted_raw, key="Copyrighted")
    multiple = _ext_value(extmetadata, "MultipleLicenses", required=False)
    if isinstance(multiple, str) and multiple.strip() == "false":
        multiple = False
    if multiple not in (None, "", False):
        raise CommonsError("multiple licenses are not accepted")

    license_url = _normalize_license_url(_ext_value(extmetadata, "LicenseUrl", required=False))
    clearance_candidate = False
    if license_value == "cc0" and short_value == "CC0 1.0" and license_url == CANONICAL_CC0_URL:
        if attribution or restrictions or copyrighted is True:
            raise CommonsError("CC0 tuple has attribution or restrictions")
        license_kind = "cc0-1.0"
    elif license_value == "cc-by-4.0" and short_value == "CC BY 4.0" and license_url == CANONICAL_CC_BY_URL:
        if not attribution or not artist_text:
            raise CommonsError("CC BY 4.0 requires AttributionRequired=true and Artist")
        if restrictions:
            raise CommonsError("CC BY 4.0 has non-empty Restrictions")
        license_kind = "cc-by-4.0"
    elif license_value == "pd" and short_value == "Public domain":
        if copyrighted is not False or attribution or restrictions:
            raise CommonsError("Public domain tuple is not exact")
        license_kind = "public-domain"
        clearance_candidate = True
    else:
        raise CommonsError("license tuple is not allowlisted")
    return {
        "license": license_value,
        "license_short_name": short_value,
        "license_kind": license_kind,
        "license_url": license_url,
        "attribution_required": attribution,
        "copyrighted": copyrighted,
        "restrictions": restrictions,
        "artist_raw_html": artist_raw,
        "artist_text": artist_text,
        "credit_raw_html": credit_raw,
        "credit_text": _html_text(credit_raw),
        "clearance_candidate": clearance_candidate,
    }


def _positive_int(value: Any, *, key: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise CommonsError(f"{key} must be a positive integer")
    return value


def _expected_download_dimensions(
    thumburl: str,
    original_url: str,
    width: int,
    height: int,
    thumb_width: int,
    thumb_height: int,
) -> dict[str, Any]:
    thumb_parts = urlsplit(thumburl)
    original_parts = urlsplit(original_url)
    thumb_query = parse_qs(thumb_parts.query, keep_blank_values=True)
    if thumb_parts.path == original_parts.path and thumb_query.get("utm_content") == ["thumbnail_unscaled"]:
        return {
            "width": width,
            "height": height,
            "source": "original_unscaled",
            "bucket_width": None,
            "bucket_height": None,
            "display_width": thumb_width,
            "display_height": thumb_height,
            "height_tolerance": 0,
        }
    bucket_match = re.search(r"/([1-9]\d*)px-[^/]+$", thumb_parts.path)
    if bucket_match is not None:
        bucket_width = _positive_int(int(bucket_match.group(1)), key="thumbnail bucket width")
        bucket_height = max(1, (bucket_width * height * 2 + width) // (2 * width))
        return {
            "width": bucket_width,
            "height": bucket_height,
            "source": "thumbnail_bucket",
            "bucket_width": bucket_width,
            "bucket_height": bucket_height,
            "display_width": thumb_width,
            "display_height": thumb_height,
            "height_tolerance": 1,
        }
    return {
        "width": thumb_width,
        "height": thumb_height,
        "source": "thumbnail",
        "bucket_width": None,
        "bucket_height": None,
        "display_width": thumb_width,
        "display_height": thumb_height,
        "height_tolerance": 0,
    }


def _normalize_candidate(
    page: Mapping[str, Any],
    category: Mapping[str, Any],
    response_hash: str,
    spec: Mapping[str, Any],
) -> dict[str, Any]:
    if not isinstance(page, dict):
        raise CommonsError("imageinfo page is not an object")
    pageid = _positive_int(page.get("pageid"), key="pageid")
    if page.get("ns") != 6:
        raise CommonsError("imageinfo namespace is not 6")
    title = page.get("title")
    if not isinstance(title, str) or not title.strip() or not title.startswith("File:"):
        raise CommonsError("imageinfo title is malformed")
    imageinfo = page.get("imageinfo")
    if not isinstance(imageinfo, list) or not imageinfo or not isinstance(imageinfo[0], dict):
        raise CommonsError("imageinfo record is missing")
    info = imageinfo[0]
    timestamp = info.get("timestamp")
    if not isinstance(timestamp, str) or not timestamp.strip():
        raise CommonsError("imageinfo timestamp is missing")
    descriptionurl = _validate_url(info.get("descriptionurl"), {API_HOST}, label="descriptionurl")
    raw_thumburl = info.get("thumburl")
    if isinstance(raw_thumburl, str) and urlsplit(raw_thumburl).hostname == "thumb.wikimedia.org":
        thumb_parts = urlsplit(raw_thumburl)
        if not thumb_parts.path.startswith("/wikipedia/commons/thumb/"):
            raise CommonsError("thumbnail CDN path is not allowlisted")
        raw_thumburl = urlunsplit(("https", MEDIA_HOST, thumb_parts.path, thumb_parts.query, ""))
    thumburl = _validate_url(raw_thumburl, {MEDIA_HOST}, label="thumburl")
    original_url = _validate_url(info.get("url"), {MEDIA_HOST}, label="original URL")
    sha1 = info.get("sha1")
    if not isinstance(sha1, str) or not SHA1_RE.fullmatch(sha1):
        raise CommonsError("original SHA-1 is missing or malformed")
    width = _positive_int(info.get("width"), key="width")
    height = _positive_int(info.get("height"), key="height")
    thumb_width = _positive_int(info.get("thumbwidth"), key="thumbwidth")
    thumb_height = _positive_int(info.get("thumbheight"), key="thumbheight")
    expected_dimensions = _expected_download_dimensions(
        thumburl, original_url, width, height, thumb_width, thumb_height
    )
    expected_download_width = int(expected_dimensions["width"])
    expected_download_height = int(expected_dimensions["height"])
    expected_download_dimensions_source = str(expected_dimensions["source"])
    if thumb_width > int(spec["download"]["thumbnail_width"]):
        raise CommonsError("thumbnail width exceeds requested width")
    if thumb_width * thumb_height > int(spec["download"]["max_pixels"]):
        raise CommonsError("thumbnail exceeds pixel ceiling")
    if expected_download_width * expected_download_height > int(spec["download"]["max_pixels"]):
        raise CommonsError("expected download exceeds pixel ceiling")
    mime = info.get("mime")
    if not isinstance(mime, str) or mime.strip().casefold() not in ALLOWED_MIME:
        raise CommonsError("MIME type is not an allowlisted bitmap")
    mime = mime.strip().casefold()
    # Commons omits thumbmime on some Imageinfo responses; for those responses
    # the API's bitmap MIME is the only permitted thumbnail MIME value.
    thumb_mime = info.get("thumbmime", mime)
    if not isinstance(thumb_mime, str) or thumb_mime.strip().casefold() not in ALLOWED_MIME:
        raise CommonsError("thumbnail MIME type is not an allowlisted bitmap")
    mediatype = info.get("mediatype")
    if not isinstance(mediatype, str) or mediatype.strip().casefold() != "bitmap":
        raise CommonsError("media type is not BITMAP")
    extmetadata = info.get("extmetadata")
    if not isinstance(extmetadata, dict) or not extmetadata:
        raise CommonsError("full extmetadata is missing")
    candidate = {
        "source_id": SOURCE_ID,
        "source_record_id": f"commons-{pageid}",
        "category_id": str(category["id"]),
        "category_title": str(category["title"]),
        "pageid": pageid,
        "title": title,
        "timestamp": timestamp,
        "descriptionurl": descriptionurl.rstrip("/"),
        "thumburl": thumburl,
        "original_url": original_url,
        "original_sha1": sha1.lower(),
        "width": width,
        "height": height,
        "thumbwidth": thumb_width,
        "thumbheight": thumb_height,
        "expected_download_width": expected_download_width,
        "expected_download_height": expected_download_height,
        "expected_download_dimensions_source": expected_download_dimensions_source,
        "expected_download_bucket_width": expected_dimensions["bucket_width"],
        "expected_download_bucket_height": expected_dimensions["bucket_height"],
        "expected_download_display_width": expected_dimensions["display_width"],
        "expected_download_display_height": expected_dimensions["display_height"],
        "expected_download_height_tolerance": expected_dimensions["height_tolerance"],
        "mime": mime,
        "thumbmime": thumb_mime.strip().casefold(),
        "mediatype": "BITMAP",
        "imageinfo_raw": dict(info),
        "extmetadata": extmetadata,
        "api_response_sha256": response_hash,
    }
    candidate["rights"] = _classify_rights(extmetadata)
    candidate["file_extension"] = ALLOWED_MIME[mime]
    return candidate


def _quarantine(
    reason: str,
    *,
    category: Mapping[str, Any] | None = None,
    raw: Any = None,
    response_hash: str | None = None,
    pageid: Any = None,
    title: Any = None,
) -> dict[str, Any]:
    value: dict[str, Any] = {"source_id": SOURCE_ID, "reason": reason}
    if category is not None:
        value["category_id"] = category.get("id")
        value["category_title"] = category.get("title")
    if pageid is not None:
        value["pageid"] = pageid
    if title is not None:
        value["title"] = title
    if response_hash:
        value["api_response_sha256"] = response_hash
    if raw is not None:
        value["raw"] = raw
    return value


def _category_capacity(
    spec: Mapping[str, Any],
    category: Mapping[str, Any],
    *,
    contact: str,
    limiter: _RateLimiter,
    opener: Any = None,
    sleeper: Callable[[float], None] = time.sleep,
) -> tuple[int, str]:
    payload, response_hash = _api_request(
        spec,
        {
            "action": "query",
            "prop": "categoryinfo",
            "titles": category["title"],
        },
        contact=contact,
        limiter=limiter,
        opener=opener,
        sleeper=sleeper,
    )
    query = payload.get("query")
    pages = query.get("pages") if isinstance(query, dict) else None
    if not isinstance(pages, list) or len(pages) != 1 or not isinstance(pages[0], dict):
        raise CommonsError("categoryinfo response is malformed")
    page = pages[0]
    if page.get("missing") is not None:
        return 0, response_hash
    info = page.get("categoryinfo")
    if not isinstance(info, dict):
        raise CommonsError("categoryinfo record is missing")
    files = info.get("files")
    if not isinstance(files, int) or isinstance(files, bool) or files < 0:
        raise CommonsError("categoryinfo direct-file capacity is malformed")
    return files, response_hash


def _discover_members(
    spec: Mapping[str, Any],
    category: Mapping[str, Any],
    target: int,
    capacity: int,
    *,
    contact: str,
    limiter: _RateLimiter,
    opener: Any = None,
    sleeper: Callable[[float], None] = time.sleep,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str], bool]:
    if target <= 0 or capacity <= 0:
        return [], [], [], True
    desired = min(capacity, min(5000, max(target, target * int(category.get("candidate_multiplier", 1)))))
    api = spec["api"]
    members: list[dict[str, Any]] = []
    quarantined: list[dict[str, Any]] = []
    response_hashes: list[str] = []
    continuation: dict[str, Any] = {}
    seen_pageids: set[int] = set()
    exhausted = False
    for _ in range(MAX_CONTINUATIONS):
        params: dict[str, Any] = {
            "action": "query",
            "list": "categorymembers",
            "cmtitle": category["title"],
            "cmnamespace": api["namespace"],
            "cmtype": "file",
            "cmprop": "ids|title",
            "cmsort": "sortkey",
            "cmdir": "ascending",
            "cmlimit": min(500, max(1, desired - len(members))),
        }
        params.update(continuation)
        payload, response_hash = _api_request(
            spec,
            params,
            contact=contact,
            limiter=limiter,
            opener=opener,
            sleeper=sleeper,
        )
        response_hashes.append(response_hash)
        query = payload.get("query")
        raw_members = query.get("categorymembers") if isinstance(query, dict) else None
        if not isinstance(raw_members, list):
            raise CommonsError("categorymembers response is malformed")
        for raw in raw_members:
            if not isinstance(raw, dict):
                quarantined.append(_quarantine("malformed_category_member", category=category, raw=raw, response_hash=response_hash))
                continue
            pageid = raw.get("pageid")
            title = raw.get("title")
            if not isinstance(pageid, int) or isinstance(pageid, bool) or pageid < 1 or raw.get("ns") != api["namespace"] or not isinstance(title, str) or not title.startswith("File:"):
                quarantined.append(_quarantine("malformed_category_member", category=category, raw=raw, response_hash=response_hash, pageid=pageid, title=title))
                continue
            if pageid in seen_pageids:
                quarantined.append(_quarantine("duplicate_pageid", category=category, raw=raw, response_hash=response_hash, pageid=pageid, title=title))
                continue
            seen_pageids.add(pageid)
            members.append({"pageid": pageid, "title": title, "category": dict(category), "response_hash": response_hash})
            if len(members) >= desired:
                exhausted = False
                break
        if len(members) >= desired:
            break
        continuation_value = payload.get("continue")
        if not isinstance(continuation_value, dict):
            exhausted = True
            break
        token = continuation_value.get("cmcontinue")
        if not isinstance(token, str) or not token:
            raise CommonsError("categorymembers continuation is malformed")
        continuation = {"cmcontinue": token}
    else:
        raise CommonsError("categorymembers continuation bound exceeded")
    members.sort(key=lambda row: (int(row["pageid"]), str(row["title"])))
    return members, quarantined, response_hashes, exhausted


def _imageinfo_candidates(
    spec: Mapping[str, Any],
    members: Sequence[Mapping[str, Any]],
    *,
    contact: str,
    limiter: _RateLimiter,
    opener: Any = None,
    sleeper: Callable[[float], None] = time.sleep,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str]]:
    candidates: list[dict[str, Any]] = []
    quarantined: list[dict[str, Any]] = []
    response_hashes: list[str] = []
    by_pageid = {int(member["pageid"]): member for member in members}
    pageids = sorted(by_pageid)
    batch_size = int(spec["api"]["batch_size"])
    for start in range(0, len(pageids), batch_size):
        batch = pageids[start : start + batch_size]
        payload, response_hash = _api_request(
            spec,
            {
                "action": "query",
                "prop": "imageinfo",
                "pageids": "|".join(str(pageid) for pageid in batch),
                "iiprop": "url|size|mime|sha1|timestamp|mediatype|extmetadata",
                "iiurlwidth": spec["download"]["thumbnail_width"],
            },
            contact=contact,
            limiter=limiter,
            opener=opener,
            sleeper=sleeper,
        )
        response_hashes.append(response_hash)
        query = payload.get("query")
        pages = query.get("pages") if isinstance(query, dict) else None
        if not isinstance(pages, list):
            raise CommonsError("imageinfo response is malformed")
        page_map: dict[int, Any] = {}
        for page in pages:
            if isinstance(page, dict) and isinstance(page.get("pageid"), int) and not isinstance(page.get("pageid"), bool):
                page_map[int(page["pageid"])] = page
        for pageid in batch:
            member = by_pageid[pageid]
            page = page_map.get(pageid)
            if page is None:
                quarantined.append(_quarantine("missing_imageinfo", category=member["category"], response_hash=response_hash, pageid=pageid, title=member["title"]))
                continue
            try:
                candidate = _normalize_candidate(page, member["category"], response_hash, spec)
            except CommonsError as exc:
                quarantined.append(_quarantine(str(exc), category=member["category"], raw=page, response_hash=response_hash, pageid=page.get("pageid"), title=page.get("title")))
            else:
                if candidate["title"] != member["title"]:
                    quarantined.append(_quarantine("imageinfo_title_mismatch", category=member["category"], raw=page, response_hash=response_hash, pageid=pageid, title=member["title"]))
                else:
                    candidates.append(candidate)
    candidates.sort(key=lambda row: (str(row["category_id"]), int(row["pageid"]), str(row["title"])))
    return candidates, quarantined, response_hashes


def _candidate_sort_key(row: Mapping[str, Any]) -> tuple[str, int, str]:
    return str(row.get("category_id", "")), int(row.get("pageid", 0) or 0), str(row.get("title", ""))


def _quarantine_sort_key(row: Mapping[str, Any]) -> tuple[str, int, str, str]:
    pageid = row.get("pageid")
    try:
        numeric_pageid = int(pageid) if not isinstance(pageid, bool) else 0
    except (TypeError, ValueError):
        numeric_pageid = 0
    return str(row.get("category_id", "")), numeric_pageid, str(row.get("title", "")), str(row.get("reason", ""))


def _unique_rows(rows: Iterable[Mapping[str, Any]]) -> list[dict[str, Any]]:
    unique: list[dict[str, Any]] = []
    seen: set[str] = set()
    for row in rows:
        value = dict(row)
        marker = _canonical_hash(value)
        if marker not in seen:
            unique.append(value)
            seen.add(marker)
    return unique


def _load_reusable_candidates(
    root: Path,
    path: Path,
    quarantine_path: Path,
    receipt_path: Path,
    spec_hash: str,
    limit: int,
    metadata_only: bool,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str], list[dict[str, Any]]] | None:
    if not path.is_file() or path.is_symlink() or not receipt_path.is_file() or receipt_path.is_symlink():
        return None
    receipt = _read_json(receipt_path)
    if (
        not isinstance(receipt, dict)
        or receipt.get("source_id") != SOURCE_ID
        or receipt.get("spec_sha256") != spec_hash
        or receipt.get("requested_limit") != limit
        or receipt.get("metadata_only") is not metadata_only
        or receipt.get("run_mode") != ("metadata-only" if metadata_only else "download")
    ):
        return None
    candidates = _read_jsonl(path)
    quarantined = _read_jsonl(quarantine_path)
    for row in candidates:
        if row.get("spec_sha256") != spec_hash or row.get("requested_limit") != limit:
            raise CommonsError("candidate cache metadata does not match its receipt; use a new data root")
    output_map = receipt.get("outputs")
    if not isinstance(output_map, dict):
        raise CommonsError("candidate cache receipt has no output hashes; use a new data root")
    for relative, actual_path, expected_count in (
        (str(path.relative_to(root)), path, len(candidates)),
        (str(quarantine_path.relative_to(root)), quarantine_path, len(quarantined)),
    ):
        expected = output_map.get(relative)
        if not isinstance(expected, dict) or expected.get("records") != expected_count:
            raise CommonsError("candidate cache count does not match its receipt; use a new data root")
        if expected.get("sha256") != _sha256_file(actual_path):
            raise CommonsError("candidate cache hash does not match its receipt; use a new data root")
    discovery_hashes = receipt.get("discovery_response_sha256")
    if (
        not isinstance(discovery_hashes, list)
        or discovery_hashes != sorted(set(discovery_hashes))
        or any(not isinstance(value, str) or not SHA256_RE.fullmatch(value) for value in discovery_hashes)
    ):
        raise CommonsError("candidate cache discovery hashes are missing; use a new data root")
    row_hashes = {
        str(row["api_response_sha256"])
        for row in [*candidates, *quarantined]
        if isinstance(row.get("api_response_sha256"), str)
    }
    if not row_hashes.issubset(set(discovery_hashes)):
        raise CommonsError("candidate cache has an unrecorded discovery response; use a new data root")
    category_stats = receipt.get("category_quota")
    if not isinstance(category_stats, list):
        raise CommonsError("candidate cache category facts are missing; use a new data root")
    return candidates, quarantined, discovery_hashes, [dict(row) for row in category_stats if isinstance(row, dict)]


def _public_candidate(row: Mapping[str, Any]) -> dict[str, Any]:
    value = dict(row)
    value.pop("rights", None)
    return value


def _prepare(
    spec: Mapping[str, Any],
    spec_hash: str,
    limit: int,
    *,
    root: Path,
    contact: str,
    candidates_path: Path,
    limiter: _RateLimiter,
    quarantine_path: Path | None = None,
    receipt_path: Path | None = None,
    metadata_only: bool = False,
    opener: Any = None,
    sleeper: Callable[[float], None] = time.sleep,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]], list[str], list[dict[str, Any]]]:
    quotas = _quota_counts(spec["categories"], limit)
    reusable = None
    capacities: dict[str, int | None] = {}
    if quarantine_path is not None and receipt_path is not None:
        reusable = _load_reusable_candidates(
            root,
            candidates_path,
            quarantine_path,
            receipt_path,
            spec_hash,
            limit,
            metadata_only,
        )
    prior_category_stats: list[dict[str, Any]] = []
    if reusable is not None:
        candidates, initial_quarantine, response_hashes, prior_category_stats = reusable
    else:
        members: list[dict[str, Any]] = []
        initial_quarantine = []
        response_hashes = []
        for category, target in zip(spec["categories"], quotas):
            capacity, capacity_hash = _category_capacity(
                spec,
                category,
                contact=contact,
                limiter=limiter,
                opener=opener,
                sleeper=sleeper,
            )
            capacities[str(category["id"])] = capacity
            response_hashes.append(capacity_hash)
            category_members, member_quarantine, hashes, _ = _discover_members(
                spec,
                category,
                target,
                capacity,
                contact=contact,
                limiter=limiter,
                opener=opener,
                sleeper=sleeper,
            )
            members.extend(category_members)
            initial_quarantine.extend(member_quarantine)
            response_hashes.extend(hashes)
        # A page appearing in two fixed categories is retained under its first category only.
        seen_pageids: set[int] = set()
        unique_members: list[dict[str, Any]] = []
        for member in sorted(members, key=lambda row: (str(row["category"]["id"]), int(row["pageid"]), str(row["title"]))):
            pageid = int(member["pageid"])
            if pageid in seen_pageids:
                initial_quarantine.append(_quarantine("duplicate_pageid", category=member["category"], raw=member, response_hash=member.get("response_hash"), pageid=pageid, title=member["title"]))
                continue
            seen_pageids.add(pageid)
            unique_members.append(member)
        candidates, metadata_quarantine, hashes = _imageinfo_candidates(
            spec,
            unique_members,
            contact=contact,
            limiter=limiter,
            opener=opener,
            sleeper=sleeper,
        )
        initial_quarantine.extend(metadata_quarantine)
        response_hashes.extend(hashes)
        candidates.sort(key=_candidate_sort_key)
        for row in candidates:
            row["spec_sha256"] = spec_hash
            row["requested_limit"] = limit
        _atomic_jsonl(candidates_path, candidates)

    quotas = _quota_counts(spec["categories"], limit)
    selected: list[dict[str, Any]] = []
    quarantined = list(initial_quarantine)
    category_stats: list[dict[str, Any]] = []
    for category, target in zip(spec["categories"], quotas):
        identifier = str(category["id"])
        eligible = []
        for row in sorted((candidate for candidate in candidates if candidate.get("category_id") == identifier), key=_candidate_sort_key):
            try:
                rights = _classify_rights(row.get("extmetadata"))
            except CommonsError as exc:
                row["status"] = "quarantined"
                row["quarantine_reason"] = str(exc)
                quarantined.append(_quarantine(str(exc), category=category, raw=row, pageid=row.get("pageid"), title=row.get("title")))
                continue
            row["rights"] = rights
            if rights["license_kind"] in {"cc0-1.0", "cc-by-4.0", "public-domain"}:
                eligible.append(row)
            else:
                row["status"] = "quarantined"
                row["quarantine_reason"] = "license tuple is not allowlisted"
                quarantined.append(_quarantine("license tuple is not allowlisted", category=category, raw=row, pageid=row.get("pageid"), title=row.get("title")))
        chosen = eligible[:target] if metadata_only else eligible
        selected.extend(chosen)
        for row in chosen[:target]:
            row["status"] = "rights_accepted"
        if metadata_only:
            excluded = eligible[target:]
        else:
            excluded = []
        for row in excluded:
            row["status"] = "quota_excluded"
            row["quarantine_reason"] = "category quota exhausted"
            quarantined.append(_quarantine("category quota exhausted", category=category, raw=row, pageid=row.get("pageid"), title=row.get("title")))
        planned = min(target, len(eligible))
        prior = next((row for row in prior_category_stats if row.get("category_id") == identifier), {})
        if identifier not in capacities:
            capacities[identifier] = prior.get("direct_file_capacity")
        category_stats.append({
            "category_id": identifier,
            "category_title": category["title"],
            "quota_fraction": category["quota_fraction"],
            "target": target,
            "accepted_rights": planned,
            "direct_file_capacity": capacities.get(identifier),
            "attempted": 0,
            "rejected": 0,
            "backfilled": 0,
            "shortfall": max(0, target - planned),
            "shortfall_reason": "category supply or rights metadata below target" if planned < target else None,
        })
    selected.sort(key=_candidate_sort_key)
    candidates.sort(key=_candidate_sort_key)
    return candidates, selected, quarantined, sorted(set(response_hashes)), category_stats


def _download_media(
    url: str,
    destination: Path,
    *,
    max_bytes: int,
    expected_sha256: str | None = None,
    expected_width: int | None = None,
    expected_height: int | None = None,
    expected_height_tolerance: int = 0,
    expected_mime: str | None = None,
    max_pixels: int = 16_000_000,
    contact: str | None = None,
    opener: Any = None,
    limiter: _RateLimiter | None = None,
    sleeper: Callable[[float], None] = time.sleep,
) -> dict[str, Any]:
    _validate_url(url, {MEDIA_HOST}, label="thumbnail URL")
    _ensure_directory(destination.parent)
    if destination.is_symlink():
        raise DownloadError("destination is a symlink")
    if destination.exists() and not destination.is_file():
        raise DownloadError("destination is not a regular file")
    part = Path(f"{destination}.part")
    if part.is_symlink():
        raise DownloadError("partial destination is a symlink")
    if part.exists() and not part.is_file():
        raise DownloadError("partial destination is not a regular file")
    try:
        part_age = time.time() - part.stat().st_mtime if part.exists() else 0
    except OSError as exc:
        raise DownloadError("cannot inspect partial destination") from exc
    if part.exists() and part_age > STALE_PART_SECONDS:
        _safe_unlink(part)
    if expected_sha256 is not None and not SHA256_RE.fullmatch(expected_sha256):
        raise DownloadError("expected SHA-256 is malformed")
    if destination.exists() and expected_sha256 and _sha256_file(destination) == expected_sha256:
        return _inspect_local_image(
            destination,
            max_bytes=max_bytes,
            expected_sha256=expected_sha256,
            expected_width=expected_width,
            expected_height=expected_height,
            expected_height_tolerance=expected_height_tolerance,
            expected_mime=expected_mime,
            max_pixels=max_pixels,
        )

    limiter = limiter or _RateLimiter(0.0)
    range_error = False
    for attempt in range(MAX_ATTEMPTS):
        offset = part.stat().st_size if part.exists() else 0
        if offset > max_bytes:
            _safe_unlink(part)
            raise DownloadError("partial download exceeds byte ceiling")
        user_agent = "SET-OS-Camera-Coach-Commons/1.0"
        if contact:
            user_agent += f" (+{contact})"
        headers = {"User-Agent": user_agent, "Accept": "image/jpeg,image/png,image/webp"}
        if offset:
            headers["Range"] = f"bytes={offset}-"
        request = Request(url, headers=headers, method="GET")
        limiter.wait()
        try:
            response = _open_request(opener, request, 60.0)
            _validate_url(_response_url(response, url), {MEDIA_HOST}, label="thumbnail response URL")
            status = int(getattr(response, "status", getattr(response, "code", 200)))
            if 300 <= status < 400:
                raise DownloadError("redirect rejected")
            if status >= 400:
                raise HTTPError(url, status, f"HTTP {status}", getattr(response, "headers", {}), None)
            append = offset > 0 and status == 206
            if offset > 0 and status not in (200, 206):
                raise DownloadError(f"unexpected resume HTTP status: {status}")
            expected_range_length: int | None = None
            if append:
                content_range = getattr(response, "headers", {}).get("Content-Range")
                match = re.fullmatch(r"bytes\s+(\d+)-(\d+)/(\d+)", str(content_range or "").strip(), re.IGNORECASE)
                valid_range = False
                if match is not None:
                    range_start, range_end, range_total = (int(value) for value in match.groups())
                    valid_range = range_start == offset and range_end >= range_start and range_end == range_total - 1 and range_total <= max_bytes
                    if valid_range:
                        expected_range_length = range_end - range_start + 1
                if not valid_range:
                    range_error = True
                    close = getattr(response, "close", None)
                    if callable(close):
                        close()
                    _safe_unlink(part)
                    continue
            if not append and offset:
                _safe_unlink(part)
            mode = "ab" if append else "wb"
            received = 0
            with response, part.open(mode) as stream:
                while True:
                    chunk = response.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    received += len(chunk)
                    if stream.tell() + len(chunk) > max_bytes:
                        _safe_unlink(part)
                        raise DownloadError("download exceeds byte ceiling")
                    stream.write(chunk)
                stream.flush()
                os.fsync(stream.fileno())
            if append and expected_range_length is not None and received != expected_range_length:
                _safe_unlink(part)
                raise DownloadError("resume Content-Range length does not match received bytes")
            os.replace(part, destination)
            try:
                return _inspect_local_image(
                    destination,
                    max_bytes=max_bytes,
                    expected_sha256=expected_sha256,
                    expected_width=expected_width,
                    expected_height=expected_height,
                    expected_height_tolerance=expected_height_tolerance,
                    expected_mime=expected_mime,
                    max_pixels=max_pixels,
                )
            except DownloadError:
                _safe_unlink(destination)
                raise
        except HTTPError as exc:
            if exc.code not in RETRYABLE_HTTP or attempt + 1 >= MAX_ATTEMPTS:
                raise DownloadError(f"thumbnail HTTP {exc.code}") from exc
            delay = _retry_after(exc.headers)
            sleeper(delay if delay is not None else min(30.0, float(2**attempt)))
        except (URLError, TimeoutError, OSError) as exc:
            if attempt + 1 >= MAX_ATTEMPTS:
                raise DownloadError("thumbnail request failed after bounded retries") from exc
            sleeper(min(30.0, float(2**attempt)))
        except CommonsError:
            raise
    if range_error:
        raise DownloadError("resume Content-Range was unreliable after bounded restart")
    raise DownloadError("thumbnail download failed")


def _inspect_local_image(
    path: Path,
    *,
    max_bytes: int,
    expected_sha256: str | None = None,
    expected_width: int | None = None,
    expected_height: int | None = None,
    expected_height_tolerance: int = 0,
    expected_mime: str | None = None,
    max_pixels: int = 16_000_000,
) -> dict[str, Any]:
    try:
        info = path.lstat()
    except OSError as exc:
        raise DownloadError("cannot inspect downloaded image") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise DownloadError("downloaded image is not a regular file")
    if info.st_size < 1 or info.st_size > max_bytes:
        raise DownloadError("downloaded image exceeds byte ceiling")
    try:
        from PIL import Image

        with Image.open(path) as image:
            width, height = int(image.width), int(image.height)
            if width < 1 or height < 1 or width * height > max_pixels:
                raise DownloadError("downloaded image exceeds pixel ceiling")
            image.verify()
        with Image.open(path) as image:
            width, height = int(image.width), int(image.height)
            if width < 1 or height < 1 or width * height > max_pixels:
                raise DownloadError("downloaded image exceeds pixel ceiling")
            if expected_width is not None and width != expected_width:
                raise DownloadError("downloaded image width does not match API thumbnail")
            if expected_height is not None and abs(height - expected_height) > expected_height_tolerance:
                raise DownloadError("downloaded image height does not match API thumbnail")
            image.load()
            image_format = str(image.format or "").upper()
    except DownloadError:
        raise
    except Exception as exc:
        raise DownloadError("downloaded object is not a decodable image") from exc
    format_to_mime = {"JPEG": "image/jpeg", "PNG": "image/png", "WEBP": "image/webp"}
    if image_format not in format_to_mime:
        raise DownloadError("downloaded image format is not allowlisted")
    actual_mime = format_to_mime[image_format]
    if expected_mime is not None and actual_mime != expected_mime:
        raise DownloadError("downloaded image MIME does not match API thumbnail")
    digest = _sha256_file(path)
    if expected_sha256 is not None and digest != expected_sha256:
        raise DownloadError("local SHA-256 mismatch")
    return {
        "local_sha256": digest,
        "byte_count": int(info.st_size),
        "local_width": width,
        "local_height": height,
        "local_format": image_format.lower(),
        "local_mime": actual_mime,
    }


def _remember_unique_digest(digest: str, seen: set[str]) -> None:
    if digest in seen:
        raise DownloadError("duplicate image content")
    seen.add(digest)


def _run_intake(root: Path, *, output_path: Path | None = None) -> tuple[str, int]:
    manifest = _fixed_file(root, "raw-manifest.jsonl")
    if output_path is None:
        output = _fixed_file(root, "inventory.jsonl", create_parent=True)
    else:
        _ensure_directory(output_path.parent)
        if output_path.is_symlink() or (output_path.exists() and not output_path.is_file()):
            raise CommonsError("temporary inventory output is not a regular file")
        output = output_path
    result = subprocess.run(
        [
            sys.executable,
            str(INTAKE_SCRIPT),
            "verify-local",
            "--source-id",
            SOURCE_ID,
            "--data-root",
            str(root),
            "--manifest",
            str(manifest),
            "--output",
            str(output),
        ],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "camera_source_intake verify-local failed").strip().splitlines()[-1]
        raise CommonsError(detail)
    match = re.search(r"records=(\d+) output_sha256=([0-9a-f]{64})", result.stdout)
    if not match:
        raise CommonsError("camera_source_intake output is malformed")
    return match.group(2), int(match.group(1))


def _receipt_map(path: Path) -> dict[str, dict[str, Any]]:
    if not path.is_file() or path.is_symlink():
        return {}
    try:
        rows = _read_jsonl(path)
    except CommonsError:
        return {}
    return {str(row["source_record_id"]): row for row in rows if isinstance(row.get("source_record_id"), str)}


def _matching_prior_receipt(candidate: Mapping[str, Any], prior: Mapping[str, Any] | None) -> str | None:
    if not isinstance(prior, Mapping) or prior.get("download_status") != "downloaded":
        return None
    for key in (
        "thumburl",
        "thumbwidth",
        "thumbheight",
        "thumbmime",
        "expected_download_width",
        "expected_download_height",
        "expected_download_dimensions_source",
        "expected_download_bucket_width",
        "expected_download_bucket_height",
        "expected_download_display_width",
        "expected_download_display_height",
        "expected_download_height_tolerance",
        "api_response_sha256",
        "original_sha1",
        "mime",
    ):
        if prior.get(key) != candidate.get(key):
            return None
    digest = prior.get("local_sha256")
    return digest if isinstance(digest, str) and SHA256_RE.fullmatch(digest) else None


def _is_backfilled(candidate_index: int, original_target: int) -> bool:
    return candidate_index >= original_target


def _assert_unique_output_rows(rows: Sequence[Mapping[str, Any]], *, require_paths: bool) -> None:
    ids: set[str] = set()
    paths: set[str] = set()
    for row in rows:
        record_id = row.get("source_record_id")
        if not isinstance(record_id, str) or not record_id or record_id in ids:
            raise CommonsError("output source record ids are not unique")
        ids.add(record_id)
        if require_paths:
            relative = row.get("relative_path")
            if not isinstance(relative, str) or relative in paths:
                raise CommonsError("output relative paths are not unique")
            paths.add(relative)


def _fetch(
    spec_path: Path,
    data_root_value: Path,
    limit: int,
    *,
    metadata_only: bool,
    contact_override: str | None = None,
    opener: Any = None,
    sleeper: Callable[[float], None] = time.sleep,
) -> int:
    if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 3000:
        raise CommonsError("limit must be an integer from 1 through 3000")
    spec, spec_hash = _load_spec(spec_path)
    contact = _validate_contact(contact_override or str(spec.get("contact_default", DEFAULT_CONTACT)))
    root = _external_root(data_root_value)
    candidates_path = _fixed_file(root, str(spec["output"]["candidates"]), create_parent=True)
    accepted_path = _fixed_file(root, str(spec["output"]["accepted_rights_receipt"]), create_parent=True)
    quarantine_path = _fixed_file(root, str(spec["output"]["quarantined"]), create_parent=True)
    raw_path = _fixed_file(root, str(spec["output"]["raw_manifest"]), create_parent=True)
    inventory_path = _fixed_file(root, str(spec["output"]["inventory"]), create_parent=True)
    receipt_path = _fixed_file(root, str(spec["output"]["receipt"]), create_parent=True)
    if receipt_path.is_file():
        prior_run = _read_json(receipt_path)
        expected_mode = "metadata-only" if metadata_only else "download"
        if (
            not isinstance(prior_run, dict)
            or prior_run.get("source_id") != SOURCE_ID
            or prior_run.get("spec_sha256") != spec_hash
            or prior_run.get("requested_limit") != limit
            or prior_run.get("metadata_only") is not metadata_only
            or prior_run.get("run_mode") != expected_mode
        ):
            raise CommonsError("existing run root has a different spec, limit, or mode; use a new data root")
    _fixed_directory(root, str(spec["output"]["image_directory"]), create=True)
    limiter = _RateLimiter(float(spec["api"]["request_interval_seconds"]), sleeper=sleeper)
    candidates, selected, quarantined, response_hashes, category_stats = _prepare(
        spec,
        spec_hash,
        limit,
        root=root,
        contact=contact,
        candidates_path=candidates_path,
        quarantine_path=quarantine_path,
        receipt_path=receipt_path,
        metadata_only=metadata_only,
        limiter=limiter,
        opener=opener,
        sleeper=sleeper,
    )
    _atomic_jsonl(candidates_path, (_public_candidate(row) for row in candidates))
    _atomic_jsonl(quarantine_path, _unique_rows(quarantined))
    prior_receipts = _receipt_map(accepted_path)
    accepted: list[dict[str, Any]] = []
    raw_rows: list[dict[str, Any]] = []
    seen_hashes: set[str] = set()
    target_by_category = {str(stats["category_id"]): int(stats["target"]) for stats in category_stats}
    accepted_by_category = {category_id: 0 for category_id in target_by_category}
    attempted_by_category = {category_id: 0 for category_id in target_by_category}
    rejected_by_category = {category_id: 0 for category_id in target_by_category}
    backfilled_by_category = {category_id: 0 for category_id in target_by_category}
    candidate_index_by_category = {category_id: 0 for category_id in target_by_category}
    for candidate in selected:
        category_id = str(candidate["category_id"])
        candidate_index = candidate_index_by_category.get(category_id, 0)
        candidate_index_by_category[category_id] = candidate_index + 1
        if accepted_by_category.get(category_id, 0) >= target_by_category.get(category_id, 0):
            candidate["status"] = "quota_excluded"
            candidate["quarantine_reason"] = "category quota exhausted"
            quarantined.append(_quarantine("category quota exhausted", category={"id": category_id, "title": candidate["category_title"]}, raw=candidate, pageid=candidate["pageid"], title=candidate["title"]))
            continue
        attempted_by_category[category_id] = attempted_by_category.get(category_id, 0) + 1
        record_id = str(candidate["source_record_id"])
        extension = ALLOWED_MIME[str(candidate["thumbmime"])]
        relative_image = f"{spec['output']['image_directory']}/{record_id}.{extension}"
        destination = _safe_relative(root, relative_image)
        if metadata_only:
            local = {
                "download_status": "metadata_only",
                "local_sha256": None,
                "byte_count": None,
                "local_width": None,
                "local_height": None,
                "local_format": None,
                "local_mime": None,
            }
        else:
            expected = _matching_prior_receipt(candidate, prior_receipts.get(record_id))
            try:
                local = _download_media(
                    str(candidate["thumburl"]),
                    destination,
                    max_bytes=int(spec["download"]["max_bytes"]),
                    expected_sha256=expected,
                    expected_width=int(candidate["expected_download_width"]),
                    expected_height=int(candidate["expected_download_height"]),
                    expected_height_tolerance=int(candidate["expected_download_height_tolerance"]),
                    expected_mime=str(candidate["thumbmime"]),
                    max_pixels=int(spec["download"]["max_pixels"]),
                    contact=contact,
                    opener=opener,
                    limiter=limiter,
                    sleeper=sleeper,
                )
                try:
                    _remember_unique_digest(local["local_sha256"], seen_hashes)
                except DownloadError:
                    _safe_unlink(destination)
                    raise
                local["download_status"] = "downloaded"
            except (CommonsError, DownloadError) as exc:
                rejected_by_category[category_id] = rejected_by_category.get(category_id, 0) + 1
                candidate["status"] = "download_quarantined"
                candidate["quarantine_reason"] = str(exc)
                quarantined.append(_quarantine(str(exc), category={"id": candidate["category_id"], "title": candidate["category_title"]}, raw=candidate, pageid=candidate["pageid"], title=candidate["title"]))
                continue
        candidate["status"] = "accepted"
        accepted_row = {
            "source_id": SOURCE_ID,
            "source_record_id": record_id,
            "category_id": candidate["category_id"],
            "category_title": candidate["category_title"],
            "pageid": candidate["pageid"],
            "title": candidate["title"],
            "timestamp": candidate["timestamp"],
            "descriptionurl": candidate["descriptionurl"],
            "thumburl": candidate["thumburl"],
            "original_url": candidate["original_url"],
            "original_sha1": candidate["original_sha1"],
            "width": candidate["width"],
            "height": candidate["height"],
            "thumbwidth": candidate["thumbwidth"],
            "thumbheight": candidate["thumbheight"],
            "expected_download_width": candidate["expected_download_width"],
            "expected_download_height": candidate["expected_download_height"],
            "expected_download_dimensions_source": candidate["expected_download_dimensions_source"],
            "expected_download_bucket_width": candidate["expected_download_bucket_width"],
            "expected_download_bucket_height": candidate["expected_download_bucket_height"],
            "expected_download_display_width": candidate["expected_download_display_width"],
            "expected_download_display_height": candidate["expected_download_display_height"],
            "expected_download_height_tolerance": candidate["expected_download_height_tolerance"],
            "mime": candidate["mime"],
            "thumbmime": candidate["thumbmime"],
            "mediatype": candidate["mediatype"],
            "api_response_sha256": candidate["api_response_sha256"],
            "extmetadata": candidate["extmetadata"],
            "rights": _classify_rights(candidate["extmetadata"]),
            "relative_path": None if metadata_only else relative_image,
            "research_only": True,
            "human_gold": False,
            "release_admissible": False,
            "clearance_candidate": bool(candidate["rights"]["clearance_candidate"]),
            **local,
        }
        accepted.append(accepted_row)
        accepted_by_category[category_id] = accepted_by_category.get(category_id, 0) + 1
        if _is_backfilled(candidate_index, target_by_category.get(category_id, 0)):
            backfilled_by_category[category_id] = backfilled_by_category.get(category_id, 0) + 1
        if not metadata_only:
            raw_rows.append({"image_id": record_id, "path": relative_image})

    accepted.sort(key=lambda row: (str(row["category_id"]), int(row["pageid"]), str(row["title"])))
    for stats in category_stats:
        category_id = stats["category_id"]
        actual = sum(1 for row in accepted if row["category_id"] == category_id)
        stats["accepted_rights"] = actual
        stats["attempted"] = attempted_by_category.get(category_id, 0)
        stats["rejected"] = rejected_by_category.get(category_id, 0)
        stats["backfilled"] = backfilled_by_category.get(category_id, 0)
        stats["shortfall"] = max(0, int(stats["target"]) - actual)
        stats["shortfall_reason"] = "category supply, rights metadata, or media below target" if stats["shortfall"] else None
    quarantined = _unique_rows(quarantined)
    accepted_ids = {str(row["source_record_id"]) for row in accepted}
    quarantined = [
        row
        for row in quarantined
        if not (isinstance(row.get("raw"), dict) and str(row["raw"].get("source_record_id")) in accepted_ids)
    ]
    quarantined.sort(key=_quarantine_sort_key)
    raw_rows.sort(key=lambda row: str(row["image_id"]))
    _assert_unique_output_rows(candidates, require_paths=False)
    _assert_unique_output_rows(accepted, require_paths=not metadata_only)
    if not metadata_only:
        raw_ids = [str(row.get("image_id")) for row in raw_rows]
        raw_paths = [str(row.get("path")) for row in raw_rows]
        if len(raw_ids) != len(set(raw_ids)) or len(raw_paths) != len(set(raw_paths)) or set(raw_ids) != {str(row["source_record_id"]) for row in accepted}:
            raise CommonsError("raw manifest output linkage is not unique")
    _atomic_jsonl(candidates_path, (_public_candidate(row) for row in candidates))
    _atomic_jsonl(accepted_path, accepted)
    _atomic_jsonl(quarantine_path, quarantined)
    _atomic_jsonl(raw_path, raw_rows)
    if raw_rows:
        inventory_sha, inventory_count = _run_intake(root)
    else:
        inventory_sha, inventory_count = _atomic_jsonl(inventory_path, [])

    output_hashes: dict[str, dict[str, Any]] = {}
    for relative, count in (
        (spec["output"]["candidates"], len(candidates)),
        (spec["output"]["accepted_rights_receipt"], len(accepted)),
        (spec["output"]["quarantined"], len(quarantined)),
        (spec["output"]["raw_manifest"], len(raw_rows)),
        (spec["output"]["inventory"], inventory_count),
    ):
        output_hashes[str(relative)] = {"sha256": _sha256_file(_fixed_file(root, str(relative))), "records": count}
    receipt: dict[str, Any] = {
        "schema_id": "camera-commons-ingest-receipt-v1",
        "status": "PARTIAL" if any(int(stats["shortfall"]) > 0 for stats in category_stats) else "PASS",
        "exit_code": 2 if any(int(stats["shortfall"]) > 0 for stats in category_stats) else 0,
        "source_id": SOURCE_ID,
        "spec_sha256": spec_hash,
        "requested_limit": limit,
        "metadata_only": metadata_only,
        "run_mode": "metadata-only" if metadata_only else "download",
        "contact": contact,
        "api_endpoint": spec["api"]["endpoint"],
        "api_response_sha256": sorted(set(response_hashes)),
        "discovery_response_sha256": sorted(set(response_hashes)),
        "intake_tier": "research_only",
        "research_only": True,
        "human_gold": False,
        "release_admissible": False,
        "rights_boundary": "Per-file tuples only; category membership never establishes a license. PD is a clearance_candidate, not release clearance.",
        "counts": {
            "candidates": len(candidates),
            "accepted_rights": len(accepted),
            "downloaded": sum(1 for row in accepted if row["download_status"] == "downloaded"),
            "quarantined": len(quarantined),
            "attempted": sum(int(stats["attempted"]) for stats in category_stats),
            "rejected": sum(int(stats["rejected"]) for stats in category_stats),
            "backfilled": sum(int(stats["backfilled"]) for stats in category_stats),
        },
        "category_quota": category_stats,
        "outputs": output_hashes,
    }
    _atomic_json(receipt_path, receipt)
    partial = receipt["status"] == "PARTIAL"
    print(
        f"{'PARTIAL' if partial else 'PASS'} fetch-commons source_id={SOURCE_ID} candidates={len(candidates)} "
        f"accepted_rights={len(accepted)} downloaded={receipt['counts']['downloaded']} "
        f"quarantined={len(quarantined)} metadata_only={str(metadata_only).lower()}"
    )
    return 2 if partial else 0


def _verify_local(spec_path: Path, data_root_value: Path) -> int:
    spec, spec_hash = _load_spec(spec_path)
    root = _external_root(data_root_value, create=False)
    _fixed_directory(root, str(spec["output"]["image_directory"]), create=False)
    candidates_path = _fixed_file(root, str(spec["output"]["candidates"]))
    quarantine_path = _fixed_file(root, str(spec["output"]["quarantined"]))
    raw_path = _fixed_file(root, str(spec["output"]["raw_manifest"]))
    accepted_path = _fixed_file(root, str(spec["output"]["accepted_rights_receipt"]))
    inventory_path = _fixed_file(root, str(spec["output"]["inventory"]))
    receipt_path = _fixed_file(root, str(spec["output"]["receipt"]))
    candidates = _read_jsonl(candidates_path)
    quarantined = _read_jsonl(quarantine_path)
    raw_rows = _read_jsonl(raw_path)
    accepted = _read_jsonl(accepted_path)
    inventory_rows = _read_jsonl(inventory_path)
    receipt = _read_json(receipt_path)
    metadata_only = receipt.get("metadata_only") if isinstance(receipt, dict) else None
    expected_mode = "metadata-only" if metadata_only else "download"
    if (
        not isinstance(receipt, dict)
        or receipt.get("source_id") != SOURCE_ID
        or receipt.get("spec_sha256") != spec_hash
        or not isinstance(metadata_only, bool)
        or receipt.get("run_mode") != expected_mode
        or receipt.get("status") not in {"PASS", "PARTIAL"}
        or not isinstance(receipt.get("requested_limit"), int)
        or isinstance(receipt.get("requested_limit"), bool)
        or not 1 <= int(receipt.get("requested_limit", 0)) <= 3000
    ):
        raise CommonsError("receipt does not match the tracked Commons spec")
    output_map = receipt.get("outputs")
    expected_inventory = output_map.get(str(spec["output"]["inventory"])) if isinstance(output_map, dict) else None
    persisted_inventory_sha = _sha256_file(inventory_path)
    if not isinstance(expected_inventory, dict) or expected_inventory.get("records") != len(inventory_rows) or expected_inventory.get("sha256") != persisted_inventory_sha:
        raise CommonsError("persisted inventory hash or count does not match receipt")
    _assert_unique_output_rows(candidates, require_paths=False)
    _assert_unique_output_rows(accepted, require_paths=not metadata_only)
    candidate_by_id = {str(row["source_record_id"]): row for row in candidates}
    accepted_by_id = {str(row["source_record_id"]): row for row in accepted}
    for row in accepted:
        record_id = str(row["source_record_id"])
        candidate = candidate_by_id.get(record_id)
        if candidate is None:
            raise CommonsError(f"accepted record is absent from candidates: {record_id}")
        if row.get("source_id") != SOURCE_ID or row.get("research_only") is not True or row.get("human_gold") is not False or row.get("release_admissible") is not False:
            raise CommonsError(f"rights boundary is invalid: {record_id}")
        recomputed_rights = _classify_rights(row.get("extmetadata"))
        if row.get("rights") != recomputed_rights or row.get("clearance_candidate") is not recomputed_rights["clearance_candidate"]:
            raise CommonsError(f"rights classification changed: {record_id}")
        for key in ("category_id", "category_title", "pageid", "title", "timestamp", "descriptionurl", "thumburl", "original_url", "original_sha1", "width", "height", "thumbwidth", "thumbheight", "expected_download_width", "expected_download_height", "expected_download_dimensions_source", "expected_download_bucket_width", "expected_download_bucket_height", "expected_download_display_width", "expected_download_display_height", "expected_download_height_tolerance", "mime", "thumbmime", "mediatype", "api_response_sha256", "extmetadata"):
            if row.get(key) != candidate.get(key):
                raise CommonsError(f"accepted record differs from candidate: {record_id}")
        try:
            expected_dimensions = _expected_download_dimensions(
                _validate_url(candidate["thumburl"], {MEDIA_HOST}, label="candidate thumbnail URL"),
                _validate_url(candidate["original_url"], {MEDIA_HOST}, label="candidate original URL"),
                _positive_int(candidate["width"], key="width"),
                _positive_int(candidate["height"], key="height"),
                _positive_int(candidate["thumbwidth"], key="thumbwidth"),
                _positive_int(candidate["thumbheight"], key="thumbheight"),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise CommonsError(f"expected download dimensions are malformed: {record_id}") from exc
        expected_fields = {
            "expected_download_width": expected_dimensions["width"],
            "expected_download_height": expected_dimensions["height"],
            "expected_download_dimensions_source": expected_dimensions["source"],
            "expected_download_bucket_width": expected_dimensions["bucket_width"],
            "expected_download_bucket_height": expected_dimensions["bucket_height"],
            "expected_download_display_width": expected_dimensions["display_width"],
            "expected_download_display_height": expected_dimensions["display_height"],
            "expected_download_height_tolerance": expected_dimensions["height_tolerance"],
        }
        for key, value in expected_fields.items():
            if candidate.get(key) != value:
                raise CommonsError(f"candidate expected download dimensions are invalid: {record_id}")
            if row.get(key) != value:
                raise CommonsError(f"accepted expected download dimensions are invalid: {record_id}")
        if metadata_only:
            if row.get("download_status") != "metadata_only" or row.get("relative_path") is not None or any(row.get(key) is not None for key in ("local_sha256", "byte_count", "local_width", "local_height", "local_format", "local_mime")):
                raise CommonsError(f"metadata-only local fields are invalid: {record_id}")
        else:
            if row.get("download_status") != "downloaded" or not isinstance(row.get("relative_path"), str):
                raise CommonsError(f"downloaded local fields are invalid: {record_id}")
            path = _safe_relative(root, row["relative_path"])
            local = _inspect_local_image(
                path,
                max_bytes=int(spec["download"]["max_bytes"]),
                expected_sha256=row.get("local_sha256"),
                expected_width=int(row["expected_download_width"]),
                expected_height=int(row["expected_download_height"]),
                expected_height_tolerance=int(row["expected_download_height_tolerance"]),
                expected_mime=str(row["thumbmime"]),
                max_pixels=int(spec["download"]["max_pixels"]),
            )
            for key, value in local.items():
                if row.get(key) != value:
                    raise CommonsError(f"local image metadata changed: {record_id}")
    if metadata_only:
        if raw_rows or inventory_rows:
            raise CommonsError("metadata-only output contains local records")
        inventory_sha, count = persisted_inventory_sha, len(inventory_rows)
    else:
        expected_raw = sorted(
            [{"image_id": str(row["source_record_id"]), "path": row["relative_path"]} for row in accepted],
            key=lambda row: row["image_id"],
        )
        if raw_rows != expected_raw:
            raise CommonsError("raw manifest does not exactly match accepted rights receipt")
        if not raw_rows and accepted:
            raise CommonsError("accepted records are absent from raw manifest")
        inventory_sha, count = persisted_inventory_sha, len(inventory_rows)
        if raw_rows:
            with tempfile.TemporaryDirectory(prefix="commons-verify-") as verify_dir:
                generated_sha, generated_count = _run_intake(root, output_path=Path(verify_dir) / "inventory.jsonl")
            if generated_sha != inventory_sha or generated_count != count:
                raise CommonsError("recomputed inventory does not match persisted inventory")
        if len(inventory_rows) != len(raw_rows):
            raise CommonsError("inventory count does not match raw manifest")
        inventory_by_id = {str(row.get("source_record_id")): row for row in inventory_rows}
        if len(inventory_by_id) != len(inventory_rows) or set(inventory_by_id) != set(accepted_by_id):
            raise CommonsError("inventory ids do not exactly match accepted rights receipt")
        for record_id, row in accepted_by_id.items():
            inventory = inventory_by_id[record_id]
            if inventory.get("relative_path") != row.get("relative_path") or inventory.get("sha256") != row.get("local_sha256") or inventory.get("byte_count") != row.get("byte_count") or inventory.get("width") != row.get("local_width") or inventory.get("height") != row.get("local_height"):
                raise CommonsError(f"inventory linkage does not match accepted record: {record_id}")
    if not isinstance(output_map, dict):
        raise CommonsError("receipt output hashes are missing")
    output_rows = {
        str(spec["output"]["candidates"]): (candidates_path, len(candidates)),
        str(spec["output"]["accepted_rights_receipt"]): (accepted_path, len(accepted)),
        str(spec["output"]["quarantined"]): (quarantine_path, len(quarantined)),
        str(spec["output"]["raw_manifest"]): (raw_path, len(raw_rows)),
        str(spec["output"]["inventory"]): (inventory_path, count),
    }
    for relative, (path, records) in output_rows.items():
        expected = output_map.get(relative)
        if not isinstance(expected, dict) or expected.get("records") != records or expected.get("sha256") != _sha256_file(path):
            raise CommonsError(f"output hash or count does not match receipt: {relative}")
    discovery_hashes = receipt.get("discovery_response_sha256")
    if not isinstance(discovery_hashes, list) or discovery_hashes != sorted(set(discovery_hashes)) or any(not isinstance(value, str) or not SHA256_RE.fullmatch(value) for value in discovery_hashes):
        raise CommonsError("receipt discovery hashes are invalid")
    if receipt.get("api_response_sha256") != discovery_hashes:
        raise CommonsError("receipt API response hashes do not match discovery hashes")
    row_hashes = {str(row["api_response_sha256"]) for row in [*candidates, *quarantined] if isinstance(row.get("api_response_sha256"), str)}
    if not row_hashes.issubset(set(discovery_hashes)):
        raise CommonsError("receipt omits a candidate discovery response hash")
    quota = receipt.get("category_quota")
    if not isinstance(quota, list) or any(not isinstance(row, dict) for row in quota) or [row.get("category_id") for row in quota] != [category["id"] for category in spec["categories"]]:
        raise CommonsError("category quota receipt is invalid")
    expected_targets = _quota_counts(spec["categories"], int(receipt["requested_limit"]))
    partial = False
    for category, target, stats in zip(spec["categories"], expected_targets, quota):
        if not isinstance(stats, dict) or not isinstance(stats.get("direct_file_capacity"), int) or stats["direct_file_capacity"] < 0:
            raise CommonsError("category capacity receipt is invalid")
        if stats.get("category_title") != category["title"] or stats.get("quota_fraction") != category["quota_fraction"]:
            raise CommonsError(f"category metadata does not match receipt: {stats.get('category_id')}")
        if not isinstance(stats.get("target"), int) or stats["target"] != target:
            raise CommonsError(f"category target does not match receipt: {stats.get('category_id')}")
        actual = sum(1 for row in accepted if row.get("category_id") == stats["category_id"])
        expected_shortfall = max(0, int(stats["target"]) - actual)
        if stats.get("accepted_rights") != actual or stats.get("shortfall") != expected_shortfall:
            raise CommonsError(f"category count does not match receipt: {stats.get('category_id')}")
        if int(stats.get("attempted", -1)) < 0 or int(stats.get("rejected", -1)) < 0 or int(stats.get("backfilled", -1)) < 0:
            raise CommonsError("category attempt counts are invalid")
        partial = partial or expected_shortfall > 0
    counts = receipt.get("counts")
    expected_counts = {
        "candidates": len(candidates),
        "accepted_rights": len(accepted),
        "downloaded": sum(1 for row in accepted if row.get("download_status") == "downloaded"),
        "quarantined": len(quarantined),
        "attempted": sum(int(stats["attempted"]) for stats in quota),
        "rejected": sum(int(stats["rejected"]) for stats in quota),
        "backfilled": sum(int(stats["backfilled"]) for stats in quota),
    }
    if counts != expected_counts or receipt.get("status") != ("PARTIAL" if partial else "PASS") or receipt.get("exit_code") != (2 if partial else 0):
        raise CommonsError("receipt counts or status are inconsistent")
    if receipt.get("research_only") is not True or receipt.get("human_gold") is not False or receipt.get("release_admissible") is not False:
        raise CommonsError("receipt rights boundary is invalid")
    print(f"{'PARTIAL' if partial else 'PASS'} verify-local source_id={SOURCE_ID} records={count} output_sha256={inventory_sha}")
    return 2 if partial else 0


class _FakeResponse:
    def __init__(self, body: bytes, *, status: int = 200, url: str = f"https://{MEDIA_HOST}/x.jpg", headers: Mapping[str, str] | None = None) -> None:
        self.body = body
        self.status = status
        self.code = status
        self.url = url
        self.headers = dict(headers or {})

    def geturl(self) -> str:
        return self.url

    def read(self, size: int = -1) -> bytes:
        if size < 0:
            size = len(self.body)
        value, self.body = self.body[:size], self.body[size:]
        return value

    def __enter__(self) -> "_FakeResponse":
        return self

    def __exit__(self, *args: Any) -> None:
        return None


def _fixture_ext(license_value: str, short_name: str, *, attribution: Any = "false", artist: str | None = None, copyrighted: Any = None, restrictions: str = "") -> dict[str, dict[str, Any]]:
    value: dict[str, dict[str, Any]] = {
        "License": {"value": license_value, "source": "fixture"},
        "LicenseShortName": {"value": short_name, "source": "fixture"},
        "AttributionRequired": {"value": attribution, "source": "fixture"},
        "Restrictions": {"value": restrictions, "source": "fixture"},
        "Artist": {"value": artist or "", "source": "fixture"},
        "Credit": {"value": "<i>fixture credit</i>", "source": "fixture"},
    }
    if license_value == "cc0":
        value["LicenseUrl"] = {"value": CANONICAL_CC0_URL, "source": "fixture"}
    elif license_value == "cc-by-4.0":
        value["LicenseUrl"] = {"value": CANONICAL_CC_BY_URL, "source": "fixture"}
    if copyrighted is not None:
        value["Copyrighted"] = {"value": copyrighted, "source": "fixture"}
    return value


def _self_test() -> None:
    try:
        from PIL import Image
    except ImportError as exc:
        raise CommonsError("Pillow is required for the Commons self-test") from exc
    accepted = (
        _classify_rights(_fixture_ext("cc0", "CC0 1.0")),
        _classify_rights(_fixture_ext("cc-by-4.0", "CC BY 4.0", attribution="true", artist="<b>Jane &amp; Co.</b>")),
        _classify_rights(_fixture_ext("pd", "Public domain", copyrighted="false")),
    )
    assert [item["license_kind"] for item in accepted] == ["cc0-1.0", "cc-by-4.0", "public-domain"]
    assert accepted[1]["artist_text"] == "Jane & Co."
    assert accepted[0]["clearance_candidate"] is False and accepted[2]["clearance_candidate"] is True
    for ext in (
        _fixture_ext("cc-by-sa-4.0", "CC BY-SA 4.0"),
        _fixture_ext("unknown", "Unknown"),
        {"LicenseShortName": {"value": "CC0 1.0"}},
        _fixture_ext("CC0", "CC0 1.0"),
    ):
        try:
            _classify_rights(ext)
        except CommonsError:
            pass
        else:
            raise AssertionError("rejected license tuple was accepted")

    for unsafe in ("http://commons.wikimedia.org/w/api.php", f"https://evil.example/x", f"https://{API_HOST}/x#fragment"):
        try:
            _validate_url(unsafe, {API_HOST}, label="fixture URL")
        except CommonsError:
            pass
        else:
            raise AssertionError("unsafe URL was accepted")
    try:
        _NoRedirect().redirect_request(Request(f"https://{API_HOST}/x"), None, 302, "Found", {}, f"https://{MEDIA_HOST}/x.jpg")
    except CommonsError:
        pass
    else:
        raise AssertionError("redirect was accepted")

    category = {"id": "people", "title": "Category:Portraits"}
    fixture_spec: dict[str, Any] = {
        "download": {"thumbnail_width": 1600, "max_pixels": 16_000_000},
    }
    base_page = {
        "pageid": 1,
        "ns": 6,
        "title": "File:fixture.jpg",
        "imageinfo": [{
            "timestamp": "2024-01-01T00:00:00Z",
            "descriptionurl": f"https://{API_HOST}/wiki/File:fixture.jpg",
            "thumburl": f"https://{MEDIA_HOST}/thumb/fixture.jpg",
            "url": f"https://{MEDIA_HOST}/fixture.jpg",
            "sha1": "a" * 40,
            "width": 3,
            "height": 2,
            "thumbwidth": 3,
            "thumbheight": 2,
            "mime": "image/jpeg",
            "thumbmime": "image/jpeg",
            "mediatype": "BITMAP",
            "extmetadata": _fixture_ext("cc0", "CC0 1.0"),
        }],
    }
    candidate = _normalize_candidate(base_page, category, "b" * 64, fixture_spec)
    assert candidate["original_sha1"] == "a" * 40 and candidate["api_response_sha256"] == "b" * 64
    bucket_page = dict(base_page)
    bucket_info = dict(base_page["imageinfo"][0])
    bucket_info.update({
        "thumburl": f"https://{MEDIA_HOST}/1920px-A_road_sign_post.jpg",
        "url": f"https://{MEDIA_HOST}/original-road-sign.jpg",
        "width": 1920,
        "height": 3412,
        "thumbwidth": 1600,
        "thumbheight": 2843,
    })
    bucket_page["imageinfo"] = [bucket_info]
    bucket_candidate = _normalize_candidate(bucket_page, category, "b" * 64, fixture_spec)
    assert (bucket_candidate["expected_download_width"], bucket_candidate["expected_download_height"]) == (1920, 3412)
    assert bucket_candidate["expected_download_dimensions_source"] == "thumbnail_bucket"
    assert (bucket_candidate["expected_download_bucket_width"], bucket_candidate["expected_download_bucket_height"]) == (1920, 3412)
    assert (bucket_candidate["expected_download_display_width"], bucket_candidate["expected_download_display_height"]) == (1600, 2843)
    assert bucket_candidate["expected_download_height_tolerance"] == 1
    unscaled_page = dict(base_page)
    unscaled_info = dict(base_page["imageinfo"][0])
    unscaled_info.update({
        "thumburl": f"https://{MEDIA_HOST}/wikipedia/commons/fixture.jpg?utm_content=thumbnail_unscaled",
        "url": f"https://{MEDIA_HOST}/wikipedia/commons/fixture.jpg?utm_content=original",
        "width": 1400,
        "height": 875,
        "thumbwidth": 1600,
        "thumbheight": 1000,
    })
    unscaled_page["imageinfo"] = [unscaled_info]
    unscaled_candidate = _normalize_candidate(unscaled_page, category, "b" * 64, fixture_spec)
    assert (unscaled_candidate["expected_download_width"], unscaled_candidate["expected_download_height"]) == (1400, 875)
    malformed = dict(base_page)
    malformed["imageinfo"] = [{"mime": "image/jpeg"}]
    try:
        _normalize_candidate(malformed, category, "b" * 64, fixture_spec)
    except CommonsError:
        pass
    else:
        raise AssertionError("malformed API record was accepted")

    with tempfile.TemporaryDirectory(prefix="fetch-commons-jsonl-") as jsonl_dir:
        jsonl_path = Path(jsonl_dir) / "unicode.jsonl"
        unicode_value = "before\u2028middle\u2029after\u0085end"
        jsonl_path.write_text(_json_line({"value": unicode_value}) + "\n", encoding="utf-8")
        assert _read_jsonl(jsonl_path) == [{"value": unicode_value}]

    sleeps: list[float] = []
    calls = 0

    def retry_opener(request: Request, *, timeout: float) -> _FakeResponse:
        nonlocal calls
        calls += 1
        if calls == 1:
            raise HTTPError(request.full_url, 429, "Too Many Requests", {"Retry-After": "0"}, io.BytesIO())
        return _FakeResponse(b'{"ok":true}', url=request.full_url)

    payload, digest = _request_json(
        f"https://{API_HOST}/w/api.php",
        {"action": "query"},
        headers={"User-Agent": "fixture"},
        allowed_host=API_HOST,
        opener=retry_opener,
        limiter=_RateLimiter(0, sleeper=lambda seconds: None),
        sleeper=sleeps.append,
    )
    assert payload == {"ok": True} and digest == _canonical_hash(payload) and calls == 2 and sleeps == [0.0]

    maxlag_calls = 0
    maxlag_sleeps: list[float] = []

    def maxlag_opener(request: Request, *, timeout: float) -> _FakeResponse:
        nonlocal maxlag_calls
        maxlag_calls += 1
        if maxlag_calls == 1:
            return _FakeResponse(b'{"error":{"code":"maxlag","info":"busy"}}', url=request.full_url, headers={"Retry-After": "0"})
        return _FakeResponse(b'{"ok":true}', url=request.full_url)

    payload, _ = _request_json(
        f"https://{API_HOST}/w/api.php",
        {"action": "query"},
        headers={"User-Agent": "fixture"},
        allowed_host=API_HOST,
        opener=maxlag_opener,
        limiter=_RateLimiter(0, sleeper=lambda seconds: None),
        sleeper=maxlag_sleeps.append,
    )
    assert payload == {"ok": True} and maxlag_calls == 2 and maxlag_sleeps == [0.0]

    with tempfile.TemporaryDirectory(prefix="fetch-commons-") as temp_dir:
        root = Path(temp_dir) / "external"
        images = root / "images"
        images.mkdir(parents=True)
        payload_bytes = io.BytesIO()
        Image.new("RGB", (3, 2), (20, 40, 60)).save(payload_bytes, format="JPEG")
        image_bytes = payload_bytes.getvalue()
        destination = images / "resume.jpg"
        part = Path(f"{destination}.part")
        download_calls = 0

        class InterruptedResponse(_FakeResponse):
            def read(self, size: int = -1) -> bytes:
                if self.body:
                    value, self.body = self.body[: max(1, len(self.body) // 2)], self.body[max(1, len(self.body) // 2) :]
                    if not self.body:
                        raise URLError("interrupted")
                    return value
                return b""

        def download_opener(request: Request, *, timeout: float) -> _FakeResponse:
            nonlocal download_calls
            download_calls += 1
            offset_header = request.get_header("Range")
            offset = int(offset_header.split("=", 1)[1].split("-", 1)[0]) if offset_header else 0
            if download_calls == 1:
                return InterruptedResponse(image_bytes, url=request.full_url)
            assert offset > 0
            return _FakeResponse(image_bytes[offset:], status=206, url=request.full_url, headers={"Content-Range": f"bytes {offset}-{len(image_bytes) - 1}/{len(image_bytes)}"})

        local = _download_media(
            f"https://{MEDIA_HOST}/thumb/fixture.jpg",
            destination,
            max_bytes=100000,
            opener=download_opener,
            limiter=_RateLimiter(0, sleeper=lambda seconds: None),
            sleeper=lambda seconds: None,
        )
        assert destination.read_bytes() == image_bytes and not part.exists() and local["local_sha256"] == hashlib.sha256(image_bytes).hexdigest()

        stale_destination = images / "stale.jpg"
        stale_part = Path(f"{stale_destination}.part")
        stale_part.write_bytes(b"stale")
        old_time = time.time() - STALE_PART_SECONDS - 1
        os.utime(stale_part, (old_time, old_time))
        _download_media(
            f"https://{MEDIA_HOST}/thumb/fixture.jpg",
            stale_destination,
            max_bytes=100000,
            opener=lambda request, timeout: _FakeResponse(image_bytes, url=request.full_url),
            limiter=_RateLimiter(0, sleeper=lambda seconds: None),
            sleeper=lambda seconds: None,
        )
        assert stale_destination.read_bytes() == image_bytes and not stale_part.exists()

        bad_range_destination = images / "bad-range.jpg"
        bad_range_part = Path(f"{bad_range_destination}.part")
        bad_range_part.write_bytes(image_bytes[:4])
        try:
            _download_media(
                f"https://{MEDIA_HOST}/thumb/fixture.jpg",
                bad_range_destination,
                max_bytes=100000,
                opener=lambda request, timeout: _FakeResponse(image_bytes[4:], status=206, url=request.full_url, headers={"Content-Range": f"bytes 0-{len(image_bytes) - 5}/{len(image_bytes)}"}),
                limiter=_RateLimiter(0, sleeper=lambda seconds: None),
                sleeper=lambda seconds: None,
            )
        except DownloadError as exc:
            assert not bad_range_part.exists()
        else:
            raise AssertionError("invalid resume Content-Range was accepted")
        short_destination = images / "short-range.jpg"
        short_range_part = Path(f"{short_destination}.part")
        short_range_part.write_bytes(image_bytes[:4])
        try:
            _download_media(
                f"https://{MEDIA_HOST}/thumb/fixture.jpg",
                short_destination,
                max_bytes=100000,
                opener=lambda request, timeout: _FakeResponse(image_bytes[4:-1], status=206, url=request.full_url, headers={"Content-Range": f"bytes 4-{len(image_bytes) - 1}/{len(image_bytes)}"}),
                limiter=_RateLimiter(0, sleeper=lambda seconds: None),
                sleeper=lambda seconds: None,
            )
        except DownloadError as exc:
            assert "length" in str(exc) and not short_range_part.exists()
        else:
            raise AssertionError("short resume body was accepted")

        try:
            _download_media(
                f"https://{MEDIA_HOST}/thumb/fixture.jpg",
                images / "mismatch.jpg",
                max_bytes=100000,
                expected_sha256="0" * 64,
                opener=lambda request, timeout: _FakeResponse(image_bytes, url=request.full_url),
                limiter=_RateLimiter(0, sleeper=lambda seconds: None),
                sleeper=lambda seconds: None,
            )
        except DownloadError as exc:
            assert "mismatch" in str(exc)
        else:
            raise AssertionError("hash mismatch was accepted")
        oversized = images / "oversized.jpg"
        try:
            _download_media(
                f"https://{MEDIA_HOST}/thumb/fixture.jpg",
                oversized,
                max_bytes=4,
                opener=lambda request, timeout: _FakeResponse(image_bytes, url=request.full_url),
                limiter=_RateLimiter(0, sleeper=lambda seconds: None),
                sleeper=lambda seconds: None,
            )
        except DownloadError:
            pass
        else:
            raise AssertionError("oversized object was accepted")
        try:
            _download_media(
                f"https://{MEDIA_HOST}/thumb/fixture.jpg",
                images / "text.jpg",
                max_bytes=100000,
                opener=lambda request, timeout: _FakeResponse(b"not an image", url=request.full_url),
                limiter=_RateLimiter(0, sleeper=lambda seconds: None),
                sleeper=lambda seconds: None,
            )
        except DownloadError:
            pass
        else:
            raise AssertionError("non-image object was accepted")
        linked = images / "linked.jpg"
        linked.symlink_to(destination)
        try:
            _download_media(
                f"https://{MEDIA_HOST}/thumb/fixture.jpg",
                linked,
                max_bytes=100000,
                opener=lambda request, timeout: _FakeResponse(image_bytes, url=request.full_url),
                limiter=_RateLimiter(0, sleeper=lambda seconds: None),
                sleeper=lambda seconds: None,
            )
        except DownloadError:
            pass
        else:
            raise AssertionError("symlink destination was accepted")
        rows = sorted([{"source_record_id": "commons-2"}, {"source_record_id": "commons-1"}], key=lambda row: row["source_record_id"])
        first_hash, _ = _atomic_jsonl(root / "deterministic.jsonl", rows)
        second_hash, _ = _atomic_jsonl(root / "deterministic-rerun.jsonl", sorted(reversed(rows), key=lambda row: row["source_record_id"]))
        assert first_hash == second_hash
        assert _canonical_hash({"b": 2, "a": 1}) == _canonical_hash({"a": 1, "b": 2})
        assert _external_root(root, create=False) == root.resolve()
        root_link = Path(temp_dir) / "root-link"
        root_link.symlink_to(root, target_is_directory=True)
        try:
            _external_root(root_link)
        except CommonsError:
            pass
        else:
            raise AssertionError("symlink root was accepted")
        duplicate_hashes: set[str] = set()
        duplicate_digest = hashlib.sha256(image_bytes).hexdigest()
        _remember_unique_digest(duplicate_digest, duplicate_hashes)
        try:
            _remember_unique_digest(duplicate_digest, duplicate_hashes)
        except DownloadError as exc:
            assert "duplicate" in str(exc)
        else:
            raise AssertionError("duplicate image content was accepted")
        backfill_sequence = ("success", "fail", "success", "success")
        assert sum(1 for index, outcome in enumerate(backfill_sequence) if outcome == "success" and _is_backfilled(index, 3)) == 1

        tracked_spec_path = ROOT / "datasets" / "camera-coach" / "v1" / "sources" / "wikimedia-commons-v1.json"
        tracked_spec, _ = _load_spec(tracked_spec_path)
        quotas = _quota_counts(tracked_spec["categories"], 4)
        fixture_pages: dict[int, dict[str, Any]] = {}
        fixture_members: dict[str, dict[str, Any]] = {}
        next_pageid = 1
        duplicate_categories = [category["id"] for category, target in zip(tracked_spec["categories"], quotas) if target][:2]
        for category, target in zip(tracked_spec["categories"], quotas):
            if target <= 0:
                continue
            pageid = next_pageid
            next_pageid += 1
            title = f"File:fixture-{pageid}.jpg"
            fixture_members[str(category["title"])] = {"pageid": pageid, "ns": 6, "title": title}
            info = dict(base_page["imageinfo"][0])
            info.update({
                "descriptionurl": f"https://{API_HOST}/wiki/{title}",
                "thumburl": f"https://{MEDIA_HOST}/thumb/{pageid}.jpg",
                "url": f"https://{MEDIA_HOST}/{pageid}.jpg",
                "sha1": f"{pageid:040d}",
            })
            page = {"pageid": pageid, "ns": 6, "title": title, "imageinfo": [info]}
            fixture_pages[pageid] = page

        def e2e_opener(request: Request, *, timeout: float) -> _FakeResponse:
            parsed = parse_qs(urlsplit(request.full_url).query)
            if urlsplit(request.full_url).hostname == MEDIA_HOST:
                return _FakeResponse(image_bytes, url=request.full_url)
            action = parsed.get("action", [""])[0]
            if action != "query":
                raise AssertionError(f"unexpected fixture API action: {action}")
            if "prop" in parsed and parsed["prop"][0] == "categoryinfo":
                title = parsed["titles"][0]
                return _FakeResponse(_json_line({"query": {"pages": [{"pageid": 100, "ns": 14, "title": title, "categoryinfo": {"files": 1}}]}}).encode(), url=request.full_url)
            if "list" in parsed and parsed["list"][0] == "categorymembers":
                title = parsed["cmtitle"][0]
                member = fixture_members.get(title)
                return _FakeResponse(_json_line({"query": {"categorymembers": [member] if member else []}}).encode(), url=request.full_url)
            if "prop" in parsed and parsed["prop"][0] == "imageinfo":
                pageids = [int(value) for value in parsed["pageids"][0].split("|")]
                return _FakeResponse(_json_line({"query": {"pages": [fixture_pages[pageid] for pageid in pageids]}}).encode(), url=request.full_url)
            raise AssertionError("unexpected fixture API query")

        e2e_root = Path(temp_dir) / "e2e"
        fetch_status = _fetch(
            tracked_spec_path,
            e2e_root,
            4,
            metadata_only=False,
            opener=e2e_opener,
            sleeper=lambda seconds: None,
        )
        assert fetch_status == 2
        inventory_before = (e2e_root / str(tracked_spec["output"]["inventory"])).read_bytes()
        verify_status = _verify_local(tracked_spec_path, e2e_root)
        assert verify_status == 2
        assert (e2e_root / str(tracked_spec["output"]["inventory"])).read_bytes() == inventory_before
        e2e_quarantine = _read_jsonl(e2e_root / str(tracked_spec["output"]["quarantined"]))
        assert any(row.get("reason") == "duplicate image content" for row in e2e_quarantine)
        e2e_receipt = _read_json(e2e_root / str(tracked_spec["output"]["receipt"]))
        assert e2e_receipt.get("status") == "PARTIAL" and e2e_receipt.get("counts", {}).get("backfilled") == 0
        assert duplicate_categories
    print(
        "PASS fetch_commons self-test accepted_cc0 accepted_cc_by accepted_pd "
        "reject_sa_unknown_missing unsafe_host redirect malformed_api retry_429 "
        "maxlag resume stale_part bad_content_range hash_mismatch duplicate "
        "oversized non_image symlink unscaled_dimensions bucket_dimensions unicode_jsonl deterministic e2e_receipt_verify"
    )


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run the network-free adapter self-test")
    subparsers = parser.add_subparsers(dest="command")
    fetch = subparsers.add_parser("fetch", help="discover and optionally download fixed Commons categories")
    fetch.add_argument("--spec", type=Path, required=True)
    fetch.add_argument("--data-root", type=Path, required=True)
    fetch.add_argument("--limit", type=int, required=True)
    fetch.add_argument("--metadata-only", action="store_true")
    fetch.add_argument("--contact")
    verify = subparsers.add_parser("verify-local", help="verify downloaded Commons media and receipts")
    verify.add_argument("--spec", type=Path, required=True)
    verify.add_argument("--data-root", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _parser()
    args = parser.parse_args(argv)
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.command == "fetch":
            return _fetch(args.spec, args.data_root, args.limit, metadata_only=args.metadata_only, contact_override=args.contact)
        if args.command == "verify-local":
            return _verify_local(args.spec, args.data_root)
        parser.error("choose --self-test, fetch, or verify-local")
    except CommonsError as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
