#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/.build/WakeySync.app"
BIN="$APP_DIR/Contents/MacOS/wakeyctl"

swift build --package-path "$ROOT"
swift "$ROOT/scripts/generate_app_icon.swift" "$ROOT" >/dev/null

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources/Assets"

swiftc \
  "$ROOT/App/WakeyAppMain.swift" \
  "$ROOT/App/Telemetry.swift" \
  "$ROOT/Sources/WakeySync/Core.swift" \
  -framework AppKit \
  -framework CoreText \
  -framework CoreBluetooth \
  -framework IOBluetooth \
  -o "$BIN"

cp "$ROOT/WakeySync-Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT"/App/Assets/wakey_device.* "$APP_DIR/Contents/Resources/Assets/"
cp "$ROOT/App/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep -s - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "$APP_DIR"
