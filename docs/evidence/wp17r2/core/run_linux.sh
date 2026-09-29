#!/usr/bin/env bash
# WP17-R2 Linux leg: drive the same CLI over the same corpus and record raw
# engine output.  Scoring happens on the reference platform (tools/score_raw.py)
# so that Windows / Linux / Android results are judged by identical code.
#
# Usage:  bash core/run_linux.sh [extra run_bench.py flags]
set -euo pipefail

WORK="${WORK:-$HOME/wp17r2}"
R2_WIN="${R2_WIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

export LD_LIBRARY_PATH="$WORK/tess-libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export TESSDATA_PREFIX="$WORK/assets/tessdata_fast"

# Copy the corpus onto the Linux filesystem: reading it through /mnt/c adds
# drvfs overhead that would show up as image decode time.
if [ ! -d "$WORK/samples" ]; then
    cp -r "$R2_WIN/samples" "$WORK/"
fi

exec python3 "$R2_WIN/tools/run_bench.py" \
    --platform linux \
    --cli "$WORK/build/wp17r2_ocr" \
    --assets "$WORK/assets" \
    --samples "$WORK/samples" \
    --no-score \
    "$@"
