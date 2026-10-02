# WP17-I4/I5 third-party and model notices

I5 (2026-10-02): the official PIR conversion and two independent byte-identical
replays succeeded on Linux; the pinned artifacts passed the unchanged R2
text/geometry comparison on Windows and Linux. See `docs/WP17_I5_NOTES.md`.
This verifies the official model path, not authorization to publish a release.
Default builds still contain no OCR model or native OCR library.

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
| PP-OCRv5 mobile weights — **official conversion** | Six unchanged I4 input hashes, now also pinned to HF det `0d63e78e2b680928f6b1747d76a08db6e645efb7` / rec `682f20538d8c086cb2128e5cfac775e6c4904e85`; output hashes in `native/ocr/tools/models.lock.json` | Apache-2.0 per the saved model cards | exact pinned conversion verified in I5; ship the licence, cards and provenance with any subsequently authorized distribution |
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
| export | `paddle2onnx 2.1.0`, `paddlepaddle 3.0.0`, `onnx 1.17.0`, `onnxoptimizer 0.4.2`; all 22 conversion packages/wheel sources in `conversion_toolchain.lock.json` | `--opset_version 11 --enable_onnx_checker True --enable_auto_update_opset False --optimize_tool onnxoptimizer` |
| convert | `pnnx 20260526`, Linux executable sha256 `c3555c48e054245e50fa434a7673fbdad2b8f8c6cdca8c1579601f9882f474a0` | det: `inputshape=[1,3,320,320] inputshape2=[1,3,256,256]`; rec: `inputshape=[1,3,48,160] inputshape2=[1,3,48,256]`; `fp16=1 optlevel=2` |
| load | `lib/ocr/ocr_runtime.dart` | `<assetsRoot>/ncnn/PP_OCRv5_mobile_{det,rec}.ncnn.{param,bin}` + `ppocrv5_dict.txt` |

The input shapes match the multi-shape models the runtime expects; the runtime
selects the shape at inference time, so a single-shape conversion is not an
acceptable substitute.

## Licence attachments and deployment

`licenses/` contains unmodified upstream Apache-2.0, stb MIT/Unlicense, the
complete ncnn notice (including its embedded zlib/MIT dependency notices), and
both official model cards. `models.lock.json` pins each attachment's source,
size and SHA-256. The publisher stages these five attachments beside `ncnn/`
and `deployed.json`; missing or changed attachments stop publication. Retain
that whole directory and this notice in any authorized OCR distribution.

The ncnn licence's upstream LF bytes have SHA-256
`7c974bac98848df46be1af5bdaa3c3c9c01f6082a90f55caeb7f60c6208aa255`.
The historical Windows checkout's CRLF bytes have the I4 hash
`3a066e39806976fe274a042929523c68821c54bcf73369ed61aae2717edd54e8`;
the texts match after CRLF-to-LF normalization. The supplied attachment uses
the upstream bytes and Git attributes preserve LF on Windows.

Paddle/Paddle2ONNX/ONNX/onnxoptimizer/pnnx and the other conversion packages are
private build tools, not part of the deployed C++ runtime. Their wheels and
venv are not shipped. pnnx's native CLI does not require the optional PyTorch
Python wrapper. Windows dynamically requires the MSVC/OpenMP runtime; Linux
requires system libc/libm/libstdc++/libgcc_s. Distribution of those system
dependencies belongs to the later packaging gate; no such binaries are in this
package. ncnn is linked statically, CPU only, Vulkan disabled.

## Files that must never enter the repository

* any `PP_OCRv5_mobile_*.ncnn.bin` / `.param` (weights)
* `stb_image.h` (vendored copy) — fetched into the asset root instead
* `ncnn` source tree, `ncnn.lib` / `libncnn.a` / `ncnn.dll`
* `matrixflow_ocr.dll`, `libmatrixflow_ocr.so`
* APKs, build caches, download logs
