#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeMonitor"

SKIP_TESTS=false
for arg in "$@"; do
    case "$arg" in
        --skip-tests) SKIP_TESTS=true ;;
    esac
done

# --- Build

"${PROJECT_DIR}/build.sh"

# --- Test

if [ "${SKIP_TESTS}" = false ]; then
    echo ""
    echo "Running tests..."
    swift "${PROJECT_DIR}/scripts/generate-xcstrings.swift" "${PROJECT_DIR}/${APP_NAME}"
    cd "${PROJECT_DIR}"
    swift run ClaudeMonitorTestRunner
    echo ""
fi

# --- Migrate sandbox preferences

BUNDLE_ID="com.dancingZdenda.ClaudeMonitor"
SANDBOX_PREFS="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Preferences/${BUNDLE_ID}.plist"
REGULAR_PREFS="${HOME}/Library/Preferences/${BUNDLE_ID}.plist"

if [ -f "${SANDBOX_PREFS}" ] && [ ! -f "${REGULAR_PREFS}" ]; then
    echo "Migrating preferences from sandbox container..."
    cp "${SANDBOX_PREFS}" "${REGULAR_PREFS}"
fi

# --- Install & launch

BUNDLE="${PROJECT_DIR}/.build/${APP_NAME}.app"

pkill -x "${APP_NAME}" 2>/dev/null && sleep 0.5 || true

echo "Installing to /Applications..."
rm -rf "/Applications/${APP_NAME}.app"
cp -R "${BUNDLE}" "/Applications/${APP_NAME}.app"

echo "Launching ${APP_NAME}..."
open "/Applications/${APP_NAME}.app"

echo "Done."
