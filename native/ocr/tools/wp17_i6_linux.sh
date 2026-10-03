#!/usr/bin/env bash
# Build normal/official bundles or run explicitly isolated acceptance. Opt-in.
set -euo pipefail
: "${WP17_I6_ROOT:?external private directory required}"
: "${WP17_REPO:?dedicated source checkout required}"
: "${WP17_FLUTTER:?fixed Linux Flutter SDK required}"
mode="${1:-official}"
test "$(basename "$(realpath "$WP17_I6_ROOT")")" = wp17i6-private
mkdir -p "$WP17_I6_ROOT/logs" "$WP17_I6_ROOT/artifacts"
cd "$WP17_REPO"
export PATH="$WP17_FLUTTER/bin:$PATH"
case "$mode" in
  accept|accept-file-entry)
    # Each run gets fresh application storage, an independent display and only
    # the caller's dedicated executable. System libraries and user data stay local.
    session=$(mktemp -d "$WP17_I6_ROOT/xdg-session-XXXXXX")
    case "$(realpath "$session")" in
      "$(realpath "$WP17_I6_ROOT")"/xdg-session-*) ;;
      *) echo 'Invalid private session path' >&2; exit 2 ;;
    esac
    trap 'rm -rf -- "$session"' EXIT
    export XDG_DATA_HOME="$session/data" XDG_CONFIG_HOME="$session/config" XDG_CACHE_HOME="$session/cache"
    export GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1
    mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
    printf '%s\n' "$session" > "$WP17_I6_ROOT/logs/xdg-session.txt"
    driver_arguments=()
    if [ "$mode" = accept-file-entry ]; then driver_arguments+=(--file-entry); fi
    xvfb-run -a dbus-run-session -- python3 native/ocr/tools/drive_official_import.py \
      --platform linux --repo "$WP17_REPO" --root "$WP17_I6_ROOT" \
      --flutter "$WP17_FLUTTER/bin/flutter" \
      --application "$WP17_I6_ROOT/artifacts/linux-device/matrixflow_native" "${driver_arguments[@]}"
    ;;
  normal)
    unset WP17_OCR_NCNN_DIR WP17_OCR_STB_DIR
    flutter build linux --release --no-pub > "$WP17_I6_ROOT/logs/build-normal.log" 2>&1
    bundle="$WP17_REPO/build/linux/x64/release/bundle"
    test ! -e "$bundle/lib/libmatrixflow_ocr.so"
    test ! -e "$bundle/data/wp17-ocr"
    ;;
  official|device)
    : "${WP17_NCNN_INSTALL:?verified ncnn SDK required}"
    : "${WP17_I6_DEPLOY:?verified official deployment required}"
    : "${WP17_OCR_STB_DIR:?verified stb directory required}"
    export WP17_OCR_NCNN_DIR="$WP17_NCNN_INSTALL/lib/cmake/ncnn"
    python3 native/ocr/tools/stage_official_bundle.py --deploy "$WP17_I6_DEPLOY" --out "$WP17_I6_ROOT/packaged-assets"
    arguments=(build linux --no-pub)
    if [ "$mode" = device ]; then
      arguments+=(--debug --target=test/wp17_i6_device_test.dart --dart-define=WP17_I6_DEVICE=true)
      configuration=debug
    else
      arguments+=(--release)
      configuration=release
    fi
    flutter "${arguments[@]}" > "$WP17_I6_ROOT/logs/build-$mode.log" 2>&1
    bundle="$WP17_REPO/build/linux/x64/$configuration/bundle"
    test -f "$bundle/lib/libmatrixflow_ocr.so"
    python3 native/ocr/tools/stage_official_bundle.py --deploy "$WP17_I6_DEPLOY" --out "$bundle/data"
    ;;
  *) echo 'mode must be normal, official, device, accept or accept-file-entry' >&2; exit 2 ;;
esac
if [ "$mode" = normal ] || [ "$mode" = official ] || [ "$mode" = device ]; then
  destination="$WP17_I6_ROOT/artifacts/linux-$mode"
  case "$(realpath -m "$destination")" in
    "$(realpath "$WP17_I6_ROOT")"/artifacts/linux-"$mode") ;;
    *) echo 'Invalid private artifact path' >&2; exit 2 ;;
  esac
  rm -rf -- "$destination"
  mkdir -p "$destination"
  cp -a "$bundle/." "$destination/"
fi
echo "WP17_I6_BUILD_OK=$mode"
