import Foundation

extension DataCoordinator {
    func startPolling() {
        pathMonitor.start()
        pollTask?.cancel()
        pollTask = spawnPollTask()
    }

    func restartPolling() {
        pollTask?.cancel()
        reloadCredentials()
        scheduler.reset()
        startPolling()
    }

    func switchToProfile(id: String) {
        guard profileStore.activeId != id, profileStore.setActive(id: id) else { return }
        restartPolling()
    }

    // Builds the infinitely-looping poll task with only a *weak* capture of self at the
    // Task-closure level. `pollLoop()` used to be an ordinary instance method called as
    // `self.pollLoop()`; because that call binds `self` strongly for the entire (never
    // returning, except on cancellation) execution of the method, wrapping the outer Task
    // in `[weak self]` did nothing to break the `self -> pollTask -> closure -> self` cycle.
    //
    // Here, every iteration confines its strong reference to `self` to the `do` block below —
    // a `do` without `catch` is purely a scope in Swift, and a local's lifetime ends, by
    // language guarantee (not merely as an ARC optimization that may or may not fire), at the
    // closing brace of the scope it was declared in. So the strong `self` bound by `guard let
    // self` is released right there, *before* either sleep call below ever runs — nothing
    // used while sleeping (`cycle.delay`, `cycle.isAwayMode`, `cycle.idleProvider`) is, or
    // refers back to, the coordinator. That means the coordinator is free to deallocate at
    // any point during even a long away-mode wait, not merely once per outer cycle: the two
    // sleep branches below never touch `self` again at all (only the plain values/existential
    // captured into `cycle`), so the very next time this loop needs `self` — the top of the
    // next outer iteration — a gone coordinator is detected via the weak capture and the task
    // returns for good.
    func spawnPollTask() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                // Declared outside the `do` block so its value survives past it, but only ever
                // assigned along the path that falls through to the closing brace below — the
                // only other path (`guard let self else`) returns from this whole Task closure,
                // so definite-initialization is satisfied without `cycle` needing to be Optional.
                let cycle: (delay: TimeInterval, isAwayMode: Bool, idleProvider: any SystemIdleProviding)
                do {
                    guard let self else { return }
                    await self.refresh()
                    guard !Task.isCancelled else { return }
                    let delay = self.nextPollDate.map { $0.timeIntervalSinceNow } ?? Constants.Polling.baseInterval
                    cycle = (delay, self.scheduler.isAwayMode, self.systemIdleProvider)
                } // `self` goes out of scope here.

                guard cycle.delay > 0 else { continue }

                if cycle.isAwayMode {
                    let deadline = Date().addingTimeInterval(cycle.delay)
                    while !Task.isCancelled {
                        let sleepTime = min(Constants.Polling.heartbeatInterval, deadline.timeIntervalSinceNow)
                        guard sleepTime > 0 else { break }
                        try? await Task.sleep(for: .seconds(sleepTime))
                        if cycle.idleProvider.idleTime() < Constants.Polling.awayThreshold {
                            break
                        }
                    }
                } else {
                    try? await Task.sleep(for: .seconds(cycle.delay))
                }
            }
        }
    }

    func commitPollState(now: Date, schedulerInterval: TimeInterval) {
        lastRefreshed = now
        nextPollDate = now.addingTimeInterval(schedulerInterval)
        currentPollInterval = schedulerInterval
    }
}
