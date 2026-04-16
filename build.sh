#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${PROJECT_DIR}/BuildConfig.sh"
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
## BUNDLE_ID, APP_NAME, VERSION sourced from BuildConfig.sh

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

# --- 1. Generated sources

bash "${PROJECT_DIR}/scripts/generate-build-info.sh"

# --- 2. Compile

if [ "${RELEASE}" = true ]; then
    echo "Compiling ${APP_NAME} (${ARCH}, Swift ${SWIFT_VERSION}, Release)..."
    OPT_FLAGS="-O"
else
    echo "Compiling ${APP_NAME} (${ARCH}, Swift ${SWIFT_VERSION}, Debug)..."
    OPT_FLAGS="-Onone -D DEBUG"
fi

swiftc $(find "${SRC_DIR}" -name "*.swift") \
    -o "${CONTENTS}/MacOS/${APP_NAME}" \
    -target "${ARCH}-apple-macosx${DEPLOYMENT_TARGET}" \
    -sdk "${SDK_PATH}" \
    -swift-version "${SWIFT_VERSION}" \
    -default-isolation "${DEFAULT_ISOLATION}" \
    $(for f in ${UPCOMING_FEATURES}; do printf -- "-enable-upcoming-feature %s " "$f"; done) \
    -framework AppKit \
    -framework CryptoKit \
    -framework IOKit \
    -framework ServiceManagement \
    ${OPT_FLAGS}

# --- 3. Info.plist

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
    <string>${VERSION}</string>
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

# --- 4. Resources

SVG_SRC="${SRC_DIR}/Assets.xcassets/RefreshUsage.imageset/refresh-usage.svg"
if [ -f "${SVG_SRC}" ]; then
    cp "${SVG_SRC}" "${CONTENTS}/Resources/RefreshUsage.svg"
fi

# --- 5. Localization

echo "Generating localization from Translations/..."
swift "${PROJECT_DIR}/scripts/generate-xcstrings.swift" "${CONTENTS}/Resources"

# --- 6. Code sign

codesign --force --sign - "${BUNDLE}"

echo "Built: ${BUNDLE}"
