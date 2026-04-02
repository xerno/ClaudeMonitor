# CLAUDE.md

## Project Overview

**ClaudeMonitor** — macOS menu bar app that displays Claude usage limits and Anthropic service status in real time.

## Build & Run

```bash
# Open in Xcode and press ⌘R
open ClaudeMonitor.xcodeproj

# Or build from CLI
xcodebuild -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor -configuration Debug build

# Run tests
xcodebuild test -project ClaudeMonitor.xcodeproj -scheme ClaudeMonitor
```

Xcode 26 project uses `PBXFileSystemSynchronizedRootGroup` — new `.swift` files in source/test directories are auto-discovered, no pbxproj edits needed.

## Architecture

```
ClaudeMonitor/
├── AppDelegate.swift                 — @main entry point, lifecycle, editing shortcuts
├── DataCoordinator.swift             — data fetching orchestration, polling, state management
├── MenuBarController.swift           — status bar item, countdown timer, UI coordination
├── MenuBuilder.swift                 — MenuActions protocol + stateless NSMenu construction
├── Formatting.swift                  — timeUntil(), progressBar(), usageStyle(), buildTooltip()
├── Models.swift                      — StatusSummary, UsageResponse, MonitorState, etc.
├── ServiceError.swift                — shared error type for both services
├── StatusService.swift               — fetches status.claude.com/api/v2/summary.json
├── UsageService.swift                — fetches claude.ai/api/organizations/{orgId}/usage
├── CredentialFormView.swift          — reusable NSView with org ID + cookie fields, validation
├── SetupWindowController.swift       — first-run setup window (embeds CredentialFormView)
├── PreferencesWindowController.swift — preferences window (embeds CredentialFormView)
├── CredentialGuide.swift             — NSAttributedString instructions for finding credentials
├── WindowManager.swift               — activation policy + window focus management
├── KeychainService.swift             — encrypted credential storage (UserDefaults + AES-GCM)
├── Constants.swift                   — all hardcoded values (URLs, intervals, keychain keys)
└── JSONDecoder+ISO8601.swift         — shared ISO8601 decoder with fractional seconds
```

Key patterns:
- **Constants enum** — all magic strings/numbers centralized in `Constants.*`
- **MenuActions protocol** — `@objc` protocol decoupling menu actions from `MenuBarController`. MenuBuilder uses `#selector(MenuActions.*)` for type-safe target-action.
- **MonitorState** — shared value type used by `Formatting.buildTooltip()` and `MenuBuilder.build()`, eliminating parameter duplication.
- **CredentialFormView** — reusable NSView encapsulating credential fields, UUID validation, and keychain save logic. Used by both Setup and Preferences windows.
- **WindowManager** — centralized activation policy management for `.accessory` ↔ `.regular` transitions.
- **DataCoordinator** — owns services, state, and polling lifecycle. Notifies `MenuBarController` via `onUpdate` callback. Pure data orchestration with no UI dependencies.
- **Async polling** — `DataCoordinator` uses `Task` + `Task.sleep(for:)` instead of `Timer`, with dynamic retry intervals via `PollingScheduler`.
- **Formatting** — pure functions, testable in isolation. `usageStyle()` is the core UX logic.
- **Sendable conformance** — all models conform to `Sendable` for strict concurrency safety. `ComponentStatus` is `Comparable` for natural severity ordering.

## What it shows in the menu bar

**Icon** — service status (green checkmark = all OK, colored icons for outages/maintenance).

**Text** — `42% | 18%` showing 5-hour and 7-day usage. Styled with bold and color based on urgency (see UX rules below).

**Tooltip** — single shared tooltip on the entire status item with usage details, time until reset, service status, and last refresh time.

**Dropdown menu** — usage bars, service component list, active incidents with links, refresh button, preferences.

### UX rules for usage text styling

Dual-rule pattern: each visual level triggers on EITHER a fixed utilization threshold OR when the projected consumption rate exceeds the limit (with per-level offsets).

| Level  | Fixed threshold     | Time-based rule                        |
|--------|--------------------|-----------------------------------------|
| Bold   | utilization ≥ 50%  | utilization > timeElapsedPercent        |
| Orange | utilization ≥ 70%  | utilization > timeElapsedPercent + 20   |
| Red    | utilization ≥ 80%  | utilization > timeElapsedPercent + 35   |

`timeElapsedPercent = (1 − timeRemaining / windowDuration) × 100`

The time-based rule checks whether consumption at the current rate would exceed the limit before the window resets. The offsets (+20, +35) require progressively more severe overpacing.

Window durations are hardcoded constants (5h, 7d) since the API doesn't return them.

## APIs

**Status**: `GET https://status.claude.com/api/v2/summary.json` — public, no auth. Returns `StatusSummary` with components, incidents, page status.

**Usage**: `GET https://claude.ai/api/organizations/{orgId}/usage` — requires session cookie. Returns `UsageResponse` with optional `five_hour`, `seven_day`, `seven_day_sonnet` windows (each has `utilization: Int` and `resets_at: ISO8601`).

Both APIs are polled together. Adaptive polling: base 60s, speeds up to 30s when usage is increasing, slows to 10min when stable. In critical state (red), floor is 2min. Exponential backoff on failures (10s→300s cap).

Authentication: user provides session cookie string and organization ID via Preferences, stored in Keychain.

## Tests

Unit tests in `ClaudeMonitorTests/`:
- **DataCoordinatorTests** — success/failure paths, auth failure, credential handling, scheduler integration, onUpdate callback, mixed service results (uses mock services via `StatusFetching`/`UsageFetching` protocols)
- **FormattingTests** — `timeUntil`, `progressBar`, `usageStyle` (dual-rule thresholds, edge cases), `buildTooltip` (all state permutations)
- **ModelsTests** — JSON decoding, `ComponentStatus` severity/`Comparable` ordering, `Equatable` conformance, fractional-seconds fallback
- **MenuBuilderTests** — menu structure, section content, incident links, sorted components, controls

All formatting, model, data coordination, and menu-building logic is tested. Services and UI are not unit-tested (they hit real APIs / AppKit).

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
