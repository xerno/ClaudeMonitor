import Foundation

/// Quartiles rather than one number: the published per-query figures span 3.75× between quartiles,
/// and the choice of accounting boundary adds another 43×.
struct EnergyEstimate: Equatable, Sendable {
    /// Watt-hours.
    let low: Double
    let median: Double
    let high: Double

    static let zero = EnergyEstimate(low: 0, median: 0, high: 0)
}

/// Whole-datacentre electricity (compute, host CPU/DRAM, idle capacity, power/cooling overhead),
/// not silicon draw. See `Constants.Energy` for the anchor and why PUE is not applied twice.
///
/// Known limitation: the anchor assumes short prompts, so long-context agentic work reads low
/// (a flat per-output-token coefficient understates the total by ~34%).
/// `TokenTotals.contextOutputProduct` is accumulated so a correction needs no rescan.
enum EnergyModel {

    static var whPerOutputToken: (low: Double, median: Double, high: Double) {
        (
            Constants.Energy.anchorWhPerQueryLow / Constants.Energy.anchorOutputTokensPerQuery,
            Constants.Energy.anchorWhPerQueryMedian / Constants.Energy.anchorOutputTokensPerQuery,
            Constants.Energy.anchorWhPerQueryHigh / Constants.Energy.anchorOutputTokensPerQuery
        )
    }

    static func estimate(totals: TokenTotals) -> EnergyEstimate {
        estimate(outputTokens: totals.usage.output)
    }

    static func estimate(outputTokens: Int) -> EnergyEstimate {
        guard outputTokens > 0 else { return .zero }
        let tokens = Double(outputTokens)
        let perToken = whPerOutputToken
        let pue = Constants.Energy.pue
        return EnergyEstimate(
            low: tokens * perToken.low * pue,
            median: tokens * perToken.median * pue,
            high: tokens * perToken.high * pue
        )
    }
}

// MARK: - Formatting

extension EnergyEstimate {
    /// Best estimate only, e.g. `~17 kWh`: the error is systematic (constant coefficient), so
    /// day-to-day comparisons hold, and the published spread is variation across models and
    /// deployments, not an error bar for this one. Purely numeric, so it needs no localized string.
    var description: String {
        guard median > 0 else { return "0 Wh" }
        let unit = EnergyUnit.fitting(wattHours: median)
        return "~\(unit.format(median, decimals: unit.decimals(for: median))) \(unit.symbol)"
    }

    var rangeDescription: String {
        guard high > 0 else { return "0 Wh" }
        let unit = EnergyUnit.fitting(wattHours: high)
        // Precision from the upper end for both ends; "8.5–32 kWh" would mix precisions.
        let decimals = unit.decimals(for: high)
        return "\(unit.format(low, decimals: decimals))–\(unit.format(high, decimals: decimals)) \(unit.symbol)"
    }
}

enum EnergyUnit: Equatable {
    case wattHours
    case kilowattHours
    case megawattHours

    static func fitting(wattHours: Double) -> EnergyUnit {
        if wattHours >= 1_000_000 { return .megawattHours }
        if wattHours >= 1_000 { return .kilowattHours }
        return .wattHours
    }

    var symbol: String {
        switch self {
        case .wattHours: "Wh"
        case .kilowattHours: "kWh"
        case .megawattHours: "MWh"
        }
    }

    var divisor: Double {
        switch self {
        case .wattHours: 1
        case .kilowattHours: 1_000
        case .megawattHours: 1_000_000
        }
    }

    /// One decimal below 10, whole numbers above; finer is inside the noise of a ~4× spread.
    func decimals(for wattHours: Double) -> Int {
        wattHours / divisor < 10 ? 1 : 0
    }

    func format(_ wattHours: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", wattHours / divisor)
    }
}
