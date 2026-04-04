#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeMonitor"

# --- Prerequisites

XCODEBUILD=$(xcrun -f xcodebuild 2>/dev/null || true)

if [ -z "${XCODEBUILD}" ]; then
    echo "Error: xcodebuild not found."
    echo "If Xcode is installed, run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "Otherwise, install Xcode from the App Store."
    exit 1
fi

# --- Run tests

echo "Running ${APP_NAME} tests..."

"${XCODEBUILD}" test \
    -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -quiet

echo "Done."
