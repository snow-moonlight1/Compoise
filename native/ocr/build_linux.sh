#!/usr/bin/env bash
set -euo pipefail

R2_WORK="${WP17_R2_WORK:-$HOME/wp17r2}"
BUILD="${WP17_I1_BUILD:-$HOME/wp17i1-native-build}"
SOURCE="$(cd "$(dirname "$0")" && pwd)"

cmake -S "$SOURCE" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release \
  -Dncnn_DIR="$R2_WORK/ncnn-build/install/lib/cmake/ncnn" \
  -DWP17_STB_DIR="$R2_WORK/assets/third_party"
cmake --build "$BUILD" -j "$(nproc)"
printf 'library: %s/libmatrixflow_ocr.so\n' "$BUILD"
