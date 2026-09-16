#!/usr/bin/env python3
"""Release log-leak check: user content must not reach the system log.

S07 (2026-09-13) flagged unguarded `print` calls in the Scene lane. On review the
finding was real and wider than reported: eleven calls outside any `#if DEBUG`
block interpolated user-authored content — scene text, action dialogue, source
and fallback text. Those call sites were then fixed, so the check passes on the
tree today; this tool exists to keep them from coming back.

It exits non-zero when such a call site exists, so it cannot be mistaken for a
green gate; the detector itself is covered by a test so the check cannot silently
rot. A scan that finds no Swift files at all also fails closed: a scan of nothing
is not a clean scan.

A call site may be accepted explicitly by putting `RELEASE-LOG-OK:` on the same
line or the line above, with a reason — an allowlist that is visible in review
rather than implicit.

Usage
    python3 tools/release/check_release_logs.py [--json-out path] [--root dir]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SWIFT_ROOT = REPO_ROOT / "shafinMultitool"

# Variables that carry content authored by the user (or a model echoing it).
# Enumerated explicitly on purpose: a suffix rule like "…Text" also matches
# `context`, which carries no user content, and an earlier `\btext\b`-only rule
# missed `matchedText` (a leak the Release-binary inspection caught). When a new
# content-bearing variable appears, add it here; the binary check in
# `tools/tests/` note below is the backstop for names nobody listed yet.
USER_CONTENT_TOKENS = (
    "description", "scriptText", "sceneDescription", "promptText", "userText",
    "sourceText", "fallbackText", "dialogue", "matchedText", "originalText",
    "generatedText", "rawText", "inputText", "outputText", "keyword", r"\btext\b",
)
_PRINT = re.compile(r"\bprint\(|\bdebugPrint\(|\bos_log\(|\bNSLog\(")
_ALLOW = "RELEASE-LOG-OK:"


def _inside_debug(lines: list[str]) -> list[bool]:
    """True for each line that sits inside any #if ... #endif region."""
    depth = 0
    flags = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("#if"):
            depth += 1
        elif stripped.startswith("#endif"):
            depth = max(0, depth - 1)
        flags.append(depth > 0)
    return flags


def swift_files(root: Path = SWIFT_ROOT) -> list[Path]:
    return sorted(root.rglob("*.swift"))


def find_leaks(root: Path = SWIFT_ROOT, files: list[Path] | None = None) -> list[dict]:
    pattern = re.compile("|".join(USER_CONTENT_TOKENS))
    leaks = []
    for path in swift_files(root) if files is None else files:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        guarded = _inside_debug(lines)
        for index, line in enumerate(lines):
            if not _PRINT.search(line):
                continue
            if pattern.search(line) is None:
                continue
            if guarded[index]:
                continue
            if _ALLOW in line or (index > 0 and _ALLOW in lines[index - 1]):
                continue
            try:
                display = str(path.relative_to(REPO_ROOT))
            except ValueError:
                display = str(path)
            leaks.append({
                "file": display,
                "line": index + 1,
                "snippet": line.strip()[:160],
            })
    return leaks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--root", type=Path, default=SWIFT_ROOT,
                        help="Swift source root to scan (default: the app sources)")
    args = parser.parse_args()

    files = swift_files(args.root)
    if not files:
        print(f"FAIL CLOSED: no Swift sources found under {args.root}")
        print("A scan of nothing is not a clean scan; point --root at the app sources.")
        return 2

    leaks = find_leaks(args.root, files=files)
    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(
            json.dumps({"scanned": len(files), "leaks": leaks}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8")
    if not leaks:
        print(f"PASS: no unguarded release log writes of user content ({len(files)} Swift files scanned)")
        return 0
    print(f"FAIL: {len(leaks)} unguarded release log write(s) of user content")
    for leak in leaks:
        print(f"  - {leak['file']}:{leak['line']}  {leak['snippet']}")
    print("\nGate them behind #if DEBUG, drop the interpolated content, or mark the line "
          f"with `{_ALLOW} <reason>` if the write is deliberate.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
