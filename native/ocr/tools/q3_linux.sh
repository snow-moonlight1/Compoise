#!/usr/bin/env bash
# Opt-in Linux generate + score. Reads a private font, library and model cache.
set -euo pipefail
ROOT="${Q3_PRIVATE_ROOT:-/home/ubuntu/wp17q3-private}"
FONT="${Q3_FONT:?set Q3_FONT to the local OFL font}"
LIBRARY="${Q3_LIBRARY:?set Q3_LIBRARY to the existing OCR shared library}"
ASSETS="${Q3_ASSETS:?set Q3_ASSETS to the read-only official model directory}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/fixtures" "$ROOT/logs"
python3 "$HERE/q3_cli.py" generate --out "$ROOT/fixtures" --font "$FONT" >"$ROOT/logs/generate.json"
python3 "$HERE/q3_cli.py" validate --labels "$ROOT/fixtures" --font "$FONT" >"$ROOT/logs/validate.json"
set +e
python3 "$HERE/q3_cli.py" score --labels "$ROOT/fixtures" --enable-model \
  --library "$LIBRARY" --assets "$ASSETS" --out "$ROOT/score" \
  >"$ROOT/logs/score.json" 2>"$ROOT/logs/score.stderr"
score_status=$?
set -e
printf '%s\n' "$score_status" >"$ROOT/logs/score.exit"
python3 "$HERE/q3_cli.py" probe-dict --assets "$ASSETS" --out "$ROOT/dict-probe.json" \
  >"$ROOT/logs/probe.json"
exit "$score_status"
