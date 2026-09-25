import Testing
import AppKit
@testable import ClaudeMonitor

/// The stats row under the graph shares one line with the energy reading, so every branch of its
/// text has to fit the width left over. This is the check that was missing when the row first
/// overflowed and truncated mid-date.
@MainActor
struct StatsRowWidthTests {

    /// What the layout actually leaves for the stats text, taken from a real view carrying a
    /// realistic reading rather than recomputed from the constants — the split is dynamic now, so a
    /// formula here could agree with itself while disagreeing with what is drawn.
    private var availableWidth: CGFloat {
        let view = UsageGraphView()
        view.update(energy: EnergyModel.estimate(outputTokens: 16_112_710))
        return labels(in: view).stats.frame.width
    }

    private func labels(in view: UsageGraphView) -> (stats: NSTextField, energy: NSTextField) {
        let fields = view.subviews.compactMap { $0 as? NSTextField }
        return (fields[0], fields[1])
    }

    private func width(_ text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)]).size().width
    }

    private func analysis(
        utilization: Int,
        resetsIn: TimeInterval,
        rate: Double,
        projected: Double,
        timeToLimit: TimeInterval?,
        rateSource: RateSource,
        now: Date
    ) -> WindowAnalysis {
        WindowAnalysis(
            entry: WindowEntry(
                key: "five_hour", duration: 18_000, durationLabel: "5h", modelScope: nil,
                window: UsageWindow(utilization: utilization, resetsAt: now.addingTimeInterval(resetsIn))
            ),
            samples: [], events: [], consumptionRate: rate,
            projectedAtReset: projected, timeToLimit: timeToLimit, rateSource: rateSource,
            style: Formatting.UsageStyle(level: .normal, isBold: false),
            segments: [], timeSinceLastChange: nil, recentRate: nil
        )
    }

    /// Fixed instant so the rendered text is the same on every run.
    private static let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 16; c.hour = 10; c.minute = 30
        return Calendar.current.date(from: c)!
    }()

    /// Every branch of `statsLabelTextCore`, at values that make each one the widest it gets.
    private func everyBranch() -> [(name: String, text: String)] {
        let now = Self.now
        var out: [(String, String)] = []

        func add(_ name: String, _ a: WindowAnalysis) {
            out.append((name, Formatting.statsLabelText(analysis: a, now: now)))
        }

        add("blocked, today", analysis(utilization: 100, resetsIn: 3600, rate: 16.0 / 3600, projected: 120,
                                      timeToLimit: nil, rateSource: .implied, now: now))
        add("blocked, later day", analysis(utilization: 100, resetsIn: 30 * 3600, rate: 16.0 / 3600, projected: 120,
                                          timeToLimit: nil, rateSource: .implied, now: now))
        add("collecting", analysis(utilization: 40, resetsIn: 7200, rate: 0, projected: 40,
                                   timeToLimit: nil, rateSource: .insufficient, now: now))
        add("idle", analysis(utilization: 22, resetsIn: 7200, rate: 0, projected: 22,
                             timeToLimit: nil, rateSource: .implied, now: now))
        add("projected", analysis(utilization: 62, resetsIn: 7200, rate: 16.4 / 3600, projected: 78,
                                  timeToLimit: nil, rateSource: .implied, now: now))
        add("limit, time unknown", analysis(utilization: 62, resetsIn: 7200, rate: 16.4 / 3600, projected: 140,
                                            timeToLimit: nil, rateSource: .implied, now: now))
        add("limit at a time today", analysis(utilization: 62, resetsIn: 40_000, rate: 16.4 / 3600, projected: 140,
                                              timeToLimit: 7200, rateSource: .implied, now: now))
        add("limit on a later day", analysis(utilization: 62, resetsIn: 200_000, rate: 16.4 / 3600, projected: 140,
                                             timeToLimit: 100_000, rateSource: .implied, now: now))
        return out
    }

    @Test func everyStatsBranchFitsBesideTheEnergyReading() {
        for (name, text) in everyBranch() where !text.isEmpty {
            #expect(width(text) <= availableWidth,
                    "\"\(text)\" (\(name)) is \(width(text)) pt, only \(availableWidth) pt available")
        }
    }

    @Test func theEnergyReadingFitsItsOwnReservation() {
        // Widest the formatter can produce: three digits and the largest unit.
        let widest = UsageGraphView.energyText(for: EnergyEstimate(low: 1, median: 123_000_000, high: 200_000_000))
        #expect(width(widest) <= GraphDrawer.Layout.energyLabelWidth, "\(widest) is \(width(widest)) pt")
    }

    /// The clock time names when the limit is reached, not when the window resets — the old wording
    /// said "before reset (at 17:44)", which reads as the reset time and was simply wrong.
    @Test func limitTextNamesWhenTheLimitIsHitNotWhenTheWindowResets() {
        let now = Self.now
        let a = analysis(utilization: 62, resetsIn: 40_000, rate: 16.4 / 3600, projected: 140,
                         timeToLimit: 7200, rateSource: .implied, now: now)
        let text = Formatting.statsLabelText(analysis: a, now: now)
        let limitMoment = Formatting.absoluteTime(now.addingTimeInterval(7200), .hourMinute)
        let resetMoment = Formatting.absoluteTime(now.addingTimeInterval(40_000), .hourMinute)
        #expect(text.contains(limitMoment), "\(text) should name the limit moment \(limitMoment)")
        #expect(!text.contains(resetMoment), "\(text) must not name the reset moment \(resetMoment)")
    }

    @Test func limitTextDropsTheOldBeforeResetWording() {
        for (_, text) in everyBranch() {
            #expect(!text.contains("before reset"))
        }
    }
}

/// The stats row splits its width between the two labels at run time. These pin that split, because
/// a fixed reserve is what made a Croatian string overflow by under two points.
@MainActor
struct StatsRowLayoutTests {

    private func labels(in view: UsageGraphView) -> (stats: NSTextField, energy: NSTextField) {
        let fields = view.subviews.compactMap { $0 as? NSTextField }
        return (fields[0], fields[1])
    }

    private func width(_ text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)]).size().width
    }

    @Test func energyLabelShrinksToItsTextAndHandsTheRestToTheStatsText() {
        let view = UsageGraphView()
        view.update(energy: EnergyModel.estimate(outputTokens: 16_112_710))
        let (stats, energy) = labels(in: view)

        let text = UsageGraphView.energyText(for: EnergyModel.estimate(outputTokens: 16_112_710))
        #expect(energy.frame.width >= width(text))
        #expect(energy.frame.width <= width(text) + 8, "the label should fit its text, not a fixed reserve")

        let usable = view.bounds.width - MenuBuilder.rowTrailingInset * 2
        #expect(stats.frame.width == usable - energy.frame.width - GraphDrawer.Layout.statsEnergyGap)
        #expect(stats.frame.maxX <= energy.frame.minX)
    }

    /// Before the first scan there is no reading, and the whole row belongs to the stats text.
    @Test func withNoReadingTheStatsTextGetsTheWholeRow() {
        let view = UsageGraphView()
        view.update(energy: nil)
        let (stats, energy) = labels(in: view)
        #expect(energy.frame.width == 0)
        #expect(stats.frame.width == view.bounds.width - MenuBuilder.rowTrailingInset * 2)
    }

    /// A reading can never eat the row, however large the number gets.
    @Test func anAbsurdReadingIsCappedSoTheStatsTextSurvives() {
        let view = UsageGraphView()
        view.update(energy: EnergyEstimate(low: 1, median: 999_000_000_000, high: 1_000_000_000_000))
        let (stats, energy) = labels(in: view)
        #expect(energy.frame.width <= GraphDrawer.Layout.energyLabelMaxWidth)
        #expect(stats.frame.width > 100, "the stats text must keep a usable share of the row")
    }

    @Test func energyLabelStaysPinnedToTheTrailingEdge() {
        let view = UsageGraphView()
        view.update(energy: EnergyModel.estimate(outputTokens: 300))
        let (_, energy) = labels(in: view)
        #expect(energy.frame.maxX == view.bounds.width - MenuBuilder.rowTrailingInset)
    }
}

/// Diagnostics for the energy label's own box: an NSTextField needs slightly more width than the
/// bare text measures, and a label sized to the text alone clips its last glyph.
@MainActor
struct EnergyLabelFitTests {

    private func energyLabel(in view: UsageGraphView) -> NSTextField {
        view.subviews.compactMap { $0 as? NSTextField }[1]
    }

    @Test func labelIsWideEnoughForItsOwnTextField() {
        let view = UsageGraphView()
        view.update(energy: EnergyModel.estimate(outputTokens: 16_112_710))
        let label = energyLabel(in: view)
        #expect(label.frame.width >= label.fittingSize.width,
                "frame \(label.frame.width) pt vs fitting \(label.fittingSize.width) pt for \"\(label.stringValue)\"")
    }

    /// The row should line up with the rows above and below it, which inset by the header padding.
    @Test func labelTrailingEdgeMatchesTheRestOfTheMenu() {
        let view = UsageGraphView()
        view.update(energy: EnergyModel.estimate(outputTokens: 16_112_710))
        let label = energyLabel(in: view)
        let inset = view.bounds.width - label.frame.maxX
        #expect(inset == MenuBuilder.rowTrailingInset,
                "energy label is inset \(inset) pt, other rows use \(MenuBuilder.rowTrailingInset) pt")
    }
}
