"""Submission metadata consistency guards.

The metadata and privacy answers in docs/implementation/release are only useful
if they stay true to the code. These checks fail when a fact the documents rely
on changes: a tracking SDK appears, the remote VLM seam stops being DEBUG-only,
the privacy manifest loses a declaration for an API the app uses, or the gates
report stops covering the product plan's list.
"""

from __future__ import annotations

import json
import pathlib
import re


ROOT = pathlib.Path(__file__).resolve().parents[2]
RELEASE = ROOT / "docs/implementation/release"
APP_SOURCES = ROOT / "shafinMultitool"
PLAN = ROOT / "docs/app-store-product-plan.md"

TRACKING_IDENTIFIERS = (
    "ASIdentifierManager",
    "ATTrackingManager",
    "import AdSupport",
    "FirebaseAnalytics",
    "Amplitude",
    "Mixpanel",
    "Sentry",
    "AppsFlyer",
)


def _swift_sources() -> list[pathlib.Path]:
    return [p for p in APP_SOURCES.rglob("*.swift")]


def test_no_tracking_sdk_is_linked_or_referenced() -> None:
    for path in _swift_sources():
        text = path.read_text(encoding="utf-8", errors="ignore")
        for identifier in TRACKING_IDENTIFIERS:
            assert identifier not in text, f"{path.relative_to(ROOT)} references {identifier}"
    podfile = (ROOT / "Podfile").read_text(encoding="utf-8")
    pods = re.findall(r"^\s*pod\s+'([^']+)'", podfile, flags=re.MULTILINE)
    assert sorted(set(pods)) == ["SnapKit"], f"unexpected pods: {sorted(set(pods))}"


def test_remote_visual_evidence_stays_debug_only() -> None:
    text = (
        ROOT
        / "shafinMultitool/Multitool2Module/Services/Reasoning/VisualSemanticEvidenceCoordinator.swift"
    ).read_text(encoding="utf-8")
    assert 'case "remote":' in text
    guard_index = text.index('case "remote":')
    preceding_if_debug = text.rfind("#if DEBUG", 0, guard_index)
    assert preceding_if_debug != -1, "the remote provider case must stay inside #if DEBUG"
    assert "#endif" in text[guard_index:], "the remote provider case must be closed by #endif"


def test_scene_remote_composition_stays_fail_closed() -> None:
    text = (
        ROOT / "shafinMultitool/SceneGeneratorModule/Services/SceneRemoteServiceComposition.swift"
    ).read_text(encoding="utf-8")
    assert "return nil" in text
    assert "isValidEndpoint" in text or "https" in text


def test_privacy_manifest_declares_every_required_reason_api_in_use() -> None:
    """The manifest must declare what the code actually uses, in both directions.

    S07 (2026-09-13) added FileTimestamp and DiskSpace after verifying the usage:
    RecordingArtifactStore calls the stat()/lstat() family (Apple's FileTimestamp
    category) and volumeAvailableCapacity(ForImportantUsage) (DiskSpace). The old
    pin listed only two APIs, so it asserted a stale fact set rather than a
    stronger one; this version scans for all four and fails if the scan finds an
    API the manifest does not declare.
    """
    manifest = (APP_SOURCES / "PrivacyInfo.xcprivacy").read_text(encoding="utf-8")
    sources = [(p, p.read_text(encoding="utf-8", errors="ignore")) for p in _swift_sources()]
    uses_user_defaults = any("UserDefaults" in text for _, text in sources)
    uses_boot_time = any("systemUptime" in text for _, text in sources)
    uses_file_timestamp = any(
        "lstat(" in text or "stat(" in text or ".modificationDate" in text or ".creationDate" in text
        for _, text in sources
    )
    uses_disk_space = any("volumeAvailableCapacity" in text for _, text in sources)
    for used, category, reason in (
        (uses_user_defaults, "NSPrivacyAccessedAPICategoryUserDefaults", "CA92.1"),
        (uses_boot_time, "NSPrivacyAccessedAPICategorySystemBootTime", "35F9.1"),
        (uses_file_timestamp, "NSPrivacyAccessedAPICategoryFileTimestamp", "C617.1"),
        (uses_disk_space, "NSPrivacyAccessedAPICategoryDiskSpace", "E174.1"),
    ):
        if used:
            assert category in manifest, f"the code uses {category} but the manifest does not declare it"
            assert reason in manifest, f"{category} is declared without its reason code {reason}"
    assert uses_user_defaults and uses_boot_time and uses_file_timestamp and uses_disk_space, (
        "the scan assumptions changed; revisit the manifest audit"
    )


def _selected_privacy_manifest_and_profile() -> tuple[dict, str]:
    """Use the actual built bundle when supplied, otherwise tracked Release defaults."""
    import os
    import plistlib
    from urllib.parse import urlsplit

    built_app = os.environ.get("SETOS_PRIVACY_BUILT_APP")
    if built_app:
        app = pathlib.Path(built_app)
        with (app / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        endpoint = info.get("SETOSSceneBaseURL", "")
        manifest_path = app / "PrivacyInfo.xcprivacy"
    else:
        project = (ROOT / "shafinMultitool.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        release_blocks = re.findall(
            r"[A-F0-9]{24} /\* Release \*/ = \{(.*?)name = Release;", project, re.S
        )
        app_blocks = [block for block in release_blocks if "INFOPLIST_FILE = shafinMultitool/Info.plist;" in block]
        assert len(app_blocks) == 1, "Resolve the app's Release configuration before privacy admission"
        values = re.findall(r'SETOS_SCENE_BASE_URL\s*=\s*"([^"\n]*)";', app_blocks[0])
        assert len(values) == 1, "A missing or ambiguous endpoint is not proof of local-only behavior"
        endpoint = values[0]
        manifest_path = APP_SOURCES / "PrivacyInfo.xcprivacy"
    assert isinstance(endpoint, str) and "$(" not in endpoint, "Unresolved built configuration"
    if endpoint:
        parsed = urlsplit(endpoint)
        assert parsed.scheme == "https" and parsed.hostname and not parsed.username and not parsed.password
    with manifest_path.open("rb") as stream:
        manifest = plistlib.load(stream)
    return manifest, "remote_enabled" if endpoint else "remote_disabled"


def test_privacy_answers_match_the_manifest_and_the_code() -> None:
    from urllib.parse import urlsplit

    answers = json.loads((RELEASE / "AppPrivacyAnswers.json").read_text(encoding="utf-8"))
    assert answers["tracking"]["answer"] is False
    profiles = answers["data_collection"]["profiles"]
    remote = profiles["remote_enabled"]
    assert remote["developer_collection"] is True
    remote_categories = {item["type"]: item for item in remote["categories"]}
    assert {"Other User Content", "Device ID"} <= remote_categories.keys()
    assert remote_categories["Other User Content"]["linked_to_user"] is True
    assert remote_categories["Device ID"]["linked_to_user"] is True

    manifest, selected_profile = _selected_privacy_manifest_and_profile()
    assert manifest["NSPrivacyTracking"] is False
    declared = {item["manifest_type"]: item for item in profiles[selected_profile].get("categories", [])}
    shipped = {item["NSPrivacyCollectedDataType"]: item for item in manifest["NSPrivacyCollectedDataTypes"]}
    assert shipped.keys() == declared.keys(), f"Privacy manifest differs from {selected_profile} disclosure"
    for identifier, disclosure in declared.items():
        item = shipped[identifier]
        assert item["NSPrivacyCollectedDataTypeLinked"] is disclosure["linked_to_user"]
        assert item["NSPrivacyCollectedDataTypeTracking"] is disclosure["used_for_tracking"]
        assert set(item["NSPrivacyCollectedDataTypePurposes"]) == set(disclosure["manifest_purposes"])

    policy = answers["privacy_policy"]
    if policy["answer"] is None:
        assert "required" in policy["status"] and answers["release_gates"], "Missing hosted policy must remain an open admission gate"
    else:
        url = urlsplit(policy["answer"])
        assert url.scheme == "https" and url.hostname and not url.username and not url.password
    stated = {entry["api"] for entry in answers["required_reason_apis"]["answer"]}
    shipped_reasons = {entry["NSPrivacyAccessedAPIType"] for entry in manifest["NSPrivacyAccessedAPITypes"]}
    assert stated == shipped_reasons


def test_metadata_draft_marks_owner_decisions_and_makes_no_quality_promise() -> None:
    meta = json.loads((RELEASE / "AppStoreMetadata.draft.json").read_text(encoding="utf-8"))
    for locale in ("ru", "en"):
        block = meta["locales"][locale]
        assert block["name"]["status"] == "owner_decision", locale
        assert block["subtitle"]["status"] == "owner_decision", locale
        assert block["description"]["status"] == "draft_bounded_by_evidence", locale
        assert block["screenshots"]["value"] is None, locale
    assert meta["shared"]["in_app_purchases"] is False
    assert meta["shared"]["privacy_policy_url"] is None
    assert "beta evidence" in meta["status"]


def test_gates_report_covers_every_gate_from_the_product_plan() -> None:
    report = json.loads((RELEASE / "AppStoreSubmissionGates.json").read_text(encoding="utf-8"))
    plan = PLAN.read_text(encoding="utf-8")
    section = plan.split("## 13. App Store: обязательные ворота")[1].split("## 14.")[0]
    numbered = re.findall(r"^\s*(\d{1,2})\.\s", section, flags=re.MULTILINE)
    assert numbered, "the product plan gate list must stay parseable"
    reported = [str(gate["n"]) for gate in report["gates"]]
    assert reported == numbered, f"gates report out of sync with the plan: {reported} vs {numbered}"
    assert report["summary"]["owner_gated"] >= 1
    assert isinstance(report["claim_scope"], str) and report["claim_scope"].strip()
    assert type(report["release_ready"]) is bool
    if any(gate["missing"] for gate in report["gates"]):
        assert report["release_ready"] is False, "Open requirements cannot be presented as release-ready"
    for gate in report["gates"]:
        if gate["status"] == "satisfied":
            assert gate["evidence"] and not gate["missing"], "A satisfied gate needs evidence and no unresolved requirement"


def test_review_notes_declare_the_open_device_gate() -> None:
    notes = (RELEASE / "ReviewNotes.draft.md").read_text(encoding="utf-8")
    assert "physical-device pass" in notes
    assert "gate 11" in notes
    assert "not\nsubstituted by" in notes or "not substituted by" in notes
