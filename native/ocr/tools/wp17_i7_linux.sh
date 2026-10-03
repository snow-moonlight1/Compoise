#!/usr/bin/env bash
# Explicit build/acceptance. No ordinary test run launches an application.
set -euo pipefail
if [ "${WP17_I7_ENABLE:-false}" != true ]; then
  echo 'SKIPPED: set WP17_I7_ENABLE=true for I7 Linux device work'
  exit 0
fi
: "${WP17_I7_ROOT:?external private directory required}"
: "${WP17_FLUTTER:?Flutter 3.32.8 / Dart 3.8.1 required}"
root=$(realpath "$WP17_I7_ROOT")
test "$(basename "$root")" = wp17i7-private
export WP17_I7_ROOT="$root"
export WP17_REPO="$root/repo" PUB_CACHE="$root/pub-cache"
export PATH="$root/tools/usr/bin:$WP17_FLUTTER/bin:$PATH"
export LD_LIBRARY_PATH="$root/tools/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export TMPDIR="$root/tmp"
mkdir -p "$root/logs" "$root/artifacts" "$root/runs" "$TMPDIR"
cd "$WP17_REPO"
test "$(stat -f -c %T .)" = ext2/ext3
python3 - "$WP17_FLUTTER/bin/cache/flutter.version.json" <<'PY'
import json, sys
sdk = json.load(open(sys.argv[1]))
assert sdk['frameworkVersion'] == '3.32.8' and sdk['dartSdkVersion'] == '3.8.1', sdk
PY
case "${1:-disabled}" in
  build)
    : "${WP17_NCNN_INSTALL:?verified ncnn install required}"
    : "${WP17_I7_DEPLOY:?verified official deployment required}"
    : "${WP17_OCR_STB_DIR:?verified stb directory required}"
    export WP17_OCR_NCNN_DIR="$WP17_NCNN_INSTALL/lib/cmake/ncnn"
    flutter build linux --debug --no-pub --target=test/wp17_i7_device_test.dart \
      --dart-define=WP17_I7_DEVICE=true \
      --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false \
      > "$root/logs/build-device.log" 2>&1
    bundle="$WP17_REPO/build/linux/x64/debug/bundle"
    test -f "$bundle/lib/libmatrixflow_ocr.so"
    python3 native/ocr/tools/stage_official_bundle.py --deploy "$WP17_I7_DEPLOY" --out "$bundle/data"
    # mktemp avoids deleting or overwriting previous accepted artifacts.
    destination=$(mktemp -d "$root/artifacts/linux-device-XXXXXX")
    cp -a "$bundle/." "$destination/"
    printf '%s\n' "$destination" > "$root/logs/latest-bundle.txt"
    ;;
  accept)
    : "${WP17_I7_APPLICATION:?I7 device executable required}"
    export WP17_I7_RUN
    WP17_I7_RUN=$(mktemp -d "$root/runs/run-XXXXXX")
    export XDG_DATA_HOME="$WP17_I7_RUN/data" XDG_CONFIG_HOME="$WP17_I7_RUN/config" XDG_CACHE_HOME="$WP17_I7_RUN/cache"
    export XDG_RUNTIME_DIR="$WP17_I7_RUN/runtime"
    mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    export GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 LC_ALL=C.UTF-8 GTK_A11Y=atspi
    unset WAYLAND_DISPLAY WP17_OCR_ASSETS WP17_OCR_LIBRARY
    # xvfb-run and dbus-run-session own and reap this display/session. Both
    # processes share these disk directories; evidence remains on failure.
    set +e
    xvfb-run -a -s '-screen 0 1280x1024x24' dbus-run-session -- \
      bash -c 'export WP17_LINUX_PRIVATE_DISPLAY="$DISPLAY"; exec "$@"' bash \
      python3 native/ocr/tools/drive_linux_reopen.py --enable --root "$root" --repo "$WP17_REPO" \
      --application "$WP17_I7_APPLICATION" > "$WP17_I7_RUN/session.log" 2>&1
    code=$?
    set -e
    printf '%s\n' "$code" > "$WP17_I7_RUN/session-exit.txt"
    printf '%s\n' "$WP17_I7_RUN" > "$root/logs/latest-run.txt"
    cat "$WP17_I7_RUN/host.json"
    exit "$code"
    ;;
  *) echo 'Specify build or accept with WP17_I7_ENABLE=true' >&2; exit 2 ;;
esac
