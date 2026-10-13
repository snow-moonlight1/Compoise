#!/usr/bin/env bash
# WP17-R2 Linux leg: build ncnn + the shared OCR CLI without root.
#
# Validated inside WSL2 (Ubuntu 24.04, glibc 2.39, gcc 13.3, cmake 3.28).
# `sudo` is not available in that environment, so Tesseract comes from the
# manylinux wheels published for tesserocr, which bundle libtesseract.so and
# libleptonica.so.  The library version therefore differs from the Windows leg
# and is recorded in the report.
#
# Usage:  WIN_ASSETS=/mnt/c/.../wp17r2-assets bash core/build_linux.sh
set -euo pipefail

WIN_ASSETS="${WIN_ASSETS:-/mnt/c/Users/20214/AppData/Local/wp17r2-assets}"
WORK="${WORK:-$HOME/wp17r2}"
NCNN_REPO="${NCNN_REPO:-https://github.com/Tencent/ncnn.git}"
NCNN_REF="${NCNN_REF:-c6b351b56fbe32e0381ae00331e3df649b20d7b7}"
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS="$(nproc)"

echo "== work dir: $WORK =="
mkdir -p "$WORK"

# ---------------------------------------------------------------- assets
mkdir -p "$WORK/assets"
for d in ncnn tessdata_fast third_party; do
    if [ ! -d "$WORK/assets/$d" ]; then
        echo "-- copying $d from $WIN_ASSETS"
        cp -r "$WIN_ASSETS/$d" "$WORK/assets/"
    fi
done

# ------------------------------------------------------------ tesseract lib
if [ ! -e "$WORK/tess-libs/libtesseract.so.5" ]; then
    echo "== extracting libtesseract from the tesserocr manylinux wheel =="
    WHEEL="$(ls "$WIN_ASSETS"/tessocr-wheel/tesserocr-*.manylinux*.whl | head -1)"
    python3 - "$WHEEL" "$WORK" <<'PY'
import sys, zipfile
wheel, work = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(wheel) as z:
    for name in z.namelist():
        if name.startswith("tesserocr.libs/") and not name.endswith("/"):
            z.extract(name, work + "/tesswheel")
print("extracted", wheel)
PY
    mkdir -p "$WORK/tess-libs"
    cp "$WORK"/tesswheel/tesserocr.libs/* "$WORK/tess-libs/"
fi
# The wheel renames the libraries; recreate every SONAME so both the linker and
# the dynamic loader can resolve the DT_NEEDED entries by their real names.
( cd "$WORK/tess-libs"
  for f in *.so.*; do
      soname="$(objdump -p "$f" | awk '/SONAME/{print $2}')"
      if [ -n "${soname:-}" ] && [ "$soname" != "$f" ]; then
          ln -sf "$f" "$soname"
      fi
  done
  # auditwheel rewrites DT_NEEDED to the mangled names, so the plain names have
  # to be recreated explicitly for the linker and for the loader.
  TESS_SO="$(find . -maxdepth 1 -name 'libtesseract-*.so.*' -type f | head -1)"
  LEPT_SO="$(find . -maxdepth 1 -name 'libleptonica-*.so.*' -type f | head -1)"
  ln -sf "$(basename "$TESS_SO")" libtesseract.so.5
  ln -sf "$(basename "$LEPT_SO")" libleptonica.so.6 )
ls -l "$WORK/tess-libs" | sed 's/^/   /'
ls -l "$WORK/tess-libs"
echo "-- libtesseract deps:"
LD_LIBRARY_PATH="$WORK/tess-libs" ldd "$WORK"/tess-libs/libtesseract-*.so.5.* | sed 's/^/   /'

# ------------------------------------------------------------------- ncnn
if [ ! -d "$WORK/ncnn-src/.git" ]; then
    echo "== cloning ncnn =="
    git clone "$NCNN_REPO" "$WORK/ncnn-src"
fi
( cd "$WORK/ncnn-src" && git fetch --depth 1 origin "$NCNN_REF" 2>/dev/null || true
  git checkout -q "$NCNN_REF" 2>/dev/null || true
  echo "ncnn commit: $(git rev-parse HEAD)" )

echo "== building ncnn =="
cmake -S "$WORK/ncnn-src" -B "$WORK/ncnn-build" -DCMAKE_BUILD_TYPE=Release \
    -DNCNN_VULKAN=OFF -DNCNN_BUILD_EXAMPLES=OFF -DNCNN_BUILD_TOOLS=OFF \
    -DNCNN_BUILD_BENCHMARK=OFF -DNCNN_BUILD_TESTS=OFF -DNCNN_OPENMP=ON \
    -DNCNN_SHARED_LIB=OFF -DNCNN_PIXEL=ON > "$WORK/ncnn-configure.log" 2>&1
cmake --build "$WORK/ncnn-build" --target install -j "$JOBS" > "$WORK/ncnn-build.log" 2>&1
echo "ncnn installed: $WORK/ncnn-build/install"

# --------------------------------------------------------------------- CLI
echo "== building wp17r2_ocr =="
cmake -S "$CORE_DIR" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release \
    -Dncnn_DIR="$WORK/ncnn-build/install/lib/cmake/ncnn" \
    -DWP17R2_THIRD_PARTY="$WORK/assets/third_party" \
    -DWP17R2_TESSERACT_LIB="$WORK/tess-libs/libtesseract.so.5" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,--allow-shlib-undefined -Wl,-rpath,$WORK/tess-libs" \
    > "$WORK/cli-configure.log" 2>&1
cmake --build "$WORK/build" -j "$JOBS" >> "$WORK/cli-build.log" 2>&1
echo "cli: $WORK/build/wp17r2_ocr"
LD_LIBRARY_PATH="$WORK/tess-libs" "$WORK/build/wp17r2_ocr" --help | head -3 || true
