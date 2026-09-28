import Testing
import Foundation
@testable import ClaudeMonitor

/// A drifting derivation still yields plausible numbers, so these pin the derivation, not just the output shape.
struct EnergyModelTests {

    // MARK: - Anchor derivation

    /// The estimate hangs off one published figure: Joule's median 0.31 Wh per query at 300 output tokens.
    @Test func perTokenCoefficientsComeFromThePublishedPerQueryFigures() {
        let perToken = EnergyModel.whPerOutputToken
        #expect(abs(perToken.low - 0.16 / 300) < 1e-12)
        #expect(abs(perToken.median - 0.31 / 300) < 1e-12)
        #expect(abs(perToken.high - 0.60 / 300) < 1e-12)
        #expect(perToken.low < perToken.median)
        #expect(perToken.median < perToken.high)
    }

    @Test func anchorShapedQueryReproducesTheAnchorValue() {
        let estimate = EnergyModel.estimate(outputTokens: 300)
        #expect(abs(estimate.median - 0.31) < 1e-9)
        #expect(abs(estimate.low - 0.16) < 1e-9)
        #expect(abs(estimate.high - 0.60) < 1e-9)
    }

    /// PUE is already inside the anchor; anything but 1.0 would inflate every figure a second time.
    @Test func pueIsNotAppliedOnTopOfAFullNodeAnchor() {
        #expect(Constants.Energy.pue == 1.0)
    }

    // MARK: - Scale

    /// Real totals from this machine's logs: ~16.0M output tokens across ~32k responses.
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

    @Test func bothEndsOfTheRangeShareOneUnit() {
        // low 533 Wh, high 2000 Wh: straddles the kWh boundary.
        let estimate = EnergyModel.estimate(outputTokens: 1_000_000)
        #expect(estimate.rangeDescription == "0.5–2.0 kWh")
    }

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

    @Test func rangeDoesNotMixPrecisionBetweenItsEnds() {
        let text = EnergyModel.estimate(outputTokens: 16_023_921).rangeDescription
        let ends = text.replacingOccurrences(of: " kWh", with: "").split(separator: "–")
        #expect(ends.count == 2)
        #expect(ends.allSatisfy { !$0.contains(".") } || ends.allSatisfy { $0.contains(".") })
    }

    @Test func rangeContainsNoWordsThatWouldNeedTranslating() {
        let text = EnergyModel.estimate(outputTokens: 16_023_921).description
        let allowed = Set("0123456789.~  WhkM")
        #expect(text.allSatisfy { allowed.contains($0) }, "unexpected characters in \(text)")
    }
}
