#!/system/bin/sh
# WP17-I4 Android leg: run the C ABI smoke caller over the pushed R2 synthetic
# screenshots on this device and print one summary line.
#
# Requires (pushed separately, never committed):
#   /data/local/tmp/wp17i4-smoke                 the smoke executable
#   /data/local/tmp/libmatrixflow_ocr.so         the shared object
#   /data/local/tmp/wp17i4-assets/ncnn/...       the five model files
#   /data/local/tmp/wp17i4-evidence/images/*.png the 12 synthetic screenshots
set -u
ROOT=/data/local/tmp
export LD_LIBRARY_PATH="$ROOT"
echo "abi: $(getprop ro.product.cpu.abi) sdk: $(getprop ro.build.version.sdk)"
"$ROOT/wp17i4-smoke" "$ROOT/wp17i4-assets" "$ROOT"/wp17i4-evidence/images/*.png | tail -1
echo "== missing model root =="
"$ROOT/wp17i4-smoke" "$ROOT/wp17i4-missing" "$ROOT/wp17i4-evidence/images/zh_light_base.png" | tail -2
echo "== corrupt png =="
printf 'not a png' > "$ROOT/wp17i4-corrupt.png"
"$ROOT/wp17i4-smoke" "$ROOT/wp17i4-assets" "$ROOT/wp17i4-corrupt.png" | tail -2
rm -f "$ROOT/wp17i4-corrupt.png"
