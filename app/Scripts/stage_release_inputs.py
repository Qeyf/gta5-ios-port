#!/usr/bin/env python3
"""Stage user-owned private Release ZIP inputs into a new minimal game mirror.

Usage:
  python3 app/Scripts/stage_release_inputs.py --archive Release-inputs.zip \
      --shaders-archive shaders.zip --out /tmp/game-files
  python3 app/Scripts/check_game_files.py --mirror /tmp/game-files

Only game.wasm, manifest.json, index.json, and the index's raw shader packs are
read. Nested ZIP paths are mapped by basename onto fixed b/ and data/ paths;
unknown files/directories are ignored without extraction. Core hashes are
pinned to build 8b0b5899ed. A pack must have its index's exact byte size.
Identical copies across the two ZIPs merge after streamed SHA-256 comparison;
duplicate recognized basenames within either ZIP and conflicting copies fail.

Missing packs are allowed during staging and reported as warnings. Staging
success does not imply a complete build mirror: check_game_files.py remains
strict, and the raw packs must be supplied before building. Existing output
paths, including empty directories and symlinks, are never reused. Validation
finishes in temporary storage before a destination is exclusively created and
populated. No build consumer should start until this command succeeds.
"""
import argparse
from contextlib import ExitStack
import hashlib
import ntpath
import os
from pathlib import Path
import shlex
import shutil
import stat
import sys
import tempfile
import zipfile

import check_game_files as check


InputError = check.InputError
SHADERS = Path('b/8b0b5899ed/shaders')
CORE_TARGETS = {'game.wasm': Path('b/8b0b5899ed/game.wasm'),
                'manifest.json': Path('data/manifest.json'),
                'index.json': SHADERS / 'index.json'}
# Decimal byte ceilings cover the supported 63.2 MB engine, 0.7 MB index,
# 0.4 MB manifest, and packs of at most 4.2 MB without unbounded inflation.
CORE_LIMITS = {'game.wasm': 64_000_000, 'manifest.json': 500_000,
               'index.json': 1_000_000}
MAX_ARCHIVE_BYTES = 250_000_000
MAX_TOTAL_BYTES = 250_000_000
MAX_ENTRIES = 10_000
CHUNK_BYTES = 1 << 20


def member_basename(member):
    return member.filename.replace('\\', '/').rsplit('/', 1)[-1]


def recognized_entries(entries, name):
    found, seen = [], set()
    for number, archive, member in entries:
        if member_basename(member) != name:
            continue
        if number in seen:
            raise InputError(f'Duplicate recognized basename {name} within one ZIP.')
        seen.add(number)
        found.append((archive, member))
    return found


def validate_member(member, limit, expected=None):
    normalized = member.filename.replace('\\', '/')
    if ('\0' in member.orig_filename or normalized.startswith('/')
            or ntpath.splitdrive(normalized)[0] or '..' in normalized.split('/')):
        raise InputError(f'Unsafe ZIP member {member.filename!r}.')
    mode = stat.S_IFMT(member.external_attr >> 16)
    if mode not in (0, stat.S_IFREG) or member.external_attr & 0x10:
        raise InputError(f'Recognized ZIP member {member.filename!r} must be a regular file.')
    if member.flag_bits & 1:
        raise InputError(f'Encrypted ZIP member {member.filename!r} is not supported.')
    if member.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
        raise InputError(f'Unsupported ZIP compression for {member.filename!r}; use a normal ZIP.')
    if not 0 <= member.file_size <= limit:
        raise InputError(f'{member_basename(member)} exceeds its {limit}-byte size limit.')
    if expected is not None and member.file_size != expected:
        raise InputError(f'Wrong size for shader pack {member_basename(member)}: expected {expected} bytes, got {member.file_size}.')


def copy_recognized(copies, target, limit, budget, expected=None):
    """Bound reads even if ZIP metadata lies, verify CRC, and compare duplicates."""
    target.parent.mkdir(parents=True, exist_ok=True)
    first = None
    for archive, member in copies:
        validate_member(member, limit, expected)
        budget['declared'] += member.file_size
        if budget['declared'] > MAX_TOTAL_BYTES:
            raise InputError('Recognized ZIP entries exceed the total decompressed size limit.')
        digest, total = hashlib.sha256(), 0
        with ExitStack() as stack:
            source = stack.enter_context(archive.open(member))
            destination = stack.enter_context(target.open('xb')) if first is None else None
            while True:
                chunk = source.read(min(CHUNK_BYTES, limit + 1 - total))
                if not chunk:
                    break
                total += len(chunk)
                budget['actual'] += len(chunk)
                if total > limit or budget['actual'] > MAX_TOTAL_BYTES:
                    raise InputError('ZIP data exceeds its decompressed size limit.')
                digest.update(chunk)
                if destination is not None:
                    destination.write(chunk)
        if total != member.file_size:
            raise InputError(f'Truncated ZIP member {member.filename!r}: expected {member.file_size} bytes, got {total}.')
        identity = (total, digest.digest())
        if first is not None and identity != first:
            raise InputError(f'Conflicting copies of {member_basename(member)} across ZIP archives.')
        first = identity


def publish(validated, output):
    """Reserve a new directory; roll back only the directory this call created."""
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        output.mkdir(mode=0o700)
    except FileExistsError as error:
        raise InputError(f'Output already exists: {output}. Choose a new --out path.') from error
    try:
        for child in validated.iterdir():
            shutil.move(str(child), str(output / child.name))
    except BaseException:
        shutil.rmtree(output, ignore_errors=True)
        raise


def stage_release_inputs(archive, output, shaders_archive=None):
    """Validate ZIPs, stage a new mirror, and return counts plus missing packs."""
    output = Path(output)
    if os.path.lexists(output):
        raise InputError(f'Output already exists: {output}. Choose a new --out path.')
    sources = [Path(archive)] + ([Path(shaders_archive)] if shaders_archive else [])
    try:
        if sum(path.stat().st_size for path in sources) > MAX_ARCHIVE_BYTES:
            raise InputError('Input archives exceed the archive size limit.')
        with ExitStack() as stack, tempfile.TemporaryDirectory(prefix='release-inputs-') as temporary:
            validated = Path(temporary)
            entries, directories = [], 0
            for number, path in enumerate(sources):
                opened = stack.enter_context(zipfile.ZipFile(path))
                members = opened.infolist()
                if len(members) > MAX_ENTRIES:
                    raise InputError(f'ZIP archive {path.name} has too many entries.')
                for member in members:
                    if member.is_dir():
                        directories += 1
                    else:
                        entries.append((number, opened, member))
            core = {}
            for name in CORE_TARGETS:
                core[name] = recognized_entries(entries, name)
                if not core[name]:
                    raise InputError(f'Missing {name} in the supplied ZIP inputs.')
            budget = {'declared': 0, 'actual': 0}
            copy_recognized(core['index.json'], validated / CORE_TARGETS['index.json'],
                            CORE_LIMITS['index.json'], budget)
            packs = check.shader_pack_sizes(validated / CORE_TARGETS['index.json'])
            for name in ('game.wasm', 'manifest.json'):
                copy_recognized(core[name], validated / CORE_TARGETS[name], CORE_LIMITS[name], budget)
            recognized = set(CORE_TARGETS)
            copies = sum(len(group) for group in core.values())
            files = len(core)
            for name, expected in packs.items():
                group = recognized_entries(entries, name)
                if group:
                    copy_recognized(group, validated / SHADERS / name,
                                    check.MAX_PACK_BYTES, budget, expected)
                    recognized.add(name)
                    copies += len(group)
                    files += 1
            missing = check.validate_game_files(validated, allow_missing_packs=True)
            ignored = directories + sum(member_basename(member) not in recognized for _, _, member in entries)
            publish(validated, output)
            return {'files_written': files, 'merged_duplicates': copies - files,
                    'ignored_entries': ignored, 'missing_packs': missing}
    except (zipfile.BadZipFile, zipfile.LargeZipFile, NotImplementedError, RuntimeError) as error:
        raise InputError(f'Could not read ZIP input: {error}') from error
    except OSError as error:
        raise InputError(f'Could not stage ZIP inputs: {error}') from error


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--archive', type=Path, required=True, help='private Release input ZIP with engine, manifest and index')
    parser.add_argument('--shaders-archive', type=Path, help='optional ZIP of raw shader packs, with or without its index')
    parser.add_argument('--out', type=Path, required=True, help='new minimal mirror directory; existing paths are refused')
    args = parser.parse_args(argv)
    try:
        result = stage_release_inputs(args.archive, args.out, args.shaders_archive)
    except InputError as error:
        print(error, file=sys.stderr)
        return 1
    print(f"Staged {result['files_written']} recognized files in {args.out}.")
    if result['merged_duplicates']:
        print(f"Merged {result['merged_duplicates']} identical copies across ZIP inputs.")
    if result['ignored_entries']:
        print(f"Warning: Ignored {result['ignored_entries']} unknown files/directories; no archive paths were extracted.", file=sys.stderr)
    if result['missing_packs']:
        missing = result['missing_packs']
        print(f"Warning: Missing {len(missing)} shader packs: {', '.join(missing)}. Supply the raw packs before building.", file=sys.stderr)
    print(f'Check before building: python3 app/Scripts/check_game_files.py --mirror {shlex.quote(str(args.out))}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
