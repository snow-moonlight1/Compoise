#!/usr/bin/env bash
# Build and run the WP17-I4 bundle OCR integration test on Linux.
#
# `flutter drive` refuses --release and its debug bundle is not the one we want,
# so this script builds the bundle with the OCR target enabled and then runs the
# integration test on the Linux device under Xvfb.
#
# The model root reaches the app through WP17_OCR_ASSETS in the process
# environment, which is the first entry of the production resolution order in
# lib/screenshot_import/screenshot_backend.dart. WP17_I4_EVIDENCE points the
# test at the repository so it can read the printed-text baseline; it is a
# test-only define and has no effect on product code.
set -euo pipefail

REPO="${WP17_REPO:-$HOME/wp17i4-build}"
DEPLOY="${WP17_LINUX_OUT:-$HOME/wp17i4-linux-deploy}"
FLUTTER="${WP17_FLUTTER:-$HOME/develop/flutter}"
ASSETS="${WP17R2_ASSETS:-$HOME/.cache/wp17r2-assets}"
NCNN="${WP17_NCNN_INSTALL:-$HOME/wp17i4-ncnn-linux/install}"
LOG="${WP17_LINUX_LOG:-$HOME/wp17i4-linux-drive.log}"
MODE="${WP17_LINUX_MODE:-profile}"
# The bundle library the app ships; passed to the test because flutter_tester is
# the resolved executable under `flutter test`/`flutter run` on Linux.
BUNDLE_LIB="$REPO/build/linux/x64/$MODE/bundle/lib/libmatrixflow_ocr.so"

export PATH="$FLUTTER/bin:$PATH"
export WP17_OCR_NCNN_DIR="$NCNN/lib/cmake/ncnn"
export WP17_OCR_STB_DIR="$ASSETS/third_party"
export WP17_OCR_ASSETS="$DEPLOY"
export GDK_BACKEND=x11
export LIBGL_ALWAYS_SOFTWARE=1

# xvfb-run chooses a free display and cleans up only its own server.

cd "$REPO"
echo "== flutter build linux --$MODE =="
flutter build linux "--$MODE" --no-pub --dart-define=WP17_I4_EVIDENCE="$REPO" 2>&1 | tail -5
ls -l "build/linux/x64/$MODE/bundle/lib/" | grep -i ocr || {
  echo "the $MODE bundle has no OCR library" >&2
  exit 1
}

echo "== flutter test on the linux device =="
set +e
xvfb-run -a flutter test --no-pub -d linux --dart-define=WP17_I4_EVIDENCE="$REPO" \
  --dart-define=WP17_I4_BUNDLE=true \
  --dart-define=WP17_OCR_TEST_LIBRARY="$BUNDLE_LIB" \
  test/wp17_i4_bundle_ocr_test.dart 2>&1 | tee "$LOG" | tail -30
status=${PIPESTATUS[0]}
set -e

echo "---- exit: $status ----"
grep -E "WP17_I4_|All tests passed|Some tests failed" "$LOG" | sort -u | head -20
exit "$status"
