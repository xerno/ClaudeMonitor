import Foundation

extension DataCoordinator {
    func startPolling() {
        pathMonitor.start()
        pollTask?.cancel()
        pollTask = Task { await pollLoop() }
    }

    func restartPolling() {
        pollTask?.cancel()
        reloadCredentials()
        scheduler.reset()
        startPolling()
    }

    func pollLoop() async {
        while !Task.isCancelled {
            await refresh()
            guard !Task.isCancelled else { break }
            let delay = nextPollDate.map { $0.timeIntervalSinceNow } ?? Constants.Polling.baseInterval
            guard delay > 0 else { continue }

            if scheduler.isAwayMode {
                let deadline = Date().addingTimeInterval(delay)
                while Date() < deadline && !Task.isCancelled {
                    let sleepTime = min(Constants.Polling.heartbeatInterval, deadline.timeIntervalSinceNow)
                    guard sleepTime > 0 else { break }
                    try? await Task.sleep(for: .seconds(sleepTime))
                    if systemIdleProvider.idleTime() < Constants.Polling.awayThreshold {
                        break
                    }
                }
            } else {
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func commitPollState(now: Date, schedulerInterval: TimeInterval) {
        lastRefreshed = now
        nextPollDate = now.addingTimeInterval(schedulerInterval)
        currentPollInterval = schedulerInterval
    }
}
