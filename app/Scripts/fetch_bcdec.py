#!/usr/bin/env python3
"""Verify/fetch the same pinned upstream header for portable and Apple checks."""
import hashlib
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
HEADER = ROOT / "Tools/bcdec/bcdec.h"
SHA256 = "134520764d96f70a27db814173616c89ad85db95fbd3328417c7a8c77e7ca189"
URL = "https://raw.githubusercontent.com/iOrange/bcdec/80859ed3b7afb1c527a2a99d70c61457bea72d0c/bcdec.h"


def main():
    if HEADER.is_file() and hashlib.sha256(HEADER.read_bytes()).hexdigest() == SHA256:
        return
    with urllib.request.urlopen(URL, timeout=30) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise SystemExit("Pinned BC decoder checksum mismatch")
    HEADER.parent.mkdir(parents=True, exist_ok=True)
    temporary = HEADER.with_suffix(".tmp")
    temporary.write_bytes(data)
    temporary.replace(HEADER)


if __name__ == "__main__":
    main()
