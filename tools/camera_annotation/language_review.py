#!/usr/bin/env python3
"""Loopback assisted review with explicit, cached visual proposals."""
from __future__ import annotations

import argparse
import base64
import getpass
import fcntl
import hashlib
import json
import io
import math
import mimetypes
import os
from pathlib import Path
import re
import secrets
import sys
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from http.cookies import SimpleCookie
from urllib.parse import urlsplit, parse_qs, quote
import uuid
import webbrowser
import subprocess
import tempfile

from PIL import Image, ImageOps

from annotation_labels import DATA, LEGACY_DATA, local_media_path, sha256_file
from language_labels import (FLAGS, MODEL, output_schema, prompt, projection, summary,
    validate, validate_visual, visual_prompt)

COMMAND_ENDPOINT = "https://api.commandcode.ai/provider/v1/"
DERIVATIVE_RECIPE = "exif-transpose-rgb-jpeg-long-side-1024-quality-85-v1"
LOOKAHEAD = 6


def command_api(path, key="", payload=None):
    """Minimal Command Code OpenAI-compatible transport; never logs request text/key."""
    if path not in {"models", "chat/completions"}:
        raise ValueError("unsupported Command Code endpoint")
    if key and not re.fullmatch(r"[A-Za-z0-9_-]{12,200}", key):
        raise ValueError("invalid key characters")
    # The owner-selected Muse model rejects ZDR with cmd_zdr_no_providers.
    # Do not silently substitute a provider/model.
    config = ""
    if key:
        config += 'header = "Authorization: Bearer ' + key + '"\n'
    if payload is not None:
        config += 'header = "Content-Type: application/json"\n'
        config += "data-binary = " + json.dumps(json.dumps(payload)) + "\n"
    result = subprocess.run(
        ["curl", "--silent", "--show-error", "--proto", "=https", "--max-time", "70",
         "--max-filesize", "2097152", "--config", "-", "--write-out", "\n%{http_code}",
         COMMAND_ENDPOINT + path], input=config, text=True, capture_output=True, timeout=80,
    )
    if result.returncode:
        raise RuntimeError(f"command_transport_exit_{result.returncode}; billing_unknown")
    body, status = result.stdout.rsplit("\n", 1)
    if status != "200":
        try:
            error = json.loads(body).get("error", {})
            code = error.get("code") or error.get("type") or "provider_error"
        except (ValueError, AttributeError):
            code = "invalid_provider_error"
        raise RuntimeError(f"command_http_{status}_{str(code)[:80]}; billing_unknown")
    try:
        response = json.loads(body)
    except ValueError:
        raise RuntimeError("command_invalid_provider_json; billing_unknown") from None
    if not isinstance(response, dict):
        raise RuntimeError("command_invalid_provider_envelope; billing_unknown")
    return response


def rows(path):
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()] if path.exists() else []


def append(path, value):
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(value, ensure_ascii=False, allow_nan=False) + "\n")
        f.flush(); os.fsync(f.fileno())


def prepare_queue(path, pilot, temporal_root):
    if path.exists():
        items = rows(path)
    else:
        items = []
        for row in rows(pilot):
            items.append(dict(record_id=row["record_id"], kind="photo", media_path=row["image_path"],
                media_sha256=row["image_sha256"], title="Фотография", source=row, **FLAGS))
        for row in rows(temporal_root / "temporal.jsonl"):
            media = (temporal_root / row["video_relpath"]).resolve()
            if not media.is_relative_to(temporal_root.resolve()): raise ValueError("video path escape")
            items.append(dict(record_id=row["sequence_id"], kind="video", media_path=str(media),
                media_sha256=row["video_sha256"], title="Видео · " + row["source_family"], source=row, **FLAGS))
        if not items or len({r["record_id"] for r in items}) != len(items): raise ValueError("empty/duplicate queue")
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("x", encoding="utf-8") as f:
            for item in items: f.write(json.dumps(item, ensure_ascii=False) + "\n")
    frame_rows = {r["record_id"]: r for r in rows(temporal_root / "manifest.jsonl")}
    root = temporal_root.resolve()
    for item in items:
        item["media_path"] = str(local_media_path(item["media_path"]))
        if item["kind"] != "video": continue
        ids = [frame_id for frame_id in item.get("source", {}).get("source_frame_record_ids", []) if frame_id in frame_rows]
        chosen = list(dict.fromkeys(ids[i] for i in (0, len(ids)//2, len(ids)-1))) if ids else []
        visual_frames = []
        for frame_id in chosen:
            row = frame_rows[frame_id]
            frame = local_media_path(row["image_path"]).resolve()
            if not frame.is_relative_to(root): raise ValueError("video frame path escape")
            visual_frames.append(dict(path=str(frame), sha256=row["image_sha256"], timestamp_s=row.get("timestamp_s")))
        if not visual_frames: raise ValueError(f"video has no visual frames: {item['record_id']}")
        item["visual_frames"] = visual_frames
    return items


def jpeg_part(path, expected_sha256):
    if sha256_file(path) != expected_sha256: raise ValueError("Кадр для модели изменился: SHA не совпадает")
    with Image.open(path) as source:
        image = ImageOps.exif_transpose(source).convert("RGB")
        image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        buffer = io.BytesIO(); image.save(buffer, "JPEG", quality=85, optimize=True)
    data = buffer.getvalue()
    digest = hashlib.sha256(data).hexdigest()
    return dict(type="image_url", image_url=dict(url="data:image/jpeg;base64," + base64.b64encode(data).decode())), \
        dict(sha256=digest, bytes=len(data), width=image.width, height=image.height, recipe=DERIVATIVE_RECIPE)


class Review:
    def __init__(self, folder, queue, annotator, max_requests):
        self.folder = folder; self.items = {r["record_id"]: r for r in queue}
        self.annotator = annotator; self.max_requests = max_requests
        self.journal = folder / "opinions.jsonl"
        self.events = rows(self.journal)
        self.lock = threading.RLock(); self.condition = threading.Condition(self.lock)
        self.paid_lock = threading.Lock()  # ponytail: one paid request at a time for this single-user tool.
        self.key = ""; self.model = None
        self.request_count = sum(e["state"] in ("dispatch", "visual_dispatch") and e.get("provider") == "command-code" for e in self.events)
        drafts = {(e["state"], e.get("review_id") or e.get("job_id")) for e in self.events if e["state"] in ("dispatch", "visual_dispatch")}
        finished = {("dispatch", e.get("review_id")) for e in self.events if e["state"] in ("proposal", "error")}
        finished |= {("visual_dispatch", e.get("job_id")) for e in self.events if e["state"] in ("visual_proposal", "visual_error")}
        self.billing_unknown = bool(drafts - finished) or any(e.get("billing_unknown") and not
            (e.get("state") in ("visual_error", "error") and e.get("error") == "ValueError") for e in self.events)
        self.file_checks = {}
        self.pending = []; self.inflight = None; self.stopping = False
        self.worker = threading.Thread(target=self._worker, name="camera-visual-prefetch", daemon=True)
        self.worker.start()

    def event(self, state, **fields):
        value = dict(schema_id="camera-human-visual-review-v2", state=state,
            annotator_id=self.annotator, created_at=datetime.now(timezone.utc).isoformat(), **FLAGS, **fields)
        with self.lock:
            append(self.journal, value); self.events.append(value)
        return value

    def close(self):
        with self.condition:
            self.stopping = True; self.condition.notify_all()
        self.worker.join(timeout=2)

    def cache_key(self, rid):
        item = self.items[rid]
        identity = dict(record_id=rid, media_sha256=item["media_sha256"], model=MODEL,
            prompt_sha256=hashlib.sha256(visual_prompt().encode()).hexdigest(),
            schema_sha256=hashlib.sha256(json.dumps(output_schema(), sort_keys=True).encode()).hexdigest(),
            derivative_recipe=DERIVATIVE_RECIPE)
        return hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()

    def visual_event(self, rid):
        cache_key = self.cache_key(rid)
        for event in reversed(self.events):
            if (event.get("annotator_id") == self.annotator and event.get("record_id") == rid and
                    event.get("cache_key") == cache_key and event.get("state") in
                    ("visual_proposal", "visual_error", "visual_confirmed")):
                return event
        return None

    def visual_superseded(self, event):
        # Journal order, not response time, owns revisions across tabs. A slow
        # proposal may finish after the human has already started a correction.
        baseline = event
        for candidate in reversed(self.events):
            if (candidate.get("state") == "visual_dispatch" and
                    candidate.get("annotator_id") == self.annotator and
                    candidate.get("record_id") == event.get("record_id") and
                    candidate.get("job_id") == event.get("job_id") and
                    candidate.get("cache_key") == event.get("cache_key")):
                baseline = candidate
                break
        for newer in reversed(self.events):
            if newer is baseline: break
            if (newer.get("record_id") == event.get("record_id") and
                    newer.get("annotator_id") == self.annotator and
                    newer.get("state") in ("draft", "raw", "proposal", "confirmed")):
                return True
        return False

    def visual_status(self, rid):
        event = self.visual_event(rid)
        if event:
            if self.visual_superseded(event):
                return dict(status="error", job_id=event.get("job_id"), human_confirmed=False,
                    error="Для этого кадра уже есть более новое мнение. Проверьте перевод вашей правки.")
            status = "ready" if event["state"] in ("visual_proposal", "visual_confirmed") else "error"
            interpretation = dict(event["interpretation"]) if event.get("interpretation") else None
            if interpretation: interpretation["summary"] = summary(interpretation, visual=True)
            return dict(status=status, interpretation=interpretation, job_id=event.get("job_id"),
                error=event.get("public_error"), created_at=event.get("created_at"),
                human_confirmed=event["state"] == "visual_confirmed")
        if self.inflight == rid: return dict(status="processing")
        if rid in self.pending: return dict(status="queued")
        return dict(status="idle" if self.key else "needs_key")

    def media(self, rid):
        item = self.items[rid]; path = Path(item["media_path"])
        stat = path.stat(); identity = (stat.st_dev, stat.st_ino, stat.st_mtime_ns, stat.st_size)
        if self.file_checks.get(rid) != identity:
            if sha256_file(path) != item["media_sha256"]: raise ValueError("Исходный файл изменился: SHA не совпадает")
            self.file_checks[rid] = identity
        return path

    def connect(self, key):
        if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_-]{12,200}", key): raise ValueError("Неверный формат ключа")
        catalog = command_api("models", key)
        if MODEL not in {m.get("id") for m in catalog.get("data", []) if isinstance(m, dict)}:
            raise ValueError("Модель отсутствует в каталоге Command Code для этого ключа")
        self.key = key; self.model = MODEL
        self.event("connection", provider="command-code", endpoint=COMMAND_ENDPOINT,
            model=MODEL, zdr_enforced=False, max_requests=self.max_requests, key_persisted=False,
            monetary_usage_available=False)

    def prefetch(self, record_ids):
        if (not isinstance(record_ids, list) or not 1 <= len(record_ids) <= LOOKAHEAD or
                len(set(record_ids)) != len(record_ids) or any(rid not in self.items for rid in record_ids)):
            raise ValueError(f"Ожидалось до {LOOKAHEAD} уникальных элементов очереди")
        with self.condition:
            if not self.key: return dict(scheduled=0, reason="needs_key")
            if self.billing_unknown: return dict(scheduled=0, reason="billing_unknown")
            if self.request_count >= self.max_requests: return dict(scheduled=0, reason="limit")
            self.pending = [rid for rid in record_ids if rid != self.inflight and not self.visual_event(rid)]
            self.condition.notify()
            return dict(scheduled=len(self.pending))

    def _worker(self):
        while True:
            with self.condition:
                self.condition.wait_for(lambda: self.stopping or bool(self.pending))
                if self.stopping: return
                rid = self.pending.pop(0); self.inflight = rid
            try: self.analyze_visual(rid)
            finally:
                with self.condition:
                    self.inflight = None; self.condition.notify_all()

    def media_parts(self, rid):
        item = self.items[rid]; self.media(rid)
        sources = ([dict(path=item["media_path"], sha256=item["media_sha256"], timestamp_s=None)]
            if item["kind"] == "photo" else item["visual_frames"])
        parts = []; audit = []
        for source in sources:
            part, meta = jpeg_part(Path(source["path"]), source["sha256"])
            meta["source_sha256"] = source["sha256"]
            if source.get("timestamp_s") is not None: meta["timestamp_s"] = source["timestamp_s"]
            parts.append(part); audit.append(meta)
        intro = ("Assess this single photo." if item["kind"] == "photo" else
            "Assess these three video frames in chronological order: start, middle, end.")
        return [dict(type="text", text=json.dumps(dict(media_kind=item["kind"], instruction=intro), ensure_ascii=False)), *parts], audit

    def analyze_visual(self, rid):
        cache_key = self.cache_key(rid)
        with self.lock:
            if self.visual_event(rid) or not self.key or self.billing_unknown or self.request_count >= self.max_requests: return
        job_id = "visual-" + cache_key[:32]
        try:
            content, derivatives = self.media_parts(rid)
        except Exception as exc:
            # No dispatch has happened: report a local item failure without
            # consuming the request budget or terminating the sole worker.
            self.event("visual_error", record_id=rid, job_id=job_id, cache_key=cache_key,
                media_sha256=self.items[rid]["media_sha256"], media_kind=self.items[rid]["kind"],
                billing_unknown=False, paid=False, pixels_sent=False, error=type(exc).__name__,
                public_error="Медиа недоступно, повреждено или изменилось. Проверьте исходный файл; платный запрос не отправлен.",
                provider="command-code")
            return
        with self.paid_lock:
            with self.lock:
                if self.visual_event(rid) or self.billing_unknown or self.request_count >= self.max_requests: return
                self.event("visual_dispatch", record_id=rid, job_id=job_id, cache_key=cache_key,
                    media_sha256=self.items[rid]["media_sha256"], media_kind=self.items[rid]["kind"],
                    provider="command-code", endpoint=COMMAND_ENDPOINT, model=MODEL, zdr_enforced=False,
                    prompt_sha256=hashlib.sha256(visual_prompt().encode()).hexdigest(),
                    schema_sha256=hashlib.sha256(json.dumps(output_schema(), sort_keys=True).encode()).hexdigest(),
                    derivatives=derivatives, paid=True, pixels_sent=True)
                self.request_count += 1
            response = None
            try:
                response = command_api("chat/completions", self.key, dict(model=MODEL, max_tokens=6000, temperature=0,
                    response_format=dict(type="json_object"), messages=[dict(role="system", content=visual_prompt()),
                    dict(role="user", content=content)]))
                value = json.loads(response["choices"][0]["message"]["content"])
                validate_visual(value, self.items[rid]["kind"]); value["summary"] = summary(value, visual=True)
                usage = {k: v for k, v in (response.get("usage") or {}).items()
                    if k in {"prompt_tokens", "completion_tokens", "total_tokens"} and type(v) is int and v >= 0}
                self.event("visual_proposal", record_id=rid, job_id=job_id, cache_key=cache_key,
                    media_sha256=self.items[rid]["media_sha256"], media_kind=self.items[rid]["kind"],
                    interpretation=value, usage=usage, model=MODEL, provider="command-code",
                    response_id=response.get("id"), visual_assisted=True, pixels_sent=True)
            except Exception as exc:
                self.billing_unknown = response is None
                public = "Визуальный анализ остановлен: " + str(exc)[:180] + ". Автоповтора нет."
                self.event("visual_error", record_id=rid, job_id=job_id, cache_key=cache_key,
                    media_sha256=self.items[rid]["media_sha256"], media_kind=self.items[rid]["kind"],
                    billing_unknown=self.billing_unknown, error=type(exc).__name__, public_error=public,
                    usage=({k: v for k, v in (response.get("usage") or {}).items() if k in
                        {"prompt_tokens", "completion_tokens", "total_tokens"} and type(v) is int and v >= 0}
                        if response else {}), provider="command-code")

    def snapshot(self):
        with self.lock:
            latest = {}; latest_at = {}; visual_confirmed_at = {}
            for position, e in enumerate(self.events):
                if e.get("annotator_id") == self.annotator and e["state"] in ("draft", "raw", "confirmed"):
                    latest[e["record_id"]] = e; latest_at[e["record_id"]] = position
                elif e.get("annotator_id") == self.annotator and e["state"] == "proposal":
                    previous = latest.get(e["record_id"], {})
                    if previous.get("review_id") == e["review_id"]:
                        latest[e["record_id"]] = dict(previous, interpretation=e["interpretation"]); latest_at[e["record_id"]] = position
                elif e.get("annotator_id") == self.annotator and e["state"] == "visual_confirmed":
                    visual_confirmed_at[e["record_id"]] = position
            items = []
            for rid, item in self.items.items():
                e = latest.get(rid, {})
                latest_is_visual_confirmation = visual_confirmed_at.get(rid, -1) > latest_at.get(rid, -1)
                if latest_is_visual_confirmation: e = {}
                items.append(dict(record_id=rid, kind=item["kind"], title=item["title"],
                    media_url="/media/" + quote(rid, safe=""),
                    reviewed=e.get("state") in ("raw", "confirmed") or latest_is_visual_confirmation,
                    raw_text=e.get("raw_text", ""), interpretation=e.get("interpretation"),
                    review_id=e.get("review_id"), manual_updated_at=e.get("created_at"), visual=self.visual_status(rid)))
            return dict(items=items, total=len(items), remaining=sum(not i["reviewed"] for i in items),
                key_ready=bool(self.key), model=MODEL, provider="Command Code",
                request_count=self.request_count, max_requests=self.max_requests,
                prefetch_inflight=self.inflight, prefetch_queued=len(self.pending), billing_unknown=self.billing_unknown,
                session_id=hashlib.sha256((str(self.folder.resolve()) + self.annotator).encode()).hexdigest()[:20])

    def opinion(self, data):
        rid = data.get("record_id"); text = data.get("text")
        request_id = data.get("request_id")
        if rid not in self.items: raise ValueError("Неизвестный кадр")
        if not isinstance(text, str) or not 1 <= len(text.strip()) <= 6000: raise ValueError("Напишите отзыв длиной до 6000 символов")
        if not isinstance(request_id, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{8,80}", request_id): raise ValueError("Нет идентификатора запроса")
        at = data.get("viewed_at_s")
        if at is not None and (type(at) not in (int, float) or not math.isfinite(at) or not 0 <= at <= 86400): raise ValueError("Неверная позиция просмотра")
        self.media(rid)
        return dict(record_id=rid, raw_text=text, review_id=request_id,
            viewed_at_s=at, media_sha256=self.items[rid]["media_sha256"], media_kind=self.items[rid]["kind"])

    def interpret(self, data, paid=True):
        with self.condition:
            if paid: self.pending = []  # Human correction takes priority over speculative lookahead.
        if not self.paid_lock.acquire(timeout=85): raise ValueError("Фоновый анализ не завершился; повторная оплата не запущена")
        fields = None
        try:
            fields = self.opinion(data)
            fields["operation"] = "interpret" if paid else "raw"
            prior = [e for e in self.events if e.get("review_id") == fields["review_id"]]
            if prior:
                first = prior[0]
                if any(first.get(k) != fields[k] for k in ("record_id", "raw_text", "media_sha256", "viewed_at_s", "operation")):
                    raise ValueError("Идентификатор повторно использован для другого отзыва")
                last = prior[-1]
                if last["state"] == "proposal": return dict(review_id=fields["review_id"], interpretation=last["interpretation"], usage=last.get("usage"))
                if last["state"] in ("raw", "confirmed"): return dict(saved=True)
                return dict(error="Этот запрос уже записан; автоматического платного повтора нет", draft_saved=True)
            if not paid:
                self.event("raw", **fields, normalized=False)
                return dict(saved=True)
            # Write the raw opinion BEFORE any model call, including failed configuration.
            self.event("draft", **fields, paid=False)
            if not self.key: return dict(error="Подключите ключ Command Code в настройках или сохраните только текст", draft_saved=True)
            if self.billing_unknown: return dict(error="Предыдущий платный запрос имеет неизвестную стоимость; нужна сверка журнала", draft_saved=True)
            if self.request_count >= self.max_requests:
                return dict(error="Достигнут лимит запросов этой сессии. Можно сохранить только текст", draft_saved=True)
            content, derivatives = self.media_parts(fields["record_id"])
            self.event("dispatch", **fields, paid=True, provider="command-code", endpoint=COMMAND_ENDPOINT,
                model=MODEL, zdr_enforced=False, derivatives=derivatives, pixels_sent=True,
                prompt_sha256=hashlib.sha256(prompt().encode()).hexdigest(),
                schema_sha256=hashlib.sha256(json.dumps(output_schema(), sort_keys=True).encode()).hexdigest())
            self.request_count += 1
            try:
                # Muse exposes its answer after a reasoning phase; 2,200 ends at that phase.
                response = command_api("chat/completions", self.key, dict(model=MODEL, max_tokens=6000, temperature=0,
                    response_format=dict(type="json_object"),
                    messages=[dict(role="system", content=prompt()), dict(role="user", content=[
                        dict(type="text", text=json.dumps(dict(media_kind=fields["media_kind"],
                            human_review=fields["raw_text"]), ensure_ascii=False)), *content])]))
                value = json.loads(response["choices"][0]["message"]["content"])
                validate(value, fields["raw_text"], fields["media_kind"])
                value["summary"] = summary(value)
                usage = {k: v for k, v in (response.get("usage") or {}).items()
                    if k in {"prompt_tokens", "completion_tokens", "total_tokens"} and type(v) is int and v >= 0}
                self.event("proposal", **fields, interpretation=value, usage=usage, model=MODEL,
                    provider="command-code", response_id=response.get("id"), language_assisted=True, pixels_sent=True)
                return dict(review_id=fields["review_id"], interpretation=value, usage=usage)
            except Exception as exc:
                self.billing_unknown = True
                self.event("error", **fields, billing_unknown=True, error=type(exc).__name__, provider="command-code")
                return dict(error="Перевод не принят: " + str(exc)[:250] + ". Ваш исходный текст сохранён; повтор не запускался.", draft_saved=True)
        finally:
            self.paid_lock.release()

    def confirm(self, data):
        with self.lock:
            rid = data.get("record_id"); review_id = data.get("review_id")
            matches = [e for e in self.events if e.get("review_id") == review_id and e.get("annotator_id") == self.annotator]
            if not matches: raise ValueError("Не найден перевод")
            last = matches[-1]
            if last.get("record_id") != rid or last.get("raw_text") != data.get("text"): raise ValueError("Отзыв изменён: сначала получите новый перевод")
            if last["state"] == "confirmed": return dict(saved=True)
            if last["state"] != "proposal": raise ValueError("Нет принятого перевода")
            newer = [e for e in self.events if e.get("record_id") == rid and e.get("annotator_id") == self.annotator and e["state"] in ("draft", "raw", "confirmed")]
            if newer and newer[-1]["review_id"] != review_id: raise ValueError("Для этого кадра уже есть более новое мнение")
            self.media(rid)
            value = dict(last["interpretation"]); value.setdefault("spatial_requests", [])
            validate({k: v for k, v in value.items() if k != "summary"}, last["raw_text"], last["media_kind"])
            self.event("confirmed", record_id=rid, review_id=review_id, raw_text=last["raw_text"],
                media_sha256=last["media_sha256"], media_kind=last["media_kind"], viewed_at_s=last["viewed_at_s"],
                interpretation=value, contract_projection=projection(value, last["media_kind"]),
                human_confirmed_translation=True, language_assisted=True, pixels_sent=True)
            return dict(saved=True)

    def confirm_visual(self, data):
        rid = data.get("record_id"); job_id = data.get("job_id")
        if rid not in self.items or not isinstance(job_id, str): raise ValueError("Не найден визуальный разбор")
        with self.lock:
            event = self.visual_event(rid)
            if not event or event.get("job_id") != job_id or event["state"] not in ("visual_proposal", "visual_confirmed"):
                raise ValueError("Визуальный разбор устарел или ещё не готов")
            if self.visual_superseded(event):
                raise ValueError("Для этого кадра уже есть более новое мнение. Проверьте перевод вашей правки.")
            if event["state"] == "visual_confirmed": return dict(saved=True)
            self.media(rid)
            value = event["interpretation"]
            validate_visual({k: v for k, v in value.items() if k != "summary"}, self.items[rid]["kind"])
            self.event("visual_confirmed", record_id=rid, job_id=job_id, cache_key=event["cache_key"],
                media_sha256=self.items[rid]["media_sha256"], media_kind=self.items[rid]["kind"],
                interpretation=value, contract_projection=projection(value, self.items[rid]["kind"]),
                human_confirmed_assessment=True, visual_assisted=True, pixels_sent=True)
            return dict(saved=True)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args): pass  # Never log cookies, text, keys or capability URLs.

    def send(self, status, body=b"", typ="application/json; charset=utf-8", extra=None):
        if not isinstance(body, bytes): body = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status); self.send_header("Content-Type", typ)
        self.send_header("Content-Length", str(len(body))); self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff"); self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self'; media-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'")
        for key, value in (extra or {}).items(): self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD": self.wfile.write(body)

    def authorized(self):
        if self.headers.get("Host") != urlsplit(self.server.origin).netloc: return False
        if self.headers.get("Origin", self.server.origin) != self.server.origin: return False
        if self.headers.get("Sec-Fetch-Site", "same-origin") not in ("same-origin", "none"): return False
        cookie = SimpleCookie()
        try: cookie.load(self.headers.get("Cookie", ""))
        except Exception: return False
        return "review_session" in cookie and secrets.compare_digest(cookie["review_session"].value, self.server.token)

    def do_GET(self):
        url = urlsplit(self.path)
        if url.path == "/" and self.headers.get("Host") == urlsplit(self.server.origin).netloc:
            token = parse_qs(url.query).get("session", [""])[0]
            if secrets.compare_digest(token, self.server.token):
                self.send(303, extra={"Location": "/", "Set-Cookie": f"review_session={token}; HttpOnly; SameSite=Strict; Path=/"}); return
        if not self.authorized(): self.send(403, dict(error="Откройте страницу через ярлык разметчика")); return
        try:
            if url.path == "/": self.send(200, Path(__file__).with_name("language_review.html").read_bytes(), "text/html; charset=utf-8")
            elif url.path == "/help": self.send(200, Path(__file__).with_name("README_REVIEW.md").read_bytes(), "text/plain; charset=utf-8")
            elif url.path == "/api/queue": self.send(200, dict(self.server.review.snapshot(), csrf_token=self.server.csrf))
            elif url.path.startswith("/media/"):
                from urllib.parse import unquote
                self.serve_media(unquote(url.path[len("/media/"):]))
            else: self.send(404, dict(error="Не найдено"))
        except (ValueError, KeyError, OSError) as exc: self.send(400, dict(error=str(exc)[:200]))

    def serve_media(self, rid):
        path = self.server.review.media(rid); size = path.stat().st_size
        start, end = 0, size-1; status = 200
        header = self.headers.get("Range")
        if header:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", header)
            if not match or not any(match.groups()): self.send(416, extra={"Content-Range": f"bytes */{size}"}); return
            left, right = match.groups()
            if left: start = int(left); end = min(int(right), end) if right else end
            else: start = max(0, size-int(right))
            if start > end or start >= size: self.send(416, extra={"Content-Range": f"bytes */{size}"}); return
            status = 206
        self.send_response(status); self.send_header("Content-Type", mimetypes.guess_type(path.name)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(end-start+1)); self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "private, no-store"); self.send_header("X-Content-Type-Options", "nosniff")
        if status == 206: self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        try:
            with path.open("rb") as f:
                f.seek(start); remaining = end-start+1
                while remaining:
                    data = f.read(min(65536, remaining))
                    if not data: break
                    self.wfile.write(data); remaining -= len(data)
        except (BrokenPipeError, ConnectionResetError): pass

    def do_POST(self):
        if not self.authorized() or not secrets.compare_digest(self.headers.get("X-CSRF-Token", ""), self.server.csrf):
            self.send(403, dict(error="Недопустимый источник запроса")); return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 32768: raise ValueError("Слишком большой или пустой запрос")
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict): raise ValueError("Ожидался объект")
            state = self.server.review
            if self.path == "/api/key":
                if not state.paid_lock.acquire(blocking=False): raise ValueError("Дождитесь текущего перевода")
                try: state.connect(data.get("key"))
                finally: state.paid_lock.release()
                result = dict(key_ready=True, request_count=state.request_count, max_requests=state.max_requests)
            elif self.path == "/api/prefetch": result = state.prefetch(data.get("record_ids"))
            elif self.path == "/api/interpret": result = state.interpret(data)
            elif self.path == "/api/raw": result = state.interpret(data, paid=False)
            elif self.path == "/api/confirm": result = state.confirm(data)
            elif self.path == "/api/confirm-visual": result = state.confirm_visual(data)
            else: self.send(404, dict(error="Не найдено")); return
            self.send(200, result)
        except Exception as exc:
            self.send(400, dict(error=str(exc)[:250]))


def self_check():
    assert local_media_path(LEGACY_DATA / "annotation/photo.jpg") == DATA / "annotation/photo.jpg"
    assert local_media_path("/tmp/unrelated.jpg") == Path("/tmp/unrelated.jpg")
    with tempfile.TemporaryDirectory(prefix="camera-visual-review-") as directory:
        root = Path(directory); image_path = root / "photo.png"
        Image.new("RGB", (1600, 900), (80, 120, 160)).save(image_path)
        digest = sha256_file(image_path)
        queue = [dict(record_id="photo-1", kind="photo", media_path=str(image_path), media_sha256=digest,
            title="Фото", source={}, **FLAGS)]
        review = Review(root, queue, "self-check", 3)
        try:
            content, audit = review.media_parts("photo-1")
            assert len(content) == 2 and len(audit) == 1 and audit[0]["width"] == 1024
            assert audit[0]["bytes"] < image_path.stat().st_size + 100000
            assert review.prefetch(["photo-1"])["reason"] == "needs_key"
            try: review.prefetch(["photo-1"] * 2)
            except ValueError: pass
            else: raise AssertionError("duplicate prefetch admitted")
        finally: review.close()
    print("LANGUAGE REVIEW SELF-CHECK PASS: derivative, allowlist, lookahead and worker shutdown")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--folder", type=Path, default=DATA / "annotation/language-review-20260915")
    p.add_argument("--pilot", type=Path, default=DATA / "annotation/pilot-20260914-v4/pilot.jsonl")
    p.add_argument("--temporal-root", type=Path, default=DATA / "Datasets/camera-coach/colab_package_v2_20260914")
    p.add_argument("--annotator-id", default=getpass.getuser()); p.add_argument("--max-requests", type=int, default=100)
    p.add_argument("--ask-key", action="store_true"); p.add_argument("--no-browser", action="store_true")
    p.add_argument("--self-check", action="store_true")
    args = p.parse_args()
    if args.self_check: self_check(); return
    if not 1 <= args.max_requests <= 1000: p.error("max-requests must be 1..1000")
    args.folder.mkdir(parents=True, exist_ok=True)
    lease = os.open(args.folder / "server.lock", os.O_RDWR | os.O_CREAT, 0o600)
    try: fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        url = os.read(lease, 1024).decode().strip(); os.close(lease)
        if re.fullmatch(r"http://127\.0\.0\.1:\d+/\?session=[A-Za-z0-9_-]+", url):
            print("Разметчик уже работает:", url)
            if not args.no_browser: webbrowser.open(url)
        else: print("Разметчик уже запускается. Повторите открытие через несколько секунд.")
        return
    queue = prepare_queue(args.folder / "queue.jsonl", args.pilot, args.temporal_root)
    state = Review(args.folder, queue, args.annotator_id, args.max_requests)
    key = os.environ.get("CMD_API_KEY") or (getpass.getpass("Command Code key (hidden, not saved): ") if args.ask_key else "")
    if key: state.connect(key)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.review = state; server.token = secrets.token_urlsafe(32); server.csrf = secrets.token_urlsafe(32)
    server.origin = f"http://127.0.0.1:{server.server_port}"
    url = server.origin + "/?session=" + server.token
    os.ftruncate(lease, 0); os.write(lease, url.encode()); os.fsync(lease)
    print("Camera Coach:", url, "\nReviews:", state.journal, flush=True)
    if not args.no_browser: webbrowser.open(url)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: state.close(); server.server_close(); os.close(lease)


if __name__ == "__main__": main()
