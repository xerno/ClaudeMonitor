import Foundation

extension DataCoordinator {
    var monitorState: MonitorState {
        MonitorState(
            usage: UsageSnapshot(
                currentUsage: currentUsage,
                usageError: usageError,
                windowAnalyses: windowAnalyses
            ),
            service: ServiceHealth(
                currentStatus: currentStatus,
                statusError: statusError
            ),
            polling: PollingState(
                isOnline: demoFrame?.isOnline ?? pathMonitor.isSatisfied,
                hasRecentFailure: demoFrame?.hasRecentFailure ?? scheduler.hasRecentFailure,
                lastFailedAt: demoFrame?.lastFailedAt ?? lastFailedAt,
                isAnyServiceStale: demoFrame?.isAnyServiceStale ?? scheduler.isAnyServiceStale,
                currentPollInterval: currentPollInterval,
                isUsageDataExpired: scheduler.isUsageDataExpired
            ),
            lastRefreshed: lastRefreshed,
            hasCredentials: hasCredentials
        )
    }
}
