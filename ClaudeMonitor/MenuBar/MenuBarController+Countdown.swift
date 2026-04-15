import AppKit

extension MenuBarController {
    // MARK: - Critical Reset Alert

    func handleCriticalReset() {
        if UserDefaults.standard.bool(forKey: Constants.Preferences.resetSoundEnabled) {
            NSSound(named: .init(Constants.Sounds.criticalReset))?.play()
        }
        animateResetIcon()
    }

    private func animateResetIcon() {
        guard let button = statusItem.button else { return }
        animationTask?.cancel()
        button.image = StatusBarRenderer.makeImage(symbolName: "checkmark.circle.fill", color: .systemGreen)
        animationTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            StatusBarRenderer.updateIcon(
                button: button,
                status: coordinator.currentStatus,
                hasRefreshWarning: coordinator.scheduler.hasRefreshWarning
            )
        }
    }

    // MARK: - Countdown

    var shouldCountdownRun: Bool {
        let isBlocked = Formatting.blockingLimit(coordinator.currentUsage) != nil
        let menuHasResetTimes = isMenuOpen && coordinator.currentUsage != nil
        return isBlocked || menuHasResetTimes
    }

    func updateCountdownState() {
        if shouldCountdownRun {
            startCountdown()
        } else {
            stopCountdown()
        }
    }

    func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task {
            while !Task.isCancelled {
                guard let target = nextWakeTime() else { break }
                let delay = target.timeIntervalSinceNow
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                guard !Task.isCancelled else { break }
                updateCountdownDisplays()
            }
            if !Task.isCancelled,
               let blockedUntil = Formatting.blockingLimit(coordinator.currentUsage),
               blockedUntil.timeIntervalSinceNow <= 0 {
                coordinator.restartPolling()
            }
        }
    }

    func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func updateCountdownDisplays() {
        if let button = statusItem.button {
            StatusBarRenderer.updateText(
                button: button, usage: coordinator.currentUsage,
                hasCredentials: coordinator.hasCredentials,
                isStale: coordinator.scheduler.isUsageStale
            )
        }
        if isMenuOpen, let menu = statusItem.menu {
            if let usage = coordinator.currentUsage {
                MenuBuilder.refreshTimes(in: menu, usage: usage)
            }
            MenuBuilder.refreshGraph(in: menu, analyses: coordinator.monitorState.windowAnalyses)
            MenuBuilder.refreshControlTimes(
                in: menu,
                lastRefreshed: coordinator.lastRefreshed,
                interval: coordinator.currentPollInterval
            )
        }
    }

    private func nextWakeTime() -> Date? {
        var resetTimes: [Date] = []
        if let blockedUntil = Formatting.blockingLimit(coordinator.currentUsage) {
            resetTimes.append(blockedUntil)
        }
        if isMenuOpen, let usage = coordinator.currentUsage {
            resetTimes.append(contentsOf: usage.entries.compactMap(\.window.resetsAt))
        }
        guard !resetTimes.isEmpty else { return nil }
        return Formatting.nextTickTarget(resetTimes: resetTimes, now: Date())
    }
}
