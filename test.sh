#!/bin/bash
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${PROJECT_DIR}/scripts/build-config.sh"
APP_NAME="ClaudeMonitor"
PRODUCT="ClaudeMonitorTestRunner"

echo "Generating build files..."
bash "${PROJECT_DIR}/scripts/generate-build-info.sh"
# The dir argument also writes .lproj files, which SPM bundles as localized resources;
# without them String(localized:) returns raw keys.
swift "${PROJECT_DIR}/scripts/generate-xcstrings.swift" "${PROJECT_DIR}/ClaudeMonitor/Generated/Translations"

echo "Running ${APP_NAME} tests..."
cd "${PROJECT_DIR}"
swift build --product "${PRODUCT}" || exit 1

BIN="$(swift build --product "${PRODUCT}" --show-bin-path)/${PRODUCT}"
LOG="$(mktemp)"
trap 'rm -f "${LOG}"' EXIT

env "${UNDER_TEST_ENV_VAR}=1" "${BIN}" 2>&1 | tee "${LOG}"
STATUS="${PIPESTATUS[0]}"

if [ "${STATUS}" -ne 0 ]; then
    echo ""
    echo "==> Failed test details:"
    # Skip the run-summary line: it has no location or expectation detail.
    grep "✘" "${LOG}" | grep -v "^✘ Test run with " || true
fi

exit "${STATUS}"
