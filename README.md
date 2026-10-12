# Compoise OCR models v1

On-demand download for Compoise screenshot import (local OCR). Not part of the app source tree.

- PP-OCRv5 mobile det/rec (PaddlePaddle, Apache-2.0), converted to ncnn with the pinned
  toolchain in `native/ocr/tools/conversion_toolchain.lock.json`; byte-identical to
  `native/ocr/tools/models.lock.json` in the main branch.
- `ppocrv5_dict.txt` from PaddleOCR (Apache-2.0).
- Licences and notices: `licenses/`. Hashes: `SHA256SUMS.txt` (files under `ncnn/`).
