import Foundation

/// An energy estimate as the three quartiles its anchor actually measured.
///
/// Deliberately not a single number. The published per-query figures this is built on span a factor
/// of 3.75 between quartiles, and the choice of accounting boundary spans a factor of 43 on top of
/// that, so a single figure would claim a precision nobody has.
struct EnergyEstimate: Equatable, Sendable {
    /// Watt-hours.
    let low: Double
    let median: Double
    let high: Double

    static let zero = EnergyEstimate(low: 0, median: 0, high: 0)
}

/// Converts token counts into estimated datacentre electricity.
///
/// Scope: the whole datacentre — compute, host CPU and DRAM, idle capacity and power/cooling
/// overhead — because the question being answered is what the electricity meter saw, not what the
/// silicon drew. See `Constants.Energy` for the anchor and why PUE is not applied twice.
///
/// Known limitation: the anchor assumes short prompts and treats output length as the only driver.
/// Real agentic traffic reads a very large cached context on every generated token — measured on
/// this machine's logs, energy tracks `context × output`, and a flat per-output-token coefficient
/// understates the total by around a third. This estimate therefore reads low for long-context work,
/// and `TokenTotals.contextOutputProduct` is accumulated so that correction can be added without
/// re-reading the logs.
enum EnergyModel {

    /// Watt-hours per output token, derived from the anchor's per-query figures.
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
    /// What the menu shows: the single best estimate, e.g. `~17 kWh`.
    ///
    /// One number rather than the quartile range it was derived from. The uncertainty here is
    /// systematic, not random — the coefficient is a constant, so if it is wrong it is wrong by the
    /// same factor every time and comparisons between days stay correct, which is what a menu bar
    /// reading is actually used for. The published spread is also interquartile variation across
    /// models and deployments rather than measurement error about this one deployment, so printing
    /// it as this number's error bar would misrepresent what it says. The tilde marks an estimate;
    /// `rangeDescription` carries the spread for anywhere the provenance needs stating.
    ///
    /// Purely numeric — no words — so it needs no localized string, which would otherwise mean
    /// editing thirty translation files.
    var description: String {
        guard median > 0 else { return "0 Wh" }
        let unit = EnergyUnit.fitting(wattHours: median)
        return "~\(unit.format(median, decimals: unit.decimals(for: median))) \(unit.symbol)"
    }

    /// The underlying quartile spread, e.g. `8.6–32 kWh`. Not shown in the menu; used where the
    /// number's provenance and its uncertainty have to be stated in full.
    var rangeDescription: String {
        guard high > 0 else { return "0 Wh" }
        let unit = EnergyUnit.fitting(wattHours: high)
        // One precision for the whole range, taken from the upper end: "8.5–32 kWh" reads as two
        // different precisions for one quantity.
        let decimals = unit.decimals(for: high)
        return "\(unit.format(low, decimals: decimals))–\(unit.format(high, decimals: decimals)) \(unit.symbol)"
    }
}

/// Unit the estimate is rendered in. Steps at 1000 so the number stays at most four digits.
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

    /// One decimal below 10, whole numbers above — a tenth of a kWh is well inside the noise once
    /// the range itself spans a factor of nearly four.
    func decimals(for wattHours: Double) -> Int {
        wattHours / divisor < 10 ? 1 : 0
    }

    func format(_ wattHours: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", wattHours / divisor)
    }
}
