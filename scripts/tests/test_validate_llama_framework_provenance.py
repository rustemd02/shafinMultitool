from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts/validate_llama_framework_provenance.py"
NOTICE_PATH = REPO_ROOT / "docs/implementation/third-party-notices/llama-cpp/LICENSE"
UPSTREAM_URL = "https://github.com/ggerganov/llama.cpp.git"
UPSTREAM_COMMIT = "8f974d2392da4e6fa422a67050e90f1471d72966"
SHORT_COMMIT = UPSTREAM_COMMIT[:7]
LICENSE_SHA256 = "94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d"
SCRIPT_SHA256 = "fba0661d8efc621b1116c0d3365e43fd536833af61417424aa363dd3cccf8673"
BUILD_INFO_SHA256 = "2db48f66ed50cc61c52f5925aba2180d169bad5a5841731ded94d4971830da68"
BUILD_INFO = (
    b'int LLAMA_BUILD_NUMBER = 1;\n'
    b'char const *LLAMA_COMMIT = "8f974d2";\n'
    b'char const *LLAMA_COMPILER = "AppleClang 17.0.0.17000319";\n'
    b'char const *LLAMA_BUILD_TARGET = "iOS ";\n'
)

VALIDATOR_SPEC = importlib.util.spec_from_file_location("llama_framework_validator", SCRIPT_PATH)
assert VALIDATOR_SPEC is not None and VALIDATOR_SPEC.loader is not None
VALIDATOR_MODULE = importlib.util.module_from_spec(VALIDATOR_SPEC)
VALIDATOR_SPEC.loader.exec_module(VALIDATOR_MODULE)


class LlamaFrameworkProvenanceTests(unittest.TestCase):
    def _fixture(self, temporary_root: Path) -> dict[str, Path]:
        repo_root = temporary_root / "repo"
        framework = repo_root / "Frameworks/llama.xcframework"
        file_contents = {
            "Info.plist": b"fixture-xcframework\n",
            "ios-arm64/llama.framework/Headers/llama.h": b"device-header\n",
            "ios-arm64/llama.framework/Info.plist": b"device-info\n",
            "ios-arm64/llama.framework/Modules/module.modulemap": b"device-module\n",
            "ios-arm64/llama.framework/llama": b"device-binary\n",
            "ios-arm64_x86_64-simulator/llama.framework/Headers/llama.h": b"sim-header\n",
            "ios-arm64_x86_64-simulator/llama.framework/Info.plist": b"sim-info\n",
            "ios-arm64_x86_64-simulator/llama.framework/Modules/module.modulemap": b"sim-module\n",
            "ios-arm64_x86_64-simulator/llama.framework/llama": b"sim-binary\n",
        }
        for relative_path, content in file_contents.items():
            path = framework / relative_path
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)

        notice_relative = Path("docs/implementation/third-party-notices/llama-cpp/LICENSE")
        notice = repo_root / notice_relative
        notice.parent.mkdir(parents=True, exist_ok=True)
        notice.write_bytes(NOTICE_PATH.read_bytes())

        preserved_recipe_relative = Path("docs/implementation/provenance/llama/build-ios-only.sh")
        preserved_recipe = repo_root / preserved_recipe_relative
        preserved_recipe.parent.mkdir(parents=True, exist_ok=True)
        preserved_recipe.write_bytes(
            (REPO_ROOT / "docs/implementation/provenance/llama/build-ios-only.sh").read_bytes()
        )

        manifest_files = [
            {"path": path, "sha256": hashlib.sha256(content).hexdigest()}
            for path, content in sorted(file_contents.items())
        ]
        record = {
            "build": {
                "architectures": {
                    "ios-arm64": ["arm64"],
                    "ios-arm64_x86_64-simulator": ["arm64", "x86_64"],
                },
                "cmake_options": {
                    "BUILD_SHARED_LIBS": False,
                    "GGML_BLAS_DEFAULT": True,
                    "GGML_METAL": True,
                    "GGML_METAL_EMBED_LIBRARY": True,
                    "GGML_METAL_USE_BF16": True,
                    "GGML_NATIVE": False,
                    "GGML_OPENMP": False,
                    "LLAMA_BUILD_EXAMPLES": False,
                    "LLAMA_BUILD_SERVER": False,
                    "LLAMA_BUILD_TESTS": False,
                    "LLAMA_BUILD_TOOLS": False,
                    "LLAMA_OPENSSL": False,
                },
                "command": "./build-ios-only.sh",
                "configuration": "Release",
                "generator": "Xcode",
                "minimum_os_version": "16.4",
                "output": "build-apple/llama.xcframework",
                "platform": "iOS",
                "source_checkout": "llama.cpp",
                "source_script": "build-ios-only.sh",
                "source_script_sha256": SCRIPT_SHA256,
                "preserved_recipe_path": str(preserved_recipe_relative),
                "preserved_recipe_sha256": SCRIPT_SHA256,
            },
            "build_metadata": {
                "device": self._build_slice_metadata("device", "iphoneos", ["arm64"]),
                "simulator": self._build_slice_metadata(
                    "simulator", "iphonesimulator", ["arm64", "x86_64"]
                ),
            },
            "component": "llama.xcframework",
            "build_observation": {
                "current_host_mismatch": True,
                "rebuild_reason": "No clean rebuild was run; the current host toolchain and SDK metadata differ from the historical build output metadata.",
                "rebuild_status": "not_proven",
                "status": "existing_build_output_match",
            },
            "license": {
                "notice_path": str(notice_relative),
                "notice_sha256": LICENSE_SHA256,
                "spdx_id": "MIT",
                "upstream_path": "LICENSE",
                "upstream_sha256": LICENSE_SHA256,
            },
            "manifest": {
                "algorithm": "sha256",
                "file_count": len(manifest_files),
                "files": manifest_files,
                "path_format": "posix-relative",
                "root": "Frameworks/llama.xcframework",
            },
            "redistribution": {
                "scope": "exact vendored binary and applicable upstream notice",
                "status": "owner_approval_pending",
            },
            "schema_version": 1,
            "technical_provenance": {
                "offline_gate": "manifest-and-license-hash",
                "status": "traceability_complete_rebuild_unproven",
                "upstream_check": "explicit-checkout-only",
            },
            "tool_metadata": {
                "apple_clang": "AppleClang 17.0.0.17000319",
                "cmake_executable": "/opt/homebrew/bin/cmake",
                "cmake_generator": "Xcode",
                "current_host": {
                    "compiler": "AppleClang 21.0.0 (clang-2100.1.1.101)",
                    "device_sdk": "iPhoneOS26.5",
                    "simulator_sdk": "iPhoneSimulator26.5",
                    "xcode_build": "17F113",
                    "xcode_version": "26.6",
                },
                "historical": {
                    "cmake_version": "4.2.3",
                    "compiler": "AppleClang 17.0.0.17000319",
                    "device_sdk": "iPhoneOS26.0",
                    "simulator_sdk": "iPhoneSimulator26.0",
                    "xcode_build": "17A324",
                    "xcode_version": "26.0",
                },
            },
            "upstream": {
                "commit": UPSTREAM_COMMIT,
                "remote": "origin",
                "url": UPSTREAM_URL,
            },
            "vendored_path": "Frameworks/llama.xcframework",
        }
        record_path = repo_root / "record.json"
        record_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return {"repo": repo_root, "framework": framework, "record": record_path, "notice": notice}

    @staticmethod
    def _build_slice_metadata(name: str, sysroot: str, architectures: list[str]) -> dict[str, object]:
        build_directory = "build-ios-device" if name == "device" else "build-ios-sim"
        return {
            "architectures": architectures,
            "build_info_path": f"{build_directory}/common/build-info.cpp",
            "build_info_sha256": BUILD_INFO_SHA256,
            "build_target": "iOS ",
            "build_number": 1,
            "cmake_generator": "Xcode",
            "compiler": "AppleClang 17.0.0.17000319",
            "configuration": "Release",
            "deployment_target": "16.4",
            "llama_commit": SHORT_COMMIT,
            "sysroot": sysroot,
            "system_name": "iOS",
        }

    @staticmethod
    def _run(fixture: dict[str, Path]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "--repo-root",
                str(fixture["repo"]),
                "--framework",
                str(fixture["framework"]),
                "--record",
                str(fixture["record"]),
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def _upstream_fixture(self, temporary_root: Path) -> dict[str, Path]:
        fixture = self._fixture(temporary_root)
        checkout = temporary_root / "llama.cpp"
        checkout.mkdir()
        (checkout / "build-ios-only.sh").write_bytes(
            (REPO_ROOT / "docs/implementation/provenance/llama/build-ios-only.sh").read_bytes()
        )
        for relative_path in (
            "build-ios-device/common/build-info.cpp",
            "build-ios-sim/common/build-info.cpp",
        ):
            build_info = checkout / relative_path
            build_info.parent.mkdir(parents=True, exist_ok=True)
            build_info.write_bytes(BUILD_INFO)
        shutil.copytree(fixture["framework"], checkout / "build-apple/llama.xcframework")
        (checkout / "LICENSE").write_bytes(NOTICE_PATH.read_bytes())
        fixture["checkout"] = checkout
        return fixture

    @staticmethod
    def _local_git_environment() -> dict[str, str]:
        environment = os.environ.copy()
        environment.update(
            {
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_SYSTEM": "/dev/null",
            }
        )
        return environment

    def _init_local_git_checkout(
        self,
        checkout: Path,
        additional_files: dict[str, bytes],
    ) -> None:
        for relative_path, content in additional_files.items():
            path = checkout / relative_path
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        environment = self._local_git_environment()
        subprocess.run(
            ["git", "-C", str(checkout), "init", "--quiet"],
            check=True,
            capture_output=True,
            text=True,
            env=environment,
        )
        subprocess.run(
            ["git", "-C", str(checkout), "add", "--all"],
            check=True,
            capture_output=True,
            text=True,
            env=environment,
        )
        subprocess.run(
            [
                "git",
                "-C",
                str(checkout),
                "-c",
                "user.name=provenance-fixture",
                "-c",
                "user.email=provenance-fixture@example.invalid",
                "commit",
                "--quiet",
                "-m",
                "fixture",
            ],
            check=True,
            capture_output=True,
            text=True,
            env=environment,
        )

    def _git_checkout_command(self, checkout: Path, *arguments: str) -> None:
        subprocess.run(
            ["git", "-C", str(checkout), *arguments],
            check=True,
            capture_output=True,
            text=True,
            env=self._local_git_environment(),
        )

    def _run_upstream_validation(
        self,
        fixture: dict[str, Path],
        *,
        remote: str = UPSTREAM_URL,
        head: str = UPSTREAM_COMMIT,
        status_entries: list[tuple[str, list[str]]] | None = None,
        use_real_status: bool = False,
    ) -> list[str]:
        record = json.loads(fixture["record"].read_text(encoding="utf-8"))
        validated = VALIDATOR_MODULE._validate_record(record)
        real_git_output = VALIDATOR_MODULE._git_output

        def fake_git_output(checkout: Path, *arguments: str) -> str:
            if arguments[:2] == ("remote", "get-url"):
                return remote
            if arguments == ("rev-parse", "HEAD"):
                return head
            return real_git_output(checkout, *arguments)

        def validate() -> list[str]:
            return VALIDATOR_MODULE._validate_upstream_checkout(
                fixture["checkout"],
                fixture["framework"],
                fixture["repo"],
                record,
                validated["license_notice_path"],
            )

        with mock.patch.object(VALIDATOR_MODULE, "_git_output", side_effect=fake_git_output):
            if use_real_status:
                return validate()
            with mock.patch.object(
                VALIDATOR_MODULE,
                "_git_status_lines",
                return_value=status_entries or [],
            ):
                return validate()

    def test_happy_path(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = self._run(self._fixture(Path(directory)))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PASS llama framework provenance", result.stdout)

    def test_modified_file_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._fixture(Path(directory))
            (fixture["framework"] / "Info.plist").write_bytes(b"modified\n")
            result = self._run(fixture)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("modified file: Info.plist", result.stderr)

    def test_missing_file_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._fixture(Path(directory))
            (fixture["framework"] / "Info.plist").unlink()
            result = self._run(fixture)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing file: Info.plist", result.stderr)

    def test_extra_file_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._fixture(Path(directory))
            extra = fixture["framework"] / "unexpected.bin"
            extra.write_bytes(b"unexpected\n")
            result = self._run(fixture)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unexpected file: unexpected.bin", result.stderr)

    def test_malformed_and_missing_required_metadata_fail(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._fixture(Path(directory))
            fixture["record"].write_text("{not-json", encoding="utf-8")
            malformed = self._run(fixture)
            self.assertNotEqual(malformed.returncode, 0)
            self.assertIn("malformed JSON", malformed.stderr)

        with tempfile.TemporaryDirectory() as directory:
            fixture = self._fixture(Path(directory))
            record = json.loads(fixture["record"].read_text(encoding="utf-8"))
            del record["upstream"]["commit"]
            fixture["record"].write_text(json.dumps(record), encoding="utf-8")
            missing = self._run(fixture)
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("upstream.commit", missing.stderr)

    def test_altered_license_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._fixture(Path(directory))
            fixture["notice"].write_bytes(fixture["notice"].read_bytes() + b"altered\n")
            result = self._run(fixture)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("MIT notice artifact hash mismatch", result.stderr)

    def test_upstream_wrong_remote_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._upstream_fixture(Path(directory))
            with self.assertRaisesRegex(VALIDATOR_MODULE.ProvenanceError, "upstream remote mismatch"):
                self._run_upstream_validation(fixture, remote="https://example.invalid/llama.cpp.git")

    def test_upstream_wrong_head_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._upstream_fixture(Path(directory))
            with self.assertRaisesRegex(VALIDATOR_MODULE.ProvenanceError, "upstream HEAD mismatch"):
                self._run_upstream_validation(fixture, head="0000000000000000000000000000000000000000")

    def test_upstream_altered_recipe_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._upstream_fixture(Path(directory))
            (fixture["checkout"] / "build-ios-only.sh").write_bytes(b"altered recipe\n")
            with self.assertRaisesRegex(VALIDATOR_MODULE.ProvenanceError, "build recipe hash mismatch"):
                self._run_upstream_validation(fixture)

    def test_upstream_build_relevant_dirty_source_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._upstream_fixture(Path(directory))
            changed_source = fixture["checkout"] / "src/changed.cpp"
            changed_source.parent.mkdir(parents=True)
            changed_source.write_text("changed\n", encoding="utf-8")
            with self.assertRaisesRegex(VALIDATOR_MODULE.ProvenanceError, "build-relevant dirty paths"):
                self._run_upstream_validation(
                    fixture,
                    status_entries=[("??", ["src/changed.cpp"])],
                )

    def test_upstream_unrelated_dirty_docs_are_reported_but_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._upstream_fixture(Path(directory))
            unrelated = self._run_upstream_validation(
                fixture,
                status_entries=[(" D", ["AGENTS.md"]), (" D", ["CLAUDE.md"])],
            )
            self.assertEqual(unrelated, ["AGENTS.md", "CLAUDE.md"])

    def test_upstream_rename_from_source_to_docs_fails_with_local_git_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._upstream_fixture(Path(directory))
            self._init_local_git_checkout(
                fixture["checkout"],
                {"src/changed.cpp": b"changed source\n"},
            )
            (fixture["checkout"] / "docs").mkdir()
            self._git_checkout_command(
                fixture["checkout"],
                "mv",
                "src/changed.cpp",
                "docs/changed.cpp",
            )
            status_entries = VALIDATOR_MODULE._git_status_lines(fixture["checkout"])
            self.assertTrue(
                any(
                    status[0] == "R" and set(paths) == {"src/changed.cpp", "docs/changed.cpp"}
                    for status, paths in status_entries
                ),
                status_entries,
            )
            with self.assertRaisesRegex(VALIDATOR_MODULE.ProvenanceError, "src/changed.cpp"):
                self._run_upstream_validation(fixture, use_real_status=True)

    def test_upstream_docs_only_rename_is_allowed_and_reported_with_local_git_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._upstream_fixture(Path(directory))
            self._init_local_git_checkout(
                fixture["checkout"],
                {"docs/old note.md": b"documentation\n"},
            )
            self._git_checkout_command(
                fixture["checkout"],
                "mv",
                "docs/old note.md",
                "docs/new note.md",
            )
            status_entries = VALIDATOR_MODULE._git_status_lines(fixture["checkout"])
            self.assertTrue(
                any(
                    status[0] == "R" and set(paths) == {"docs/old note.md", "docs/new note.md"}
                    for status, paths in status_entries
                ),
                status_entries,
            )
            unrelated = self._run_upstream_validation(fixture, use_real_status=True)
            self.assertEqual(unrelated, ["docs/new note.md", "docs/old note.md"])

    def test_upstream_stale_build_info_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._upstream_fixture(Path(directory))
            build_info = fixture["checkout"] / "build-ios-device/common/build-info.cpp"
            build_info.write_bytes(BUILD_INFO.replace(b"8f974d2", b"0000000"))
            with self.assertRaisesRegex(VALIDATOR_MODULE.ProvenanceError, "build-info hash mismatch"):
                self._run_upstream_validation(fixture)

    def test_upstream_mismatched_output_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._upstream_fixture(Path(directory))
            output_info = fixture["checkout"] / "build-apple/llama.xcframework/Info.plist"
            output_info.write_bytes(b"mismatched output\n")
            with self.assertRaisesRegex(VALIDATOR_MODULE.ProvenanceError, "byte mismatch: Info.plist"):
                self._run_upstream_validation(fixture)


if __name__ == "__main__":
    unittest.main()
