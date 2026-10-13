"""Test private ZIP staging and build-input checks using tiny synthetic files."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile


SCRIPTS = Path(__file__).resolve().parents[1] / "Scripts"
sys.path.insert(0, str(SCRIPTS))
import stage_release_inputs as stage
import check_game_files as check


ENGINE = b"synthetic supported engine"
MANIFEST = b'{"version":"fixture","files":[["common/test.rpf",4]]}'
PACKS = {"pack0.01234567.bin": b"a" * 32, "pack1.89abcdef.bin": b"b" * 17}
INDEX = json.dumps({"_packs": [
    {"file": name, "bytes": len(data)} for name, data in PACKS.items()
]}).encode()
CORE = [("Release/game.wasm", ENGINE), ("Release/manifest.json", MANIFEST),
        ("Release/shaders/index.json", INDEX)]
SHADERS = "b/8b0b5899ed/shaders"


class ReleaseInputsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.archive = self.root / "release.zip"
        self.shaders_archive = self.root / "shaders.zip"
        self.output = self.root / "mirror"
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(check, "ENGINE_SHA256", hashlib.sha256(ENGINE).hexdigest()).start()
        mock.patch.object(check, "SHADER_INDEX_SHA256", hashlib.sha256(INDEX).hexdigest()).start()

    def package(self, entries=CORE, *, path=None, compression=zipfile.ZIP_DEFLATED):
        path = path or self.archive
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(path, "w", compression=compression) as archive:
                for name, data in entries:
                    archive.writestr(name, data)
        return path

    def stage(self, shaders=False):
        return stage.stage_release_inputs(self.archive, self.output,
                                          self.shaders_archive if shaders else None)

    def rejected(self, text, shaders=False):
        with self.assertRaisesRegex(stage.InputError, text):
            self.stage(shaders)
        self.assertFalse(self.output.exists(), "Rejected input published a destination")

    def complete_entries(self):
        return CORE + [("shaders/" + name, data) for name, data in PACKS.items()]

    def test_stages_only_fixed_paths_and_reports_missing_packs(self):
        outside = "outside-" + self.root.name + ".txt"
        self.package(CORE + [("README.md", b"ignored"), ("docs/", b""),
                             ("../../" + outside, b"never extracted")])
        result = self.stage()
        self.assertEqual((self.output / "b/8b0b5899ed/game.wasm").read_bytes(), ENGINE)
        self.assertEqual((self.output / "data/manifest.json").read_bytes(), MANIFEST)
        self.assertEqual((self.output / SHADERS / "index.json").read_bytes(), INDEX)
        self.assertEqual(result["missing_packs"], list(PACKS))
        self.assertEqual(result["ignored_entries"], 3)
        self.assertEqual(sorted(str(p.relative_to(self.output)) for p in self.output.rglob("*") if p.is_file()),
                         sorted([SHADERS + "/index.json", "b/8b0b5899ed/game.wasm", "data/manifest.json"]))
        self.assertFalse((self.root.parent / outside).exists())
        with self.assertRaisesRegex(check.InputError, "Missing shader pack pack0.01234567.bin"):
            check.validate_game_files(self.output)

    def test_merges_full_shader_zip_with_identical_index_without_overwriting(self):
        self.package()
        self.package([("shaders/index.json", INDEX)] +
                     [("shaders/" + name, data) for name, data in PACKS.items()], path=self.shaders_archive)
        result = self.stage(shaders=True)
        self.assertEqual(result["missing_packs"], [])
        self.assertEqual(result["merged_duplicates"], 1)
        for name, data in PACKS.items():
            self.assertEqual((self.output / SHADERS / name).read_bytes(), data)
        self.assertEqual(check.validate_game_files(self.output), [])

    def test_accepts_windows_separators_but_uses_fixed_mirror_paths(self):
        self.package([(name.replace("/", "\\"), data) for name, data in self.complete_entries()])
        self.assertEqual(self.stage()["missing_packs"], [])
        self.assertTrue((self.output / SHADERS / "index.json").is_file())

    def test_conflicting_index_across_archives_is_rejected(self):
        self.package()
        self.package([("shaders/index.json", INDEX + b" ")], path=self.shaders_archive)
        self.rejected("Conflicting.*index.json", shaders=True)

    def test_identical_core_duplicates_across_archives_merge(self):
        self.package()
        self.package(CORE, path=self.shaders_archive)
        self.assertEqual(self.stage(shaders=True)["merged_duplicates"], 3)

    def test_duplicate_recognized_basename_in_one_zip_is_rejected(self):
        for name, data in [("nested/game.wasm", ENGINE), ("nested/index.json", INDEX),
                           ("nested/manifest.json", MANIFEST)]:
            with self.subTest(name=name):
                self.package(CORE + [(name, data)])
                self.rejected("Duplicate recognized.*" + name.split("/")[-1])

    def test_duplicate_pack_in_one_zip_is_rejected(self):
        name, data = next(iter(PACKS.items()))
        self.package(self.complete_entries() + [("another/" + name, data)])
        self.rejected("Duplicate recognized.*" + name)

    def test_conflicting_pack_across_archives_is_rejected(self):
        name, data = next(iter(PACKS.items()))
        self.package(self.complete_entries())
        self.package([(name, b"z" * len(data))], path=self.shaders_archive)
        self.rejected("Conflicting.*" + name, shaders=True)

    def test_missing_core_files_do_not_publish(self):
        for missing, _ in CORE:
            with self.subTest(missing=missing):
                self.package([(name, data) for name, data in CORE if name != missing])
                self.rejected("Missing.*" + missing.split("/")[-1])

    def test_recognized_traversal_and_absolute_paths_are_rejected(self):
        for name in ["../../game.wasm", "/game.wasm", "C:\\game.wasm"]:
            with self.subTest(name=name):
                self.package([(name, ENGINE)] + CORE[1:])
                self.rejected("Unsafe.*game.wasm")

    def test_recognized_symlink_is_not_materialized(self):
        link = zipfile.ZipInfo("game.wasm")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.package([(link, b"/private/file")] + CORE[1:])
        self.rejected("regular file")

    def test_existing_destinations_are_never_modified(self):
        self.package(self.complete_entries())
        for kind in ["empty directory", "nonempty directory", "file", "symlink"]:
            with self.subTest(kind=kind):
                output = self.root / kind
                if kind.endswith("directory"):
                    output.mkdir()
                    if kind.startswith("nonempty"):
                        (output / "keep").write_bytes(b"unchanged")
                elif kind == "file":
                    output.write_bytes(b"unchanged")
                else:
                    output.symlink_to(self.root / "nonexistent")
                with self.assertRaisesRegex(stage.InputError, "already exists"):
                    stage.stage_release_inputs(self.archive, output)
                if kind == "nonempty directory":
                    self.assertEqual((output / "keep").read_bytes(), b"unchanged")
                elif kind == "empty directory":
                    self.assertEqual(list(output.iterdir()), [])
                elif kind == "file":
                    self.assertEqual(output.read_bytes(), b"unchanged")
                else:
                    self.assertTrue(output.is_symlink())

    def test_corrupt_zip_and_member_crc_leave_no_output(self):
        self.archive.write_bytes(b"not a zip")
        self.rejected("ZIP")
        self.package(compression=zipfile.ZIP_STORED)
        raw = bytearray(self.archive.read_bytes())
        name_size, extra_size = struct.unpack_from("<HH", raw, 26)
        raw[30 + name_size + extra_size] ^= 1
        self.archive.write_bytes(raw)
        self.rejected("ZIP")

    def test_recognized_entry_size_limit_prevents_decompression(self):
        self.package()
        with mock.patch.dict(stage.CORE_LIMITS, {"game.wasm": len(ENGINE) - 1}):
            self.rejected("size limit")

    def test_stream_limit_is_enforced_even_if_member_metadata_is_smaller(self):
        self.package()
        original = zipfile.ZipFile.open
        def lying_open(archive, member, *args, **kwargs):
            if member.filename == "Release/game.wasm":
                return io.BytesIO(b"x" * 1_000)
            return original(archive, member, *args, **kwargs)
        with mock.patch.object(zipfile.ZipFile, "open", lying_open), \
                mock.patch.dict(stage.CORE_LIMITS, {"game.wasm": len(ENGINE) + 1}):
            self.rejected("decompressed size limit")

    def test_total_and_archive_size_limits_are_enforced(self):
        self.package(self.complete_entries())
        with mock.patch.object(stage, "MAX_TOTAL_BYTES", len(ENGINE) + len(MANIFEST)):
            self.rejected("total.*size limit")
        with mock.patch.object(stage, "MAX_ARCHIVE_BYTES", self.archive.stat().st_size - 1):
            self.rejected("archive.*size limit")

    def test_unknown_large_compressed_entry_is_never_opened(self):
        self.package(CORE + [("docs/ignored.bin", b"x" * 2_000_000)])
        original = zipfile.ZipFile.open
        opened = []
        def record_open(archive, name, *args, **kwargs):
            opened.append(name.filename if isinstance(name, zipfile.ZipInfo) else name)
            return original(archive, name, *args, **kwargs)
        with mock.patch.object(zipfile.ZipFile, "open", record_open):
            self.assertEqual(self.stage()["ignored_entries"], 1)
        self.assertNotIn("docs/ignored.bin", opened)

    def test_wrong_pack_size_is_rejected_by_staging_and_checker(self):
        name, data = next(iter(PACKS.items()))
        self.package(CORE + [(name, data[:-1])])
        self.rejected("Wrong size.*" + name)
        self.package(self.complete_entries())
        self.stage()
        (self.output / SHADERS / name).write_bytes(data[:-1])
        with self.assertRaisesRegex(check.InputError, "Wrong size.*" + name + ".*expected 32.*got 31"):
            check.validate_game_files(self.output)

    def test_unsupported_engine_and_index_are_rejected(self):
        self.package([(CORE[0][0], ENGINE + b"x")] + CORE[1:])
        self.rejected("game.wasm.*supports")
        self.package(CORE[:2] + [(CORE[2][0], INDEX + b" ")])
        self.rejected("shader index.*match")

    def test_malformed_or_unsafe_index_is_rejected_after_hash_validation(self):
        indices = [b"{", b'{"_packs":[]}',
                   b'{"_packs":[{"file":"../pack0.01234567.bin","bytes":32}]}',
                   b'{"_packs":[{"file":"pack0.01234567.bin","bytes":true}]}',
                   b'{"_packs":[{"file":"pack0.01234567.bin","bytes":32},{"file":"pack0.01234567.bin","bytes":32}]}']
        for index in indices:
            with self.subTest(index=index):
                self.package(CORE[:2] + [(CORE[2][0], index)])
                with mock.patch.object(check, "SHADER_INDEX_SHA256", hashlib.sha256(index).hexdigest()):
                    self.rejected("shader index")

    def test_publish_failure_cleans_only_the_newly_created_destination(self):
        self.package(self.complete_entries())
        marker = self.root / "keep"
        marker.write_bytes(b"unchanged")
        original = stage.shutil.move
        moved = []
        def fail_after_first_move(*args):
            if moved:
                raise OSError("synthetic disk failure")
            moved.append(args)
            return original(*args)
        with mock.patch.object(stage.shutil, "move", fail_after_first_move):
            self.rejected("disk failure")
        self.assertEqual(len(moved), 1, "Rollback was not tested after copying content")
        self.assertEqual(marker.read_bytes(), b"unchanged")

    def test_destination_created_during_validation_is_left_untouched(self):
        self.package(self.complete_entries())
        validate = check.validate_game_files
        def raced_validate(*args, **kwargs):
            result = validate(*args, **kwargs)
            self.output.mkdir()
            (self.output / "keep").write_bytes(b"concurrent writer")
            return result
        with mock.patch.object(check, "validate_game_files", raced_validate):
            with self.assertRaisesRegex(stage.InputError, "already exists"):
                self.stage()
        self.assertEqual((self.output / "keep").read_bytes(), b"concurrent writer")

    def test_cli_reports_ignored_entries_and_missing_packs_without_claiming_ready(self):
        self.package(CORE + [("README.md", b"ignored")])
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            result = stage.main(["--archive", str(self.archive), "--out", str(self.output)])
        self.assertEqual(result, 0, errors.getvalue())
        self.assertIn("Ignored 1", errors.getvalue())
        self.assertIn("Missing 2 shader packs", errors.getvalue())
        self.assertNotIn("ready", output.getvalue().lower())

    def test_cli_entrypoint_rejects_invalid_zip_without_traceback(self):
        self.archive.write_bytes(b"not a zip")
        result = subprocess.run([sys.executable, str(SCRIPTS / "stage_release_inputs.py"),
                                 "--archive", str(self.archive), "--out", str(self.output)],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ZIP", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
