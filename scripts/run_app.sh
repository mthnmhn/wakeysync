#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build_app.sh" >/dev/null

rm -rf "$ROOT/WakeySync.app"
cp -R "$ROOT/.build/WakeySync.app" "$ROOT/WakeySync.app"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep -s - "$ROOT/WakeySync.app" >/dev/null 2>&1 || true
fi

if [ "$#" -gt 0 ]; then
  osascript -e 'tell application id "dev.wakeysync.app" to quit' >/dev/null 2>&1 || true
  sleep 0.5
  open -n "$ROOT/WakeySync.app" --args "$@"
else
  open "$ROOT/WakeySync.app"
fi
