"""The owner packets must not send the owner to a path that does not exist, or to the wrong one.

`evidence-release/OWNER-PACKET.md` and `owner-decision-form.md` are the artifacts the
owner actually acts on: they name files to open, commands to run and outputs to
expect. A stale or ambiguous reference there costs the owner a detour, and an
ambiguous one can send them to the wrong corpus — the repository contains three
different `rights-manifest.jsonl` files, only one of which the rights chain writes.

So this suite checks three things:

* every artifact path cited in backticks either exists (in the repo, by basename, or
  under the home data root) or is on the explicit list of outputs the owner's own
  steps will create;
* a bare filename is not used when the same filename exists in more than one place
  (the ambiguity that was fixed here for `rights-manifest.jsonl`);
* the expected-output list stays honest: a path on it must not exist yet.
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
PACKETS = REPO_ROOT / "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release"
PACKET_FILES = ("OWNER-PACKET.md", "owner-decision-form.md")
CITED = re.compile(r"`([^`]+\.(?:md|json|jsonl|py|ipynb|sh|yaml|plist))`")

# Paths the owner's own steps create: they must not exist yet, and naming them is the point.
EXPECTED_OUTPUTS = {
    "accepted-rights-receipt.jsonl",
    "audit-decisions.json",
    "labels-owner.jsonl",
    "receipts/commons-source-receipt.json",
    "result-manifest.json",
}


def _listed_files() -> list[str]:
    return subprocess.run(["rg", "--files"], cwd=REPO_ROOT, capture_output=True, text=True).stdout.split()


def _cited_paths(name: str) -> list[str]:
    text = (PACKETS / name).read_text(encoding="utf-8")
    return sorted({match for match in CITED.findall(text)
                   if not any(placeholder in match for placeholder in "<*…")})


def _exists(path: str, listed: list[str]) -> bool:
    if path.startswith("~/"):
        return (Path.home() / path[2:]).exists()
    if (REPO_ROOT / path).exists():
        return True
    basename = Path(path).name
    return any(Path(item).name == basename for item in listed)


@pytest.mark.parametrize("name", PACKET_FILES)
def test_every_cited_path_resolves_or_is_a_known_output(name: str):
    listed = _listed_files()
    unresolved = [path for path in _cited_paths(name)
                  if not _exists(path, listed)
                  and path not in EXPECTED_OUTPUTS
                  and Path(path).name not in EXPECTED_OUTPUTS]
    assert unresolved == [], f"{name} cites paths that resolve nowhere: {unresolved}"


@pytest.mark.parametrize("name", PACKET_FILES)
def test_an_ambiguously_named_file_is_cited_with_its_directory(name: str):
    """A bare name is fine only while it is unique in the repository."""
    listed = [item for item in _listed_files()]
    for path in _cited_paths(name):
        if "/" in path:
            continue
        occurrences = [item for item in listed if Path(item).name == path]
        assert len(occurrences) <= 1, (
            f"{name} cites {path!r} bare, but {len(occurrences)} files share that name: "
            f"{occurrences}")


def test_the_expected_outputs_really_do_not_exist_yet():
    stub = []

    def _fake_exists(self):  # noqa: ANN001
        return False

    for name in EXPECTED_OUTPUTS:
        if (REPO_ROOT / name).exists():
            stub.append(name)
    assert stub == [], f"these are on the expected-output list but already exist: {stub}"


def test_the_rights_chain_writes_the_camera_coach_manifest():
    """The packet points at the manifest the toolkit actually defaults to."""
    tool = (REPO_ROOT / "tools/datasets/build_split_groups.py").read_text(encoding="utf-8")
    assert 'DEFAULT_RIGHTS_MANIFEST = REPO_ROOT / "datasets/camera-coach/v1/rights-manifest.jsonl"' in tool
    packet = (PACKETS / "OWNER-PACKET.md").read_text(encoding="utf-8")
    assert "`datasets/camera-coach/v1/rights-manifest.jsonl`" in packet
