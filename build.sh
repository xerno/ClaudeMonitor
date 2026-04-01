#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeMonitor"

echo "Building ${APP_NAME}..."
xcodebuild -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Debug \
    build 2>&1 | tail -3

BUILD_DIR=$(xcodebuild -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Debug \
    -showBuildSettings 2>/dev/null \
    | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')

APP_PATH="${BUILD_DIR}/${APP_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    echo "Error: ${APP_PATH} not found"
    exit 1
fi

# Kill running instance if any
pkill -x "${APP_NAME}" 2>/dev/null && sleep 0.5 || true

echo "Installing to /Applications..."
rm -rf "/Applications/${APP_NAME}.app"
cp -R "${APP_PATH}" "/Applications/${APP_NAME}.app"

echo "Launching ${APP_NAME}..."
open "/Applications/${APP_NAME}.app"

echo "Done."
