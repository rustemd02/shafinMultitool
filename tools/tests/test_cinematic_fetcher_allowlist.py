"""The licence allowlist of the cinematic-frame fetcher must stay enforced.

`tools/dataset/fetch_cinematic_frames.py` acquires frames from a fixed registry of
freely-licensed films. The registry is only a control if it is also the *only*
thing the CLI accepts: if `--source` ever became free-form, an unvetted film could
enter the corpus and carry whatever licence the operator typed.

These tests run offline. The declared-source case is pointed at a nonexistent
extractor so it fails before any network use.

Run: python3 -m pytest tools/tests/test_cinematic_fetcher_allowlist.py -q
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FETCHER = REPO_ROOT / "tools/dataset/fetch_cinematic_frames.py"
AVA = REPO_ROOT / "tools/dataset/fetch_ava_human_ratings.py"


def _load():
    spec = importlib.util.spec_from_file_location("fetch_cinematic_frames", FETCHER)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules["fetch_cinematic_frames"] = module
    spec.loader.exec_module(module)
    return module


fetcher = _load()


def run(script: Path, *args: str) -> tuple[int, str]:
    result = subprocess.run([sys.executable, str(script), *args],
                            cwd=REPO_ROOT, capture_output=True, text=True, timeout=300)
    return result.returncode, result.stdout + result.stderr


def test_every_registered_source_declares_a_licence():
    """A source without a licence field could not be attributed later."""
    assert fetcher.SOURCE_REGISTRY, "the registry is empty, so the lane has no sources"
    missing = sorted(key for key, entry in fetcher.SOURCE_REGISTRY.items()
                     if not str(entry.get("license", "")).strip())
    assert missing == [], f"registered sources without a licence: {missing}"


def test_the_registry_is_not_trivially_small():
    assert len(fetcher.SOURCE_REGISTRY) >= 3, sorted(fetcher.SOURCE_REGISTRY)


def test_an_unregistered_source_is_rejected_by_the_cli(tmp_path: Path):
    code, output = run(FETCHER, "--out", str(tmp_path / "out"), "--source", "not-a-real-film")
    assert code == 2, f"an unvetted source was not rejected as a usage error (exit {code}): {output[-300:]}"
    assert "invalid choice" in output


@pytest.mark.parametrize("source", ["big_buck_bunny", "tears_of_steel"])
def test_a_registered_source_is_accepted_as_a_choice(tmp_path: Path, source: str):
    """Not a usage error: the failure is the missing extractor, which comes later.

    This is the positive control for the test above — if every source were rejected,
    the allowlist check would pass while making the fetcher unusable.
    """
    code, output = run(FETCHER, "--out", str(tmp_path / "out"), "--source", source,
                       "--extractor", str(tmp_path / "no-such-extractor"))
    assert code != 2, output[-300:]
    assert "invalid choice" not in output


def test_the_ava_lane_rejects_an_unknown_split(tmp_path: Path):
    code, output = run(AVA, "--out", str(tmp_path / "ava"), "--split", "secret-test-set")
    assert code == 2, output[-300:]
    assert "invalid choice" in output
