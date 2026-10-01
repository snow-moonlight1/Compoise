#!/usr/bin/env bash
# Rebuild the pinned ncnn commit for the Linux host so the same OCR source can
# link against it. The ncnn tree and its install prefix live outside the
# repository; only this script is tracked.
set -euo pipefail

WP17R2_ASSETS="${WP17R2_ASSETS:-$HOME/.cache/wp17r2-assets}"
WORK="${WP17_NCNN_WORK:-$HOME/wp17i4-ncnn-linux}"
SRC="$WP17R2_ASSETS/ncnn-src"
INSTALL="$WORK/install"

if [ ! -d "$SRC/.git" ]; then
  printf 'missing ncnn source tree: %s\n' "$SRC" >&2
  exit 2
fi

wanted="$(tr -d '\r\n' < "$(dirname "$0")/../../third_party/ncnn_pin.txt" 2>/dev/null || true)"
if [ -z "${wanted:-}" ]; then
  wanted=c6b351b56fbe32e0381ae00331e3df649b20d7b7
fi
have="$(git -C "$SRC" rev-parse HEAD)"
if [ "$have" != "$wanted" ]; then
  printf 'ncnn source is %s, expected %s\n' "$have" "$wanted" >&2
  exit 3
fi

cmake -S "$SRC" -B "$WORK" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL" \
  -DNCNN_VULKAN=OFF \
  -DNCNN_OPENMP=ON \
  -DNCNN_SHARED_LIB=OFF \
  -DNCNN_BUILD_TOOLS=OFF \
  -DNCNN_BUILD_TESTS=OFF \
  -DNCNN_BUILD_BENCHMARK=OFF \
  -DNCNN_BUILD_EXAMPLES=OFF \
  -DNCNN_INSTALL_SDK=ON \
  -DNCNN_PIXEL=ON \
  -DNCNN_PIXEL_AFFINE=ON \
  -DNCNN_PIXEL_DRAWING=ON \
  -DNCNN_PIXEL_ROTATE=ON \
  -DNCNN_STRING=ON \
  -DNCNN_INT8=ON \
  -DNCNN_BF16=ON \
  -DNCNN_BATCH=ON \
  -DNCNN_WEIGHT_QUANT=ON \
  -DNCNN_C_API=ON
cmake --build "$WORK" --parallel "$(nproc)"
cmake --install "$WORK"
printf 'ncnn install: %s\n' "$INSTALL"
