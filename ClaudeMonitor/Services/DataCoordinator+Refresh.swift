import AppKit
import Foundation

extension DataCoordinator {
    func refresh(now: Date = Date()) async {
        if Constants.Demo.isActive {
            return await refreshDemo()
        }
        async let statusResult: Void = refreshStatus()
        await activeMonitor?.refresh(now: now)
        _ = await statusResult
        guard !Task.isCancelled else { return }
        onUpdate?()
    }

    func refreshDemo() async {
        let scenario = Constants.Demo.rotationOrder[demoRotationIndex]
        demoRotationIndex = (demoRotationIndex + 1) % Constants.Demo.rotationOrder.count
        let frame = DemoData.scenario(scenario)
        demoFrame = frame
        currentStatus = frame.status
        statusError = nil
        let now = Date()
        demoWindowAnalyses = frame.usage.entries.map { entry in
            UsageHistory.analyze(entry: entry, samples: frame.samples[entry.key] ?? [], now: now)
        }
        demoRefreshedAt = now
        onUpdate?()
        if frame.isCriticalReset {
            onCriticalReset?()
        }
    }

    func refreshStatus() async {
        guard !Task.isCancelled else { return }
        if !pathMonitor.isSatisfied {
            statusScheduler.recordStatusFailure(category: .transient)
            return
        }
        do {
            currentStatus = try await statusService.fetch()
            statusError = nil
            statusLastFailedAt = nil
            statusScheduler.recordStatusSuccess()
        } catch {
            if Task.isCancelled { return }
            statusScheduler.recordStatusFailure(category: RetryCategory(classifying: error))
            statusLastFailedAt = Date()
            if statusScheduler.statusState.consecutiveFailures >= Constants.Retry.failureThreshold {
                statusError = error.localizedDescription
            }
        }
    }
}
