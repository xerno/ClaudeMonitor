import AppKit
import Foundation

extension DataCoordinator {
    func refresh(now: Date = Date()) async {
        if Constants.Demo.isActive {
            return await refreshDemo()
        }
        if !pathMonitor.isSatisfied {
            scheduler.recordStatusFailure(category: .transient)
            scheduler.recordUsageFailure(category: .transient)
            // Don't stamp lastFailedAt for offline ticks: the "Last update failed at HH:MM" row
            // would advance every tick despite no real attempt being made. Stale banner already
            // signals the problem at threshold.
            commitPollState(now: now, schedulerInterval: scheduler.nextPollInterval(usage: currentUsage))
            onUpdate?()
            return
        }
        let previousAnalyses = windowAnalyses
        let generationAtStart = usageHistory.generation
        async let statusResult: Void = refreshStatus()
        async let usageOutcome: UsageFetchOutcome = refreshUsage()
        _ = await statusResult
        let outcome = await usageOutcome
        guard !Task.isCancelled else { return }
        if scheduler.statusState.consecutiveFailures == 0 && scheduler.usageState.consecutiveFailures == 0 {
            lastFailedAt = nil
        }
        // Only a FRESH, complete usage response may drive history recording, boundary
        // detection, and missing-window archiving — never a stale `currentUsage` retained
        // from a previous successful cycle (see `refreshUsage()`'s doc comment). The UI may
        // still display stale data (via `monitorState`/`currentUsage`), but stale data must
        // never be re-recorded as if it were a fresh, confirmed-unchanged observation.
        if case .fresh(let newUsage) = outcome {
            guard isRefreshCurrent(generation: generationAtStart) else { return }
            let genuineBoundaryKeys = await detectAndStoreResets(current: newUsage.entries, at: now)
            guard isRefreshCurrent(generation: generationAtStart) else { return }
            usageHistory.record(entries: newUsage.entries, at: now)
            await usageHistory.archiveMissingWindows(
                currentIdentities: Set(newUsage.entries.map { $0.storageIdentity }),
                at: now
            )
            guard isRefreshCurrent(generation: generationAtStart) else { return }
            await usageHistory.save()
            guard isRefreshCurrent(generation: generationAtStart) else { return }
            windowAnalyses = newUsage.entries.map { entry in
                UsageHistory.analyze(
                    entry: entry,
                    samples: usageHistory.samples(for: entry),
                    events: usageHistory.storage[entry.storageIdentity]?.events ?? [],
                    now: now
                )
            }
            if Formatting.detectCriticalReset(previousAnalyses: previousAnalyses, genuineBoundaryKeys: genuineBoundaryKeys) {
                onCriticalReset?()
            }
        }
        scheduler.adjustPollingRate(windowAnalyses: windowAnalyses, systemIdleTime: systemIdleProvider.idleTime())
        commitPollState(now: Date(), schedulerInterval: scheduler.nextPollInterval(usage: currentUsage))
        onUpdate?()
    }

    private func isRefreshCurrent(generation: Int) -> Bool {
        usageHistory.generation == generation
    }

    func refreshDemo() async {
        let scenario = Constants.Demo.rotationOrder[demoRotationIndex]
        demoRotationIndex = (demoRotationIndex + 1) % Constants.Demo.rotationOrder.count
        let frame = DemoData.scenario(scenario)
        demoFrame = frame
        currentUsage = frame.usage
        currentStatus = frame.status
        usageError = nil
        statusError = nil
        let now = Date()
        windowAnalyses = frame.usage.entries.map { entry in
            UsageHistory.analyze(entry: entry, samples: frame.samples[entry.key] ?? [], now: now)
        }
        commitPollState(now: now, schedulerInterval: Constants.Demo.rotationInterval)
        currentPollInterval = frame.pollInterval
        onUpdate?()
        if frame.isCriticalReset {
            onCriticalReset?()
        }
    }

    func refreshStatus() async {
        guard !Task.isCancelled else { return }
        do {
            currentStatus = try await statusService.fetch()
            statusError = nil
            scheduler.recordStatusSuccess()
        } catch {
            if Task.isCancelled { return }
            scheduler.recordStatusFailure(category: RetryCategory(classifying: error))
            handleServiceFailure(error: error, consecutiveFailures: scheduler.statusState.consecutiveFailures, errorStorage: &statusError)
        }
    }

    /// Whether a `refreshUsage()` cycle produced a response fresh enough to drive history
    /// recording (`.fresh`), or is merely retaining a previously-fetched value for display
    /// while this cycle's fetch didn't happen or failed (`.stale`). `currentUsage` alone can't
    /// express this distinction — on any non-auth failure it's left holding the PREVIOUS
    /// successful value, so `if let newUsage = currentUsage` cannot tell a failed cycle apart
    /// from a fresh success. Callers of `refreshUsage()` must use this return value (not
    /// `currentUsage`) to decide whether to feed a cycle into `UsageHistory.record`,
    /// `archiveMissingWindows`, or boundary detection — recording a stale value would
    /// fabricate a "confirmed unchanged at now" sample that never happened, destroying gap
    /// detection and violating `archiveMissingWindows`' documented precondition.
    enum UsageFetchOutcome: Sendable {
        case fresh(UsageResponse)
        case stale
    }

    func refreshUsage() async -> UsageFetchOutcome {
        guard !Task.isCancelled else { return .stale }
        guard let credentials = loadedCredentials else {
            usageError = String(localized: "credentials.configure", bundle: .module)
            return .stale
        }
        // Captured BEFORE the fetch's suspension point. `UsageHistory.generation` is bumped by
        // exactly the two operations that replace what `storage` represents — `switchOrganization`
        // and `clearAll` — and both are synchronous and eager, so either can complete while this
        // fetch is suspended.
        //
        // Without this guard the response of a fetch issued for organization A, arriving after the
        // user switched to organization B, was treated as a fully fresh observation of B: it set
        // `currentUsage`, then `refresh()` fed it through `record()`, `archiveMissingWindows()` and
        // `save()`, writing A's utilization numbers into B's in-memory storage AND persisting them
        // to B's directory on disk. That is silent, permanent cross-organization corruption of the
        // user's history, and it violates the project's core invariant that a sample belongs to the
        // instance it was recorded into. The same applies to `clearAll()`: an in-flight response
        // landing afterwards would repopulate history the user had just explicitly erased.
        //
        // Discarding as `.stale` is deliberately total — no `currentUsage`, no scheduler success,
        // no history write. There is nothing to salvage: the data is correct for an organization
        // that is no longer selected. The org switch triggers its own poll, so the current
        // organization's data arrives on that cycle.
        let generationAtFetch = usageHistory.generation
        do {
            let response = try await usageService.fetch(organizationId: credentials.orgId, cookieString: credentials.cookie)
            guard usageHistory.generation == generationAtFetch else { return .stale }
            currentUsage = response
            usageError = nil
            scheduler.recordUsageSuccess()
            return .fresh(response)
        } catch {
            if Task.isCancelled { return .stale }
            let category = RetryCategory(classifying: error)
            scheduler.recordUsageFailure(category: category)
            handleServiceFailure(error: error, consecutiveFailures: scheduler.usageState.consecutiveFailures, errorStorage: &usageError)
            if category == .authFailure {
                currentUsage = nil
                windowAnalyses = []
            }
            return .stale
        }
    }

    private func handleServiceFailure(error: Error, consecutiveFailures: Int, errorStorage: inout String?) {
        lastFailedAt = Date()
        if consecutiveFailures >= Constants.Retry.failureThreshold {
            errorStorage = error.localizedDescription
        }
    }

    /// Runs `UsageHistory`'s boundary detection per entry and returns the keys of entries
    /// that had a genuine new-window boundary this cycle — the single authoritative signal
    /// consumed both for archive pruning and for `Formatting.detectCriticalReset` (Task 5:
    /// critical-reset detection no longer re-derives a boundary from raw timestamps).
    @discardableResult
    @MainActor func detectAndStoreResets(current: [WindowEntry], at now: Date) async -> Set<String> {
        var genuineBoundaryKeys: Set<String> = []
        for entry in current {
            let didReset = await usageHistory.detectAndHandleReset(
                entry: entry,
                newResetsAt: entry.window.resetsAt,
                at: now
            )
            if didReset {
                genuineBoundaryKeys.insert(entry.key)
            }
        }
        if !genuineBoundaryKeys.isEmpty {
            await usageHistory.pruneArchives()
        }
        return genuineBoundaryKeys
    }
}
