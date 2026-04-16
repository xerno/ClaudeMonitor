#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GENERATED_DIR="${PROJECT_DIR}/ClaudeMonitor/Generated"
mkdir -p "${GENERATED_DIR}"

BUILD_DATE=$(date +"%Y-%m-%d")

cat > "${GENERATED_DIR}/BuildInfo.swift" << EOF
enum BuildInfo {
    static let date = "${BUILD_DATE}"
}
EOF

echo "Generated BuildInfo.swift (date: ${BUILD_DATE})"
