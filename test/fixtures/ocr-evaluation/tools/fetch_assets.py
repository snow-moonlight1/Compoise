#!/usr/bin/env python3
"""Download and verify third-party artefacts for the WP17-R2 benchmark.

Existing entries in ``assets.lock.json`` are immutable checksums. A changed
upstream ``main`` file therefore fails verification instead of silently changing
the benchmark inputs. New entries are added with their observed digest.

Asset root resolution order:
  1. ``$WP17R2_ASSETS``
  2. ``%LOCALAPPDATA%/wp17r2-assets``  (Windows)
  3. ``~/.cache/wp17r2-assets``        (Linux/macOS)

Large blobs (models, tessdata, installers) live outside the repository on
purpose: WP17-R2 must not commit model binaries.
"""
from __future__ import annotations

import hashlib
import json
import os
import platform
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
LOCK = os.path.join(os.path.dirname(HERE), "assets.lock.json")

NCNN = "https://raw.githubusercontent.com/nihui/ncnn-android-ppocrv5/master/app/src/main/assets/"
PADDLE_DICT = [
    "https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/ppocr/utils/dict/ppocrv5_dict.txt",
    "https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/release/3.0/ppocr/utils/dict/ppocrv5_dict.txt",
]
TESSDATA = "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/"
TESS_WIN = "https://digi.bib.uni-mannheim.de/tesseract/tesseract-ocr-w64-setup-5.4.0.20240606.exe"

ASSETS: list[tuple[str, str, str]] = [  # (key, url(s), relative dest)
    ("ppocrv5_det_param", NCNN + "PP_OCRv5_mobile_det.ncnn.param", "ncnn/PP_OCRv5_mobile_det.ncnn.param"),
    ("ppocrv5_det_bin", NCNN + "PP_OCRv5_mobile_det.ncnn.bin", "ncnn/PP_OCRv5_mobile_det.ncnn.bin"),
    ("ppocrv5_rec_param", NCNN + "PP_OCRv5_mobile_rec.ncnn.param", "ncnn/PP_OCRv5_mobile_rec.ncnn.param"),
    ("ppocrv5_rec_bin", NCNN + "PP_OCRv5_mobile_rec.ncnn.bin", "ncnn/PP_OCRv5_mobile_rec.ncnn.bin"),
    ("ppocrv5_dict", PADDLE_DICT, "ncnn/ppocrv5_dict.txt"),
    ("stb_image", "https://raw.githubusercontent.com/nothings/stb/master/stb_image.h", "third_party/stb_image.h"),
    ("tessdata_chi_sim", TESSDATA + "chi_sim.traineddata", "tessdata_fast/chi_sim.traineddata"),
    ("tessdata_eng", TESSDATA + "eng.traineddata", "tessdata_fast/eng.traineddata"),
    ("tessdata_jpn", TESSDATA + "jpn.traineddata", "tessdata_fast/jpn.traineddata"),
]

if platform.system() == "Windows":
    ASSETS.append(("tesseract_win_setup", TESS_WIN, "installer/tesseract-ocr-w64-setup.exe"))


def asset_root() -> str:
    if os.environ.get("WP17R2_ASSETS"):
        return os.path.abspath(os.environ["WP17R2_ASSETS"])
    if platform.system() == "Windows":
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
        return os.path.join(base, "wp17r2-assets")
    return os.path.expanduser("~/.cache/wp17r2-assets")


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(urls, dest: str, tries: int = 4) -> None:
    if isinstance(urls, str):
        urls = [urls]
    last = None
    for attempt in range(tries):
        for url in urls:
            tmp = dest + ".part"
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "wp17r2-ocr-bench/1.0"})
                with urllib.request.urlopen(req, timeout=180) as r, open(tmp, "wb") as f:
                    while True:
                        chunk = r.read(1 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
                os.replace(tmp, dest)
                return
            except Exception as e:  # noqa: BLE001
                last = f"{url}: {e}"
                if os.path.exists(tmp):
                    os.remove(tmp)
        time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"failed to fetch {dest}: {last}")


def main() -> int:
    root = asset_root()
    os.makedirs(root, exist_ok=True)
    lock: dict[str, dict[str, object]] = {}
    if os.path.exists(LOCK):
        with open(LOCK, encoding="utf-8") as f:
            lock = json.load(f)
    for key, urls, rel in ASSETS:
        dest = os.path.join(root, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if not os.path.exists(dest):
            print(f"[fetch] {rel}")
            fetch(urls, dest)
        digest = sha256(dest)
        pinned = lock.get(key)
        if pinned and digest != pinned["sha256"]:
            raise RuntimeError(
                f"checksum mismatch for {rel}: expected {pinned['sha256']}, got {digest}"
            )
        lock[key] = {
            "path": rel,
            "url": urls if isinstance(urls, list) else [urls],
            "bytes": os.path.getsize(dest),
            "sha256": digest,
        }
        print(f"[ok]    {rel:44} {os.path.getsize(dest):>10} {digest[:16]}")
    with open(LOCK, "w", encoding="utf-8") as f:
        json.dump(lock, f, indent=2, sort_keys=True, ensure_ascii=False)
        f.write("\n")
    print(f"\nasset root: {root}\nlock file : {LOCK}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
