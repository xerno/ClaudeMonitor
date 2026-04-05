#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeMonitor"
SRC_DIR="${PROJECT_DIR}/${APP_NAME}"
BUILD_DIR="${PROJECT_DIR}/.build"
BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${BUNDLE}/Contents"
BUNDLE_ID="com.dancingZdenda.ClaudeMonitor"

# --- Prerequisites

if ! command -v swiftc &>/dev/null; then
    echo "Error: swiftc not found. Install Command Line Tools: xcode-select --install"
    exit 1
fi

SDK_PATH=$(xcrun --show-sdk-path 2>/dev/null || true)
if [ -z "${SDK_PATH}" ] || [ ! -d "${SDK_PATH}" ]; then
    echo "Error: macOS SDK not found. Install Command Line Tools: xcode-select --install"
    exit 1
fi

ARCH=$(uname -m)

# --- Clean & prepare

rm -rf "${BUILD_DIR}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

# --- 1. Compile

echo "Compiling ${APP_NAME} (${ARCH}, Swift 6)..."

swiftc $(find "${SRC_DIR}" -name "*.swift") \
    -o "${CONTENTS}/MacOS/${APP_NAME}" \
    -target "${ARCH}-apple-macosx15.0" \
    -sdk "${SDK_PATH}" \
    -swift-version 6 \
    -default-isolation MainActor \
    -enable-upcoming-feature MemberImportVisibility \
    -framework AppKit \
    -framework CryptoKit \
    -framework IOKit \
    -framework ServiceManagement \
    -Onone \
    -D DEBUG

# --- 2. Info.plist

cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Monitor</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# --- 3. Resources

SVG_SRC="${SRC_DIR}/Assets.xcassets/RefreshUsage.imageset/refresh-usage.svg"
if [ -f "${SVG_SRC}" ]; then
    cp "${SVG_SRC}" "${CONTENTS}/Resources/RefreshUsage.svg"
fi

# --- 4. Localization

echo "Generating localization from Translations/..."
swift "${PROJECT_DIR}/scripts/generate-xcstrings.swift" "${CONTENTS}/Resources"

# --- 5. Code sign

codesign --force --sign - "${BUNDLE}"

# --- 6. Migrate sandbox preferences

SANDBOX_PREFS="${HOME}/Library/Containers/${BUNDLE_ID}/Data/Library/Preferences/${BUNDLE_ID}.plist"
REGULAR_PREFS="${HOME}/Library/Preferences/${BUNDLE_ID}.plist"

if [ -f "${SANDBOX_PREFS}" ] && [ ! -f "${REGULAR_PREFS}" ]; then
    echo "Migrating preferences from sandbox container..."
    cp "${SANDBOX_PREFS}" "${REGULAR_PREFS}"
fi

# --- 7. Install & launch

pkill -x "${APP_NAME}" 2>/dev/null && sleep 0.5 || true

echo "Installing to /Applications..."
rm -rf "/Applications/${APP_NAME}.app"
cp -R "${BUNDLE}" "/Applications/${APP_NAME}.app"

echo "Launching ${APP_NAME}..."
open "/Applications/${APP_NAME}.app"

echo "Done."
