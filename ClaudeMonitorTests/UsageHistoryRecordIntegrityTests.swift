import Foundation
import Testing
@testable import ClaudeMonitor

@Suite struct RecordIntegrityTests {

    @Test @MainActor func multiWindowRecordNeverCrossContaminates() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
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

        let fiveHourValues = Set(fiveHourSamples.map { $0.utilization })
        let sevenDayValues = Set(sevenDaySamples.map { $0.utilization })
        let sonnetValues = Set(sonnetSamples.map { $0.utilization })
        #expect(fiveHourValues.intersection(sevenDayValues).isEmpty,
                "five_hour values leaked into seven_day: \(fiveHourValues.intersection(sevenDayValues))")
        #expect(fiveHourValues.intersection(sonnetValues).isEmpty,
                "five_hour values leaked into seven_day_sonnet: \(fiveHourValues.intersection(sonnetValues))")
        await fixture.cleanup()
    }

    @Test @MainActor func recordPreservesExactUtilizationValues() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
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
        await fixture.cleanup()
    }

    @Test @MainActor func recordWithAllThreeWindowsStoresCorrectCounts() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
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
        await fixture.cleanup()
    }

    @Test @MainActor func recordTimestampsAreExactlyAsProvided() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
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
        await fixture.cleanup()
    }

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

    @Test @MainActor func concurrentWindowsWithSameDurationButDifferentScopeAreIsolated() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let resetsAt = now.addingTimeInterval(86400)

        for i in 0..<15 {
            let t = now.addingTimeInterval(TimeInterval(i * 60))
            let sevenDay = makeEntry(key: "seven_day", utilization: 50 + i, resetsAt: resetsAt)
            let sonnet = makeEntry(key: "seven_day_sonnet", utilization: 5 + i, resetsAt: resetsAt)
            history.record(entries: [sevenDay, sonnet], at: t)
        }

        let sevenDayEntry = makeEntry(key: "seven_day", utilization: 64, resetsAt: resetsAt)
        let sonnetEntry = makeEntry(key: "seven_day_sonnet", utilization: 19, resetsAt: resetsAt)

        let sevenDaySamples = history.samples(for: sevenDayEntry)
        let sonnetSamples = history.samples(for: sonnetEntry)

        #expect(sevenDaySamples.count == 15)
        #expect(sonnetSamples.count == 15)

        for sample in sevenDaySamples {
            #expect(sample.utilization >= 50,
                    "seven_day sample \(sample.utilization) looks like sonnet data (< 50)")
        }
        for sample in sonnetSamples {
            #expect(sample.utilization <= 25,
                    "sonnet sample \(sample.utilization) looks like seven_day data (>= 50)")
        }

        let sevenDayValues = Set(sevenDaySamples.map { $0.utilization })
        let sonnetValues = Set(sonnetSamples.map { $0.utilization })
        #expect(sevenDayValues.intersection(sonnetValues).isEmpty,
                "Data leaked between seven_day and seven_day_sonnet: \(sevenDayValues.intersection(sonnetValues))")
        await fixture.cleanup()
    }

    @Test @MainActor func recordThenSaveThenLoadRoundTrips() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let testOrgId = UUID().uuidString
        history.switchOrganization(testOrgId)

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

        let fiveHourKey = makeEntry(key: "five_hour", utilization: 19, resetsAt: fiveHourResetsAt)
        let sevenDayKey = makeEntry(key: "seven_day", utilization: 29, resetsAt: sevenDayResetsAt)
        let sonnetKey = makeEntry(key: "seven_day_sonnet", utilization: 39, resetsAt: sevenDayResetsAt)

        let originalFiveHour = history.samples(for: fiveHourKey)
        let originalSevenDay = history.samples(for: sevenDayKey)
        let originalSonnet = history.samples(for: sonnetKey)

        #expect(originalFiveHour.count == 10)
        #expect(originalSevenDay.count == 10)
        #expect(originalSonnet.count == 10)

        await history.save()

        let loaded = UsageHistory(baseDirectory: fixture.baseDirectory)
        loaded.switchOrganization(testOrgId)

        let loadedFiveHour = loaded.samples(for: fiveHourKey)
        let loadedSevenDay = loaded.samples(for: sevenDayKey)
        let loadedSonnet = loaded.samples(for: sonnetKey)

        #expect(loadedFiveHour.count == originalFiveHour.count)
        #expect(loadedSevenDay.count == originalSevenDay.count)
        #expect(loadedSonnet.count == originalSonnet.count)

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
        await fixture.cleanup()
    }

    @Test @MainActor func windowBoundaryPruningDoesNotAffectOtherWindows() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let fiveHourResetsAt = now.addingTimeInterval(3600)
        let sevenDayResetsAt = now.addingTimeInterval(86400)

        let oldWindowStart = now.addingTimeInterval(-20000)
        let fiveHourEntryOld = makeEntry(key: "five_hour", utilization: 15, resetsAt: fiveHourResetsAt)
        history.record(entries: [fiveHourEntryOld], at: oldWindowStart)

        let sevenDayEntryOld = makeEntry(key: "seven_day", utilization: 25, resetsAt: sevenDayResetsAt)
        history.record(entries: [sevenDayEntryOld], at: oldWindowStart)

        let newFiveHourResetsAt = now.addingTimeInterval(1800)
        let fiveHourEntryNew = makeEntry(key: "five_hour", utilization: 20, resetsAt: newFiveHourResetsAt)
        let sevenDayEntryNew = makeEntry(key: "seven_day", utilization: 30, resetsAt: sevenDayResetsAt)
        history.record(entries: [fiveHourEntryNew, sevenDayEntryNew], at: now)

        let fiveHourSamples = history.samples(for: fiveHourEntryNew)
        let sevenDaySamples = history.samples(for: sevenDayEntryNew)

        for sample in fiveHourSamples {
            #expect(sample.utilization != 15,
                    "Pruned five_hour sample (util=15) still present after window boundary moved")
        }
        #expect(fiveHourSamples.contains(where: { $0.utilization == 20 }),
                "New five_hour sample (util=20) should be present")

        #expect(sevenDaySamples.contains(where: { $0.utilization == 25 }),
                "seven_day sample (util=25) should not be pruned — it is within its window")
        #expect(sevenDaySamples.contains(where: { $0.utilization == 30 }),
                "New seven_day sample (util=30) should be present")
        await fixture.cleanup()
    }
}
