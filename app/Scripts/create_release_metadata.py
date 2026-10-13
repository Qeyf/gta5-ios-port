#!/usr/bin/env python3
"""Inspect a packaged IPA and create public release assets using only stdlib.

This checks archive integrity and bundle metadata. It never runs app binaries,
reads source project settings, or infers successful game/device execution.
Version rules: Apple's current CFBundleShortVersionString / CFBundleVersion
documentation and https://developer.apple.com/help/glossary/build-string/
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import sys
import tempfile
from urllib.parse import urlsplit
from xml.parsers.expat import ExpatError
import zipfile
import zlib


EXPECTED_NAME = "GtaV Mobile"
EXPECTED_IDENTIFIER = "io.github.qeyf.gtavmobile"
OUTPUT_FILES = ("release-metadata.json", "SHA256SUMS", "release-notes.md")


class ValidationError(ValueError):
    """The supplied archive or public build identity cannot be released."""


def required_string(info, key):
    value = info.get(key)
    if (not isinstance(value, str) or not value or value != value.strip()
            or len(value) > 200 or any(ord(char) < 32 or ord(char) == 127 for char in value)
            or "$(" in value or "${" in value):
        raise ValidationError(f"Missing or invalid {key} in packaged Info.plist")
    return value


def validate_public_identity(commit, run_id, run_url):
    if not re.fullmatch(r"[0-9a-fA-F]{40}(?:[0-9a-fA-F]{24})?", commit):
        raise ValidationError("--commit must be a full hexadecimal Git commit hash")
    if not re.fullmatch(r"[1-9][0-9]*", run_id):
        raise ValidationError("--run-id must be a positive GitHub workflow run ID")
    if any(ord(char) < 32 or ord(char) == 127 for char in run_url):
        raise ValidationError("--run-url must be a public GitHub workflow URL without control characters")
    try:
        url = urlsplit(run_url)
    except ValueError as error:
        raise ValidationError("--run-url must be a valid public GitHub workflow URL") from error
    path = rf"/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/{run_id}(?:/attempts/[1-9][0-9]*)?"
    if (url.scheme != "https" or url.netloc != "github.com" or url.query or url.fragment
            or not re.fullmatch(path, url.path)):
        raise ValidationError("--run-url must be a public https://github.com workflow URL matching --run-id, without credentials or query parameters")


def toolchain_value(value, flag):
    if value is None:
        return None
    value = " ".join(value.split())
    if not value or len(value) > 120 or not re.fullmatch(r"[A-Za-z0-9_.(), +/\-]+", value):
        raise ValidationError(f"{flag} must contain only a public toolchain version")
    return value


def archive_members(archive):
    members = {}
    folded = set()
    app_roots = set()
    for member in archive.infolist():
        name = member.orig_filename
        parts = name.rstrip("/").split("/")
        if (not name or name.startswith("/") or "\\" in name
                or any(part in ("", ".", "..") for part in parts)
                or any(ord(char) < 32 or ord(char) == 127 for char in name)):
            raise ValidationError("ZIP contains an unsafe member path")
        canonical = str(PurePosixPath(name)).casefold()
        if canonical in folded:
            raise ValidationError("ZIP contains a duplicate member path")
        folded.add(canonical)
        if member.flag_bits & 1:
            raise ValidationError("Encrypted ZIP members cannot be validated")
        if stat.S_ISLNK(member.external_attr >> 16):
            raise ValidationError("ZIP contains an unsafe symbolic link")
        members[member.filename] = member
        if len(parts) >= 2 and parts[0] == "Payload" and parts[1].endswith(".app"):
            app_roots.add("/".join(parts[:2]) + "/")
    if len(app_roots) != 1:
        raise ValidationError("IPA must contain a single Payload/*.app bundle")
    return members, next(iter(app_roots))


def inspect_ipa(ipa):
    if not ipa.is_file():
        raise ValidationError("--ipa must refer to an existing IPA file")
    if (not ipa.name.endswith(".ipa") or "\\" in ipa.name
            or any(ord(char) < 32 or ord(char) == 127 for char in ipa.name)):
        raise ValidationError("--ipa must have a safe .ipa filename")
    try:
        with ipa.open("rb") as stream:
            before = os.fstat(stream.fileno())
            with zipfile.ZipFile(stream) as archive:
                members, app_root = archive_members(archive)
                plist_name = app_root + "Info.plist"
                plist_member = members.get(plist_name)
                if plist_member is None or plist_member.is_dir() or not 0 < plist_member.file_size <= 1_048_576:
                    raise ValidationError("IPA must contain one readable Payload/*.app/Info.plist")
                try:
                    info = plistlib.loads(archive.read(plist_member))
                except (plistlib.InvalidFileException, ValueError, TypeError, OverflowError, ExpatError) as error:
                    raise ValidationError("Packaged Info.plist is malformed") from error
                if not isinstance(info, dict):
                    raise ValidationError("Packaged Info.plist must be a dictionary")
                name = required_string(info, "CFBundleDisplayName")
                identifier = required_string(info, "CFBundleIdentifier")
                if name != EXPECTED_NAME:
                    raise ValidationError(f"CFBundleDisplayName must be {EXPECTED_NAME!r}")
                if identifier != EXPECTED_IDENTIFIER:
                    raise ValidationError(f"CFBundleIdentifier must be {EXPECTED_IDENTIFIER!r}")
                version = required_string(info, "CFBundleShortVersionString")
                build = required_string(info, "CFBundleVersion")
                if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
                    raise ValidationError("CFBundleShortVersionString must have three period-separated ASCII integers")
                # Release builds exclude development suffixes; keep the actual
                # packaged numeric string, including its component count.
                if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", build):
                    raise ValidationError("CFBundleVersion must have one to three period-separated ASCII integers")
                minimum_os = required_string(info, "MinimumOSVersion")
                if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", minimum_os) or int(minimum_os.split(".")[0]) <= 0:
                    raise ValidationError("MinimumOSVersion must be a positive numeric OS version")
                languages = info.get("CFBundleLocalizations")
                if (not isinstance(languages, list) or not languages
                        or any(not isinstance(language, str) or not re.fullmatch(r"[a-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})*", language) for language in languages)
                        or len({language.casefold() for language in languages}) != len(languages)):
                    raise ValidationError("CFBundleLocalizations must advertise distinct valid language identifiers")
                executable_name = required_string(info, "CFBundleExecutable")
                if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_. \-]*", executable_name) or executable_name in (".", ".."):
                    raise ValidationError("CFBundleExecutable must be a safe filename within the app bundle")
                executable = app_root + executable_name
                member = members.get(executable)
                if member is None or member.is_dir() or member.file_size == 0:
                    raise ValidationError("CFBundleExecutable is missing or empty in the IPA")
                corrupt = archive.testzip()
                if corrupt is not None:
                    raise ValidationError("ZIP integrity validation failed")
            stream.seek(0)
            digest = hashlib.sha256()
            for block in iter(lambda: stream.read(1_048_576), b""):
                digest.update(block)
            after = os.fstat(stream.fileno())
            if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                raise ValidationError("IPA changed while being inspected")
    except (zipfile.BadZipFile, RuntimeError, NotImplementedError, zlib.error) as error:
        raise ValidationError("IPA ZIP is malformed or uses unsupported encryption/compression") from error
    return {
        "display_name": name,
        "bundle_identifier": identifier,
        "version": version,
        "build": build,
        "minimum_os_version": minimum_os,
        "languages": languages,
        "executable": executable,
        "ipa": {"filename": ipa.name, "size_bytes": after.st_size, "sha256": digest.hexdigest()},
    }


def release_notes(metadata):
    toolchain = metadata["toolchain"]
    commit = metadata["commit"]
    if metadata["source_repository"]:
        commit = f'[{commit}](https://github.com/{metadata["source_repository"]}/commit/{commit})'
    rows = [
        ("Sürüm / Version", metadata["version"]),
        ("Derleme kodu / Build", metadata["build"]),
        ("Paket kimliği / Bundle ID", metadata["bundle_identifier"]),
        ("En düşük iOS / Minimum iOS", metadata["minimum_os_version"]),
        ("Bildirilen diller / Advertised languages", ", ".join(metadata["languages"])),
        ("IPA boyutu / IPA size", f'{metadata["ipa"]["size_bytes"]:,} bytes'),
        ("SHA-256", metadata["ipa"]["sha256"]),
        ("Kaynak commit / Source commit", commit),
        ("İş akışı / Workflow", f'[Run {metadata["workflow"]["run_id"]}]({metadata["workflow"]["run_url"]})'),
        ("UTC", metadata["created_at_utc"]),
        ("Doğrulama / Validation", "Geçti / Passed — archive, metadata, executable presence, SHA-256"),
        ("İmzalama / Signing", "adhoc — yeniden imzalama gerekir / re-signing required"),
    ]
    if toolchain["xcode_version"]:
        rows.append(("Xcode", toolchain["xcode_version"]))
    if toolchain["sdk_version"]:
        rows.append(("iOS SDK", toolchain["sdk_version"]))
    table = "\n".join(f"| {label} | {value} |" for label, value in rows)
    return (
        f'# {metadata["title"]}\n\n'
        "**Türkçe:** IPA arşivi ve paket bilgileri doğrulandı. Kurmadan önce IPA'yı kendi Apple hesabınızla yeniden imzalayın. "
        "Bu adım yerel oyun motorunu çalıştırmaz ve cihaz testi yapmaz.\n\n"
        "**English:** The IPA archive and packaged metadata were validated. Re-sign the IPA with your own Apple account before installation. "
        "This step does not run the native game engine or perform on-device testing.\n\n"
        "| Alan / Field | Değer / Value |\n| --- | --- |\n" + table + "\n"
    )


def create_release_metadata(ipa, output, commit, run_id, run_url, *, signing="adhoc", xcode_version=None, sdk_version=None, github_output=None, source_repository=None):
    ipa, output = Path(ipa), Path(output)
    validate_public_identity(commit, run_id, run_url)
    if source_repository is not None:
        if (not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+", source_repository)
                or source_repository.split("/")[1] in (".", "..")):
            raise ValidationError("--source-repository must be an owner/repo slug without URLs, query parameters, or extra path components")
    if signing != "adhoc":
        raise ValidationError("Only --signing adhoc is supported; the IPA requires re-signing before installation")
    toolchain = {"xcode_version": toolchain_value(xcode_version, "--xcode-version"), "sdk_version": toolchain_value(sdk_version, "--sdk-version")}
    if github_output is not None:
        github_output = Path(github_output)
        protected_paths = {ipa.resolve()}
        protected_paths.update((output / name).resolve() for name in OUTPUT_FILES)
        if github_output.resolve() in protected_paths:
            raise ValidationError("--github-output must not overwrite the IPA or release assets")
    packaged = inspect_ipa(ipa)
    metadata = {
        "schema_version": 1,
        "tag": f'v{packaged["version"]}-build.{packaged["build"]}',
        "title": f'{packaged["display_name"]} {packaged["version"]} (build {packaged["build"]})',
        **packaged,
        "commit": commit,
        "source_repository": source_repository,
        "workflow": {"run_id": run_id, "run_url": run_url},
        "created_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "toolchain": toolchain,
        "signing": {"mode": signing, "requires_resigning": True},
        "validation": {
            "status": "passed",
            "scope": "archive_metadata_and_checksum",
            "checks": ["zip_integrity", "single_payload_app", "bundle_identity", "version_build", "minimum_os", "advertised_languages", "executable_presence", "sha256"],
            "native_engine_run": False,
            "device_tested": False,
        },
    }
    contents = {
        "release-metadata.json": json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        "SHA256SUMS": f'{metadata["ipa"]["sha256"]}  {ipa.name}\n',
        "release-notes.md": release_notes(metadata),
    }
    # All validation finishes before creating or replacing any release output.
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".release-metadata-", dir=output) as temporary:
        staging = Path(temporary)
        for name, content in contents.items():
            (staging / name).write_text(content, encoding="utf-8")
        for name in OUTPUT_FILES:
            os.replace(staging / name, output / name)
    if github_output is not None:
        with github_output.open("a", encoding="utf-8") as handle:
            for key in ("tag", "title", "version", "build"):
                handle.write(f"{key}={metadata[key]}\n")
    return metadata


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--source-repository", help="Public source owner/repo used to link the actual --commit; independent of the workflow caller")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-url", required=True)
    parser.add_argument("--signing", choices=("adhoc",), default="adhoc", help="Ad-hoc signed IPA; users must re-sign before installation")
    parser.add_argument("--xcode-version")
    parser.add_argument("--sdk-version")
    parser.add_argument("--github-output", type=Path, help="Append tag/title/version/build to a GitHub Actions output file")
    args = parser.parse_args(argv)
    try:
        metadata = create_release_metadata(**vars(args))
    except (ValidationError, OSError) as error:
        print(f"Release metadata failed: {error}", file=sys.stderr)
        return 2
    print(f'Validated {metadata["ipa"]["filename"]}: {metadata["tag"]}; {metadata["ipa"]["size_bytes"]} bytes; SHA-256 {metadata["ipa"]["sha256"]}')
    print("Wrote release-metadata.json, SHA256SUMS, release-notes.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
