#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeMonitor"
SRC_DIR="${PROJECT_DIR}/${APP_NAME}"

RELEASE=false
for arg in "$@"; do
    case "$arg" in
        --release) RELEASE=true ;;
    esac
done

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

if [ "${RELEASE}" = true ]; then
    echo "Compiling ${APP_NAME} (${ARCH}, Swift 6, Release)..."
    OPT_FLAGS="-O"
else
    echo "Compiling ${APP_NAME} (${ARCH}, Swift 6, Debug)..."
    OPT_FLAGS="-Onone -D DEBUG"
fi

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
    ${OPT_FLAGS}

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

echo "Built: ${BUNDLE}"
