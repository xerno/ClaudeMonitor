import Foundation

extension DataCoordinator {
    func startPolling() {
        pathMonitor.start()
        restartLoops()
    }

    func restartPolling() {
        reconcileMonitors()
        statusScheduler.reset()
        for monitor in monitors.values {
            monitor.scheduler.reset()
        }
        restartLoops()
    }

    func stopPolling() {
        statusPollTask?.cancel()
        statusPollTask = nil
        for monitor in monitors.values {
            monitor.stopPolling()
        }
    }

    func switchToProfile(id: String) {
        guard profileStore.activeId != id, profileStore.setActive(id: id) else { return }
        activeMonitor?.startPolling()
    }

    func restartLoops() {
        statusPollTask?.cancel()
        statusPollTask = spawnStatusPollTask()
        for monitor in monitors.values {
            monitor.startPolling()
        }
    }

    private func spawnStatusPollTask() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                let delay: TimeInterval
                do {
                    guard let self else { return }
                    delay = await self.runStatusCycle()
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func runStatusCycle() async -> TimeInterval {
        if Constants.Demo.isActive {
            await refreshDemo()
            return Constants.Demo.rotationInterval
        }
        await refreshStatus()
        guard !Task.isCancelled else { return 0 }
        onUpdate?()
        return statusScheduler.nextPollInterval(usage: nil)
    }
}
