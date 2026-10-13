#!/usr/bin/env python3
"""Create an MSVC import library for a Tesseract DLL built with MinGW.

The UB Mannheim Windows distribution ships ``libtesseract-5.dll`` but neither
headers nor an import library, and MSVC's linker refuses to link the DLL
directly (LNK1107).  ``dumpbin /exports`` followed by ``lib /def:`` produces a
usable import library; this script does the bookkeeping.

Usage (from a VS developer environment, or with explicit tool paths):

    python make_tess_implib.py \
        --dll "C:/Program Files/Tesseract-OCR/libtesseract-5.dll" \
        --dumpbin "<MSVC bin>/dumpbin.exe" \
        --lib "<MSVC bin>/lib.exe" \
        --out    "<asset root>/tess-implib"
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

EXPORT_RE = re.compile(r"^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)\s*$")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dll", required=True)
    ap.add_argument("--dumpbin", required=True)
    ap.add_argument("--lib", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    res = subprocess.run([args.dumpbin, "/exports", args.dll], capture_output=True, text=True)
    text = res.stdout
    names = []
    for line in text.splitlines():
        m = EXPORT_RE.match(line)
        if m:
            names.append(m.group(1))
    if not names:
        print("no exports parsed from dumpbin output", file=sys.stderr)
        print(text[-2000:], file=sys.stderr)
        return 1

    def_path = os.path.join(args.out, "tesseract.def")
    with open(def_path, "w", encoding="ascii", newline="\r\n") as f:
        f.write("LIBRARY " + os.path.basename(args.dll) + "\nEXPORTS\n")
        for n in names:
            f.write(n + "\n")

    lib_path = os.path.join(args.out, "tesseract.lib")
    res2 = subprocess.run(
        [args.lib, "/nologo", "/def:" + def_path, "/machine:x64", "/out:" + lib_path],
        capture_output=True,
        text=True,
    )
    if res2.returncode != 0 or not os.path.exists(lib_path):
        print("lib.exe failed", file=sys.stderr)
        print(res2.stdout[-2000:], file=sys.stderr)
        print(res2.stderr[-2000:], file=sys.stderr)
        return 1
    print(f"{len(names)} exports -> {lib_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
