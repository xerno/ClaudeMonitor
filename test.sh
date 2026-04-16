#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeMonitor"
PRODUCT="ClaudeMonitorTestRunner"

# Generate Localizable.xcstrings so SPM can include it as a module resource.
# String(localized:) in Swift 6 uses the module bundle, which SPM builds from
# declared resources — without this file the localization falls back to raw keys.
echo "Generating build files..."
bash "${PROJECT_DIR}/scripts/generate-build-info.sh"
# Pass Generated/Translations/ as second arg to also write per-language .lproj/Localizable.strings files.
# SPM auto-discovers .lproj dirs as localized resources; Foundation reads .strings at runtime
# (the .xcstrings JSON is not readable by Foundation without Xcode compilation).
swift "${PROJECT_DIR}/scripts/generate-xcstrings.swift" "${PROJECT_DIR}/ClaudeMonitor/Generated/Translations"

echo "Running ${APP_NAME} tests..."
cd "${PROJECT_DIR}"
swift build --product "${PRODUCT}"
"$(swift build --product "${PRODUCT}" --show-bin-path)/${PRODUCT}"

echo "Done."
