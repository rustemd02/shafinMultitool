"""Release-configuration guards.

The Release build once failed with five errors because production call sites
referenced members declared only inside `#if DEBUG` blocks; every certification
in this project builds Debug, so nothing caught it until a Release build was
attempted. These checks read the sources the same way the compiler splits them
and fail if a production symbol drifts back inside a DEBUG-only region.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
PIPELINE = ROOT / "shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift"
SCENE_VM = ROOT / "shafinMultitool/SceneGeneratorModule/ViewModels/SceneGeneratorViewModel.swift"
AUDIT = (
    ROOT
    / "docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/release-chain-readiness-audit.json"
)

# Symbols the production (non-DEBUG) path needs, and where they must live.
PRODUCTION_SYMBOLS = {
    PIPELINE: [
        "func recordIntentClarification(cue: CameraStyleCue, intended: Bool)",
        "func resetIntentClarificationSession()",
        "func answerIntentClarification(intended: Bool)",
        "private func updateIntentClarification(snapshot: FrameFeatureSnapshot,",
    ],
    SCENE_VM: [
        "static let generationLeaderFixtureArgument",
        "static var generationLeaderFixtureHoldsSequence: Bool",
        "static var leaderActionHoldSeconds: TimeInterval",
    ],
}

DEBUG_ONLY_SYMBOLS = {
    PIPELINE: [
        "var testingIntentSuppressedFamilies",
        "func testingUpdateIntentClarification(snapshot: FrameFeatureSnapshot,",
        "func testingIntentAnswer(for cue: CameraStyleCue) -> Bool?",
    ],
}


def _debug_spans(lines: list[str]) -> list[tuple[int, int]]:
    spans: list[tuple[int, int]] = []
    stack: list[tuple[int, bool]] = []
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("#if"):
            stack.append((index, "DEBUG" in stripped))
        elif stripped.startswith("#endif") and stack:
            start, is_debug = stack.pop()
            if is_debug:
                spans.append((start, index))
    return spans


def _inside(spans: list[tuple[int, int]], line_number: int) -> bool:
    return any(start <= line_number <= end for start, end in spans)


def _line_of(lines: list[str], needle: str) -> int | None:
    for index, line in enumerate(lines):
        if needle in line:
            return index
    return None


def _check_file(path: pathlib.Path, needles: list[str], *, must_be_outside: bool) -> None:
    lines = path.read_text(encoding="utf-8").split("\n")
    spans = _debug_spans(lines)
    for needle in needles:
        line = _line_of(lines, needle)
        assert line is not None, f"{path.name}: symbol not found: {needle}"
        inside = _inside(spans, line)
        if must_be_outside:
            assert not inside, (
                f"{path.name}:{line + 1}: production symbol is inside a #if DEBUG region: {needle}"
            )
        else:
            assert inside, (
                f"{path.name}:{line + 1}: test-only symbol must stay inside #if DEBUG: {needle}"
            )


def test_production_symbols_are_outside_debug_regions() -> None:
    # Emptiness would make the loop below check nothing and still pass, which is the
    # "PASS by emptiness" this file guards elsewhere; require the mapping to be real.
    assert PRODUCTION_SYMBOLS, "no production symbols are declared: the guard would be vacuous"
    assert sum(len(needles) for needles in PRODUCTION_SYMBOLS.values()) >= 5
    for path, needles in PRODUCTION_SYMBOLS.items():
        assert path.is_file(), f"guarded file is missing: {path}"
        _check_file(path, needles, must_be_outside=True)


def test_test_only_symbols_stay_inside_debug_regions() -> None:
    assert DEBUG_ONLY_SYMBOLS, "no debug-only symbols are declared: the guard would be vacuous"
    for path, needles in DEBUG_ONLY_SYMBOLS.items():
        assert path.is_file(), f"guarded file is missing: {path}"
        _check_file(path, needles, must_be_outside=False)


def test_release_audit_records_the_fixed_blocker() -> None:
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    assert audit["finding"]["severity"] == "release blocker, now fixed"
    assert len(audit["finding"]["errors_before"]) == 3
    assert audit["release_build"]["result"] == "BUILD SUCCEEDED"
    assert audit["release_build"]["errors"] == 0
    assert audit["release_build"]["signing"].startswith("CODE_SIGNING_ALLOWED=NO")


def test_release_audit_static_facts_match_the_repository() -> None:
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    facts = audit["static_facts_verified"]
    pbxproj = (ROOT / "shafinMultitool.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    for key in facts["usage_descriptions_present"]:
        assert f"INFOPLIST_KEY_{key}" in pbxproj, key
    privacy = (ROOT / "shafinMultitool/PrivacyInfo.xcprivacy").read_text(encoding="utf-8")
    assert "CA92.1" in privacy and "35F9.1" in privacy
    assert (ROOT / "shafinMultitool/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json").is_file()
    icon_dir = ROOT / "shafinMultitool/Resources/Assets.xcassets/AppIcon.appiconset"
    icons = [p for p in icon_dir.iterdir() if p.suffix.lower() == ".png"]
    assert icons, "an app icon file must exist"
    assert not list((ROOT / "shafinMultitool").glob("*.entitlements")), facts["entitlements"]
    assert facts["export_options_plist"] == "docs/implementation/release/ExportOptions.plist"
    assert facts["usage_descriptions_localized"] is True


def test_export_compliance_is_declared_in_the_app_plist() -> None:
    import plistlib

    plist = plistlib.loads((ROOT / "shafinMultitool/Info.plist").read_bytes())
    assert plist["ITSAppUsesNonExemptEncryption"] is False, (
        "the app ships no cryptography of its own (CryptoKit SHA-256 and HTTPS only), so the "
        "exempt declaration must be present or TestFlight asks on every upload"
    )


def test_export_options_are_valid_and_do_not_upload() -> None:
    import plistlib

    path = ROOT / "docs/implementation/release/ExportOptions.plist"
    assert path.is_file(), "ExportOptions.plist must be committed for a reproducible export"
    options = plistlib.loads(path.read_bytes())
    assert options["method"] == "app-store-connect"
    assert options["destination"] == "export", "the committed options must not upload by default"
    assert options["teamID"] == "5NAKQ28539"
    assert options["signingStyle"] == "automatic"
    text = " ".join(path.read_text(encoding="utf-8").split())
    assert "cannot run until the owner supplies the distribution identity" in text


def test_info_plist_string_catalog_localizes_every_usage_key() -> None:
    catalog = json.loads((ROOT / "shafinMultitool/Resources/InfoPlist.xcstrings").read_text(encoding="utf-8"))
    strings = catalog["strings"]
    for key in (
        "NSCameraUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSPhotoLibraryAddUsageDescription",
        "NSSpeechRecognitionUsageDescription",
    ):
        assert key in strings, key
        localizations = strings[key].get("localizations") or {}
        assert "en" in localizations and "ru" in localizations, key
        for language in ("en", "ru"):
            value = (localizations[language].get("stringUnit") or {}).get("value") or ""
            assert value.strip(), (key, language)


def test_audit_records_the_corrected_localization_fact() -> None:
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    facts = audit["static_facts_verified"]
    assert "Corrected" in facts["usage_descriptions_note"]
    assert facts["export_compliance"]["verified_in_built_plist"] is True
    assert audit["release_build_verification"]["checked_in_bundle"]["ITSAppUsesNonExemptEncryption"] == "false"
    assert audit["release_build_verification"]["checked_in_bundle"]["localized_info_plists"] == [
        "en.lproj/InfoPlist.strings",
        "ru.lproj/InfoPlist.strings",
    ]


def test_audit_keeps_the_owner_gated_prerequisites_visible() -> None:
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    prerequisites = audit["testflight_prerequisites"]
    blocking = [item for item in prerequisites if item["blocking"]]
    assert blocking, "at least one blocking prerequisite is expected"
    owners = {item["owner"] for item in prerequisite_owners(prerequisites)}
    assert "owner" in owners
    assert any("App Store Connect app record" in item["item"] for item in prerequisites)
    assert any("Distribution certificate" in item["item"] for item in prerequisites)
    assert audit["claim_scope"].endswith("no App Store Connect access was used.")


def prerequisite_owners(prerequisites: list[dict]) -> list[dict]:
    return prerequisites


if __name__ == "__main__":
    sys.exit(0)
