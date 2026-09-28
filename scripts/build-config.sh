# Single source of truth for build settings. Keep in sync by hand: Xcode project (project.pbxproj), Package.swift.

APP_NAME="ClaudeMonitor"
BUNDLE_ID="com.dancingZdenda.ClaudeMonitor"
VERSION="1.2.0"
DEPLOYMENT_TARGET="15.0"
SWIFT_VERSION="6"
DEFAULT_ISOLATION="nonisolated"
UPCOMING_FEATURES="MemberImportVisibility"

# Exported by test.sh; UsageHistory.init traps on production storage when it is set.
UNDER_TEST_ENV_VAR="CLAUDEMONITOR_UNDER_TEST"

# Opt-in: enables the real-network tests in IntegrationTests.swift. Unset by default so ./test.sh never depends on the network.
RUN_INTEGRATION_TESTS_ENV_VAR="CLAUDEMONITOR_RUN_INTEGRATION_TESTS"
