import Testing
import Foundation
@testable import ClaudeMonitor

/// `computeRate` is `nonisolated`, so this suite stays off `@MainActor` and calls it synchronously.
///
/// A credit lowers utilization without moving `resetsAt`, so elapsed time is measured from the
/// most recent credit; from the window start the rate would be falsely low.
struct UsageHistoryCreditRateTests {
    private func credit(at: Date, from: Int, to: Int) -> UsageEvent {
        UsageEvent(at: at, kind: .credit, from: from, to: to, fromTimestamp: nil)
    }

    // MARK: - Rate after a credit reflects consumption since the credit

    @Test func creditAdjustedRateReflectsPostCreditConsumptionNotWindowStart() {
        let windowDuration: TimeInterval = 7 * Constants.Time.secondsPerDay
        let windowStart = Date(timeIntervalSince1970: 0)
        let resetsAt = windowStart.addingTimeInterval(windowDuration)

        let creditAt = windowStart.addingTimeInterval(6 * Constants.Time.secondsPerDay)
        let now = creditAt.addingTimeInterval(Constants.Time.secondsPerHour)
        let currentUtilization = 10

        let preFixTimeElapsed = now.timeIntervalSince(windowStart)
        let preFixRate = Double(currentUtilization) / preFixTimeElapsed

        let (postFixRate, source) = UsageHistory.computeRate(
            windowDuration: windowDuration,
            currentUtilization: currentUtilization,
            resetsAt: resetsAt,
            events: [credit(at: creditAt, from: 55, to: 0)],
            now: now
        )

        #expect(source == .implied)
        #expect(preFixRate < 0.0001)
        let expectedPostFixRate = Double(currentUtilization) / Constants.Time.secondsPerHour
        #expect(abs(postFixRate - expectedPostFixRate) < 0.0001)
        #expect(postFixRate > preFixRate * 100, "The credit-adjusted rate must be dramatically higher than the pre-fix window-start-based rate.")
    }

    @Test func fiveHourWindowCreditMagnitudeFromRealArchiveData() {
        let windowDuration = Constants.Time.secondsPerHour * 5
        let windowStart = Date(timeIntervalSince1970: 0)
        let resetsAt = windowStart.addingTimeInterval(windowDuration)
        let creditAt = windowStart.addingTimeInterval(3600)
        let now = creditAt.addingTimeInterval(1800)
        let currentUtilization = 8

        let (rate, source) = UsageHistory.computeRate(
            windowDuration: windowDuration,
            currentUtilization: currentUtilization,
            resetsAt: resetsAt,
            events: [credit(at: creditAt, from: 32, to: 0)],
            now: now
        )

        #expect(source == .implied)
        #expect(abs(rate - Double(currentUtilization) / 1800) < 0.0001)
    }

    // MARK: - Multiple credits: use the most recent

    @Test func multipleCreditsUseTheMostRecentOne() {
        let windowDuration: TimeInterval = 604800
        let windowStart = Date(timeIntervalSince1970: 0)
        let resetsAt = windowStart.addingTimeInterval(windowDuration)
        let olderCredit = credit(at: windowStart.addingTimeInterval(86400), from: 40, to: 0)
        let newerCredit = credit(at: windowStart.addingTimeInterval(2 * 86400), from: 20, to: 0)
        let now = newerCredit.at.addingTimeInterval(3600)

        let (rate, _) = UsageHistory.computeRate(
            windowDuration: windowDuration,
            currentUtilization: 5,
            resetsAt: resetsAt,
            events: [olderCredit, newerCredit],
            now: now
        )

        let expected = 5.0 / 3600
        #expect(abs(rate - expected) < 0.0001, "Rate must be measured from the MOST RECENT credit, not an older one.")
    }

    // MARK: - Near-zero elapsed guard

    @Test func nearZeroElapsedAfterCreditIsFlooredNotLeftAbsurd() {
        let windowDuration: TimeInterval = 604800
        let windowStart = Date(timeIntervalSince1970: 0)
        let resetsAt = windowStart.addingTimeInterval(windowDuration)
        let creditAt = windowStart.addingTimeInterval(100)
        let now = creditAt.addingTimeInterval(1)

        let (rate, source) = UsageHistory.computeRate(
            windowDuration: windowDuration,
            currentUtilization: 5,
            resetsAt: resetsAt,
            events: [credit(at: creditAt, from: 50, to: 0)],
            now: now
        )

        #expect(source == .implied)
        let naiveRate = 5.0 / 1
        let flooredRate = 5.0 / Constants.Projection.minRateElapsedAfterCredit
        #expect(abs(rate - flooredRate) < 0.0001)
        #expect(rate < naiveRate)
    }

    // MARK: - No credits

    @Test func noCreditsMatchesOriginalWindowStartBasedRate() {
        let windowDuration: TimeInterval = 604800
        let windowStart = Date(timeIntervalSince1970: 0)
        let resetsAt = windowStart.addingTimeInterval(windowDuration)
        let now = windowStart.addingTimeInterval(2 * 86400)

        let (rate, source) = UsageHistory.computeRate(
            windowDuration: windowDuration,
            currentUtilization: 30,
            resetsAt: resetsAt,
            events: [],
            now: now
        )

        #expect(source == .implied)
        let expected = 30.0 / (2 * 86400)
        #expect(abs(rate - expected) < 0.0001)
    }

    @Test func noCreditsDefaultParameterMatchesExplicitEmptyEvents() {
        let windowDuration: TimeInterval = 18000
        let windowStart = Date(timeIntervalSince1970: 0)
        let resetsAt = windowStart.addingTimeInterval(windowDuration)
        let now = windowStart.addingTimeInterval(9000)

        let (withDefault, _) = UsageHistory.computeRate(
            windowDuration: windowDuration, currentUtilization: 42, resetsAt: resetsAt, now: now
        )
        let (withExplicitEmpty, _) = UsageHistory.computeRate(
            windowDuration: windowDuration, currentUtilization: 42, resetsAt: resetsAt, events: [], now: now
        )
        #expect(withDefault == withExplicitEmpty)
    }

    @Test func noResetsAtStillReturnsInsufficientRegardlessOfEvents() {
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 42,
            resetsAt: nil,
            events: [credit(at: Date(), from: 90, to: 0)]
        )
        #expect(rate == 0)
        #expect(source == .insufficient)
    }
}
