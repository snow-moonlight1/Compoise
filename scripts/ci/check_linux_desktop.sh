#!/usr/bin/env bash
# Uses a private D-Bus session, synthetic notifications and Xvfb.
set -euo pipefail
if [[ "${1:-}" != --session ]]; then
  flutter build linux --debug --no-pub -t tool/linux_platform_smoke.dart
  mkdir -p build
  output=$(mktemp -d "$PWD/build/linux-desktop-smoke.XXXXXX")
  exec xvfb-run -a dbus-run-session -- bash "$0" --session "$output"
fi
output="$2"
export XDG_DATA_HOME="$output/data" XDG_CONFIG_HOME="$output/config"
export COMPOISE_LINUX_SMOKE_RESULT="$output/app.json"
export COMPOISE_BUS_RESULT="$output/bus.jsonl"
export LIBGL_ALWAYS_SOFTWARE=1 GDK_BACKEND=x11
/usr/bin/python3 scripts/tests/linux_desktop_bus.py &
bus_pid=$!
trap 'kill "$bus_pid" 2>/dev/null || true' EXIT
for attempt in $(seq 1 50); do
  if [[ -f "$COMPOISE_BUS_RESULT" ]] && grep -q 'ready' "$COMPOISE_BUS_RESULT"; then break; fi
  sleep 0.1
done
timeout 45s build/linux/x64/debug/bundle/compoise
/usr/bin/python3 - "$output" <<'PY'
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
facts = json.loads((root / 'app.json').read_text())
assert facts['passed'], facts
events = [json.loads(line) for line in (root / 'bus.jsonl').read_text().splitlines()]
assert any(event['kind'] == 'tray' for event in events), events
notifications = [event for event in events if event['kind'] == 'notification']
assert len(notifications) == 2, notifications
assert notifications[0]['title'] == 'Synthetic scheduled reminder', notifications
assert notifications[1]['title'] == 'Missed reminders', notifications
assert '1 reminders' in notifications[1]['body'], notifications
print(f'Linux desktop smoke passed: tray, hide/restore, timed notification, deduplicated missed summary. Evidence: {root}')
PY
