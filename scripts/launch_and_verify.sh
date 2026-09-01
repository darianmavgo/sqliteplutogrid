#!/bin/bash
set -e

WORKSPACE_DIR="/Users/darianhickman/Documents/sqliteplutogrid"
ARTIFACT_DIR="/Users/darianhickman/.gemini/antigravity-ide/brain/245b3718-8e05-4d48-b1ad-8bad128f5dc1"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

echo "🍊 [1/4] Terminating existing Sqliter instances..."
pkill -x Sqliter 2>/dev/null || true

echo "🍊 [2/4] Building macOS debug app..."
cd "$WORKSPACE_DIR"
flutter build macos --debug

echo "🍊 [3/4] Launching Sqliter.app..."
open "$WORKSPACE_DIR/build/macos/Build/Products/Debug/Sqliter.app"
sleep 3

echo "🍊 [4/4] Activating window and capturing screenshots..."
osascript -e 'tell application "Sqliter" to activate' 2>/dev/null || true
sleep 1
screencapture -x "$ARTIFACT_DIR/app_screenshot_live.png"
echo "✓ Captured main grid screenshot: $ARTIFACT_DIR/app_screenshot_live.png"

if [ -n "$1" ]; then
  echo "🍊 Sending command to /tmp/sqliter_command.txt: $1"
  echo "$1" > /tmp/sqliter_command.txt
  sleep 2
  screencapture -x "$ARTIFACT_DIR/app_screenshot_command.png"
  echo "✓ Captured command result screenshot: $ARTIFACT_DIR/app_screenshot_command.png"
fi

echo "🍊 Done!"
