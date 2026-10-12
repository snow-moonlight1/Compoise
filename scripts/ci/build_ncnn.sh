#!/usr/bin/env bash
# Build the pinned CPU-only ncnn SDK for one target and fetch the pinned
# stb_image.h. Used by .github/workflows/release.yml; results are cached there.
#
#   scripts/ci/build_ncnn.sh <target> <out-dir>
#   target: linux-x64 | windows-x64 | windows-arm64 | android-armeabi-v7a |
#           android-arm64-v8a | android-x86_64
#
# Layout written:
#   <out>/install/...              (linux/windows: ncnn install prefix)
#   <out>/ncnn-android-<abi>/install/...  (android)
#   <out>/third_party/stb_image.h
set -euo pipefail
target="$1"; out="$2"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
pin="$(tr -d '\r\n' < "$repo/third_party/ncnn_pin.txt")"
stb_sha=594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3
mkdir -p "$out/third_party"
work="$(mktemp -d)"
src="$work/ncnn"

sha() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

if [ ! -f "$out/third_party/stb_image.h" ] || [ "$(sha "$out/third_party/stb_image.h")" != "$stb_sha" ]; then
  # stb master moved past v2.30; fetch the pinned blob by commit-independent hash check.
  curl -fsSL --retry 3 -o "$out/third_party/stb_image.h" \
    https://raw.githubusercontent.com/nothings/stb/f58f558c120e9b32c217290b80bad1a0729fbb2c/stb_image.h
  got="$(sha "$out/third_party/stb_image.h")"
  [ "$got" = "$stb_sha" ] || { echo "stb_image.h hash mismatch: $got" >&2; exit 3; }
fi

git init -q "$src"
git -C "$src" fetch -q --depth=1 https://github.com/Tencent/ncnn.git "$pin"
git -C "$src" checkout -q --detach FETCH_HEAD
[ "$(git -C "$src" rev-parse HEAD)" = "$pin" ] || { echo "ncnn commit mismatch" >&2; exit 3; }

common=(-DCMAKE_BUILD_TYPE=Release -DNCNN_VULKAN=OFF -DNCNN_SHARED_LIB=OFF
  -DNCNN_BUILD_TOOLS=OFF -DNCNN_BUILD_TESTS=OFF -DNCNN_BUILD_BENCHMARK=OFF
  -DNCNN_BUILD_EXAMPLES=OFF -DNCNN_INSTALL_SDK=ON -DNCNN_PIXEL=ON)
case "$target" in
  linux-x64)
    prefix="$out/install"
    cmake -S "$src" -B "$work/b" -G Ninja "${common[@]}" -DCMAKE_INSTALL_PREFIX="$prefix" \
      -DNCNN_OPENMP=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON ;;
  windows-x64|windows-arm64)
    arch=x64; [ "$target" = windows-arm64 ] && arch=ARM64
    prefix="$out/install"
    # OpenMP off: no VCOMP140.DLL runtime dependency in the shipped DLL.
    # Let CMake pick the installed Visual Studio (2022 on windows-2022; the
    # windows-11-arm image may ship a newer one).
    vswhere="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
    [ -x "$vswhere" ] && "$vswhere" -latest -products '*' -property displayName || true
    cmake -S "$src" -B "$work/b" -A "$arch" "${common[@]}" \
      -DCMAKE_INSTALL_PREFIX="$prefix" -DNCNN_OPENMP=OFF ;;
  android-*)
    abi="${target#android-}"
    ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
    [ -n "$ndk" ] || { echo "ANDROID_NDK_HOME is required" >&2; exit 2; }
    prefix="$out/ncnn-android-$abi/install"
    cmake -S "$src" -B "$work/b" -G Ninja "${common[@]}" -DCMAKE_INSTALL_PREFIX="$prefix" \
      -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI="$abi" -DANDROID_PLATFORM=android-23 -DANDROID_STL=c++_static \
      -DNCNN_OPENMP=OFF ;;
  *) echo "unknown target $target" >&2; exit 2 ;;
esac
cmake --build "$work/b" --config Release --target install --parallel 4
test -f "$prefix/lib/cmake/ncnn/ncnnConfig.cmake"
echo "ncnn $pin installed for $target at $prefix"
