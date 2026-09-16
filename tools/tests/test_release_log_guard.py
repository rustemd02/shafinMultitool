"""Detector tests for the release log-leak check.

The unguarded writes this tool was built to find have since been fixed, so the
check passes on the real tree. These tests cover the *detector* — including the
paths that would let it pass without looking at anything — so the check cannot
rot into a silent pass.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools/release/check_release_logs.py"


def _load():
    spec = importlib.util.spec_from_file_location("release_logs", TOOL)
    module = importlib.util.module_from_spec(spec)
    sys.modules["release_logs"] = module
    spec.loader.exec_module(module)
    return module


def _write(tmp_path: Path, body: str) -> Path:
    root = tmp_path / "swift"
    root.mkdir(exist_ok=True)
    (root / "Sample.swift").write_text(body, encoding="utf-8")
    return root


def test_reports_unguarded_print_of_user_content(tmp_path: Path):
    tool = _load()
    root = _write(tmp_path, 'func f(_ description: String) {\n    print("parsing \\(description)")\n}\n')
    leaks = tool.find_leaks(root)
    assert len(leaks) == 1 and leaks[0]["line"] == 2


def test_ignores_the_same_print_inside_debug(tmp_path: Path):
    tool = _load()
    root = _write(tmp_path, '#if DEBUG\nprint("parsing \\(description)")\n#endif\n')
    assert tool.find_leaks(root) == []


def test_ignores_prints_without_user_content(tmp_path: Path):
    tool = _load()
    root = _write(tmp_path, 'print("token=\\(token.uuidString)")\n')
    assert tool.find_leaks(root) == []


def test_explicit_allowlist_marker_is_honoured(tmp_path: Path):
    tool = _load()
    root = _write(tmp_path, 'print("text=\\(text)")  // RELEASE-LOG-OK: diagnostic id only\n')
    assert tool.find_leaks(root) == []


def test_detects_dialogue_and_source_text(tmp_path: Path):
    tool = _load()
    root = _write(tmp_path,
                  'print("dialogue=\\(action.dialogue ?? "nil")")\n'
                  'print("source=\\(action.sourceText ?? "nil")")\n')
    assert len(tool.find_leaks(root)) == 2


def test_the_guard_is_not_vacuous_on_the_real_tree_shape(tmp_path: Path):
    """A nested #if must not hide a line that is outside the debug region."""
    tool = _load()
    root = _write(tmp_path,
                  '#if canImport(X)\n#endif\n'
                  'print("leaked \\(description)")\n'
                  '#if DEBUG\nprint("fine \\(description)")\n#endif\n')
    leaks = tool.find_leaks(root)
    assert [leak["line"] for leak in leaks] == [3]


def test_flags_camel_case_text_variables(tmp_path: Path):
    """`matchedText`/`originalText` slipped past an earlier \btext\b-only rule.

    Found by inspecting the built Release binary: the tag was gone but a
    `matchedText` write was still compiled in.
    """
    tool = _load()
    root = _write(tmp_path,
                  'print("matched=\(reference.matchedText)")\n'
                  'print("original=\(originalText)")\n'
                  'print("model=\(generatedText)")\n')
    assert len(tool.find_leaks(root)) == 3


def test_does_not_flag_the_word_context(tmp_path: Path):
    """`context` ends in "text" but carries no user content."""
    tool = _load()
    root = _write(tmp_path,
                  'print("stale bundle context write suppressed token=\(parseToken)")\n'
                  'print("loaded separate context for \(kind)")\n')
    assert tool.find_leaks(root) == []


def test_flags_keywords_taken_from_the_user_text(tmp_path: Path):
    tool = _load()
    root = _write(tmp_path, 'print("keyword=\(keyword) type=\(type.rawValue)")\n')
    assert len(tool.find_leaks(root)) == 1


# ------------------------------------------------------- scanning nothing
def test_an_empty_tree_fails_closed_rather_than_reporting_clean(tmp_path: Path):
    """A scan of nothing must not read as "no leaks"."""
    empty = tmp_path / "empty"
    empty.mkdir()
    result = subprocess.run([sys.executable, str(TOOL), "--root", str(empty)],
                            capture_output=True, text=True)
    assert result.returncode == 2, result.stdout
    assert "FAIL CLOSED" in result.stdout


def test_a_missing_root_fails_closed(tmp_path: Path):
    result = subprocess.run([sys.executable, str(TOOL), "--root", str(tmp_path / "nope")],
                            capture_output=True, text=True)
    assert result.returncode == 2, result.stdout
    assert "FAIL CLOSED" in result.stdout


def test_the_pass_message_states_how_many_files_were_scanned(tmp_path: Path):
    """A green result has to show it looked at something."""
    root = _write(tmp_path, 'print("token=\(token.uuidString)")\n')
    result = subprocess.run([sys.executable, str(TOOL), "--root", str(root)],
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stdout
    assert "1 Swift files scanned" in result.stdout


def test_the_json_report_records_the_scan_size(tmp_path: Path):
    root = _write(tmp_path, 'print("leaked \(description)")\n')
    out = tmp_path / "report.json"
    result = subprocess.run([sys.executable, str(TOOL), "--root", str(root), "--json-out", str(out)],
                            capture_output=True, text=True)
    assert result.returncode == 1, result.stdout
    payload = json.loads(out.read_text(encoding="utf-8"))
    assert payload["scanned"] == 1 and len(payload["leaks"]) == 1
