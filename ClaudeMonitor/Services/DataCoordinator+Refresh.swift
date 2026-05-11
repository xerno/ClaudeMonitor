import AppKit
import Foundation

extension DataCoordinator {
    func refresh() async {
        if Constants.Demo.isActive {
            return await refreshDemo()
        }
        if !pathMonitor.isSatisfied {
            scheduler.recordStatusFailure(category: .transient)
            scheduler.recordUsageFailure(category: .transient)
            // Don't stamp lastFailedAt for offline ticks: the "Last update failed at HH:MM" row
            // would advance every tick despite no real attempt being made. Stale banner already
            // signals the problem at threshold.
            let now = Date()
            commitPollState(now: now, schedulerInterval: scheduler.nextPollInterval(usage: currentUsage))
            onUpdate?()
            return
        }
        let usageBeforeRefresh = currentUsage
        async let statusResult: Void = refreshStatus()
        async let usageResult: Void = refreshUsage()
        _ = await (statusResult, usageResult)
        guard !Task.isCancelled else { return }
        if scheduler.statusState.consecutiveFailures == 0 && scheduler.usageState.consecutiveFailures == 0 {
            lastFailedAt = nil
        }
        if let newUsage = currentUsage {
            let now = Date()
            await detectAndStoreResets(current: newUsage.entries, previous: usageBeforeRefresh?.entries ?? [], at: now)
            usageHistory.record(entries: newUsage.entries, at: now)
            await usageHistory.save()
            windowAnalyses = newUsage.entries.map { entry in
                UsageHistory.analyze(entry: entry, samples: usageHistory.samples(for: entry), now: now)
            }
        }
        scheduler.adjustPollingRate(windowAnalyses: windowAnalyses, systemIdleTime: systemIdleProvider.idleTime())
        let now = Date()
        commitPollState(now: now, schedulerInterval: scheduler.nextPollInterval(usage: currentUsage))
        onUpdate?()
        if let prev = usageBeforeRefresh, let curr = currentUsage,
           Formatting.detectCriticalReset(previous: prev, current: curr) {
            onCriticalReset?()
        }
    }

    func refreshDemo() async {
        let previousUsage = currentUsage
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
        if let prev = previousUsage, let curr = currentUsage,
           Formatting.detectCriticalReset(previous: prev, current: curr) {
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

    func refreshUsage() async {
        guard !Task.isCancelled else { return }
        guard let credentials = loadedCredentials else {
            usageError = String(localized: "credentials.configure", bundle: .module)
            return
        }
        do {
            currentUsage = try await usageService.fetch(organizationId: credentials.orgId, cookieString: credentials.cookie)
            usageError = nil
            scheduler.recordUsageSuccess()
        } catch {
            if Task.isCancelled { return }
            let category = RetryCategory(classifying: error)
            scheduler.recordUsageFailure(category: category)
            handleServiceFailure(error: error, consecutiveFailures: scheduler.usageState.consecutiveFailures, errorStorage: &usageError)
            if category == .authFailure {
                currentUsage = nil
                windowAnalyses = []
            }
        }
    }

    private func handleServiceFailure(error: Error, consecutiveFailures: Int, errorStorage: inout String?) {
        lastFailedAt = Date()
        if consecutiveFailures >= Constants.Retry.failureThreshold {
            errorStorage = error.localizedDescription
        }
    }

    @MainActor func detectAndStoreResets(current: [WindowEntry], previous: [WindowEntry], at now: Date) async {
        let previousByKey = Dictionary(uniqueKeysWithValues: previous.map { ($0.key, $0) })
        var anyReset = false
        for entry in current {
            let previousEntry = previousByKey[entry.key]
            let didReset = await usageHistory.detectAndHandleReset(
                entry: entry,
                newResetsAt: entry.window.resetsAt,
                previousResetsAt: previousEntry?.window.resetsAt
            )
            if didReset {
                anyReset = true
            }
        }
        if anyReset {
            await usageHistory.pruneArchives(currentEntries: current)
        }
    }
}
