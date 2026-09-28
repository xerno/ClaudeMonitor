import Testing
import Foundation
@testable import ClaudeMonitor

/// Under region-override locales such as `en_CA@rg=czzzzz`, `Date.FormatStyle` silently returns an
/// empty string, hence the non-empty assertions.
struct AbsoluteTimeFormattingTests {
    private func containsDigit(_ s: String) -> Bool {
        s.contains { $0.isNumber }
    }

    /// Digit runs let structure be checked without depending on locale or 12/24-hour style.
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

    /// Built and read back through `Calendar.current`, so expectations hold in any time zone.
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

        #expect(hmsGroups.count == hmGroups.count + 1)
        #expect(Array(hmsGroups.prefix(hmGroups.count)) == hmGroups)
        if hmsGroups.count > hmGroups.count {
            #expect(Int(hmsGroups[hmGroups.count]) == second)
        }
    }

    /// The year is absent by design: windows last at most a week, and it pushed the stats row past its width.
    @Test func weekdayHourMinuteOmitsTheYearAndKeepsTheSameMinute() throws {
        let hm = Formatting.absoluteTime(Self.fixedInstant, .hourMinute)
        let whm = Formatting.absoluteTime(Self.fixedInstant, .weekdayHourMinute)
        let year = try #require(Self.fixedComponents.year)
        let minute = try #require(Self.fixedComponents.minute)

        #expect(!whm.isEmpty)
        let groups = digitGroups(whm)
        #expect(!groups.contains { Int($0) == year }, "\(whm) should not carry the year")
        #expect(groups.contains { Int($0) == minute })
        // The weekday adds letters, not digits, so the digit groups equal the plain rendering's.
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
        let resetsAt = Date()
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
