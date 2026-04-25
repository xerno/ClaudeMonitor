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
            let state = coordinator.monitorState
            StatusBarRenderer.updateIcon(
                button: button,
                status: state.currentStatus,
                hasRefreshWarning: state.isStale
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
        let state = coordinator.monitorState
        if let button = statusItem.button {
            StatusBarRenderer.updateText(
                button: button, usage: state.currentUsage,
                hasCredentials: state.hasCredentials,
                isStale: state.isStale || state.isUsageStale,
                windowAnalyses: state.windowAnalyses
            )
        }
        if isMenuOpen, let menu = statusItem.menu {
            MenuBuilder.refreshTimes(in: menu, cache: usageCache)
            MenuBuilder.refreshGraph(in: menu, analyses: state.windowAnalyses)
            MenuBuilder.refreshControlTimes(
                in: menu,
                lastRefreshed: state.lastRefreshed,
                interval: state.currentPollInterval
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
