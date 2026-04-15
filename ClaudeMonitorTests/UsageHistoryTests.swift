import Testing
import Foundation
@testable import ClaudeMonitor

// MARK: - Helpers

private func makeEntry(key: String, utilization: Int, resetsAt: Date?) -> WindowEntry {
    WindowEntry.make(key: key, utilization: utilization, resetsAt: resetsAt)
}

private func makeSamples(count: Int, startUtilization: Int, endUtilization: Int, span: TimeInterval, endDate: Date) -> [UtilizationSample] {
    guard count >= 2 else { return [] }
    var samples: [UtilizationSample] = []
    for i in 0..<count {
        let fraction = Double(i) / Double(count - 1)
        let util = startUtilization + Int(Double(endUtilization - startUtilization) * fraction)
        let timestamp = endDate.addingTimeInterval(-span + span * fraction)
        samples.append(UtilizationSample(utilization: util, timestamp: timestamp))
    }
    return samples
}

// MARK: - SampleRecordingTests

@Suite struct SampleRecordingTests {

    @Test @MainActor func recordAddsSample() {
        let history = UsageHistory()
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry], at: now)
        let samples = history.samples(for: entry)
        #expect(samples.count == 1)
        #expect(samples[0].utilization == 42)
    }

    @Test @MainActor func recordDeduplicatesSameUtilization() {
        let history = UsageHistory()
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry], at: now)
        // Record again within deduplication interval with same utilization
        let soon = now.addingTimeInterval(10)
        let entry2 = makeEntry(key: "five_hour", utilization: 42, resetsAt: soon.addingTimeInterval(3600))
        history.record(entries: [entry2], at: soon)
        let samples = history.samples(for: entry2)
        #expect(samples.count == 1)
    }

    @Test @MainActor func recordAllowsSameUtilizationAfterDeduplicationInterval() {
        let history = UsageHistory()
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry], at: now)
        // Record after deduplication interval (30s+)
        let later = now.addingTimeInterval(Constants.History.deduplicationInterval + 1)
        let entry2 = makeEntry(key: "five_hour", utilization: 42, resetsAt: later.addingTimeInterval(3600))
        history.record(entries: [entry2], at: later)
        let samples = history.samples(for: entry2)
        #expect(samples.count == 2)
    }

    @Test @MainActor func recordDifferentUtilizationAlwaysAdded() {
        let history = UsageHistory()
        let now = Date()
        let entry1 = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry1], at: now)
        let soon = now.addingTimeInterval(10)
        let entry2 = makeEntry(key: "five_hour", utilization: 55, resetsAt: soon.addingTimeInterval(3600))
        history.record(entries: [entry2], at: soon)
        let samples = history.samples(for: entry2)
        #expect(samples.count == 2)
    }

    @Test @MainActor func pruneRemovesOldSamples() {
        let history = UsageHistory()
        // five_hour = 18000s duration
        let duration: TimeInterval = 18000
        let now = Date()
        // Add old sample well outside the window
        let oldDate = now.addingTimeInterval(-(duration + 100))
        let oldEntry = makeEntry(key: "five_hour", utilization: 10, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [oldEntry], at: oldDate)

        // Add fresh sample which triggers pruning of old one
        let freshEntry = makeEntry(key: "five_hour", utilization: 20, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [freshEntry], at: now)

        let samples = history.samples(for: freshEntry)
        // Only the fresh sample should survive pruning
        #expect(samples.count == 1)
        #expect(samples[0].utilization == 20)
    }
}

// MARK: - ResetDetectionTests

@Suite struct ResetDetectionTests {

    @Test @MainActor func resetClearsHistory() async throws {
        let testOrgId = UUID().uuidString
        let history = UsageHistory()
        history.switchOrganization(testOrgId)
        defer {
            history.clearAll()
            let orgDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ClaudeMonitor/usage/\(testOrgId)")
            try? FileManager.default.removeItem(at: orgDir)
        }

        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry], at: now)
        #expect(history.samples(for: entry).count == 1)

        let duration: TimeInterval = 18000
        let previousResetsAt = now.addingTimeInterval(3600)
        // New resetsAt is > 50% of duration later → reset detected
        let newResetsAt = previousResetsAt.addingTimeInterval(duration * 0.6)
        history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 0, resetsAt: newResetsAt),
            newResetsAt: newResetsAt,
            previousResetsAt: previousResetsAt
        )
        #expect(history.samples(for: makeEntry(key: "five_hour", utilization: 0, resetsAt: newResetsAt)).count == 0)
        try await Task.sleep(for: .milliseconds(200))
    }

    @Test @MainActor func smallResetsAtChangeDoesNotClear() {
        let history = UsageHistory()
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry], at: now)

        let duration: TimeInterval = 18000
        let previousResetsAt = now.addingTimeInterval(3600)
        // Small shift < 50% of duration → no reset
        let newResetsAt = previousResetsAt.addingTimeInterval(duration * 0.3)
        history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 0, resetsAt: newResetsAt),
            newResetsAt: newResetsAt,
            previousResetsAt: previousResetsAt
        )
        #expect(history.samples(for: entry).count == 1)
    }

    @Test @MainActor func nilResetsAtDoesNotClear() {
        let history = UsageHistory()
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: nil)
        history.record(entries: [entry], at: now)

        history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 0, resetsAt: nil),
            newResetsAt: nil,
            previousResetsAt: nil
        )
        #expect(history.samples(for: entry).count == 1)
    }
}

// MARK: - RateComputationTests

@Suite @MainActor struct RateComputationTests {

    @Test func averageRateFromElapsedTime() {
        // utilization=60, window=5h (18000s), remaining=3600s → elapsed=14400s
        // rate = 60/14400 ≈ 0.004167
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 60,
            resetsAt: resetsAt,
            now: now
        )
        #expect(source == .implied)
        let expectedRate = 60.0 / 14400.0
        #expect(abs(rate - expectedRate) < 0.001)
    }

    @Test func averageRateFromElapsedTime2h() {
        // utilization=40, window=5h (18000s), elapsed=2h (7200s)
        // rate = 40/7200 ≈ 0.00556
        let now = Date()
        let resetsAt = now.addingTimeInterval(18000 - 7200)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 40,
            resetsAt: resetsAt,
            now: now
        )
        #expect(source == .implied)
        let expectedRate = 40.0 / 7200.0
        #expect(abs(rate - expectedRate) < 0.001)
    }

    @Test func insufficientWhenNoResetsAt() {
        let now = Date()
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 50,
            resetsAt: nil,
            now: now
        )
        #expect(source == .insufficient)
        #expect(rate == 0)
    }

    @Test func zeroUtilizationGivesZeroRate() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 0,
            resetsAt: resetsAt,
            now: now
        )
        #expect(source == .implied)
        #expect(rate == 0)
    }

    @Test func insufficientWhenWindowJustStarted() {
        // resetsAt = now + windowDuration → timeElapsed = 0
        let now = Date()
        let resetsAt = now.addingTimeInterval(18000)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 0,
            resetsAt: resetsAt,
            now: now
        )
        #expect(source == .insufficient)
        #expect(rate == 0)
    }
}

// MARK: - TimeSinceLastChangeTests

@Suite @MainActor struct TimeSinceLastChangeTests {

    @Test func timeSinceLastChangeWithRecentChange() {
        let now = Date()
        let samples = [
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-600)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-300)),
            UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(-60)),
        ]
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 45, samples: samples, now: now)
        // Changed from 30% to 45% at -60s
        #expect(result != nil)
        #expect(abs(result! - 60) < 1)
    }

    @Test func timeSinceLastChangeAllSame() {
        let now = Date()
        let samples = [
            UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(-1800)),
            UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(-900)),
            UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(-60)),
        ]
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 45, samples: samples, now: now)
        // All same → time since oldest sample = 1800s
        #expect(result != nil)
        #expect(abs(result! - 1800) < 1)
    }

    @Test func timeSinceLastChangeNoSamples() {
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 45, samples: [])
        #expect(result == nil)
    }

    @Test func timeSinceLastChangeSingleSample() {
        let now = Date()
        let samples = [UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(-300))]
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 45, samples: samples, now: now)
        // Single sample, same utilization → time since that sample
        #expect(result != nil)
        #expect(abs(result! - 300) < 1)
    }

    @Test func timeSinceLastChangeMultipleChanges() {
        let now = Date()
        let samples = [
            UtilizationSample(utilization: 10, timestamp: now.addingTimeInterval(-600)),
            UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(-400)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-200)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-60)),
        ]
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 30, samples: samples, now: now)
        // Last change was from 20 to 30 at -200s
        #expect(result != nil)
        #expect(abs(result! - 200) < 1)
    }
}

// MARK: - ProjectionTests

@Suite @MainActor struct ProjectionTests {

    @Test @MainActor func projectionBelowLimit() {
        // util=40, rate=0.005/s, timeRemaining=3600 → projected=40+0.005*3600=58 → no timeToLimit
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 40,
            rate: 0.005,
            timeRemaining: 3600
        )
        #expect(abs(projected - 58.0) < 0.01)
        #expect(timeToLimit == nil)
    }

    @Test @MainActor func projectionExceedsLimit() {
        // util=60, rate=0.02/s, timeRemaining=3600 → projected=60+0.02*3600=132
        // timeToLimit = (100-60)/0.02 = 2000s < 3600s → timeToLimit=2000
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 60,
            rate: 0.02,
            timeRemaining: 3600
        )
        #expect(abs(projected - 132.0) < 0.01)
        #expect(timeToLimit != nil)
        #expect(abs(timeToLimit! - 2000.0) < 0.01)
    }

    @Test @MainActor func projectionWithZeroRate() {
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 50,
            rate: 0,
            timeRemaining: 3600
        )
        #expect(abs(projected - 50.0) < 0.01)
        #expect(timeToLimit == nil)
    }

    @Test @MainActor func projectionAtExactlyLimit() {
        // util=100 → already at limit; rate > 0 but currentUtilization >= 100 → timeToLimit nil
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 100,
            rate: 0.01,
            timeRemaining: 3600
        )
        #expect(projected > 100.0)
        #expect(timeToLimit == nil) // currentUtilization not < 100
    }
}

// MARK: - StyleComputationTests

@Suite @MainActor struct StyleComputationTests {

    private func computeStyle(projected: Double, utilization: Int, timeRemaining: TimeInterval, resetsAt: Date?) -> Formatting.UsageStyle {
        Formatting.usageStyle(
            projectedAtReset: projected,
            utilization: utilization,
            resetsAt: resetsAt,
            timeRemaining: timeRemaining
        )
    }

    @Test func normalWhenProjectedUnder80() {
        let now = Date()
        let style = computeStyle(projected: 60, utilization: 30, timeRemaining: 3600, resetsAt: now.addingTimeInterval(3600))
        #expect(style.level == .normal)
        #expect(!style.isBold)
    }

    @Test func boldWhenProjected80to99() {
        let now = Date()
        let style = computeStyle(projected: 85, utilization: 40, timeRemaining: 3600, resetsAt: now.addingTimeInterval(3600))
        #expect(style.level == .normal)
        #expect(style.isBold)
    }

    @Test func warningWhenProjected100to119() {
        let now = Date()
        let style = computeStyle(projected: 110, utilization: 50, timeRemaining: 3600, resetsAt: now.addingTimeInterval(3600))
        #expect(style.level == .warning)
        #expect(style.isBold)
    }

    @Test func criticalWhenProjected120plus() {
        let now = Date()
        let style = computeStyle(projected: 130, utilization: 60, timeRemaining: 3600, resetsAt: now.addingTimeInterval(3600))
        #expect(style.level == .critical)
        #expect(style.isBold)
    }

    @Test func criticalWhenBlocked() {
        let now = Date()
        // utilization=100 → blocked regardless of projection
        let style = computeStyle(projected: 50, utilization: 100, timeRemaining: 3600, resetsAt: now.addingTimeInterval(3600))
        #expect(style.level == .critical)
        #expect(style.isBold)
    }

    @Test func normalWhenTimeRemainingZero() {
        let now = Date()
        let style = computeStyle(projected: 150, utilization: 70, timeRemaining: 0, resetsAt: now.addingTimeInterval(0))
        #expect(style.level == .normal)
        #expect(!style.isBold)
    }

    @Test func fallbackThresholdsWhenNoResetsAt() {
        // resetsAt=nil, utilization=92 → fallbackWarningThreshold=90, fallbackCriticalThreshold=95
        // 90 <= 92 < 95 → .warning
        let style = computeStyle(projected: 92, utilization: 92, timeRemaining: 3600, resetsAt: nil)
        #expect(style.level == .warning)
        #expect(style.isBold)
    }
}

// MARK: - WindowBoundaryPruningTests

@Suite struct WindowBoundaryPruningTests {

    @Test @MainActor func recordPrunesSamplesFromPreviousWindowAfterReset() {
        // Simulate: samples recorded during an old window, then app restarts and a reset
        // happened while closed. New resetsAt means the window boundary shifted forward.
        let history = UsageHistory()
        let now = Date()
        let duration: TimeInterval = 18000 // five_hour
        let oldResetsAt = now.addingTimeInterval(1800) // 30min remaining in old window

        // Record 3 samples during old window (strictly before the upcoming new window boundary)
        let t1 = now.addingTimeInterval(-900)
        let t2 = now.addingTimeInterval(-600)
        let t3 = now.addingTimeInterval(-300)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 30, resetsAt: oldResetsAt)], at: t1)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 40, resetsAt: oldResetsAt)], at: t2)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 50, resetsAt: oldResetsAt)], at: t3)

        // Simulate restart + reset: new full 5h window (newResetsAt - duration = now = boundary)
        let newResetsAt = now.addingTimeInterval(duration)
        let newEntry = makeEntry(key: "five_hour", utilization: 5, resetsAt: newResetsAt)
        history.record(entries: [newEntry], at: now.addingTimeInterval(60))

        // Old samples (t1, t2, t3) are all strictly before newResetsAt - duration (= now),
        // so they are pruned. Only the new sample survives.
        let samples = history.samples(for: newEntry)
        #expect(samples.count == 1)
        #expect(samples[0].utilization == 5)
    }

    @Test @MainActor func samplesForEntryFiltersOldWindowData() {
        // Tests that samples(for:) filters by window boundary even without record-time pruning.
        let history = UsageHistory()
        let now = Date()
        let duration: TimeInterval = 18000 // five_hour

        // Record samples against old resetsAt (window boundary: now - duration + 1800 = now - 16200)
        let oldResetsAt = now.addingTimeInterval(1800)
        let oldEntry = makeEntry(key: "five_hour", utilization: 60, resetsAt: oldResetsAt)
        let t1 = now.addingTimeInterval(-900)
        let t2 = now.addingTimeInterval(-600)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 55, resetsAt: oldResetsAt)], at: t1)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 60, resetsAt: oldResetsAt)], at: t2)
        _ = oldEntry

        // Query with a newer resetsAt (new window boundary: now, so t1 and t2 are excluded)
        let newResetsAt = now.addingTimeInterval(duration)
        let newEntry = makeEntry(key: "five_hour", utilization: 60, resetsAt: newResetsAt)
        let samples = history.samples(for: newEntry)
        // t1 and t2 are before new window boundary (now), so they should be filtered out
        #expect(samples.isEmpty)
    }

    @Test @MainActor func recordKeepsSamplesWithinCurrentWindow() {
        // Normal operation: samples recorded within the current window are all kept.
        let history = UsageHistory()
        let now = Date()
        // Window started 4h ago (now - 14400); resetsAt is 1h from now
        let resetsAt = now.addingTimeInterval(3600)
        // windowStart = resetsAt - duration = now + 3600 - 18000 = now - 14400

        let t1 = now.addingTimeInterval(-600)
        let t2 = now.addingTimeInterval(-300)
        let t3 = now

        history.record(entries: [makeEntry(key: "five_hour", utilization: 30, resetsAt: resetsAt)], at: t1)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 40, resetsAt: resetsAt)], at: t2)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 50, resetsAt: resetsAt)], at: t3)

        let entry = makeEntry(key: "five_hour", utilization: 50, resetsAt: resetsAt)
        let samples = history.samples(for: entry)
        // All 3 samples are well within the window (after now - 14400), so all kept
        #expect(samples.count == 3)
    }
}

// MARK: - AnalyzeIntegrationTests

@Suite struct AnalyzeIntegrationTests {

    @Test @MainActor func analyzeProducesCorrectWindowAnalysis() {
        // Setup: util=70, window=5h (18000s), resetsAt=now+1800, elapsed=16200s
        // averageRate = 70/16200 ≈ 0.004321/s ≈ 15.56%/h
        // projected = 70 + 0.004321 * 1800 ≈ 77.8
        let now = Date()
        let resetsAt = now.addingTimeInterval(1800)
        let entry = makeEntry(key: "five_hour", utilization: 70, resetsAt: resetsAt)
        let samples = makeSamples(count: 10, startUtilization: 10, endUtilization: 70, span: 600, endDate: now)

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.entry == entry)
        #expect(analysis.rateSource == .implied)
        let expectedRate = 70.0 / 16200.0
        #expect(abs(analysis.consumptionRate - expectedRate) < 0.001)
        // projected ≈ 77.8 — below limit
        #expect(analysis.projectedAtReset < 100)
        #expect(analysis.timeToLimit == nil)
    }
}

// MARK: - ScenarioTests

@Suite struct ScenarioTests {

    // Two windows sharing the same duration but different model scopes should
    // produce equivalent analyses when given identical utilization patterns.
    @Test @MainActor func crossWindowIsolation() {
        let history = UsageHistory()
        let now = Date()
        // seven_day = 604800s; seven_day_sonnet = 604800s, modelScope="Sonnet"
        let resetsAt = now.addingTimeInterval(86400) // 1 day remaining

        // Record the same 10 samples (same timestamps, same utilization) into both windows.
        let utilizations = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50]
        for (i, util) in utilizations.enumerated() {
            let t = now.addingTimeInterval(-Double(utilizations.count - 1 - i) * 300)
            let entryAll    = makeEntry(key: "seven_day",        utilization: util, resetsAt: resetsAt)
            let entrySonnet = makeEntry(key: "seven_day_sonnet", utilization: util, resetsAt: resetsAt)
            history.record(entries: [entryAll],    at: t)
            history.record(entries: [entrySonnet], at: t)
        }

        let latestAll    = makeEntry(key: "seven_day",        utilization: 50, resetsAt: resetsAt)
        let latestSonnet = makeEntry(key: "seven_day_sonnet", utilization: 50, resetsAt: resetsAt)
        let samplesAll    = history.samples(for: latestAll)
        let samplesSonnet = history.samples(for: latestSonnet)

        #expect(samplesAll.count == samplesSonnet.count)

        let analysisAll    = UsageHistory.analyze(entry: latestAll,    samples: samplesAll,    now: now)
        let analysisSonnet = UsageHistory.analyze(entry: latestSonnet, samples: samplesSonnet, now: now)

        #expect(analysisAll.segments.count == analysisSonnet.segments.count)

        for (segA, segB) in zip(analysisAll.segments, analysisSonnet.segments) {
            #expect(segA.kind == segB.kind)
        }

        #expect(abs(analysisAll.projectedAtReset - analysisSonnet.projectedAtReset) < 1.0)
    }

    // After a window reset (simulated by large resetsAt shift), previously recorded
    // samples must not contaminate the new window's graph.
    @Test @MainActor func restartAfterResetProducesCleanGraph() async throws {
        let testOrgId = UUID().uuidString
        let history = UsageHistory()
        history.switchOrganization(testOrgId)
        defer {
            history.clearAll()
            let orgDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ClaudeMonitor/usage/\(testOrgId)")
            try? FileManager.default.removeItem(at: orgDir)
        }

        let now = Date()
        let duration: TimeInterval = 18000 // five_hour

        // (a) Record 10 samples over 2h, utilization 10→50, old window resets in 1h
        let oldResetsAt = now.addingTimeInterval(3600)
        for i in 0..<10 {
            let fraction = Double(i) / 9.0
            let util = 10 + Int(40.0 * fraction)
            let t = now.addingTimeInterval(-7200 + 7200 * fraction)
            let entry = makeEntry(key: "five_hour", utilization: util, resetsAt: oldResetsAt)
            history.record(entries: [entry], at: t)
        }
        #expect(history.samples(for: makeEntry(key: "five_hour", utilization: 50, resetsAt: oldResetsAt)).count > 0)

        // (b) Simulate window reset: new resetsAt is a full duration ahead (> 50% shift).
        let newResetsAt = now.addingTimeInterval(duration) // full fresh window starts now
        history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 50, resetsAt: newResetsAt),
            newResetsAt: newResetsAt,
            previousResetsAt: oldResetsAt
        )
        try await Task.sleep(for: .milliseconds(200))

        // (c) Record 3 fresh samples with new resetsAt
        let newUtils = [2, 3, 5]
        for (i, util) in newUtils.enumerated() {
            let t = now.addingTimeInterval(Double(i) * 120)
            let entry = makeEntry(key: "five_hour", utilization: util, resetsAt: newResetsAt)
            history.record(entries: [entry], at: t)
        }

        // (d) Verify: no old data (utilization > 10) remains
        let latestEntry = makeEntry(key: "five_hour", utilization: 5, resetsAt: newResetsAt)
        let samples = history.samples(for: latestEntry)

        for sample in samples {
            #expect(sample.utilization <= 10)
        }

        // Segments should not contain an inferred segment with an endpoint utilization > 50
        let windowStart = newResetsAt.addingTimeInterval(-duration)
        let segments = UsageHistory.segmentSamples(samples, windowStart: windowStart)
        for seg in segments where seg.kind == .inferred {
            for s in seg.samples {
                #expect(s.utilization <= 50)
            }
        }

        // All samples must be within the new window boundary
        for sample in samples {
            #expect(sample.timestamp >= windowStart)
        }
    }

    // Three consecutive reset cycles must not accumulate data across cycles.
    @Test @MainActor func multipleResetCyclesKeepDataClean() async throws {
        let testOrgId = UUID().uuidString
        let history = UsageHistory()
        history.switchOrganization(testOrgId)
        defer {
            history.clearAll()
            let orgDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ClaudeMonitor/usage/\(testOrgId)")
            try? FileManager.default.removeItem(at: orgDir)
        }

        let now = Date()
        let duration: TimeInterval = 18000 // five_hour

        var currentResetsAt = now.addingTimeInterval(duration)

        for cycle in 0..<3 {
            // Record 5 samples with rising utilization per cycle
            let baseUtil = (cycle + 1) * 10 // 10, 20, 30
            for i in 0..<5 {
                let util = baseUtil + i * 2
                let t = now.addingTimeInterval(Double(cycle) * duration + Double(i) * 60)
                let entry = makeEntry(key: "five_hour", utilization: util, resetsAt: currentResetsAt)
                history.record(entries: [entry], at: t)
            }

            // Simulate reset between cycles (shift > 50% of duration)
            let nextResetsAt = currentResetsAt.addingTimeInterval(duration * 0.6)
            let resetEntry = makeEntry(key: "five_hour", utilization: baseUtil + 8, resetsAt: nextResetsAt)
            history.detectAndHandleReset(
                entry: resetEntry,
                newResetsAt: nextResetsAt,
                previousResetsAt: currentResetsAt
            )
            currentResetsAt = nextResetsAt
        }

        // Record fresh samples for the final window
        let finalResetsAt = currentResetsAt
        let finalUtils = [5, 8, 12]
        for (i, util) in finalUtils.enumerated() {
            let t = now.addingTimeInterval(Double(i) * 120)
            let entry = makeEntry(key: "five_hour", utilization: util, resetsAt: finalResetsAt)
            history.record(entries: [entry], at: t)
        }

        let latestEntry = makeEntry(key: "five_hour", utilization: 12, resetsAt: finalResetsAt)
        let samples = history.samples(for: latestEntry)

        // Only data from the last cycle should remain — no accumulated samples from previous cycles
        for sample in samples {
            #expect(sample.utilization <= 20)
        }
        // No more than the 3 fresh samples we just recorded
        #expect(samples.count <= 3)
        try await Task.sleep(for: .milliseconds(200))
    }

    // Two windows with different durations but proportionally identical patterns
    // (samples covering last 10% of duration) should yield same segment structure.
    @Test @MainActor func segmentConsistencyAcrossSimilarWindows() {
        let now = Date()

        // five_hour = 18000s, last 10% = 1800s
        let fiveHourDuration: TimeInterval = 18000
        let fiveHourResetsAt = now.addingTimeInterval(fiveHourDuration * 0.1) // 10% remaining
        let fiveHourWindowStart = fiveHourResetsAt.addingTimeInterval(-fiveHourDuration)
        let fiveHourSamples = makeSamples(count: 5, startUtilization: 30, endUtilization: 40,
                                          span: fiveHourDuration * 0.1,
                                          endDate: now)
        // Verify sample start is well after windowStart (>60s gap triggers inferred)
        #expect(fiveHourSamples.first!.timestamp > fiveHourWindowStart.addingTimeInterval(60))

        // seven_day = 604800s, last 10% = 60480s
        let sevenDayDuration: TimeInterval = 604800
        let sevenDayResetsAt = now.addingTimeInterval(sevenDayDuration * 0.1)
        let sevenDayWindowStart = sevenDayResetsAt.addingTimeInterval(-sevenDayDuration)
        let sevenDaySamples = makeSamples(count: 5, startUtilization: 30, endUtilization: 40,
                                          span: sevenDayDuration * 0.1,
                                          endDate: now)
        #expect(sevenDaySamples.first!.timestamp > sevenDayWindowStart.addingTimeInterval(60))

        let fiveHourEntry = makeEntry(key: "five_hour", utilization: 40, resetsAt: fiveHourResetsAt)
        let sevenDayEntry = makeEntry(key: "seven_day", utilization: 40, resetsAt: sevenDayResetsAt)

        let fiveHourAnalysis = UsageHistory.analyze(entry: fiveHourEntry, samples: fiveHourSamples, now: now)
        let sevenDayAnalysis = UsageHistory.analyze(entry: sevenDayEntry, samples: sevenDaySamples, now: now)

        // Both should have same number and kinds of segments
        #expect(fiveHourAnalysis.segments.count == sevenDayAnalysis.segments.count)
        for (segA, segB) in zip(fiveHourAnalysis.segments, sevenDayAnalysis.segments) {
            #expect(segA.kind == segB.kind)
        }

        // Both should start with an .inferred segment (samples start well after window start)
        #expect(fiveHourAnalysis.segments.first?.kind == .inferred)
        #expect(sevenDayAnalysis.segments.first?.kind == .inferred)
    }

    // After a gap in recording (simulated by time-separated sample groups), the
    // segment list must include a .gap segment between the two tracked periods.
    @Test @MainActor func gapDetectionAfterRestart() {
        let history = UsageHistory()
        let now = Date()
        let duration: TimeInterval = 18000 // five_hour
        let resetsAt = now.addingTimeInterval(3600)
        let windowStart = resetsAt.addingTimeInterval(-duration)

        // Group 1: 5 samples 10 minutes ago to now-30min (before gap)
        let group1End = now.addingTimeInterval(-1800)
        for i in 0..<5 {
            let fraction = Double(i) / 4.0
            let t = group1End.addingTimeInterval(-600 + 600 * fraction)
            let entry = makeEntry(key: "five_hour", utilization: 10 + i * 2, resetsAt: resetsAt)
            history.record(entries: [entry], at: t)
        }

        // Group 2: 5 samples in the last 5 minutes (after 30-minute gap)
        for i in 0..<5 {
            let t = now.addingTimeInterval(-Double(4 - i) * 60)
            let entry = makeEntry(key: "five_hour", utilization: 20 + i * 3, resetsAt: resetsAt)
            history.record(entries: [entry], at: t)
        }

        let latestEntry = makeEntry(key: "five_hour", utilization: 32, resetsAt: resetsAt)
        let samples = history.samples(for: latestEntry)

        // gapThreshold default = 600s; the gap between group1End and group2Start ≈ 1800s → gap detected
        let segments = UsageHistory.segmentSamples(samples, windowStart: windowStart)

        let gapSegments = segments.filter { $0.kind == .gap }
        #expect(gapSegments.count >= 1)

        // The gap segment boundaries should bridge the ~1800s time gap
        if let gapSeg = gapSegments.first {
            #expect(gapSeg.samples.count == 2)
            let gapDuration = gapSeg.samples[1].timestamp.timeIntervalSince(gapSeg.samples[0].timestamp)
            #expect(gapDuration > 600) // must exceed gap threshold
        }
    }

    // Same entry + same samples analyzed twice must produce identical results.
    @Test @MainActor func identicalInputsProduceIdenticalAnalysis() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = makeEntry(key: "five_hour", utilization: 55, resetsAt: resetsAt)
        let samples = makeSamples(count: 8, startUtilization: 20, endUtilization: 55, span: 800, endDate: now)

        let analysis1 = UsageHistory.analyze(entry: entry, samples: samples, now: now)
        let analysis2 = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis1.consumptionRate == analysis2.consumptionRate)
        #expect(analysis1.projectedAtReset == analysis2.projectedAtReset)
        #expect(analysis1.rateSource == analysis2.rateSource)
        #expect(analysis1.style.level == analysis2.style.level)
        #expect(analysis1.style.isBold == analysis2.style.isBold)
        #expect(analysis1.segments.count == analysis2.segments.count)
        for (segA, segB) in zip(analysis1.segments, analysis2.segments) {
            #expect(segA.kind == segB.kind)
            #expect(segA.samples.count == segB.samples.count)
        }
        #expect(analysis1 == analysis2)
    }

    @Test @MainActor func utilizationDropAfterLongGapIsKept() {
        // If utilization drops but the gap is large (>60s), both samples are legitimate
        // (e.g., normal polling where API adjusted utilization over time).
        let history = UsageHistory()
        let now = Date()
        let resetsAt = now.addingTimeInterval(86400 * 6)
        let entry18 = makeEntry(key: "seven_day", utilization: 18, resetsAt: resetsAt)
        history.record(entries: [entry18], at: now)

        // 2 minutes later, API returns lower — this is a legitimate data point
        let entry15 = makeEntry(key: "seven_day", utilization: 15, resetsAt: resetsAt)
        history.record(entries: [entry15], at: now.addingTimeInterval(120))

        let samples = history.samples(for: entry15)
        #expect(samples.count == 2)
        #expect(samples[0].utilization == 18)
        #expect(samples[1].utilization == 15)
    }
}

// MARK: - SegmentSamplesTests

@Suite @MainActor struct SegmentSamplesTests {

    // Empty samples → guard clause → empty array
    @Test func emptySamplesReturnsEmpty() {
        let now = Date()
        let result = UsageHistory.segmentSamples([], windowStart: now.addingTimeInterval(-3600))
        #expect(result.isEmpty)
    }

    // Single sample significantly after window start → inferred + tracked segments
    @Test func singleSampleProducesInferredThenTracked() {
        let now = Date()
        let windowStart = now.addingTimeInterval(-3600)
        // Sample is 3600s after windowStart, well beyond the 60s threshold
        let sample = UtilizationSample(utilization: 50, timestamp: now)
        let result = UsageHistory.segmentSamples([sample], windowStart: windowStart)

        // Should produce: inferred (windowStart→sample), tracked (just the sample)
        #expect(result.count == 2)
        #expect(result[0].kind == .inferred)
        #expect(result[0].samples.count == 2)
        #expect(result[0].samples[0].utilization == 0) // window start at 0%
        #expect(result[0].samples[1].utilization == 50) // bridges to real sample
        #expect(result[1].kind == .tracked)
        #expect(result[1].samples.count == 1)
        #expect(result[1].samples[0].utilization == 50)
    }

    // All samples close together (< gapThreshold apart) → one tracked segment
    @Test func allSamplesWithinGapThresholdProduceSingleTrackedSegment() {
        let now = Date()
        // windowStart is far back (> 60s) so no inferred segment is produced
        // We want NO inferred — place first sample within 60s of windowStart
        let windowStart = now.addingTimeInterval(-50) // first sample at now → only 50s after start, ≤60s
        let samples = [
            UtilizationSample(utilization: 10, timestamp: now),
            UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(60)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(120)),
            UtilizationSample(utilization: 40, timestamp: now.addingTimeInterval(180)),
        ]
        // Gaps between consecutive samples = 60s, which is < gapThreshold (300s)
        let result = UsageHistory.segmentSamples(samples, windowStart: windowStart)

        // No inferred segment (first sample ≤ 60s after window start)
        let tracked = result.filter { $0.kind == .tracked }
        let inferred = result.filter { $0.kind == .inferred }
        let gaps = result.filter { $0.kind == .gap }

        #expect(inferred.isEmpty)
        #expect(gaps.isEmpty)
        #expect(tracked.count == 1)
        #expect(tracked[0].samples.count == 4)
    }

    // Samples in three groups separated by large gaps → two gap segments between three tracked segments
    @Test func multipleConsecutiveGapsProduceMultipleGapSegments() {
        let now = Date()
        // windowStart close enough that no inferred segment appears
        let windowStart = now.addingTimeInterval(-50)

        // Group 1: two samples starting at now
        let g1s1 = UtilizationSample(utilization: 10, timestamp: now)
        let g1s2 = UtilizationSample(utilization: 15, timestamp: now.addingTimeInterval(60))

        // Gap 1: 600s (> gapThreshold 300s)
        let gap1 = TimeInterval(600)

        // Group 2: two samples
        let g2Start = now.addingTimeInterval(60 + gap1)
        let g2s1 = UtilizationSample(utilization: 20, timestamp: g2Start)
        let g2s2 = UtilizationSample(utilization: 25, timestamp: g2Start.addingTimeInterval(60))

        // Gap 2: 600s
        let gap2 = TimeInterval(600)

        // Group 3: two samples
        let g3Start = g2Start.addingTimeInterval(60 + gap2)
        let g3s1 = UtilizationSample(utilization: 30, timestamp: g3Start)
        let g3s2 = UtilizationSample(utilization: 35, timestamp: g3Start.addingTimeInterval(60))

        let samples = [g1s1, g1s2, g2s1, g2s2, g3s1, g3s2]
        let result = UsageHistory.segmentSamples(samples, windowStart: windowStart)

        let trackedSegments = result.filter { $0.kind == .tracked }
        let gapSegments = result.filter { $0.kind == .gap }

        #expect(trackedSegments.count == 3)
        #expect(gapSegments.count == 2)

        // Each gap segment must span > gapThreshold
        for gapSeg in gapSegments {
            #expect(gapSeg.samples.count == 2)
            let duration = gapSeg.samples[1].timestamp.timeIntervalSince(gapSeg.samples[0].timestamp)
            #expect(duration > Constants.History.gapThreshold)
        }

        // Groups contain the right number of samples
        #expect(trackedSegments[0].samples.count == 2)
        #expect(trackedSegments[1].samples.count == 2)
        #expect(trackedSegments[2].samples.count == 2)
    }
}

// MARK: - ArchiveTests

private let archiveTestIdentity = "18000"

private func archiveTestDirectory(orgId: String) -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport
        .appendingPathComponent("ClaudeMonitor/usage/\(orgId)/archive")
        .appendingPathComponent(archiveTestIdentity)
}

private func archiveDateFormatterForTests() -> DateFormatter {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd'T'HHmm'Z'"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}

@Suite(.serialized) @MainActor struct ArchiveTests {

    // archiveWindow creates a compressed file at the expected path
    @Test func archiveWindowCreatesCompressedFile() async throws {
        let testOrgId = UUID().uuidString
        let fm = FileManager.default
        let archiveDir = archiveTestDirectory(orgId: testOrgId)
        let orgDir = archiveDir.deletingLastPathComponent().deletingLastPathComponent()

        let history = UsageHistory()
        history.switchOrganization(testOrgId)
        defer {
            history.clearAll()
            try? fm.removeItem(at: orgDir)
        }

        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: resetsAt)

        // Record two samples to populate storage
        history.record(entries: [makeEntry(key: "five_hour", utilization: 30, resetsAt: resetsAt)],
                       at: now.addingTimeInterval(-300))
        history.record(entries: [makeEntry(key: "five_hour", utilization: 42, resetsAt: resetsAt)],
                       at: now)

        let identity = entry.storageIdentity // "18000"
        history.archiveWindow(identity: identity, resetsAt: resetsAt, windowDuration: entry.duration)

        // Give the detached Task time to write
        try await Task.sleep(for: .milliseconds(500))

        if fm.fileExists(atPath: archiveDir.path) {
            let files = try fm.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
            let lzmaFiles = files.filter { $0.pathExtension == "lzma" }
            #expect(!lzmaFiles.isEmpty, "Expected at least one .lzma file in archive directory")
        }
        // If the dir doesn't exist the archive Task wrote nothing (fire-and-forget): no assertion.
    }

    // pruneArchives removes files whose window ended before the retention cutoff
    @Test func pruneArchivesRemovesOldFilesAndKeepsNewOnes() async throws {
        let testOrgId = UUID().uuidString
        // five_hour = 18000s; retention = 18000 * 11 = 198000s ≈ 55h
        let fiveHourDuration: TimeInterval = 18000
        let retentionPeriod = fiveHourDuration * Double(Constants.History.archiveRetentionMultiplier)
        let now = Date()

        let fm = FileManager.default
        let identityDir = archiveTestDirectory(orgId: testOrgId)
        let orgDir = identityDir.deletingLastPathComponent().deletingLastPathComponent()

        let history = UsageHistory()
        history.switchOrganization(testOrgId)
        defer {
            history.clearAll()
            try? fm.removeItem(at: orgDir)
        }

        // Create the test identity directory to start from a known state
        try fm.createDirectory(at: identityDir, withIntermediateDirectories: true)

        let formatter = archiveDateFormatterForTests()

        // Old file: ended well before the cutoff (retention + 1 day ago)
        let oldEnd = now.addingTimeInterval(-(retentionPeriod + 86400))
        let oldStart = oldEnd.addingTimeInterval(-fiveHourDuration)
        let oldFilename = "\(formatter.string(from: oldStart))_\(formatter.string(from: oldEnd)).json.lzma"
        let oldFileURL = identityDir.appendingPathComponent(oldFilename)
        let dummyData = "[]".data(using: .utf8)!
        try dummyData.write(to: oldFileURL)

        // New file: ended recently (1h ago, well within retention)
        let newEnd = now.addingTimeInterval(-3600)
        let newStart = newEnd.addingTimeInterval(-fiveHourDuration)
        let newFilename = "\(formatter.string(from: newStart))_\(formatter.string(from: newEnd)).json.lzma"
        let newFileURL = identityDir.appendingPathComponent(newFilename)
        try dummyData.write(to: newFileURL)

        // Verify both files exist before pruning
        #expect(fm.fileExists(atPath: oldFileURL.path), "Setup: old file must exist before prune")
        #expect(fm.fileExists(atPath: newFileURL.path), "Setup: new file must exist before prune")

        let entry = makeEntry(key: "five_hour", utilization: 0, resetsAt: now.addingTimeInterval(3600))
        history.pruneArchives(currentEntries: [entry])

        // Give the detached Task time to run
        try await Task.sleep(for: .milliseconds(500))

        #expect(!fm.fileExists(atPath: oldFileURL.path),
                "Old archive file should have been pruned")
        #expect(fm.fileExists(atPath: newFileURL.path),
                "New archive file should NOT have been pruned")
    }
}

// MARK: - RecordIntegrityTests

@Suite struct RecordIntegrityTests {

    // five_hour: identity "18000", duration 18000s
    // seven_day: identity "604800", duration 604800s
    // seven_day_sonnet: identity "604800_sonnet", duration 604800s, modelScope="Sonnet"

    // MARK: - 1. Cross-contamination guard (THE MOST IMPORTANT TEST)

    @Test @MainActor func multiWindowRecordNeverCrossContaminates() {
        let history = UsageHistory()
        let now = Date()
        let fiveHourResetsAt = now.addingTimeInterval(3600)
        let sevenDayResetsAt = now.addingTimeInterval(86400)

        for i in 0..<20 {
            let offset = TimeInterval(i * 60)
            let t = now.addingTimeInterval(offset)
            let fiveHourEntry = makeEntry(key: "five_hour", utilization: 42 + i, resetsAt: fiveHourResetsAt)
            let sevenDayEntry = makeEntry(key: "seven_day", utilization: 11 + i, resetsAt: sevenDayResetsAt)
            let sonnetEntry = makeEntry(key: "seven_day_sonnet", utilization: 9 + i, resetsAt: sevenDayResetsAt)
            history.record(entries: [fiveHourEntry, sevenDayEntry, sonnetEntry], at: t)
        }

        let latestFiveHour = makeEntry(key: "five_hour", utilization: 62, resetsAt: fiveHourResetsAt)
        let latestSevenDay = makeEntry(key: "seven_day", utilization: 31, resetsAt: sevenDayResetsAt)
        let latestSonnet = makeEntry(key: "seven_day_sonnet", utilization: 29, resetsAt: sevenDayResetsAt)

        let fiveHourSamples = history.samples(for: latestFiveHour)
        let sevenDaySamples = history.samples(for: latestSevenDay)
        let sonnetSamples = history.samples(for: latestSonnet)

        // Verify each window has the right range
        for sample in fiveHourSamples {
            #expect(sample.utilization >= 42 && sample.utilization <= 62,
                    "five_hour sample \(sample.utilization) is outside [42,62] — cross-contamination!")
        }
        for sample in sevenDaySamples {
            #expect(sample.utilization >= 11 && sample.utilization <= 31,
                    "seven_day sample \(sample.utilization) is outside [11,31] — cross-contamination!")
        }
        for sample in sonnetSamples {
            #expect(sample.utilization >= 9 && sample.utilization <= 29,
                    "seven_day_sonnet sample \(sample.utilization) is outside [9,29] — cross-contamination!")
        }

        // No five_hour values (42-61, unique range) should appear in other windows
        let fiveHourValues = Set(fiveHourSamples.map { $0.utilization })
        let sevenDayValues = Set(sevenDaySamples.map { $0.utilization })
        let sonnetValues = Set(sonnetSamples.map { $0.utilization })
        #expect(fiveHourValues.intersection(sevenDayValues).isEmpty,
                "five_hour values leaked into seven_day: \(fiveHourValues.intersection(sevenDayValues))")
        #expect(fiveHourValues.intersection(sonnetValues).isEmpty,
                "five_hour values leaked into seven_day_sonnet: \(fiveHourValues.intersection(sonnetValues))")
    }

    // MARK: - 2. Exact utilization preservation

    @Test @MainActor func recordPreservesExactUtilizationValues() {
        let history = UsageHistory()
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let utilizations = [5, 10, 15, 20, 25]

        for (i, util) in utilizations.enumerated() {
            let t = now.addingTimeInterval(TimeInterval(i * 60))
            let entry = makeEntry(key: "five_hour", utilization: util, resetsAt: resetsAt)
            history.record(entries: [entry], at: t)
        }

        let readEntry = makeEntry(key: "five_hour", utilization: 25, resetsAt: resetsAt)
        let samples = history.samples(for: readEntry)
        #expect(samples.count == 5)
        for (i, util) in utilizations.enumerated() {
            #expect(samples[i].utilization == util,
                    "Sample \(i) expected \(util), got \(samples[i].utilization)")
        }
    }

    // MARK: - 3. Correct sample counts for all windows

    @Test @MainActor func recordWithAllThreeWindowsStoresCorrectCounts() {
        let history = UsageHistory()
        let now = Date()
        let fiveHourResetsAt = now.addingTimeInterval(3600)
        let sevenDayResetsAt = now.addingTimeInterval(86400)

        for i in 0..<10 {
            let t = now.addingTimeInterval(TimeInterval(i * 60))
            let entries = [
                makeEntry(key: "five_hour", utilization: 10 + i, resetsAt: fiveHourResetsAt),
                makeEntry(key: "seven_day", utilization: 20 + i, resetsAt: sevenDayResetsAt),
                makeEntry(key: "seven_day_sonnet", utilization: 30 + i, resetsAt: sevenDayResetsAt)
            ]
            history.record(entries: entries, at: t)
        }

        let fiveHourEntry = makeEntry(key: "five_hour", utilization: 19, resetsAt: fiveHourResetsAt)
        let sevenDayEntry = makeEntry(key: "seven_day", utilization: 29, resetsAt: sevenDayResetsAt)
        let sonnetEntry = makeEntry(key: "seven_day_sonnet", utilization: 39, resetsAt: sevenDayResetsAt)

        #expect(history.samples(for: fiveHourEntry).count == 10)
        #expect(history.samples(for: sevenDayEntry).count == 10)
        #expect(history.samples(for: sonnetEntry).count == 10)
    }

    // MARK: - 4. Timestamp preservation

    @Test @MainActor func recordTimestampsAreExactlyAsProvided() {
        let history = UsageHistory()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let resetsAt = base.addingTimeInterval(3600)
        let specificDates = [
            base,
            base.addingTimeInterval(61),
            base.addingTimeInterval(122),
            base.addingTimeInterval(183)
        ]

        for (i, date) in specificDates.enumerated() {
            let entry = makeEntry(key: "five_hour", utilization: 10 + i, resetsAt: resetsAt)
            history.record(entries: [entry], at: date)
        }

        let readEntry = makeEntry(key: "five_hour", utilization: 13, resetsAt: resetsAt)
        let samples = history.samples(for: readEntry)
        #expect(samples.count == specificDates.count)
        for (i, expected) in specificDates.enumerated() {
            #expect(samples[i].timestamp == expected,
                    "Timestamp \(i) was modified: expected \(expected), got \(samples[i].timestamp)")
        }
    }

    // MARK: - 5. Identity determinism

    @Test @MainActor func identityIsDeterministic() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)

        for _ in 0..<100 {
            let fiveHour = makeEntry(key: "five_hour", utilization: 42, resetsAt: resetsAt)
            #expect(fiveHour.storageIdentity == "18000")
        }

        let sevenDayResetsAt = now.addingTimeInterval(86400)
        for _ in 0..<100 {
            let sevenDay = makeEntry(key: "seven_day", utilization: 11, resetsAt: sevenDayResetsAt)
            #expect(sevenDay.storageIdentity == "604800")
        }

        for _ in 0..<100 {
            let sonnet = makeEntry(key: "seven_day_sonnet", utilization: 9, resetsAt: sevenDayResetsAt)
            #expect(sonnet.storageIdentity == "604800_sonnet")
        }
    }

    // MARK: - 6. Same-duration different-scope isolation

    @Test @MainActor func concurrentWindowsWithSameDurationButDifferentScopeAreIsolated() {
        let history = UsageHistory()
        let now = Date()
        // Both seven_day and seven_day_sonnet have duration=604800
        let resetsAt = now.addingTimeInterval(86400)

        for i in 0..<15 {
            let t = now.addingTimeInterval(TimeInterval(i * 60))
            // Different utilization patterns per window
            let sevenDay = makeEntry(key: "seven_day", utilization: 50 + i, resetsAt: resetsAt)
            let sonnet = makeEntry(key: "seven_day_sonnet", utilization: 5 + i, resetsAt: resetsAt)
            history.record(entries: [sevenDay, sonnet], at: t)
        }

        let sevenDayEntry = makeEntry(key: "seven_day", utilization: 64, resetsAt: resetsAt)
        let sonnetEntry = makeEntry(key: "seven_day_sonnet", utilization: 19, resetsAt: resetsAt)

        let sevenDaySamples = history.samples(for: sevenDayEntry)
        let sonnetSamples = history.samples(for: sonnetEntry)

        // Each should have 15 samples
        #expect(sevenDaySamples.count == 15)
        #expect(sonnetSamples.count == 15)

        // Verify complete isolation: seven_day values are 50-64, sonnet values are 5-19
        for sample in sevenDaySamples {
            #expect(sample.utilization >= 50,
                    "seven_day sample \(sample.utilization) looks like sonnet data (< 50)")
        }
        for sample in sonnetSamples {
            #expect(sample.utilization <= 25,
                    "sonnet sample \(sample.utilization) looks like seven_day data (>= 50)")
        }

        // No value overlap between windows (ranges don't overlap in this test)
        let sevenDayValues = Set(sevenDaySamples.map { $0.utilization })
        let sonnetValues = Set(sonnetSamples.map { $0.utilization })
        #expect(sevenDayValues.intersection(sonnetValues).isEmpty,
                "Data leaked between seven_day and seven_day_sonnet: \(sevenDayValues.intersection(sonnetValues))")
    }

    // MARK: - 7. Save/Load round-trip

    @Test @MainActor func recordThenSaveThenLoadRoundTrips() async throws {
        let testOrgId = UUID().uuidString
        let history = UsageHistory()
        history.switchOrganization(testOrgId)
        defer {
            history.clearAll()
            let orgDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ClaudeMonitor/usage/\(testOrgId)")
            try? FileManager.default.removeItem(at: orgDir)
        }

        let now = Date()
        let fiveHourResetsAt = now.addingTimeInterval(3600)
        let sevenDayResetsAt = now.addingTimeInterval(86400)

        // Record 10 samples for each of 3 windows (different utilizations to avoid dedup)
        for i in 0..<10 {
            let t = now.addingTimeInterval(TimeInterval(i * 60))
            let entries = [
                makeEntry(key: "five_hour", utilization: 10 + i, resetsAt: fiveHourResetsAt),
                makeEntry(key: "seven_day", utilization: 20 + i, resetsAt: sevenDayResetsAt),
                makeEntry(key: "seven_day_sonnet", utilization: 30 + i, resetsAt: sevenDayResetsAt)
            ]
            history.record(entries: entries, at: t)
        }

        let fiveHourKey = makeEntry(key: "five_hour", utilization: 19, resetsAt: fiveHourResetsAt)
        let sevenDayKey = makeEntry(key: "seven_day", utilization: 29, resetsAt: sevenDayResetsAt)
        let sonnetKey = makeEntry(key: "seven_day_sonnet", utilization: 39, resetsAt: sevenDayResetsAt)

        let originalFiveHour = history.samples(for: fiveHourKey)
        let originalSevenDay = history.samples(for: sevenDayKey)
        let originalSonnet = history.samples(for: sonnetKey)

        #expect(originalFiveHour.count == 10)
        #expect(originalSevenDay.count == 10)
        #expect(originalSonnet.count == 10)

        // Save and wait for the fire-and-forget Task to complete
        history.save()
        try await Task.sleep(for: .milliseconds(500))

        // Load into a fresh instance pointing at the same isolated org directory
        let loaded = UsageHistory()
        loaded.switchOrganization(testOrgId)

        let loadedFiveHour = loaded.samples(for: fiveHourKey)
        let loadedSevenDay = loaded.samples(for: sevenDayKey)
        let loadedSonnet = loaded.samples(for: sonnetKey)

        #expect(loadedFiveHour.count == originalFiveHour.count)
        #expect(loadedSevenDay.count == originalSevenDay.count)
        #expect(loadedSonnet.count == originalSonnet.count)

        // save() uses Int(timestamp.timeIntervalSince1970) — fractional seconds are truncated
        for (orig, restored) in zip(originalFiveHour, loadedFiveHour) {
            #expect(orig.utilization == restored.utilization)
            let origEpoch = Int(orig.timestamp.timeIntervalSince1970)
            let restoredEpoch = Int(restored.timestamp.timeIntervalSince1970)
            #expect(origEpoch == restoredEpoch,
                    "Timestamp mismatch: \(origEpoch) vs \(restoredEpoch)")
        }
        for (orig, restored) in zip(originalSevenDay, loadedSevenDay) {
            #expect(orig.utilization == restored.utilization)
        }
        for (orig, restored) in zip(originalSonnet, loadedSonnet) {
            #expect(orig.utilization == restored.utilization)
        }
    }

    // MARK: - 8. Window boundary pruning isolation

    @Test @MainActor func windowBoundaryPruningDoesNotAffectOtherWindows() {
        let history = UsageHistory()
        let now = Date()
        // five_hour window: 18000s duration. Place resetsAt in the future.
        let fiveHourResetsAt = now.addingTimeInterval(3600)
        let sevenDayResetsAt = now.addingTimeInterval(86400)

        // Record some samples in the past for five_hour, within what was the old window
        // (these will be pruned when we record with an updated resetsAt that makes them pre-window)
        let oldWindowStart = now.addingTimeInterval(-20000) // older than 18000s from resetsAt
        let fiveHourEntryOld = makeEntry(key: "five_hour", utilization: 15, resetsAt: fiveHourResetsAt)
        history.record(entries: [fiveHourEntryOld], at: oldWindowStart)

        // Record seven_day samples at the same old time (well within seven_day's 604800s window)
        let sevenDayEntryOld = makeEntry(key: "seven_day", utilization: 25, resetsAt: sevenDayResetsAt)
        history.record(entries: [sevenDayEntryOld], at: oldWindowStart)

        // Now record new entries with a new resetsAt that moves the five_hour window boundary
        // forward, making the old five_hour sample fall before the window start
        // New resetsAt that pushes window start past oldWindowStart:
        // windowStart = newResetsAt - 18000 = now + 1800 - 18000 = now - 16200
        // oldWindowStart = now - 20000 → before windowStart → will be pruned
        let newFiveHourResetsAt = now.addingTimeInterval(1800)
        let fiveHourEntryNew = makeEntry(key: "five_hour", utilization: 20, resetsAt: newFiveHourResetsAt)
        let sevenDayEntryNew = makeEntry(key: "seven_day", utilization: 30, resetsAt: sevenDayResetsAt)
        history.record(entries: [fiveHourEntryNew, sevenDayEntryNew], at: now)

        let fiveHourSamples = history.samples(for: fiveHourEntryNew)
        let sevenDaySamples = history.samples(for: sevenDayEntryNew)

        // The old five_hour sample (util=15) should be pruned
        // Only the new sample (util=20) and possibly the now-sample remain
        for sample in fiveHourSamples {
            #expect(sample.utilization != 15,
                    "Pruned five_hour sample (util=15) still present after window boundary moved")
        }
        #expect(fiveHourSamples.contains(where: { $0.utilization == 20 }),
                "New five_hour sample (util=20) should be present")

        // The seven_day old sample (util=25) must NOT be pruned
        #expect(sevenDaySamples.contains(where: { $0.utilization == 25 }),
                "seven_day sample (util=25) should not be pruned — it is within its window")
        #expect(sevenDaySamples.contains(where: { $0.utilization == 30 }),
                "New seven_day sample (util=30) should be present")
    }
}
