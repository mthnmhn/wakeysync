#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADDRESS="${1:-AC:B1:EE:25:DA:04}"
OFFSET_MINUTES="${OFFSET_MINUTES:-120}"
LISTEN_SECONDS="${LISTEN_SECONDS:-2}"
FORMAT="${FORMAT:-year16}"
COMMANDS=("${@:2}")

if [ "${#COMMANDS[@]}" -eq 0 ]; then
  COMMANDS=(
    0x0581
    0x0582
    0x0583
    0x0584
  )
fi

LOG_FILE="$HOME/Library/Logs/WakeySync.log"

for cmd in "${COMMANDS[@]}"; do
  packet="$(cd "$ROOT" && swift run wakeyctl build-time-packet --command "$cmd" --format "$FORMAT" --offset-minutes "$OFFSET_MINUTES" | tail -n 1)"
  echo "=== probing $cmd format=$FORMAT packet=$packet ==="
  pkill -f "$ROOT/WakeySync.app/Contents/MacOS/wakeyctl" >/dev/null 2>&1 || true
  rm -f "$LOG_FILE"
  "$ROOT/scripts/run_app.sh" send --address "$ADDRESS" --packet "$packet" --listen-seconds "$LISTEN_SECONDS"
  sleep "$(python3 - <<PY
listen = float(${LISTEN_SECONDS})
print(listen + 2.0)
PY
)"
  echo "--- log for $cmd ---"
  cat "$LOG_FILE" 2>/dev/null || true
  echo
done
