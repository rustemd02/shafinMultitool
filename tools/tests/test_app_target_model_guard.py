"""Release-integrity guard: no untracked model artifact may ride into the app.

Found for real on 2026-09-13: a 4.6 MB research-only `.mlpackage`
(`SETCompositionNet-Stage2-Local`) sat inside the synchronized app folder,
untracked by git, and was therefore automatically a member of the app target —
i.e. it would ship in the stored build. The owner's rule is explicit: credits do
not clear research-only weights for the App Store.

The app target uses an Xcode 16 `PBXFileSystemSynchronizedRootGroup`, which adds
every file under the folder unless it is listed in `membershipExceptions`. So the
guard is: every untracked model artifact inside the app folder must appear in
that exception list, otherwise the build silently depends on a stray file.

Run: python3 -m pytest tools/tests/test_app_target_model_guard.py -q
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
APP_DIR = REPO_ROOT / "shafinMultitool"
PBXPROJ = REPO_ROOT / "shafinMultitool.xcodeproj/project.pbxproj"


def _untracked_model_artifacts() -> list[Path]:
    """Untracked (and not ignored) .mlpackage/.mlmodel bundles inside the app folder."""
    result = subprocess.run(
        ["git", "ls-files", "--others", "--exclude-standard", "--", "shafinMultitool"],
        cwd=REPO_ROOT, capture_output=True, text=True, check=True,
    )
    artifacts = []
    for line in result.stdout.splitlines():
        path = REPO_ROOT / line
        if not path.exists():
            continue
        if path.suffix in {".mlpackage", ".mlmodel"} or any(
                part.endswith((".mlpackage", ".mlmodel")) for part in path.parts):
            artifacts.append(path)
    return artifacts


def _target_membership_exceptions() -> list[str]:
    text = PBXPROJ.read_text(encoding="utf-8")
    block = re.search(r"membershipExceptions = \((.*?)\);", text, re.S)
    assert block, "the app target no longer declares membershipExceptions — the guard needs updating"
    return [item.strip().rstrip(",") for item in block.group(1).strip().splitlines() if item.strip()]


def test_every_untracked_model_artifact_is_excluded_from_the_app_target():
    excluded = _target_membership_exceptions()
    offenders = []
    for artifact in _untracked_model_artifacts():
        relative = artifact.relative_to(APP_DIR).as_posix()
        # an exception may name the bundle itself or a parent folder
        covered = any(relative == entry or relative.startswith(entry + "/") for entry in excluded)
        if not covered:
            offenders.append(relative)
    assert not offenders, (
        "these untracked model artifacts are members of the app target and would ship: "
        f"{offenders} — add them to membershipExceptions or remove them from the folder"
    )


def test_the_guard_actually_detects_a_missing_exception():
    """Negative control: an artifact that is not listed must be reported."""
    excluded = _target_membership_exceptions()
    fake = "Multitool2Module/Models/CoreML/SomeResearchModel.mlpackage"
    covered = any(fake == entry or fake.startswith(entry + "/") for entry in excluded)
    assert not covered, "the control artifact must not be covered, or the guard proves nothing"


def test_the_known_research_artifact_is_explicitly_excluded():
    """The artifact found on 2026-09-13 must stay excluded: it is not rights-cleared."""
    excluded = _target_membership_exceptions()
    assert "Multitool2Module/Models/CoreML/SETCompositionNet-Stage2-Local.mlpackage" in excluded


def test_tracked_production_models_are_not_excluded():
    """Excluding a shipped model by accident would silently disable it."""
    excluded = _target_membership_exceptions()
    tracked = subprocess.run(
        ["git", "ls-files", "--", "shafinMultitool/Multitool2Module/Models/CoreML"],
        cwd=REPO_ROOT, capture_output=True, text=True, check=True,
    ).stdout.splitlines()
    production = {
        Path(line).name.split(".")[0]
        for line in tracked
        if line.endswith((".mlpackage", ".mlmodel")) or ".mlpackage/" in line
    }
    for name in sorted(production):
        relative = f"Multitool2Module/Models/CoreML/{name}.mlpackage"
        assert relative not in excluded, f"{relative} is tracked production weights but is excluded from the target"
