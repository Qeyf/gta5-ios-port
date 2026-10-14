"""Exercise release metadata against tiny packaged IPA fixtures; no binaries run."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "Scripts" / "create_release_metadata.py"
APP = "Payload/GtaV Mobile.app/"
COMMIT = "a" * 40
RUN_URL = "https://github.com/qeyf/gtavmobile/actions/runs/123"
SCENE_MANIFEST = {
    "UIApplicationSupportsMultipleScenes": False,
    "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [{
        "UISceneClassName": "UIWindowScene",
        "UISceneDelegateClassName": "GtaV_Mobile.SceneDelegate",
        "UISceneConfigurationName": "Game",
    }]},
}


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.ipa = self.root / "GtaV Mobile.ipa"
        self.output = self.root / "release"
        self.github_output = self.root / "github-output"

    def package(self, updates=None, *, omit=(), extra=(), executable=b"fixture executable", raw_plist=None):
        info = {
            "CFBundleDisplayName": "GtaV Mobile",
            "CFBundleIdentifier": "io.github.qeyf.gtavmobile",
            # Deliberately differs from source project version/build.
            "CFBundleShortVersionString": "3.12.7",
            "CFBundleVersion": "42.2",
            "CFBundleExecutable": "PlayGTA5Native",
            "MinimumOSVersion": "17.0",
            "CFBundleLocalizations": ["tr", "en"],
            "CFBundlePackageType": "APPL",
            "UIApplicationSceneManifest": SCENE_MANIFEST,
            # Unrelated build settings must not be copied into public metadata.
            "PGDefaultAssetServer": "http://private-server.example/token-secret",
        }
        info.update(updates or {})
        for key in omit:
            info.pop(key, None)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.ipa, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr(APP + "Info.plist", raw_plist if raw_plist is not None else plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
                if executable is not None:
                    archive.writestr(APP + "PlayGTA5Native", executable)
                for name, contents in extra:
                    archive.writestr(name, contents)

    def invoke(self, *extra):
        return subprocess.run([
            sys.executable, str(SCRIPT), "--ipa", str(self.ipa),
            "--output", str(self.output), "--commit", COMMIT,
            "--run-id", "123", "--run-url", RUN_URL,
            "--signing", "adhoc", "--github-output", str(self.github_output),
            *extra,
        ], capture_output=True, text=True)

    def assert_rejected(self, expected):
        self.github_output.write_text("existing=value\n")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(expected, result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse(self.output.exists(), "Invalid IPA created release outputs")
        self.assertEqual(self.github_output.read_text(), "existing=value\n")

    def test_reads_packaged_identity_and_hash_and_writes_bilingual_release_assets(self):
        self.package()
        result = self.invoke("--xcode-version", "Xcode 16.4 Build version 16F6", "--sdk-version", "18.5")
        self.assertEqual(result.returncode, 0, result.stderr)
        metadata = json.loads((self.output / "release-metadata.json").read_text())
        self.assertEqual(metadata["schema_version"], 1)
        self.assertEqual(metadata["version"], "3.12.7")
        self.assertEqual(metadata["build"], "42.2")
        self.assertEqual(metadata["tag"], "v3.12.7-build.42.2")
        self.assertEqual(metadata["title"], "GtaV Mobile 3.12.7 (build 42.2)")
        self.assertEqual(metadata["display_name"], "GtaV Mobile")
        self.assertEqual(metadata["bundle_identifier"], "io.github.qeyf.gtavmobile")
        self.assertEqual(metadata["minimum_os_version"], "17.0")
        self.assertEqual(metadata["languages"], ["tr", "en"])
        self.assertEqual(metadata["executable"], APP + "PlayGTA5Native")
        self.assertEqual(metadata["commit"], COMMIT)
        self.assertEqual(metadata["workflow"], {"run_id": "123", "run_url": RUN_URL})
        self.assertRegex(metadata["created_at_utc"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
        self.assertEqual(metadata["toolchain"]["sdk_version"], "18.5")
        self.assertEqual(metadata["signing"]["mode"], "adhoc")
        self.assertTrue(metadata["signing"]["requires_resigning"])
        self.assertEqual(metadata["validation"]["status"], "passed")
        self.assertFalse(metadata["validation"]["native_engine_run"])
        self.assertFalse(metadata["validation"]["device_tested"])
        digest = hashlib.sha256(self.ipa.read_bytes()).hexdigest()
        self.assertEqual(metadata["ipa"], {"filename": self.ipa.name, "size_bytes": self.ipa.stat().st_size, "sha256": digest})
        self.assertEqual((self.output / "SHA256SUMS").read_text(), f"{digest}  {self.ipa.name}\n")
        notes = (self.output / "release-notes.md").read_text()
        for expected in ("Türkçe", "English", "3.12.7", "42.2", "17.0", "tr, en", digest, COMMIT, RUN_URL, "re-sign", "yeniden imzalayın"):
            self.assertIn(expected, notes)
        self.assertNotIn("token-secret", json.dumps(metadata) + notes)
        self.assertEqual(dict(line.split("=", 1) for line in self.github_output.read_text().splitlines()), {
            "tag": "v3.12.7-build.42.2", "title": "GtaV Mobile 3.12.7 (build 42.2)", "version": "3.12.7", "build": "42.2",
        })

    def test_release_versions_require_three_ascii_integer_components(self):
        for version in ("1.3", "1.3.2.4", "v1.3.2", "1.3.2-beta", "1.-3.2", "１.3.2", "$(MARKETING_VERSION)", 7):
            with self.subTest(version=version):
                self.package({"CFBundleShortVersionString": version})
                self.assert_rejected("CFBundleShortVersionString")

    def test_ipa_without_scene_lifecycle_is_rejected_before_publication(self):
        self.package(omit=("UIApplicationSceneManifest",))
        self.assert_rejected("UIApplicationSceneManifest")

    def test_unusable_scene_configuration_is_rejected(self):
        for manifest in ({}, {"UIApplicationSupportsMultipleScenes": False, "UISceneConfigurations": {}},
                         {"UIApplicationSupportsMultipleScenes": False, "UISceneConfigurations": {
                             "UIWindowSceneSessionRoleApplication": [{"UISceneClassName": "UIScene"}]}}):
            with self.subTest(manifest=manifest):
                self.package({"UIApplicationSceneManifest": manifest})
                self.assert_rejected("UIApplicationSceneManifest")

    def test_release_builds_require_one_to_three_numeric_components(self):
        for build in ("", "1.2.3.4", "9.1b1", "9.-1", "$(CURRENT_PROJECT_VERSION)", 8):
            with self.subTest(build=build):
                self.package({"CFBundleVersion": build})
                self.assert_rejected("CFBundleVersion")

    def test_numeric_zero_and_two_or_three_component_builds_are_valid(self):
        for build in ("0", "10.5", "10.0.0"):
            with self.subTest(build=build):
                self.package({"CFBundleVersion": build})
                result = self.invoke()
                self.assertEqual(result.returncode, 0, result.stderr)
                metadata = json.loads((self.output / "release-metadata.json").read_text())
                self.assertEqual(metadata["build"], build)
                self.assertEqual(metadata["tag"], f"v3.12.7-build.{build}")

    def test_wrong_and_missing_bundle_identities_are_rejected(self):
        for updates, omit, expected in (
            ({"CFBundleDisplayName": "GTA V Port"}, (), "CFBundleDisplayName"),
            ({"CFBundleIdentifier": "com.example.app"}, (), "CFBundleIdentifier"),
            ({}, ("CFBundleDisplayName",), "CFBundleDisplayName"),
            ({}, ("CFBundleIdentifier",), "CFBundleIdentifier"),
        ):
            with self.subTest(updates=updates, omit=omit):
                self.package(updates, omit=omit)
                self.assert_rejected(expected)

    def test_missing_invalid_or_unadvertised_metadata_is_rejected(self):
        for updates, omit, expected in (
            ({}, ("MinimumOSVersion",), "MinimumOSVersion"),
            ({"MinimumOSVersion": "17beta"}, (), "MinimumOSVersion"),
            ({"CFBundleLocalizations": "tr,en"}, (), "CFBundleLocalizations"),
            ({"CFBundleLocalizations": []}, (), "CFBundleLocalizations"),
            ({"CFBundleLocalizations": ["en", "$(LANGUAGE)"]}, (), "CFBundleLocalizations"),
        ):
            with self.subTest(updates=updates, omit=omit):
                self.package(updates, omit=omit)
                self.assert_rejected(expected)

    def test_missing_empty_and_unsafe_executable_are_rejected(self):
        self.package(executable=None)
        self.assert_rejected("CFBundleExecutable")
        self.package(executable=b"")
        self.assert_rejected("CFBundleExecutable")
        self.package({"CFBundleExecutable": "../outside"})
        self.assert_rejected("CFBundleExecutable")

    def test_malformed_zip_and_plist_are_rejected_without_output(self):
        self.ipa.write_bytes(b"not an IPA zip")
        self.assert_rejected("ZIP")
        self.package(raw_plist=b"not a plist")
        self.assert_rejected("Info.plist")
        self.package(raw_plist=plistlib.dumps(["not a dictionary"]))
        self.assert_rejected("Info.plist")
        self.package(raw_plist=b'<?xml version="1.0"?><plist><dict><key>broken</key></plist>')
        self.assert_rejected("Info.plist")

    def test_corrupt_zip_member_is_rejected(self):
        info = {
            "CFBundleDisplayName": "GtaV Mobile", "CFBundleIdentifier": "io.github.qeyf.gtavmobile",
            "CFBundleShortVersionString": "3.12.7", "CFBundleVersion": "42.2",
            "CFBundleExecutable": "PlayGTA5Native", "MinimumOSVersion": "17.0", "CFBundleLocalizations": ["en", "tr"],
            "UIApplicationSceneManifest": SCENE_MANIFEST,
        }
        with zipfile.ZipFile(self.ipa, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr(APP + "Info.plist", plistlib.dumps(info))
            archive.writestr(APP + "PlayGTA5Native", b"original bytes")
        with zipfile.ZipFile(self.ipa) as archive:
            member = archive.getinfo(APP + "PlayGTA5Native")
            offset = member.header_offset + 30 + len(member.filename.encode()) + len(member.extra)
        contents = bytearray(self.ipa.read_bytes())
        contents[offset] ^= 0xFF
        self.ipa.write_bytes(contents)
        self.assert_rejected("ZIP")

    def test_duplicate_apps_and_duplicate_members_are_rejected(self):
        self.package(extra=(("Payload/Second.app/Info.plist", plistlib.dumps({})),))
        self.assert_rejected("single")
        self.package(extra=((APP + "Info.plist", plistlib.dumps({})),))
        self.assert_rejected("duplicate")

    def test_zip_with_no_app_and_traversal_paths_are_rejected(self):
        with zipfile.ZipFile(self.ipa, "w") as archive:
            archive.writestr("Info.plist", plistlib.dumps({}))
        self.assert_rejected("single")
        self.package(extra=((APP + "../../escape", b"bad"),))
        self.assert_rejected("unsafe")

    def test_failed_validation_does_not_modify_existing_release_files(self):
        self.output.mkdir()
        previous = self.output / "release-metadata.json"
        previous.write_text("previous release\n")
        self.package({"CFBundleVersion": "bad"})
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CFBundleVersion", result.stderr)
        self.assertEqual(list(self.output.iterdir()), [previous])
        self.assertEqual(previous.read_text(), "previous release\n")

    def test_public_workflow_identity_is_validated_before_writing(self):
        self.package()
        for args in (("--commit", "$(secret)"), ("--run-url", RUN_URL + "?token=secret"), ("--run-id", "99")):
            with self.subTest(args=args):
                result = self.invoke(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.output.exists())
                self.assertFalse(self.github_output.exists())

    def test_source_commit_link_is_independent_of_private_workflow_caller(self):
        self.package()
        caller = "https://github.com/qeyf/native-build-private/actions/runs/123"
        source = "qeyf/gta5-ios-port"
        result = self.invoke("--run-url", caller, "--source-repository", source)
        self.assertEqual(result.returncode, 0, result.stderr)
        metadata = json.loads((self.output / "release-metadata.json").read_text())
        self.assertEqual(metadata["commit"], COMMIT)
        self.assertEqual(metadata["source_repository"], source)
        self.assertEqual(metadata["workflow"]["run_url"], caller)
        notes = (self.output / "release-notes.md").read_text()
        self.assertIn(f"[{COMMIT}](https://github.com/{source}/commit/{COMMIT})", notes)
        self.assertIn(f"[Run 123]({caller})", notes)
        self.assertNotIn("native-build-private/commit/", notes)

    def test_unsafe_source_repository_slugs_are_rejected_before_writing(self):
        self.package()
        for source in ("https://github.com/qeyf/repo", "qeyf/repo/extra", "qeyf/repo?token=secret", "qeyf/..", "qeyf/repo\nother=value"):
            with self.subTest(source=source):
                result = self.invoke("--source-repository", source)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--source-repository", result.stderr)
                self.assertFalse(self.output.exists())
                self.assertFalse(self.github_output.exists())


if __name__ == "__main__":
    unittest.main()
