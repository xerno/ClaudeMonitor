import Testing
import Foundation
@testable import ClaudeMonitor

/// Regression tests for `Formatting.absoluteTime` — under region-override locales such as
/// `en_CA@rg=czzzzz` (English-Canada language, Czechia region override, a common macOS setup),
/// `Date.FormatStyle`/`.formatted(...)` silently returns an empty string. These tests assert
/// against emptiness directly and would fail against the old `Date.FormatStyle`-based
/// implementation.
struct AbsoluteTimeFormattingTests {
    private func containsDigit(_ s: String) -> Bool {
        s.contains { $0.isNumber }
    }

    /// Splits a string into its runs of decimal digits, e.g. "9:41:27 AM" -> ["9", "41", "27"].
    /// Used to check formatted-time STRUCTURE (which numeric components are present, and in
    /// what relative order) without depending on the machine's locale or 12/24-hour style.
    private func digitGroups(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
    }

    private func makeEntry(utilization: Int, resetsAt: Date) -> WindowEntry {
        WindowEntry(
            key: "five_hour", duration: 1000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: utilization, resetsAt: resetsAt)
        )
    }

    private func makeAnalysis(utilization: Int, resetsAt: Date) -> WindowAnalysis {
        WindowAnalysis(
            entry: makeEntry(utilization: utilization, resetsAt: resetsAt), samples: [], events: [], consumptionRate: 0,
            projectedAtReset: Double(utilization), timeToLimit: nil, rateSource: .insufficient,
            style: Formatting.UsageStyle(level: .normal, isBold: false),
            segments: [], timeSinceLastChange: nil, recentRate: nil
        )
    }

    /// A fixed instant. Built from `Calendar.current` (rather than a literal `Date()` call) so
    /// the SAME instant is used every time the suite runs — no dependency on the real wall
    /// clock — while its hour/minute/second/year, extracted below via `Calendar.current`, are
    /// whatever this machine's local time zone actually renders for that instant. That keeps
    /// the test's expectations correct under any time zone without hardcoding a value that
    /// could only be right in one zone.
    private static let fixedInstant: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 14
        components.hour = 9
        components.minute = 41
        components.second = 27
        return Calendar.current.date(from: components)!
    }()

    private static let fixedComponents: DateComponents = {
        Calendar.current.dateComponents([.year, .minute, .second], from: fixedInstant)
    }()

    @Test func absoluteTimeIsNonEmptyForAllStyles() {
        let date = Date()
        for style: Formatting.AbsoluteTimeStyle in [.hourMinute, .hourMinuteSecond, .weekdayHourMinute] {
            let result = Formatting.absoluteTime(date, style)
            #expect(!result.isEmpty)
            #expect(containsDigit(result))
        }
    }

    @Test func hourMinuteContainsCorrectMinuteDigits() throws {
        let hm = Formatting.absoluteTime(Self.fixedInstant, .hourMinute)
        let minute = try #require(Self.fixedComponents.minute)
        let groups = digitGroups(hm)
        #expect(groups.contains { Int($0) == minute })
    }

    @Test func hourMinuteSecondAddsSecondsGroupNotPresentInHourMinute() throws {
        let hm = Formatting.absoluteTime(Self.fixedInstant, .hourMinute)
        let hms = Formatting.absoluteTime(Self.fixedInstant, .hourMinuteSecond)
        let second = try #require(Self.fixedComponents.second)

        let hmGroups = digitGroups(hm)
        let hmsGroups = digitGroups(hms)

        // hourMinuteSecond must carry every digit group hourMinute has, plus exactly one more:
        // the seconds. This pins the actual structural relationship between the two styles
        // (rather than only checking the strings differ or one is longer), and would catch a
        // regression where .hourMinuteSecond drops or reorders the minute/second components.
        #expect(hmsGroups.count == hmGroups.count + 1)
        #expect(Array(hmsGroups.prefix(hmGroups.count)) == hmGroups)
        if hmsGroups.count > hmGroups.count {
            #expect(Int(hmsGroups[hmGroups.count]) == second)
        }
    }

    /// The year is deliberately absent: windows last at most a week, so it carried no information,
    /// and carrying it pushed the stats row past the width available for it in every locale tested.
    /// What must remain is a weekday and the same clock time.
    @Test func weekdayHourMinuteOmitsTheYearAndKeepsTheSameMinute() throws {
        let hm = Formatting.absoluteTime(Self.fixedInstant, .hourMinute)
        let whm = Formatting.absoluteTime(Self.fixedInstant, .weekdayHourMinute)
        let year = try #require(Self.fixedComponents.year)
        let minute = try #require(Self.fixedComponents.minute)

        #expect(!whm.isEmpty)
        let groups = digitGroups(whm)
        #expect(!groups.contains { Int($0) == year }, "\(whm) should not carry the year")
        #expect(groups.contains { Int($0) == minute })
        // The clock time survives intact; the weekday is added as letters, not digits, so the digit
        // groups match the plain hour:minute rendering exactly.
        #expect(groups == digitGroups(hm))
        #expect(whm.contains { $0.isLetter }, "\(whm) should name a weekday")
        #expect(whm.count > hm.count)
    }

    @MainActor
    @Test func updatedNextTitleWithIntervalContainsThreeFilledTimeSegments() {
        let lastRefreshed = Date()
        let title = MenuBuilder.updatedNextTitle(lastRefreshed: lastRefreshed, interval: 60)
        let expectedTime = Formatting.absoluteTime(lastRefreshed, .hourMinuteSecond)
        #expect(!expectedTime.isEmpty)
        #expect(title.contains(expectedTime))
        #expect(containsDigit(title))
    }

    @MainActor
    @Test func updatedNextTitleWithoutIntervalContainsFilledTime() {
        let lastRefreshed = Date()
        let title = MenuBuilder.updatedNextTitle(lastRefreshed: lastRefreshed, interval: nil)
        let expectedTime = Formatting.absoluteTime(lastRefreshed, .hourMinuteSecond)
        #expect(!expectedTime.isEmpty)
        #expect(title.contains(expectedTime))
    }

    @Test func statsLabelTextForBlockedWindowTodayContainsHourMinute() {
        let resetsAt = Date() // today
        let analysis = makeAnalysis(utilization: 100, resetsAt: resetsAt)
        let text = Formatting.statsLabelText(analysis: analysis, now: resetsAt.addingTimeInterval(-10))
        let expectedTime = Formatting.absoluteTime(resetsAt, .hourMinute)
        #expect(!expectedTime.isEmpty)
        #expect(text.contains(expectedTime))
    }

    @Test func statsLabelTextForBlockedWindowOtherDayContainsWeekdayAndTime() {
        let resetsAt = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let analysis = makeAnalysis(utilization: 100, resetsAt: resetsAt)
        let text = Formatting.statsLabelText(analysis: analysis, now: Date())
        let expectedTime = Formatting.absoluteTime(resetsAt, .weekdayHourMinute)
        #expect(!expectedTime.isEmpty)
        #expect(text.contains(expectedTime))
    }
}
