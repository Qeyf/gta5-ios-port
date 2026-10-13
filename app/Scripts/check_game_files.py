#!/usr/bin/env python3
"""Check that a game folder has what the build needs, from game build 8b0b5899ed:
the engine, the file list and the shaders (index.json and its packs)."""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ENGINE_SHA256 = '11ca8d2c04c5e843d18ff4aea4899d72c86973c6b031df334e67c446b2ae83e0'
SHADER_INDEX_SHA256 = '11c331895051b30126980ef666bd8935314ab400348b17c56ef8fe8983f50ee0'
MAX_PACK_BYTES = 4_200_000
PACK_NAME = re.compile(r'pack[0-9]+\.[0-9a-f]{8,64}\.bin\Z', re.ASCII)


class InputError(ValueError):
    """A supplied build input is absent, unsupported, or incomplete."""


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def shader_pack_sizes(index):
    """Read safe pack basenames and exact byte sizes from the supported index."""
    if sha256(index) != SHADER_INDEX_SHA256:
        raise InputError('Your shader index does not match game build 8b0b5899ed.')
    try:
        records = json.loads(index.read_text(encoding='utf-8'))['_packs']
        if not isinstance(records, list) or not 1 <= len(records) <= 64:
            raise ValueError('expected a nonempty _packs list with at most 64 packs')
        sizes = {}
        for record in records:
            name, size = record['file'], record['bytes']
            if not isinstance(name, str) or not PACK_NAME.fullmatch(name):
                raise ValueError('unsafe or invalid pack basename')
            if name in sizes:
                raise ValueError('duplicate pack basename')
            if type(size) is not int or not 0 < size <= MAX_PACK_BYTES:
                raise ValueError('invalid pack byte size')
            sizes[name] = size
        return sizes
    except (ValueError, TypeError, KeyError, UnicodeError) as error:
        raise InputError(f'Invalid shader index: {error}') from error


def validate_game_files(mirror, *, allow_missing_packs=False):
    """Validate core hashes and every present pack's indexed size; return missing names."""
    mirror = Path(mirror)
    engine = mirror / 'b/8b0b5899ed/game.wasm'
    index = mirror / 'b/8b0b5899ed/shaders/index.json'
    for required in [engine, mirror / 'data/manifest.json', index]:
        if not required.is_file():
            raise InputError(f'Missing {required.relative_to(mirror)} in {mirror}. Use the folder that contains data/ and b/.')
    if sha256(engine) != ENGINE_SHA256:
        raise InputError('Your game.wasm is not the build this port supports (8b0b5899ed).')
    missing = []
    for name, expected in shader_pack_sizes(index).items():
        pack = index.parent / name
        if not pack.is_file():
            missing.append(name)
            continue
        actual = pack.stat().st_size
        if actual != expected:
            raise InputError(f'Wrong size for shader pack {name}: expected {expected} bytes, got {actual}. Upload the complete raw shader pack again.')
    if missing and not allow_missing_packs:
        raise InputError(f'Missing shader pack {missing[0]} next to the shader index ({len(missing)} missing). Supply the raw shader packs before building.')
    return missing


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mirror', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        validate_game_files(args.mirror)
    except (InputError, OSError) as error:
        print(error, file=sys.stderr)
        return 1
    print('Game files OK.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
