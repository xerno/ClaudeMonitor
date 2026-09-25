import Testing
import Foundation
@testable import ClaudeMonitor

/// The energy estimate. Every number here is wrong in a way that still looks plausible if the
/// derivation drifts, so the tests pin the derivation itself, not just the output shape.
struct EnergyModelTests {

    // MARK: - Anchor derivation

    /// The whole estimate hangs off one published figure. If someone edits the constants, this says
    /// what they were: Joule's median 0.31 Wh per query at 300 output tokens.
    @Test func perTokenCoefficientsComeFromThePublishedPerQueryFigures() {
        let perToken = EnergyModel.whPerOutputToken
        #expect(abs(perToken.low - 0.16 / 300) < 1e-12)
        #expect(abs(perToken.median - 0.31 / 300) < 1e-12)
        #expect(abs(perToken.high - 0.60 / 300) < 1e-12)
        #expect(perToken.low < perToken.median)
        #expect(perToken.median < perToken.high)
    }

    /// A query of exactly the anchor's shape must reproduce the anchor's own number, otherwise the
    /// derivation has drifted away from the source it claims.
    @Test func anchorShapedQueryReproducesTheAnchorValue() {
        let estimate = EnergyModel.estimate(outputTokens: 300)
        #expect(abs(estimate.median - 0.31) < 1e-9)
        #expect(abs(estimate.low - 0.16) < 1e-9)
        #expect(abs(estimate.high - 0.60) < 1e-9)
    }

    /// PUE is inside the anchor already. Set to anything but 1.0 here and every figure is inflated
    /// a second time — which would look like a plausible number, not like a bug.
    @Test func pueIsNotAppliedOnTopOfAFullNodeAnchor() {
        #expect(Constants.Energy.pue == 1.0)
    }

    // MARK: - Scale

    /// Real totals from this machine's logs: ~16.0M output tokens across ~32k responses. Pins the
    /// order of magnitude that gets shown in the menu.
    @Test func realWorldTotalsLandInTheExpectedKilowattHourRange() {
        let estimate = EnergyModel.estimate(outputTokens: 16_023_921)
        #expect(estimate.low > 8_000 && estimate.low < 9_000)      // Wh
        #expect(estimate.median > 16_000 && estimate.median < 17_000)
        #expect(estimate.high > 32_000 && estimate.high < 33_000)
        #expect(estimate.description == "~17 kWh")
        #expect(estimate.rangeDescription == "9–32 kWh", "the spread is still available for stating provenance")
    }

    @Test func scalesLinearlyWithOutputTokens() {
        let single = EnergyModel.estimate(outputTokens: 1_000)
        let double = EnergyModel.estimate(outputTokens: 2_000)
        #expect(abs(double.median - single.median * 2) < 1e-9)
    }

    @Test func zeroTokensIsZeroNotAFloor() {
        #expect(EnergyModel.estimate(outputTokens: 0) == .zero)
        #expect(EnergyModel.estimate(outputTokens: -5) == .zero)
        #expect(EnergyEstimate.zero.description == "0 Wh")
    }

    /// Only output tokens drive the current estimate, but the totals carry the product term so the
    /// long-context correction can be added later. This checks the wiring reads from `usage.output`.
    @Test func estimateReadsOutputTokensFromTotals() {
        var totals = TokenTotals()
        totals.usage = TokenUsage(input: 9_999_999, cacheCreation: 9_999_999, cacheRead: 9_999_999, output: 300)
        #expect(abs(EnergyModel.estimate(totals: totals).median - 0.31) < 1e-9)
    }

    // MARK: - Units

    @Test func unitStepsAtEachThousand() {
        #expect(EnergyUnit.fitting(wattHours: 999) == .wattHours)
        #expect(EnergyUnit.fitting(wattHours: 1_000) == .kilowattHours)
        #expect(EnergyUnit.fitting(wattHours: 999_999) == .kilowattHours)
        #expect(EnergyUnit.fitting(wattHours: 1_000_000) == .megawattHours)
    }

    /// The unit comes from the upper end, so both ends of the range share one scale and the reader
    /// compares two numbers rather than two units.
    @Test func bothEndsOfTheRangeShareOneUnit() {
        // low 533 Wh, high 2000 Wh — straddles the kWh boundary.
        let estimate = EnergyModel.estimate(outputTokens: 1_000_000)
        #expect(estimate.rangeDescription == "0.5–2.0 kWh")
    }

    /// The displayed value is the median, not either quartile. Showing a quartile would read as a
    /// best estimate while being one by construction.
    @Test func displayedNumberIsTheMedianNotAQuartile() {
        let estimate = EnergyModel.estimate(outputTokens: 16_112_710)
        #expect(estimate.description == "~17 kWh")
        #expect(estimate.description != "~9 kWh")
        #expect(estimate.description != "~32 kWh")
    }

    @Test func tildeMarksItAsAnEstimate() {
        #expect(EnergyModel.estimate(outputTokens: 16_112_710).description.hasPrefix("~"))
    }

    @Test func precisionIsChosenFromTheUpperEndForTheWholeRange() {
        #expect(EnergyUnit.kilowattHours.decimals(for: 9_400) == 1)
        #expect(EnergyUnit.kilowattHours.decimals(for: 10_400) == 0)
        #expect(EnergyUnit.kilowattHours.format(9_400, decimals: 1) == "9.4")
        #expect(EnergyUnit.kilowattHours.format(32_048, decimals: 0) == "32")
        #expect(EnergyUnit.wattHours.format(7.26, decimals: 1) == "7.3")
    }

    /// Both ends must carry the same number of decimals. "8.5–32 kWh" reads as two precisions for
    /// one quantity, which is how this first rendered.
    @Test func rangeDoesNotMixPrecisionBetweenItsEnds() {
        let text = EnergyModel.estimate(outputTokens: 16_023_921).rangeDescription
        let ends = text.replacingOccurrences(of: " kWh", with: "").split(separator: "–")
        #expect(ends.count == 2)
        #expect(ends.allSatisfy { !$0.contains(".") } || ends.allSatisfy { $0.contains(".") })
    }

    /// Purely numeric, so it needs no localized string — the reason it can ship without editing
    /// thirty translation files.
    @Test func rangeContainsNoWordsThatWouldNeedTranslating() {
        let text = EnergyModel.estimate(outputTokens: 16_023_921).description
        let allowed = Set("0123456789.~  WhkM")
        #expect(text.allSatisfy { allowed.contains($0) }, "unexpected characters in \(text)")
    }
}
