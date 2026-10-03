#!/usr/bin/env python3
"""Opt-in native recognition. The default test path never calls this."""
from __future__ import annotations

import ctypes
import json
import os
from pathlib import Path

from q3_common import SCHEMA_RAW, Q3Error, bundle_problems


def recognize_directory(library: Path, assets: Path, labels_dir: Path, cases: list[dict], threads: int = 4) -> dict:
    problems = bundle_problems(assets)
    if problems:
        raise Q3Error("missing or unexpected model:\n" + "\n".join(problems))
    if not library.is_file():
        raise Q3Error(f"missing OCR library: {library}")
    if threads < 1 or threads > 4:
        raise Q3Error("threads must be from 1 to 4")
    lib = ctypes.CDLL(str(library.resolve()))
    lib.mf_ocr_create.argtypes = [ctypes.c_char_p, ctypes.c_int]
    lib.mf_ocr_create.restype = ctypes.c_void_p
    lib.mf_ocr_destroy.argtypes = [ctypes.c_void_p]
    lib.mf_ocr_run_file.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lib.mf_ocr_run_file.restype = ctypes.c_void_p
    lib.mf_ocr_free.argtypes = [ctypes.c_void_p]
    session = lib.mf_ocr_create(os.fsencode(str(assets.resolve())), threads)
    if not session:
        raise Q3Error("native OCR session was not created")
    images = []
    try:
        for case in cases:
            path = labels_dir / f"{case['id']}.png"
            pointer = lib.mf_ocr_run_file(session, os.fsencode(path))
            if not pointer:
                images.append({"id": case["id"], "error": "native result allocation failed", "lines": []})
                continue
            try:
                result = json.loads(ctypes.string_at(pointer).decode("utf-8"))
            finally:
                lib.mf_ocr_free(pointer)
            images.append({
                "id": case["id"],
                "error": result.get("error") or "",
                "width": result.get("width"),
                "height": result.get("height"),
                "lines": result.get("lines") or [],
            })
    finally:
        lib.mf_ocr_destroy(session)
    return {"schema": SCHEMA_RAW, "engine_schema": "wp17-i1-ocr/1", "images": images}
