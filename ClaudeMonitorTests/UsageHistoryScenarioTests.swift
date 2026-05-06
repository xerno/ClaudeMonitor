import Foundation
import Testing
@testable import ClaudeMonitor

@Suite struct ScenarioTests {

    @Test @MainActor func crossWindowIsolation() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let resetsAt = now.addingTimeInterval(86400)

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
        await fixture.cleanup()
    }

    @Test @MainActor func restartAfterResetProducesCleanGraph() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let now = Date()
        let duration: TimeInterval = 18000

        let oldResetsAt = now.addingTimeInterval(3600)
        for i in 0..<10 {
            let fraction = Double(i) / 9.0
            let util = 10 + Int(40.0 * fraction)
            let t = now.addingTimeInterval(-7200 + 7200 * fraction)
            let entry = makeEntry(key: "five_hour", utilization: util, resetsAt: oldResetsAt)
            history.record(entries: [entry], at: t)
        }
        #expect(history.samples(for: makeEntry(key: "five_hour", utilization: 50, resetsAt: oldResetsAt)).count > 0)

        let newResetsAt = now.addingTimeInterval(duration)
        await history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 50, resetsAt: newResetsAt),
            newResetsAt: newResetsAt,
            previousResetsAt: oldResetsAt
        )

        let newUtils = [2, 3, 5]
        for (i, util) in newUtils.enumerated() {
            let t = now.addingTimeInterval(Double(i) * 120)
            let entry = makeEntry(key: "five_hour", utilization: util, resetsAt: newResetsAt)
            history.record(entries: [entry], at: t)
        }

        let latestEntry = makeEntry(key: "five_hour", utilization: 5, resetsAt: newResetsAt)
        let samples = history.samples(for: latestEntry)

        for sample in samples {
            #expect(sample.utilization <= 10)
        }

        let windowStart = newResetsAt.addingTimeInterval(-duration)
        let segments = UsageHistory.segmentSamples(samples, windowStart: windowStart)
        for seg in segments where seg.kind == .inferred {
            for s in seg.samples {
                #expect(s.utilization <= 50)
            }
        }

        for sample in samples {
            #expect(sample.timestamp >= windowStart)
        }
        await fixture.cleanup()
    }

    @Test @MainActor func multipleResetCyclesKeepDataClean() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let now = Date()
        let duration: TimeInterval = 18000

        var currentResetsAt = now.addingTimeInterval(duration)

        for cycle in 0..<3 {
            let baseUtil = (cycle + 1) * 10
            for i in 0..<5 {
                let util = baseUtil + i * 2
                let t = now.addingTimeInterval(Double(cycle) * duration + Double(i) * 60)
                let entry = makeEntry(key: "five_hour", utilization: util, resetsAt: currentResetsAt)
                history.record(entries: [entry], at: t)
            }

            let nextResetsAt = currentResetsAt.addingTimeInterval(duration * 0.6)
            let resetEntry = makeEntry(key: "five_hour", utilization: baseUtil + 8, resetsAt: nextResetsAt)
            await history.detectAndHandleReset(
                entry: resetEntry,
                newResetsAt: nextResetsAt,
                previousResetsAt: currentResetsAt
            )
            currentResetsAt = nextResetsAt
        }

        let finalResetsAt = currentResetsAt
        let finalUtils = [5, 8, 12]
        for (i, util) in finalUtils.enumerated() {
            let t = now.addingTimeInterval(Double(i) * 120)
            let entry = makeEntry(key: "five_hour", utilization: util, resetsAt: finalResetsAt)
            history.record(entries: [entry], at: t)
        }

        let latestEntry = makeEntry(key: "five_hour", utilization: 12, resetsAt: finalResetsAt)
        let samples = history.samples(for: latestEntry)

        for sample in samples {
            #expect(sample.utilization <= 20)
        }
        #expect(samples.count <= 3)
        await fixture.cleanup()
    }

    @Test @MainActor func segmentConsistencyAcrossSimilarWindows() {
        let now = Date()

        let fiveHourDuration: TimeInterval = 18000
        let fiveHourResetsAt = now.addingTimeInterval(fiveHourDuration * 0.1)
        let fiveHourWindowStart = fiveHourResetsAt.addingTimeInterval(-fiveHourDuration)
        let fiveHourSamples = makeSamples(count: 5, startUtilization: 30, endUtilization: 40,
                                          span: fiveHourDuration * 0.1,
                                          endDate: now)
        #expect(fiveHourSamples.first!.timestamp > fiveHourWindowStart.addingTimeInterval(60))

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

        #expect(fiveHourAnalysis.segments.count == sevenDayAnalysis.segments.count)
        for (segA, segB) in zip(fiveHourAnalysis.segments, sevenDayAnalysis.segments) {
            #expect(segA.kind == segB.kind)
        }
        #expect(fiveHourAnalysis.segments.first?.kind == .inferred)
        #expect(sevenDayAnalysis.segments.first?.kind == .inferred)
    }

    @Test @MainActor func gapDetectionAfterRestart() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let duration: TimeInterval = 18000
        let resetsAt = now.addingTimeInterval(3600)
        let windowStart = resetsAt.addingTimeInterval(-duration)

        let group1End = now.addingTimeInterval(-1800)
        for i in 0..<5 {
            let fraction = Double(i) / 4.0
            let t = group1End.addingTimeInterval(-600 + 600 * fraction)
            let entry = makeEntry(key: "five_hour", utilization: 10 + i * 2, resetsAt: resetsAt)
            history.record(entries: [entry], at: t)
        }

        for i in 0..<5 {
            let t = now.addingTimeInterval(-Double(4 - i) * 60)
            let entry = makeEntry(key: "five_hour", utilization: 20 + i * 3, resetsAt: resetsAt)
            history.record(entries: [entry], at: t)
        }

        let latestEntry = makeEntry(key: "five_hour", utilization: 32, resetsAt: resetsAt)
        let samples = history.samples(for: latestEntry)

        let segments = UsageHistory.segmentSamples(samples, windowStart: windowStart)

        let gapSegments = segments.filter { $0.kind == .gap }
        #expect(gapSegments.count >= 1)

        if let gapSeg = gapSegments.first {
            #expect(gapSeg.samples.count == 2)
            let gapDuration = gapSeg.samples[1].timestamp.timeIntervalSince(gapSeg.samples[0].timestamp)
            #expect(gapDuration > 600)
        }
        await fixture.cleanup()
    }

    @Test @MainActor func identicalInputsProduceIdenticalAnalysis() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = makeEntry(key: "five_hour", utilization: 55, resetsAt: resetsAt)
        let samples = makeSamples(count: 8, startUtilization: 20, endUtilization: 55, span: 800, endDate: now)

        let analysis1 = UsageHistory.analyze(entry: entry, samples: samples, now: now)
        let analysis2 = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        let expectedProjected2 = 55.0 + (55.0 / 14400.0) * 3600.0
        #expect(abs(analysis1.projectedAtReset - expectedProjected2) < 2.0)
        #expect(!analysis1.segments.isEmpty)
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

    @Test @MainActor func utilizationDropAfterLongGapIsKept() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let resetsAt = now.addingTimeInterval(86400 * 6)
        let entry18 = makeEntry(key: "seven_day", utilization: 18, resetsAt: resetsAt)
        history.record(entries: [entry18], at: now)

        let entry15 = makeEntry(key: "seven_day", utilization: 15, resetsAt: resetsAt)
        history.record(entries: [entry15], at: now.addingTimeInterval(120))

        let samples = history.samples(for: entry15)
        #expect(samples.count == 2)
        #expect(samples[0].utilization == 18)
        #expect(samples[1].utilization == 15)
        await fixture.cleanup()
    }
}
