#!/usr/bin/env bash
# WP17-I4 Linux leg: build the Flutter release bundle with the optional OCR
# component enabled and stage the shared object plus the model layout next to
# it, so the bundle's own resource lookup is what gets exercised.
#
# Inputs (all outside the repository):
#   $WP17R2_ASSETS  asset root with ncnn-src, third_party/stb_image.h and ncnn/
#   $WP17_NCNN_INSTALL  an ncnn install tree (see build_ncnn_linux.sh)
set -euo pipefail

REPO="${WP17_REPO:-$HOME/wp17i4-build}"
ASSETS="${WP17R2_ASSETS:-$HOME/.cache/wp17r2-assets}"
NCNN="${WP17_NCNN_INSTALL:-$HOME/wp17i4-ncnn-linux/install}"
FLUTTER="${WP17_FLUTTER:-$HOME/develop/flutter}"
OUT="${WP17_LINUX_OUT:-$HOME/wp17i4-linux-deploy}"
API="${WP17_API:-}"

export PATH="$FLUTTER/bin:$PATH"
export WP17_OCR_NCNN_DIR="$NCNN/lib/cmake/ncnn"
export WP17_OCR_STB_DIR="$ASSETS/third_party"

echo "flutter   : $(cat "$FLUTTER/version") ($("$FLUTTER/bin/dart" --version 2>&1))"
echo "ncnn      : $WP17_OCR_NCNN_DIR"
echo "stb       : $WP17_OCR_STB_DIR"
echo "repo      : $REPO"

cd "$REPO"
if [ "${WP17_SKIP_PUB_GET:-0}" != "1" ]; then
  flutter pub get --offline 2>&1 | tail -2
else
  # A machine without a route to pub.dev reuses an existing package_config.json
  # for the same pubspec.lock; `flutter build --no-pub` does not rewrite it.
  test -f .dart_tool/package_config.json || {
    echo "WP17_SKIP_PUB_GET=1 needs .dart_tool/package_config.json" >&2
    exit 1
  }
  echo "pub get   : skipped, reusing .dart_tool/package_config.json"
fi
flutter build linux --release --no-pub 2>&1 | tail -20

BUNDLE="$REPO/build/linux/x64/release/bundle"
test -x "$BUNDLE/matrixflow_native" || { echo "missing bundle executable" >&2; exit 1; }
test -f "$BUNDLE/lib/libmatrixflow_ocr.so" || {
  echo "the bundle has no lib/libmatrixflow_ocr.so: the OCR target was not built or not installed" >&2
  exit 1
}
ls -l "$BUNDLE/matrixflow_native" "$BUNDLE/lib/" "$BUNDLE/data/flutter_assets" | head -30

mkdir -p "$OUT"
cp -f "$BUNDLE/lib/libmatrixflow_ocr.so" "$OUT/"
mkdir -p "$OUT/ncnn"
cp -f "$ASSETS"/ncnn/*.bin "$ASSETS"/ncnn/*.param "$ASSETS"/ncnn/ppocrv5_dict.txt "$OUT/ncnn/"
echo "staged    : $OUT"
ls -l "$OUT" "$OUT/ncnn"
