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

**`scripts/build-config.sh`** is the authoritative source for shared build parameters (app name, bundle ID, version, deployment target, Swift version, default isolation, upcoming features). `build.sh` and `install.sh` source it directly. `Package.swift` and the Xcode project (`project.pbxproj`) must be kept in sync manually — when changing a build setting, update `scripts/build-config.sh` first, then propagate to `Package.swift` and the Xcode project.

## Architecture

```
ClaudeMonitor/
├── AppDelegate.swift                    — @main entry point, lifecycle, editing shortcuts
├── BundleModule.swift                   — Bundle.module shim for Xcode builds
├── Constants.swift                      — all hardcoded values (URLs, intervals, file naming, thresholds)
├── DemoData.swift                       — demo mode data for screenshots/testing
├── MenuBuilder+LiveUpdate.swift         — live menu refresh while open
├── Extensions/
│   ├── JSONDecoder+ISO8601.swift        — shared ISO8601 decoder with fractional seconds
│   └── NSColor+Desaturate.swift
├── Generated/BuildInfo.swift            — GENERATED from scripts/build-config.sh (incl. the under-test env var name)
├── Models/
│   ├── AppState.swift                   — MonitorState, UsageSnapshot, ServiceHealth, HistoryHealth, ProfileSnapshot
│   ├── Profile.swift                    — Profile (id, name, organizationId); cookie lives in the encrypted store
│   ├── StatusModels.swift               — StatusSummary, StatusComponent, ComponentStatus, Incident, PageStatus
│   ├── UsageModels.swift                — UsageResponse, UsageWindow, WindowEntry, WindowKeyParser
│   ├── UsageHistory.swift               — WindowInstance, UsageEvent, record(), boundary detection, partitionEvents
│   ├── UsageHistory+Analysis.swift      — nonisolated pure analysis: segments, rate (credit-aware), projection
│   ├── UsageHistory+Archive.swift       — archiveWindow, plateau-collapse, retention, quarantine pruning
│   ├── UsageHistory+Persistence.swift   — save/load, legacy-deletion safety, quarantine
│   ├── UsageHistory+Manifest.swift      — per-org manifest (persisted missing-window clock)
│   ├── UsageHistory+LegacyArchiveMigration.swift — one-time v1 .json.lzma → current format migration
│   └── WindowInstanceCodec.swift        — v3 binary codec, v2 + legacy v1 read paths, CRC32
├── Services/
│   ├── DataCoordinator.swift            — orchestration, polling lifecycle, history maintenance task
│   ├── DataCoordinator+Refresh.swift    — refresh cycle, UsageFetchOutcome (fresh vs stale)
│   ├── DataCoordinator+Polling.swift    — poll loop (weak self, scoped per iteration), switchToProfile
│   ├── ProfileStore.swift               — profile registry, active profile, per-profile cookies, registry quarantine
│   ├── ProfileStore+LegacyMigration.swift — one-time single-account → profile migration
│   ├── StatusService.swift              — fetches status.claude.com/api/v2/summary.json
│   ├── UsageService.swift               — fetches claude.ai/api/organizations/{orgId}/usage
│   ├── PollingScheduler.swift           — adaptive polling intervals
│   ├── KeychainService.swift            — encrypted credential storage (UserDefaults + AES-GCM)
│   ├── PathMonitor.swift                — network reachability
│   ├── SystemIdleService.swift          — user idle time (away mode)
│   └── ServiceError.swift               — shared error type, RetryCategory
├── MenuBar/
│   ├── MenuBarController.swift          — status bar item, UI coordination
│   ├── MenuBarController+Countdown.swift — countdown timer, critical reset animation
│   ├── MenuBuilder.swift                — MenuActions protocol + NSMenu construction
│   ├── MenuBuilder+ControlItems.swift   — footer icon bar, hidden ⌘R/⌘,/⌘Q shortcut items, historyHealthItem
│   ├── MenuBuilder+AccountSwitcher.swift — header account switcher (shown with ≥2 profiles)
│   ├── MenuBuilder+State.swift          — state → menu reconciliation, refreshGraph
│   ├── MenuBuilder+{Reconciliation,UsageFormatting,UsageItems,ViewLayout}.swift
│   ├── GraphDrawer.swift                — usage graph rendering
│   ├── GraphDrawer+Credits.swift        — credit-event markers (dashed line + step + dot)
│   ├── GraphDrawer+{Background,Decorations,Projection,Segments}.swift
│   ├── UsageGraphView.swift, UsageRowView.swift, ControlRowView.swift
│   ├── AccountToggleView.swift          — segmented account switcher view (HeaderAccountSwitcher, AccountSegment)
│   ├── FooterIconButton.swift           — accessible icon button for the footer bar
│   ├── StatusBarRenderer{,+IconRendering,+TitleRendering}.swift
│   ├── Formatting.swift                 — timeUntil(), progressBar(), displayLabel(), creditDescription()
│   └── Formatting+UsageAnalysis.swift   — usageStyle(), shouldShowInMenuBar(), blockingLimit(), detectCriticalReset()
└── Windows/
    ├── AboutWindowController.swift      — about window
    ├── SetupWindowController.swift      — first-run setup window
    ├── PreferencesWindowController.swift — NSTabView: one tab per account, General (applies immediately), Add Account
    ├── RetentionChangeDecision.swift    — pure retention-change decision logic (AppKit-free, tested)
    ├── CredentialFormView.swift          — reusable NSView with name + org ID + cookie fields; modes .edit/.add/.setup
    ├── CredentialGuide.swift             — NSAttributedString instructions for credentials
    └── WindowManager.swift              — activation policy + window focus management
```

Key patterns:
- **Constants enum** — all magic strings/numbers centralized in `Constants.*`
- **MenuActions protocol** — `@objc` protocol decoupling menu actions from `MenuBarController`. MenuBuilder uses `#selector(MenuActions.*)` for type-safe target-action.
- **MonitorState** — shared value type used by `MenuBuilder.build()` and `StatusBarRenderer`, eliminating parameter duplication.
- **CredentialFormView** — reusable NSView encapsulating credential fields, UUID validation, and saving through `ProfileStore`. Used by both Setup and Preferences windows.
- **ProfileStore** — the only owner of profiles and their cookies. Built in production only via `ProfileStore.production()`; `init` has no defaults and traps on `UserDefaults.standard` under the test env var.
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

**Dropdown menu** — account switcher in the Usage header (two or more profiles), usage bars, usage graph (optional), service component list (compact by default: one line while all operational, otherwise only affected components), active incidents with links, footer icon bar (refresh, preferences, about, quit).

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

Authentication: per account profile, the user provides a session cookie and organization ID via Setup or Preferences. The profile registry (ids, names, org IDs) is plaintext in `UserDefaults`; each cookie is stored encrypted under `cookieString.<profileId>`.

## Account profiles

- **History stays keyed by organization ID**, not by profile. Two profiles with the same org (compared as UUIDs, case-insensitively) are rejected — they would share one history directory.
- **Switching** goes through `restartPolling()` so the scheduler's backoff never carries over, and changing the organization clears the displayed usage. The previous account's numbers must never appear under the new one — the open menu swaps its usage rows for a loading placeholder.
- **A late response never crosses accounts.** `refresh()` captures `usageHistory.generation` before fetching and re-checks it after every `await` before recording, archiving or saving.
- **Migration** from the single-account keys runs once: the registry key's presence is the marker. It is written only when there was nothing to migrate or the new cookie saved; a failed save retries next launch. The legacy keys are removed after a successful migration.
- **A corrupt registry is quarantined** (`profiles.corrupt.<epoch>`), never overwritten; entries with a non-UUID org ID are dropped in memory and the original is quarantined.
- At most `Constants.Profiles.maxCount` profiles; the Add tab hides at the limit.

## Localization

**Source of truth: `Translations/*.json`** — one flat `{"key": "value"}` file per language. `_comments.json` holds developer comments for each key.

A value is **either** a plain string **or** a CLDR plural object (`{"one": "…", "few": "…", "other": "…"}`), which the generator turns into xcstrings plural variations and a `.stringsdict` for CLI builds. Use the categories each language actually needs — `other` only for ja/ko/zh/vi/th/tr/hu/id/ms/hi, `one`/`few`/`other` for cs/sk/hr, `one`/`few`/`many`/`other` for ru/pl/uk, all six for ar, `one`/`other` for most Western European. Never blanket-copy English's category set: Czech "1 let" is wrong, it must be "1 rok / 2 roky / 5 let". `other` is required in every plural object (it is the universal fallback) and the generator hard-fails without it.

The generator **exits non-zero** on any malformed input — a value that is neither a string nor a `{category: string}` object, an empty plural object, a missing `other`, or a present-but-broken `_comments.json`. A genuinely absent `_comments.json` is fine. Verified behaviour: `.stringsdict` resolves standalone, so plural keys correctly need no `Localizable.strings` entry.

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
- **FormattingTests** — `timeUntil`, `progressBar`, `usageStyle` (dual-rule thresholds, edge cases)
- **ModelsTests** — JSON decoding (dynamic windows, unknown keys), `WindowKeyParser` (basic/compound numbers, model scopes, unknown formats), `WindowEntry` sorting, `displayLabel` (disambiguation vs no-disambiguation), `ComponentStatus` severity/`Comparable` ordering, `Equatable` conformance, fractional-seconds fallback
- **MenuBuilderTests** — menu structure, section content, incident links, sorted components, compact services (build and live update), footer buttons and hidden shortcuts, account switcher identity and staleness, live usage-row swapping after an account switch
- **ProfileStoreTests** — registry CRUD, duplicate orgs, max count, migration (success, save failure, partial/invalid legacy data, idempotence), registry quarantine
- **ProfileSwitchTests** — switching uses the new credentials, clears the previous account's usage, discards in-flight responses of the previous account
- **PreferencesWindowControllerTests** — retention confirmation, immediate General settings, no lost edits across re-show/add/remove, Add tab at the limit, setup recovery

- **StatusBarRendererTests** — icon resolution (status → symbol/color mapping, refresh warning, worst-severity), title methods (no credentials, loading, blocked countdown, usage with styled percentages), `nsColor` mapping
- **DemoDataTests** — all scenarios produce valid data, rotation order covers all scenarios, default fallback
- **CredentialGuideTests** — `parseBoldMarkdown` (plain text, single/nested markers, unclosed markers, adjacent markers, empty bold)

All formatting, model, data coordination, profile storage, rendering logic, and menu-building logic is tested. Network services are not unit-tested (they hit real APIs); window controllers are tested through injected `defaults:`/`ProfileStore` and read-only test seams, without showing windows.

### CRITICAL: tests must never contaminate production state

Isolation is structural, not a matter of discipline. Two past incidents drove this: synthetic test values appearing as real usage data, and ~1966 junk directories injected into the user's real history directory.

- **History**: `UsageHistory.init` requires `baseDirectory` — there is NO default pointing at production. The production path is built in exactly one place (`UsageHistory.productionBaseDirectory`) and only the app constructs it. Tests get a per-run root from `TestHistoryRoot`, under `NSTemporaryDirectory()` — never under `Application Support`. `test.sh` exports the env var named by `UNDER_TEST_ENV_VAR` in `scripts/build-config.sh`, and `UsageHistory.init` traps if that is set while `baseDirectory` is inside `Application Support`.
- **Preferences**: tests never touch `UserDefaults.standard`. `TestPreferencesRoot` hands out per-run suite names under one prefix; `PreferencesWindowController` takes an injectable `defaults:`.
- **Clean at START, not at end.** Each run sweeps *previous* runs' data and deliberately leaves its own behind, so a failed run's on-disk state survives for post-mortem debugging. Do NOT add `clearAll()`/`cleanup()` teardown — it deletes exactly the evidence a failing assertion needs (`#expect` does not halt, so teardown still runs after a failure).
- **One exception to "don't clean up after yourself": permissions.** A test that deliberately chmods a directory read-only MUST restore it. An unwritable directory left behind permanently wedges the next run's sweep — this actually happened.
- The sweep identifies a live run by PID **plus** the kernel-reported process start time (a bare PID gets recycled onto an unrelated live process and the directory then survives forever), and it restores write permissions and retries once before reporting a failure via `Issue.record`.

## Usage history

### Window instances — identity is stored, never derived

A `WindowInstance` (`id`, `storageIdentity`, `resetsAt`, `firstObservedAt`, `samples`, `events`) owns its samples permanently. This is the core invariant: **a sample belongs to the instance it was recorded into.**

Earlier code derived ownership at read time as `windowStart = resetsAt - duration` and keyed samples only by duration+model. One absent or stale `resets_at` from the API then merged samples across windows. `WindowEntry.windowStart` still exists but is **graph x-axis only** — never data ownership.

**Boundary rule** — a new window requires BOTH that `resets_at` moved forward beyond `resetBoundaryTolerance` AND that `now >= stored` (the previous reset moment has actually passed). No threshold derived from window duration: the old `duration * 0.5` heuristic silently missed real boundaries (3 months of weekly windows produced one archive instead of ~12), and a bare 60s threshold would destroy live windows on ordinary server jitter. A forward move while the old reset is still in the future is drift — same instance, update the stored value.

At a proven boundary, samples and events are partitioned at the old `resetsAt`: `< boundary` → archived, `>= boundary` → carried into the new instance. Without this, a post-reset sample lands in the archived window (observed live: an archive ending in a phantom crash to 0 that none of the 11 older archives had).

### Credits are not resets

Anthropic sometimes zeroes or reduces utilization mid-window **without** moving `resets_at` — a usage credit. Confirmed in real archives: 3 occurrences across 13 windows, e.g. weekly 55% → 0%.

**A utilization drop is therefore NOT a reset signal and must never split a window.** Drops are recorded as `UsageEvent(kind: .credit)` carrying `at`, `from`, `to`, and `fromTimestamp` (the origin sample's time; `nil` in files written before it existed). `fromTimestamp` exists so straddle detection compares two stored timestamps instead of matching an event to a sample by value.

Two consequences that are easy to get wrong:
- **Server lag**: at a real reset the API often drops utilization one poll *before* it advances `resets_at`, which looks exactly like a credit. The boundary partition discards an event whose from/to straddle a **proven** boundary; on a **derived** boundary it keeps it (assigned by `at`), because discarding on a guess is the worse error.
- **Projection**: the implied rate must be measured from the most recent credit, not the window start — otherwise the numerator resets, the denominator does not, and the app stops warning precisely when the user starts spending a fresh credit.

### On-disk format (v3)

`magic "CMH2" | version | metaLen | metadata JSON | sampleCount | crc32 | payload`, little-endian, written atomically. Payload: first sample absolute (uvarint epoch + uvarint utilization), then zigzag-varint deltas. Metadata JSON carries `id`, `resetsAt`, `firstObservedAt`, `events`.

Chosen by measurement over a real corpus plus a 2-year synthetic one: **48% smaller and ~150× faster** than the previous lzma'd JSON, and no compression library on the read path. Because dropping compression also dropped lzma's implicit integrity check, the **CRC32 covers everything except the magic and the CRC field itself** — v2 left `version` and `sampleCount` outside it, so a single flipped bit shrinking `sampleCount` silently discarded real samples with no error. The decoder also requires the payload to be fully consumed and caps varint length.

The reader accepts v3, the v2 layout, and legacy v1 (bare `[[epoch,util],…]` JSON, optionally lzma'd). The writer only emits v3. **Corrupt files are expected input, not programmer error** — decode failures return typed errors and never trap, and an undecodable file is quarantined (renamed with a timestamped `corrupt_` prefix), never deleted.

**Plateau-collapse** applies to archives only, never the live instance: collapse runs of equal utilization keeping first+last of each run, and **never collapse across a gap ≥ `gapThreshold`** — the app was not running then, and the graph must show a discontinuity instead of interpolating. Real data makes this non-hypothetical: one weekly archive has 74 gaps ≥ 300s, the largest 16.5 hours. Measured reduction on real archives: 72–87%.

### Retention

Calendar-based (`Calendar.date(byAdding: .year, value: -n)`, never a seconds-per-year approximation), default **2 years**, user-configurable 1–99 via a stepper in Preferences. Lowering it deletes history, so it requires confirmation stating the exact count, computed and executed against **one** captured instant. Pruning runs at launch and daily — not only after a boundary, which is why the previous 77-day policy almost never actually ran. An archive whose filename cannot be parsed is never deleted; neither is a quarantined file whose name carries no timestamp.

`HistoryHealth` on `MonitorState` surfaces save failures and quarantined-file counts in the menu. Write failures recover silently rather than trapping — a full disk or read-only volume is an environmental condition, not a bug — so the status line is the only signal the user gets.

## Token-Efficient Workflow

**Opus = brain, Sonnet agents = hands.** Main conversation on Opus: analysis, architecture, decisions, review, user communication. File reading, code search, and implementation delegated to Sonnet agents (`model: "sonnet"`).

### Opus-only (never delegate)

- **Sensitive/core files** — files where every word matters (prompts, configs, API contracts)
- **Architecture decisions** — structure, abstractions, API design
- **Code review** — mandatory for every agent change, no exceptions

### Agents never execute commands

**HARD RULE**: agents never run any command — not `./test.sh`, not `./install.sh`, nothing. They write code, analyze, and review only. The orchestrator runs all builds and tests and reports results back to the agent if iteration is needed. State this prohibition explicitly in every agent prompt.

Consequence: agents cannot verify their own work empirically. Verification belongs to the orchestrator, together with mandatory review-agent rounds using named hypotheses (an agent's own quality claim is not evidence).

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
