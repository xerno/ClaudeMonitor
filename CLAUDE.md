# CLAUDE.md

## Project Overview

**ClaudeMonitor** — macOS menu bar app that displays Claude usage limits and Anthropic service status in real time.

## Build & Run

```bash
open ClaudeMonitor.xcodeproj   # then ⌘R
./install.sh                   # build + test + install
./install.sh --skip-tests      # quick rebuild
./test.sh                      # tests only
```

**IMPORTANT**: Always use `./install.sh` and `./test.sh` for CLI builds and tests. Never search for Xcode, never use raw `xcodebuild`, and never run `xcode-select`.

Xcode 26 project uses `PBXFileSystemSynchronizedRootGroup` — new `.swift` files in source/test directories are auto-discovered, no pbxproj edits needed.

**`Assets.xcassets` is excluded from the SPM target** (`Package.swift`) and `build.sh` copies resources by name, so an image in the catalogue is invisible to the test bundle. Artwork that needs a test — the sunburst mark, the status badges — is drawn as a path or an SF Symbol composition and measured with `pixelCount` (`ClaudeMonitorTests/Support/PixelCount.swift`).

### Build settings — single source of truth

**`scripts/build-config.sh`** is the source of truth for app name, bundle ID, version, deployment target, Swift version, default isolation and upcoming features. `build.sh` and `install.sh` source it. `Package.swift` and `project.pbxproj` are synced by hand: change `build-config.sh` first, then propagate.

## Architecture

```
ClaudeMonitor/
├── AppDelegate.swift                    — @main entry point, lifecycle, editing shortcuts
├── BundleModule.swift                   — Bundle.module shim for Xcode builds
├── Constants.swift                      — all hardcoded values (URLs, intervals, file naming, thresholds)
├── DemoData.swift                       — demo mode data for screenshots/testing
├── MenuBuilder+LiveUpdate.swift         — live menu refresh while open
├── Energy/                              — datacentre energy estimate from Claude Code token logs
│   ├── TokenUsage.swift, TokenLogReader.swift — ~/.claude/projects/**/*.jsonl scan, dedup, incremental offsets
│   └── EnergyModel.swift, EnergyMonitor.swift — per-model coefficients, background rescan
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
│   ├── AccountMonitor.swift             — one account: own scheduler, history, usage state, poll loop, history maintenance task, UsageFetchOutcome
│   ├── DataCoordinator.swift            — monitor per organization, one UsageHistory per organization, active-account facades
│   ├── DataCoordinator+Refresh.swift    — status refresh, demo refresh
│   ├── DataCoordinator+Polling.swift    — status poll loop, restart/stop of all loops, switchToProfile
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
│   ├── MenuBuilder+TitleHeader.swift    — dropdown title block: mark, app name, switcher, status badge
│   ├── ClaudeGlyph.swift                — sunburst mark drawn as a path (not an asset — see above)
│   ├── GraphDrawer.swift                — usage graph rendering
│   ├── GraphDrawer+Credits.swift        — credit-event markers (dashed line + step + dot)
│   ├── GraphDrawer+{Background,Decorations,Projection,Segments}.swift
│   ├── UsageGraphView.swift, UsageRowView.swift, ControlRowView.swift
│   ├── AccountToggleView.swift          — drawn coral account pill in the title block (HeaderAccountSwitcher, AccountSegment, per-segment tooltips)
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
- **MenuActions protocol** — `@objc` protocol decoupling menu actions from `MenuBarController`; `MenuBuilder` targets it via `#selector(MenuActions.*)`.
- **MonitorState** — value type passed to `MenuBuilder.build()` and `StatusBarRenderer`.
- **ProfileStore** — the only owner of profiles and their cookies. Built in production only via `ProfileStore.production()`; `init` has no defaults and traps on `UserDefaults.standard` under the test env var.
- **DataCoordinator** — owns services, one `AccountMonitor` per profile's organization, and the status poll loop. Exposes the active account through read-only facades and forwards only the active monitor's `onUpdate`/`onCriticalReset` to `MenuBarController`. No UI dependencies.
- **Async polling** — every `AccountMonitor` polls its own account with `Task` + `Task.sleep(for:)` instead of `Timer`, with retry intervals from its own `PollingScheduler`; the status page has a separate loop and scheduler.
- **Formatting** — pure functions. `usageStyle()` is the core UX logic; `displayLabel()` implements the "all" labelling.
- **Sendable** — all models are `Sendable`.
- **Dynamic windows** — `UsageResponse` decodes any API window key via `WindowKeyParser`, which parses duration and model scope from the key (`seven_day_sonnet` → 7d, Sonnet). `WindowEntry` is `Comparable`: shortest duration first, all-models before model-specific.

## What it shows in the menu bar

**Icon** — service status (green checkmark = all OK, colored icons for outages/maintenance).

**Text** — `42% | 18%` showing usage windows. A blocked window replaces this with a 🛑 and a countdown, unless `Preferences → General → Show reset countdown in the menu bar` is off: then the title goes empty and only the icon remains. The countdown timer runs either way, because it also asks for a refresh once the block expires. The first (shortest) window is always visible; further windows appear when outpacing time. The "all" suffix appears on every non-model-specific entry whenever any model-specific variant exists, whatever the duration. Bold and color follow the urgency rules below.

**Tooltip** — one tooltip on the whole status item: usage details, time until reset, service status, last refresh time.

**Dropdown menu** — title block (mark, app name, rate-limit badge, account switcher with two or more profiles), usage bars, optional usage graph, service component list (compact by default: one line while all operational, otherwise only affected components), active incidents with links, footer icon bar (refresh, preferences, about, quit).

### UX rules for usage text styling

Projection-based styling: implied rate = `utilization / timeElapsed`, projected = `utilization + rate × timeRemaining`.

| Level  | Projection threshold            | Fallback (no resetsAt) |
|--------|---------------------------------|------------------------|
| Bold   | projectedAtReset ≥ 80%         | utilization ≥ 80%      |
| Orange | projectedAtReset ≥ 100%        | utilization ≥ 90%      |
| Red    | projectedAtReset ≥ 120%        | utilization ≥ 95%      |

Special cases: utilization ≥ 100% is always red (blocked); `timeRemaining = 0` is always normal (about to reset).

The dropdown's progress bars use the same threshold: `Formatting.barFillColor` is `restingAccent` (the services-status green) while a window has headroom and red at `blockedUtilization`. Share that constant; do not add a second literal.

Window durations come from API key names via `WindowKeyParser` (`five_hour` → 5h = 18000s).

## APIs

**Status**: `GET https://status.claude.com/api/v2/summary.json` — public, no auth. Returns `StatusSummary` with components, incidents, page status.

**Usage**: `GET https://claude.ai/api/organizations/{orgId}/usage` — requires a session cookie. Returns a JSON object with dynamic window keys (`five_hour`, `seven_day`, `seven_day_sonnet`, …), each with `utilization: Int` and `resets_at: ISO8601`. `UsageResponse` decodes all keys dynamically, so new window types need no code change.

Both APIs are polled together. Adaptive intervals by projection: under 10 min to the limit scales down to 24s; critical projection (≥120%) 30s; warning/active 60s base; idle extends gradually to a 300s cap. Failures back off exponentially (10s→300s cap).

Authentication: per account profile, the user provides a session cookie and organization ID in Setup or Preferences. The profile registry (ids, names, org IDs) is plaintext in `UserDefaults`; each cookie is encrypted under `cookieString.<profileId>`.

## Account profiles

- **History is keyed by organization ID**, not by profile. Two profiles with the same org (compared as UUIDs, case-insensitively) are rejected: they would share one history directory.
- **Every account is polled independently**, with its own adaptive scheduler, history and last-known usage. An inactive account slows down on its own and its history has no gaps. Switching changes the active profile and restarts that account's loop: its own last-known data shows immediately, and the previous account's numbers never appear under it.
- **A late response never crosses accounts.** Only the monitor that requested a response records it, into that organization's history. The coordinator owns exactly one `UsageHistory` per organization and hands it to every monitor it builds for that organization, so two instances never write the same directory. `refresh()` captures `usageHistory.generation` before fetching and re-checks it after every `await`, which guards against `clearAll()`.
- **Usage requests never share cookies.** `UsageService` uses its own ephemeral session without a cookie store; a shared jar let one account's server-set `sessionKey` ride along with another's requests.
- **Migration** from the single-account keys runs once, and the registry key's presence is the marker. It is written only when there was nothing to migrate or the new cookie saved; a failed save retries next launch. The legacy keys are removed after a successful migration.
- **A corrupt registry is quarantined** (`profiles.corrupt.<epoch>`), never overwritten; entries with a non-UUID org ID are dropped in memory and the original is quarantined.
- At most `Constants.Profiles.maxCount` profiles; the Add tab hides at the limit.

## Localization

**Source of truth: `Translations/*.json`** — one flat `{"key": "value"}` file per language. `_comments.json` holds a developer comment for each key.

A value is **either** a plain string **or** a CLDR plural object (`{"one": "…", "few": "…", "other": "…"}`), which the generator turns into xcstrings plural variations and a `.stringsdict` for CLI builds. Use the categories each language needs: `other` only for ja/ko/zh/vi/th/tr/hu/id/ms/hi, `one`/`few`/`other` for cs/sk/hr, `one`/`few`/`many`/`other` for ru/pl/uk, all six for ar, `one`/`other` for most Western European languages. Never copy English's category set: Czech "1 let" is wrong, it must be "1 rok / 2 roky / 5 let". `other` is required in every plural object (the universal fallback) and the generator hard-fails without it.

The generator **exits non-zero** on malformed input: a value that is neither a string nor a `{category: string}` object, an empty plural object, a missing `other`, or a present-but-broken `_comments.json`. A genuinely absent `_comments.json` is fine. `.stringsdict` resolves standalone, so plural keys need no `Localizable.strings` entry.

**`ClaudeMonitor/Localizable.xcstrings` is GENERATED and gitignored — never read or edit it.** `scripts/generate-xcstrings.swift` produces it; Xcode regenerates it in a Run Script build phase and `build.sh` calls the same script for CLI builds.

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

**Add a new language:** create `Translations/{code}.json` with all keys, then run the generate script.

### Agent instructions for localization

When delegating translation work to a Sonnet agent, the prompt MUST include:
- "Source of truth is `Translations/*.json`. NEVER edit `Localizable.xcstrings`."
- Explicit list of keys to add/change
- English text for each key
- "After editing JSON files, run `swift scripts/generate-xcstrings.swift`"

## Tests

Unit tests live in `ClaudeMonitorTests/`. Formatting, models, data coordination (mock services via `StatusFetching`/`UsageFetching`), profile storage, rendering and menu building are tested. Network services are not, because they hit real APIs. Window controllers are tested through injected `defaults:`/`ProfileStore` and read-only test seams, without showing windows.

**A view-tree assertion must recurse and assert it found something.** `allSatisfy` on an empty array is `true`, so a helper that walks only direct subviews passes while checking nothing (as `labels(in:)` in `MenuBuilderTests` once did). Helpers recurse, and callers pin the expected count.

### CRITICAL: tests must never contaminate production state

Isolation is structural, not discipline. Synthetic test values once showed up as real usage data, and ~1966 junk directories were injected into the real history directory.

- **History**: `UsageHistory.init` requires `baseDirectory`; there is NO default pointing at production. The production path is built in one place (`UsageHistory.productionBaseDirectory`) and only the app uses it. Tests get a per-run root from `TestHistoryRoot` under `NSTemporaryDirectory()`, never `Application Support`. `test.sh` exports the env var named by `UNDER_TEST_ENV_VAR` in `scripts/build-config.sh`, and `UsageHistory.init` traps if it is set while `baseDirectory` is inside `Application Support`.
- **Preferences**: tests never touch `UserDefaults.standard`. `TestPreferencesRoot` hands out per-run suite names under one prefix, and `PreferencesWindowController` takes an injectable `defaults:`.
- **Clean at START, not at end.** Each run sweeps *previous* runs' data and leaves its own behind, so a failed run's on-disk state survives for post-mortem. Do NOT add `clearAll()`/`cleanup()` teardown: `#expect` does not halt, so teardown would still run and delete the evidence.
- **Permissions**: a test that chmods a directory read-only MUST restore it. An unwritable directory left behind wedges the next run's sweep.
- The sweep identifies a live run by PID **plus** the kernel-reported process start time (a bare PID is recycled onto an unrelated live process and the directory then survives forever). It restores write permissions and retries once before reporting a failure via `Issue.record`.

## Usage history

### Window instances — identity is stored, never derived

A `WindowInstance` (`id`, `storageIdentity`, `resetsAt`, `firstObservedAt`, `samples`, `events`) owns its samples permanently. Core invariant: **a sample belongs to the instance it was recorded into.** Ownership is never derived from `resets_at - duration`, because one absent or stale `resets_at` would merge samples across windows. `WindowEntry.windowStart` is **graph x-axis only**, never data ownership.

**Boundary rule** — a new window requires BOTH that `resets_at` moved forward beyond `resetBoundaryTolerance` AND that the previous reset moment has passed (`now >= stored - tolerance`). No threshold is derived from window duration: a `duration * 0.5` heuristic missed real boundaries, and a bare 60s threshold would split live windows on ordinary server jitter. A forward move while the old reset is still in the future is drift: same instance, update the stored value.

At a proven boundary, samples and events are partitioned at the old `resetsAt`: `< boundary` is archived, `>= boundary` carries into the new instance. Otherwise a post-reset sample lands in the archived window and ends it in a phantom drop to 0.

### Credits are not resets

Anthropic sometimes zeroes or reduces utilization mid-window **without** moving `resets_at` — a usage credit (e.g. weekly 55% → 0%).

**A utilization drop is therefore NOT a reset signal and must never split a window.** Drops are recorded as `UsageEvent(kind: .credit)` with `at`, `from`, `to` and `fromTimestamp` (the origin sample's time; `nil` in files written before it existed). `fromTimestamp` lets straddle detection compare two stored timestamps instead of matching an event to a sample by value.

Two consequences that are easy to get wrong:
- **Server lag**: at a real reset the API often drops utilization one poll *before* it advances `resets_at`, which looks exactly like a credit. The boundary partition discards an event whose from/to straddle a **proven** boundary. On a **derived** boundary it keeps the event (assigned by `at`), because discarding on a guess is the worse error.
- **Projection**: measure the implied rate from the most recent credit, not the window start. Otherwise the numerator resets while the denominator does not, and the app stops warning exactly when the user starts spending a fresh credit.

### On-disk format (v3)

`magic "CMH2" | version | metaLen | metadata JSON | sampleCount | crc32 | payload`, little-endian, written atomically. Payload: first sample absolute (uvarint epoch + uvarint utilization), then zigzag-varint deltas. Metadata JSON carries `id`, `resetsAt`, `firstObservedAt`, `events`.

48% smaller and ~150× faster than the previous lzma'd JSON, with no compression library on the read path. Dropping compression also dropped lzma's implicit integrity check, so the **CRC32 covers everything except the magic and the CRC field itself**. v2 left `version` and `sampleCount` outside it, so one flipped bit shrinking `sampleCount` silently discarded real samples. The decoder also requires the payload to be fully consumed and caps varint length.

The reader accepts v3, v2, and legacy v1 (bare `[[epoch,util],…]` JSON, optionally lzma'd); the writer emits only v3. **Corrupt files are expected input, not programmer error**: decode failures return typed errors and never trap, and an undecodable file is quarantined (renamed with a timestamped `corrupt_` prefix), never deleted.

**Plateau-collapse** applies to archives only, never the live instance: runs of equal utilization collapse to first+last, and **never across a gap ≥ `gapThreshold`**. The app was not running then, and the graph must show a discontinuity rather than interpolate. Measured reduction on real archives: 72–87%.

### Retention

Calendar-based (`Calendar.date(byAdding: .year, value: -n)`, never a seconds-per-year approximation), default **2 years**, configurable 1–99 by a stepper in Preferences. Lowering it deletes history, so it requires a confirmation stating the exact count, computed and executed against **one** captured instant. Pruning runs at launch and daily, not only after a boundary. An archive whose filename cannot be parsed is never deleted; neither is a quarantined file whose name carries no timestamp.

`HistoryHealth` on `MonitorState` surfaces save failures and quarantined-file counts in the menu. Write failures recover silently rather than trapping (a full disk or read-only volume is environmental, not a bug), so the status line is the only signal the user gets.

## Token-Efficient Workflow

**Opus = brain, Sonnet agents = hands.** The main conversation runs on Opus: analysis, architecture, decisions, review, user communication. File reading, code search and implementation go to Sonnet agents (`model: "sonnet"`).

### Opus-only (never delegate)

- **Sensitive/core files** — files where every word matters (prompts, configs, API contracts)
- **Architecture decisions** — structure, abstractions, API design
- **Code review** — mandatory for every agent change, no exceptions

### Agents never execute commands

**HARD RULE**: agents never run any command — not `./test.sh`, not `./install.sh`, nothing. They write code, analyze and review only. The orchestrator runs all builds and tests and reports results back to the agent if iteration is needed. State this prohibition explicitly in every agent prompt.

Agents cannot verify their own work empirically, so verification belongs to the orchestrator, together with mandatory review-agent rounds using named hypotheses (an agent's own quality claim is not evidence).

### Agent instruction rules

Sonnet agents do NOT see CLAUDE.md. Every prompt MUST include:

1. **Relevant project rules** — copy-paste the applicable CLAUDE.md rules
2. **Explicit file paths** — never "find the file"; if unknown, run an Explore agent first
3. **Existing patterns** — describe or quote the pattern to follow
4. **Acceptance criteria** — what "done" looks like
5. **What NOT to do** — no extra features, no refactoring surrounding code, no comments on unchanged code, no speculative abstractions, no impossible-case error handling
6. **Verification step** — re-read the modified file and verify correctness

### Workflow

```
1. Explore agent (Sonnet) → reads code, returns summary
2. Opus analyzes → decides what and how
3. Implementation agent (Sonnet) → precise instructions + rules → makes changes
4. Opus reviews diff → approves or corrects
```

Step 4 is mandatory. Steps 1–2 can be skipped for simple changes. Step 3 can parallelize (e.g. backend + frontend).
