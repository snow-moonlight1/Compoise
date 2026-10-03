#!/usr/bin/env python3
"""Read the official CTC dictionary. Does not edit native code or emit spaces."""
from __future__ import annotations

from pathlib import Path

from q3_common import SCHEMA_DICT, Q3Error, bundle_problems, load_lock, sha256_file


def tokens_after_loader(data: bytes) -> list[str]:
    """Same line split as the production loader: drop trailing CR and ASCII space."""
    text = data.decode("utf-8")
    tokens = []
    position = 0
    while position <= len(text):
        newline = text.find("\n", position)
        line = text[position:] if newline < 0 else text[position:newline]
        while line.endswith("\r") or line.endswith(" "):
            line = line[:-1]
        tokens.append(line)
        if newline < 0:
            break
        position = newline + 1
    return tokens


def probe_assets(assets: Path) -> dict:
    problems = bundle_problems(assets)
    if problems:
        raise Q3Error("missing or unexpected model:\n" + "\n".join(problems))
    path = assets / "ncnn" / "ppocrv5_dict.txt"
    data = path.read_bytes()
    tokens = tokens_after_loader(data)
    ascii_space = [index for index, token in enumerate(tokens) if token == " "]
    ideographic = [index for index, token in enumerate(tokens) if token == "\u3000"]
    lock = load_lock()
    return {
        "schema": SCHEMA_DICT,
        "sha256": sha256_file(path),
        "lock_sha256": lock["dependencies"]["ncnn/ppocrv5_dict.txt"]["sha256"],
        "tokens_after_loader": len(tokens),
        "ascii_space_u0020_indexes": ascii_space,
        "ideographic_space_u3000_indexes": ideographic,
        "first_token_codepoints": [hex(ord(char)) for char in tokens[0]],
        "ctc_blank_class": 0,
        "dict_index_0_ctc_class": 1,
        "production_note": (
            "Class 0 is the CTC blank and is skipped. Dictionary line i is class i+1. "
            "The loader strips trailing ASCII spaces. U+0020 is not inserted into output."
        ),
    }
