# CLAUDE.md

## Project Overview

**ClaudeMonitor** — macOS menu bar app that displays Claude usage limits and Anthropic service status in real time.

## Build & Run

```bash
# Open in Xcode and press ⌘R
open ClaudeMonitor.xcodeproj

# Build + test + install from CLI (like Maven's clean install)
./install.sh

# Skip tests for quick rebuild
./install.sh --skip-tests

# Run tests only
./test.sh
```

**IMPORTANT**: Always use `./install.sh` and `./test.sh` for CLI builds and tests. Never search for Xcode, never use raw `xcodebuild`, and never run `xcode-select`.

Xcode 26 project uses `PBXFileSystemSynchronizedRootGroup` — new `.swift` files in source/test directories are auto-discovered, no pbxproj edits needed.

### Build settings — single source of truth

**`BuildConfig.sh`** is the authoritative source for shared build parameters (app name, bundle ID, version, deployment target, Swift version, default isolation, upcoming features). `build.sh` and `install.sh` source it directly. `Package.swift` and the Xcode project (`project.pbxproj`) must be kept in sync manually — when changing a build setting, update `BuildConfig.sh` first, then propagate to `Package.swift` and the Xcode project.

## Architecture

```
ClaudeMonitor/
├── AppDelegate.swift                    — @main entry point, lifecycle, editing shortcuts
├── AppState.swift                       — MonitorState, ServiceState value types
├── BundleModule.swift                   — Bundle.module shim for Xcode builds
├── Constants.swift                      — all hardcoded values (URLs, intervals, keychain keys)
├── DemoData.swift                       — demo mode data for screenshots/testing
├── JSONDecoder+ISO8601.swift            — shared ISO8601 decoder with fractional seconds
├── StatusModels.swift                   — StatusSummary, StatusComponent, ComponentStatus, Incident, PageStatus
├── UsageModels.swift                    — UsageResponse, UsageWindow, WindowEntry, WindowKeyParser
├── Services/
│   ├── DataCoordinator.swift            — data fetching orchestration, polling, state management
│   ├── StatusService.swift              — fetches status.claude.com/api/v2/summary.json
│   ├── UsageService.swift               — fetches claude.ai/api/organizations/{orgId}/usage
│   ├── PollingScheduler.swift           — adaptive polling intervals
│   ├── KeychainService.swift            — encrypted credential storage (UserDefaults + AES-GCM)
│   └── ServiceError.swift               — shared error type for both services, RetryCategory
├── MenuBar/
│   ├── MenuBarController.swift          — status bar item, UI coordination
│   ├── MenuBarController+Countdown.swift — countdown timer, critical reset animation
│   ├── MenuBuilder.swift                — MenuActions protocol + NSMenu construction
│   ├── MenuBuilder+Sections.swift       — menu section builders + attributed titles
│   ├── StatusBarRenderer.swift          — status bar icon + text rendering
│   ├── Formatting.swift                 — timeUntil(), progressBar(), displayLabel()
│   ├── Formatting+UsageAnalysis.swift   — usageStyle(), shouldShowInMenuBar(), blockingLimit(), detectCriticalReset()
│   └── Formatting+Tooltip.swift         — buildTooltip()
└── Windows/
    ├── AboutWindowController.swift      — about window
    ├── SetupWindowController.swift      — first-run setup window
    ├── PreferencesWindowController.swift — preferences window
    ├── CredentialFormView.swift          — reusable NSView with org ID + cookie fields
    ├── CredentialGuide.swift             — NSAttributedString instructions for credentials
    └── WindowManager.swift              — activation policy + window focus management
```

Key patterns:
- **Constants enum** — all magic strings/numbers centralized in `Constants.*`
- **MenuActions protocol** — `@objc` protocol decoupling menu actions from `MenuBarController`. MenuBuilder uses `#selector(MenuActions.*)` for type-safe target-action.
- **MonitorState** — shared value type used by `Formatting.buildTooltip()` and `MenuBuilder.build()`, eliminating parameter duplication.
- **CredentialFormView** — reusable NSView encapsulating credential fields, UUID validation, and keychain save logic. Used by both Setup and Preferences windows.
- **WindowManager** — centralized activation policy management for `.accessory` ↔ `.regular` transitions.
- **DataCoordinator** — owns services, state, and polling lifecycle. Notifies `MenuBarController` via `onUpdate` callback. Pure data orchestration with no UI dependencies.
- **Async polling** — `DataCoordinator` uses `Task` + `Task.sleep(for:)` instead of `Timer`, with dynamic retry intervals via `PollingScheduler`.
- **Formatting** — pure functions, testable in isolation. `usageStyle()` is the core UX logic. `displayLabel()` implements smart "all" labeling.
- **Sendable conformance** — all models conform to `Sendable` for strict concurrency safety. `ComponentStatus` is `Comparable` for natural severity ordering.
- **Dynamic windows** — `UsageResponse` decodes any API window key dynamically via `WindowKeyParser`. Window durations and model scopes are parsed from key names (e.g., `seven_day_sonnet` → 7d, Sonnet). `WindowEntry` is `Comparable` for deterministic ordering (shortest duration first, all-models before model-specific).

## What it shows in the menu bar

**Icon** — service status (green checkmark = all OK, colored icons for outages/maintenance).

**Text** — `42% | 18%` showing usage windows. First (shortest) window always visible; additional windows appear when outpacing time. "all" suffix shown on all non-model-specific entries when any model-specific variant exists (regardless of duration). Styled with bold and color based on urgency (see UX rules below).

**Tooltip** — single shared tooltip on the entire status item with usage details, time until reset, service status, and last refresh time.

**Dropdown menu** — usage bars, service component list, active incidents with links, refresh button, preferences.

### UX rules for usage text styling

Projection-based styling: implied rate = `utilization / timeElapsed`, projected = `utilization + rate × timeRemaining`. Levels:

| Level  | Projection threshold            | Fallback (no resetsAt) |
|--------|---------------------------------|------------------------|
| Bold   | projectedAtReset ≥ 80%         | utilization ≥ 80%      |
| Orange | projectedAtReset ≥ 100%        | utilization ≥ 90%      |
| Red    | projectedAtReset ≥ 120%        | utilization ≥ 95%      |

Special case: utilization ≥ 100% → always red (blocked). `timeRemaining = 0` → always normal (about to reset).

Window durations are parsed from API key names by `WindowKeyParser` (e.g., `five_hour` → 5h = 18000s).

## APIs

**Status**: `GET https://status.claude.com/api/v2/summary.json` — public, no auth. Returns `StatusSummary` with components, incidents, page status.

**Usage**: `GET https://claude.ai/api/organizations/{orgId}/usage` — requires session cookie. Returns a JSON object with dynamic window keys (e.g., `five_hour`, `seven_day`, `seven_day_sonnet`), each containing `utilization: Int` and `resets_at: ISO8601`. `UsageResponse` decodes all keys dynamically — new window types are handled without code changes.

Both APIs are polled together. Adaptive polling based on projection: approaching limit (<10min to limit) → scales down to 24s; critical projection (≥120%) → 30s; warning/active → 60s base; idle → gradually extends to 300s cap. Exponential backoff on failures (10s→300s cap).

Authentication: user provides session cookie string and organization ID via Preferences, stored in Keychain.

## Localization

**Source of truth: `Translations/*.json`** — one flat `{"key": "value"}` file per language. `_comments.json` holds developer comments for each key.

**`ClaudeMonitor/Localizable.xcstrings` is GENERATED and gitignored — never read or edit it.** It is produced by `scripts/generate-xcstrings.swift`. Xcode regenerates it automatically via a Run Script build phase. For CLI builds, `build.sh` calls the same script.

```
Translations/
  _comments.json     — {"key": "developer comment"}
  en.json            — {"key": "English text"}
  cs.json            — {"key": "Czech text"}
  …29 language files
scripts/
  generate-xcstrings.swift  — Translations/*.json → Localizable.xcstrings (+ .lproj for CLI builds)
```

### Workflow

**Add/change a translation key:**
1. Edit `Translations/en.json` (add/change the key)
2. Add the comment to `Translations/_comments.json`
3. Add the translation to each language file in `Translations/`
4. Run `swift scripts/generate-xcstrings.swift` to regenerate xcstrings

**Add a new language:** create a new `Translations/{code}.json` with all keys, run the generate script.

### Agent instructions for localization

When delegating translation work to a Sonnet agent, the prompt MUST include:
- "Source of truth is `Translations/*.json`. NEVER edit `Localizable.xcstrings`."
- Explicit list of keys to add/change
- English text for each key
- "After editing JSON files, run `swift scripts/generate-xcstrings.swift`"

## Tests

Unit tests in `ClaudeMonitorTests/`:
- **DataCoordinatorTests** — success/failure paths, auth failure, credential handling, scheduler integration, onUpdate callback, mixed service results (uses mock services via `StatusFetching`/`UsageFetching` protocols)
- **FormattingTests** — `timeUntil`, `progressBar`, `usageStyle` (dual-rule thresholds, edge cases), `buildTooltip` (all state permutations)
- **ModelsTests** — JSON decoding (dynamic windows, unknown keys), `WindowKeyParser` (basic/compound numbers, model scopes, unknown formats), `WindowEntry` sorting, `displayLabel` (disambiguation vs no-disambiguation), `ComponentStatus` severity/`Comparable` ordering, `Equatable` conformance, fractional-seconds fallback
- **MenuBuilderTests** — menu structure, section content, incident links, sorted components, controls

- **StatusBarRendererTests** — icon resolution (status → symbol/color mapping, refresh warning, worst-severity), title methods (no credentials, loading, blocked countdown, usage with styled percentages), `nsColor` mapping
- **DemoDataTests** — all scenarios produce valid data, rotation order covers all scenarios, default fallback
- **CredentialGuideTests** — `parseBoldMarkdown` (plain text, single/nested markers, unclosed markers, adjacent markers, empty bold)

All formatting, model, data coordination, rendering logic, and menu-building logic is tested. Services and window UI are not unit-tested (they hit real APIs / AppKit).

**CRITICAL: Tests must NEVER contaminate production data.** `UsageHistory` uses a hardcoded production path (`~/Library/Application Support/ClaudeMonitor/usage/`). Any test that calls `save()`, `load()`, `archiveWindow()`, or other disk I/O **MUST call `clearAll()` in cleanup** and wait for the async Task to complete. Tests that write to disk and don't clean up will inject fake data into the running app — this caused a severe, hard-to-diagnose bug where synthetic test values (10+i, 20+i, 30+i) appeared as real usage data.

## Token-Efficient Workflow

**Opus = brain, Sonnet agents = hands.** Main conversation on Opus: analysis, architecture, decisions, review, user communication. File reading, code search, and implementation delegated to Sonnet agents (`model: "sonnet"`).

### Opus-only (never delegate)

- **Sensitive/core files** — files where every word matters (prompts, configs, API contracts)
- **Architecture decisions** — structure, abstractions, API design
- **Code review** — mandatory for every agent change, no exceptions

### Agent instruction rules

Sonnet agents do NOT see CLAUDE.md. Every prompt MUST include:

1. **Relevant project rules** — copy-paste applicable CLAUDE.md rules into the prompt
2. **Explicit file paths** — never "find the file"; if unknown, Explore agent first
3. **Existing patterns** — describe/quote the pattern to follow
4. **Acceptance criteria** — what "done" looks like specifically
5. **What NOT to do** — no extra features, no refactoring surrounding code, no comments on unchanged code, no speculative abstractions, no impossible-case error handling
6. **Verification step** — re-read modified file, verify correctness

### Workflow

```
1. Explore agent (Sonnet) → reads code, returns summary
2. Opus analyzes → decides what and how
3. Implementation agent (Sonnet) → precise instructions + rules → makes changes
4. Opus reviews diff → approves or corrects
```

Step 4 mandatory. Steps 1-2 skippable for simple changes. Step 3 can parallelize (e.g., backend + frontend).
