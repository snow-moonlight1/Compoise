# WP17-I4 third-party and model notices

Scope: the optional offline OCR component (`native/ocr`, `lib/ocr`,
`lib/screenshot_import`). No model weight, no DLL/SO and no cached download is
stored in this repository. The tables below record what a prepared deployment
contains, where each file comes from, and whether redistribution is cleared.

This file is intentionally narrower than the public `assets/licenses/THIRD_PARTY_NOTICES.txt`.
The integration owner merges the cleared rows into the public notice set; rows
marked **not cleared** must not be merged.

## Component licence state

| Component | Pinned identity | Licence | Redistribution with the app |
|---|---|---|---|
| ncnn | `Tencent/ncnn` @ `c6b351b56fbe32e0381ae00331e3df649b20d7b7` (`LICENSE.txt`, sha256 `3a066e39806976fe274a042929523c68821c54bcf73369ed61aae2717edd54e8`) | BSD-3-Clause | cleared, retain the licence text |
| stb_image.h | `nothings/stb` `stb_image.h` v2.30 (sha256 `594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3`) | file header states public domain; upstream also offers MIT or Unlicense | cleared, retain the file header |
| PP-OCRv5 dictionary | `PaddlePaddle/PaddleOCR` `ppocr/utils/dict/ppocrv5_dict.txt` (sha256 `d1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b`) | repository is Apache-2.0 | cleared, retain the notice |
| PP-OCRv5 mobile weights — **official conversion** | `PaddlePaddle/PP-OCRv5_mobile_{det,rec}` on Hugging Face, model card `license: apache-2.0`; converted by `native/ocr/tools/convert_models.py` | Apache-2.0 per the model card | cleared once the pinned conversion is verified (`tool/prepare_ocr_assets.ps1 -ModelSource official`) |
| PP-OCRv5 mobile weights — **nihui conversion** | `nihui/ncnn-android-ppocrv5` `app/src/main/assets/PP_OCRv5_mobile_{det,rec}.ncnn.{param,bin}` (the four hashes in `docs/evidence/wp17r2/assets.lock.json`) | **no licence declared**; `GET /repos/nihui/ncnn-android-ppocrv5/license` returns 404 and the README documents only the conversion recipe | **not cleared**: validation only, must not be shipped or committed |

## Why the nihui weights are not cleared

The repository has no licence file, and the README explains how the weights were
derived (`paddle2onnx`, then `pnnx`) without stating terms for the result. The
upstream PaddleOCR repository being Apache-2.0 does not by itself state terms for
a third party's converted binary. Treating "the source project is Apache-2.0" as
a redistribution grant for the derived `bin`/`param` is exactly the inference this
package must not make.

The cleared path is the official one: the Hugging Face model cards for
`PaddlePaddle/PP-OCRv5_mobile_det` and `PaddlePaddle/PP-OCRv5_mobile_rec` declare
`license: apache-2.0` (also present as a `license:apache-2.0` model tag), and the
conversion input is the official Paddle inference model
(`inference.json` + `inference.pdiparams`) whose SHA-256 is pinned in
`native/ocr/tools/models.lock.json`.

## Conversion recipe (fixed toolchain)

| Step | Tool and version | Parameters |
|---|---|---|
| fetch | official Paddle inference model from Hugging Face | `inference.json`, `inference.pdiparams`, `inference.yml`, SHA-256 pinned |
| export | `paddle2onnx 0.9.2` (PaddleX CLI equivalent: `paddlex --paddle2onnx`) | `--opset_version 11` |
| convert | `pnnx 20260526` | det: `inputshape=[1,3,320,320] inputshape2=[1,3,256,256]`; rec: `inputshape=[1,3,48,160] inputshape2=[1,3,48,256]` |
| load | `lib/ocr/ocr_runtime.dart` | `<assetsRoot>/ncnn/PP_OCRv5_mobile_{det,rec}.ncnn.{param,bin}` + `ppocrv5_dict.txt` |

The input shapes match the multi-shape models the runtime expects; the runtime
selects the shape at inference time, so a single-shape conversion is not an
acceptable substitute.

## Files that must never enter the repository

* any `PP_OCRv5_mobile_*.ncnn.bin` / `.param` (weights)
* `stb_image.h` (vendored copy) — fetched into the asset root instead
* `ncnn` source tree, `ncnn.lib` / `libncnn.a` / `ncnn.dll`
* `matrixflow_ocr.dll`, `libmatrixflow_ocr.so`
* APKs, build caches, download logs
