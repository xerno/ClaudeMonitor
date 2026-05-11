import Foundation

extension UsageHistory {
    static func segmentSamples(
        _ samples: [UtilizationSample],
        windowStart: Date,
        gapThreshold: TimeInterval = Constants.History.gapThreshold
    ) -> [SampleSegment] {
        guard !samples.isEmpty else { return [] }

        var result: [SampleSegment] = []

        // If first sample is significantly after window start, add an inferred segment
        // from 0% (window resets to 0) to the first real sample.
        if samples[0].timestamp > windowStart.addingTimeInterval(Constants.History.inferredSegmentMinGap) {
            let inferredStart = UtilizationSample(utilization: 0, timestamp: windowStart)
            result.append(SampleSegment(kind: .inferred, samples: [inferredStart, samples[0]]))
        }

        var currentTracked: [UtilizationSample] = [samples[0]]

        for i in 1..<samples.count {
            let prev = samples[i - 1]
            let curr = samples[i]
            let gap = curr.timestamp.timeIntervalSince(prev.timestamp)

            if gap > gapThreshold {
                if !currentTracked.isEmpty {
                    result.append(SampleSegment(kind: .tracked, samples: currentTracked))
                    currentTracked = []
                }
                result.append(SampleSegment(kind: .gap, samples: [prev, curr]))
                currentTracked = [curr]
            } else {
                currentTracked.append(curr)
            }
        }

        if !currentTracked.isEmpty {
            result.append(SampleSegment(kind: .tracked, samples: currentTracked))
        }

        return result
    }

    static func computeRate(
        windowDuration: TimeInterval,
        currentUtilization: Int,
        resetsAt: Date?,
        now: Date = Date()
    ) -> (rate: Double, source: RateSource) {
        guard let resetsAt else { return (0, .insufficient) }

        let timeElapsed = windowDuration - max(0, resetsAt.timeIntervalSince(now))
        guard timeElapsed > 0 else { return (0, .insufficient) }

        let rate = Double(currentUtilization) / timeElapsed
        return (rate, .implied)
    }

    static func project(
        currentUtilization: Int,
        rate: Double,
        timeRemaining: TimeInterval
    ) -> (projectedAtReset: Double, timeToLimit: TimeInterval?) {
        let projectedAtReset = Double(currentUtilization) + rate * timeRemaining
        var timeToLimit: TimeInterval? = nil
        if rate > 0 && currentUtilization < 100 {
            let ttl = Double(100 - currentUtilization) / rate
            if ttl <= timeRemaining {
                timeToLimit = ttl
            }
        }
        return (projectedAtReset, timeToLimit)
    }

    static func computeTimeSinceLastChange(
        currentUtilization: Int,
        samples: [UtilizationSample],
        now: Date = Date()
    ) -> TimeInterval? {
        guard !samples.isEmpty else { return nil }

        for i in stride(from: samples.count - 1, through: 0, by: -1) {
            if samples[i].utilization != currentUtilization {
                if i + 1 < samples.count {
                    return now.timeIntervalSince(samples[i + 1].timestamp)
                }
                return 0
            }
        }

        return now.timeIntervalSince(samples.first!.timestamp)
    }

    static func computeRecentRate(samples: [UtilizationSample], tau: TimeInterval = Constants.Polling.rateEmaTau) -> Double? {
        guard samples.count >= 2 else { return nil }

        var ema: Double? = nil
        var previous = samples[0]

        for current in samples.dropFirst() {
            let deltaTime = current.timestamp.timeIntervalSince(previous.timestamp)
            guard deltaTime > 0 else {
                previous = current
                continue
            }
            let deltaUtil = Double(current.utilization - previous.utilization)

            if deltaUtil < 0 {
                previous = current
                continue  // treat negative delta as zero-rate tick, skip EMA update
            }

            let instantaneous = deltaUtil / deltaTime
            let alpha = 1.0 - exp(-deltaTime / tau)

            if let prev = ema {
                ema = alpha * instantaneous + (1 - alpha) * prev
            } else {
                ema = instantaneous
            }

            previous = current
        }

        return ema
    }

    static func analyze(entry: WindowEntry, samples: [UtilizationSample], now: Date = Date()) -> WindowAnalysis {
        let timeRemaining = max(0, (entry.window.resetsAt ?? now).timeIntervalSince(now))
        let (rate, source) = computeRate(
            windowDuration: entry.duration,
            currentUtilization: entry.window.utilization,
            resetsAt: entry.window.resetsAt,
            now: now
        )
        let (projectedAtReset, timeToLimit) = project(
            currentUtilization: entry.window.utilization,
            rate: rate,
            timeRemaining: timeRemaining
        )
        let style = Formatting.usageStyle(
            projectedAtReset: projectedAtReset,
            utilization: entry.window.utilization,
            resetsAt: entry.window.resetsAt,
            timeRemaining: timeRemaining
        )
        let windowStart = entry.windowStart ?? now
        let segs = segmentSamples(samples, windowStart: windowStart)
        let timeSinceLastChange = computeTimeSinceLastChange(
            currentUtilization: entry.window.utilization,
            samples: samples,
            now: now
        )
        let recentRate = computeRecentRate(samples: samples)
        return WindowAnalysis(
            entry: entry,
            samples: samples,
            consumptionRate: rate,
            projectedAtReset: projectedAtReset,
            timeToLimit: timeToLimit,
            rateSource: source,
            style: style,
            segments: segs,
            timeSinceLastChange: timeSinceLastChange,
            recentRate: recentRate
        )
    }
}
