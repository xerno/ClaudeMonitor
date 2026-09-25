import Foundation

/// Token counts for a single API response, as Claude Code records them in its session logs.
///
/// There is no `thinking` field on purpose: `output_tokens_details.thinking_tokens` is a subset of
/// `output_tokens`, so counting it separately would count it twice. Checked two ways — across every
/// logged response carrying the field the ratio reaches 0.999 but never exceeds 1, and the API
/// documents it as reporting how many of the *billed output tokens* were internal reasoning.
///
/// `input`, `cacheCreation` and `cacheRead` are three disjoint counters (`input_tokens` counts only
/// uncached tokens), so the whole prompt is their sum.
struct TokenUsage: Equatable, Sendable, Codable {
    var input: Int = 0
    var cacheCreation: Int = 0
    var cacheRead: Int = 0
    var output: Int = 0

    var total: Int { input + cacheCreation + cacheRead + output }

    /// Everything the model had to read for this response — the whole prompt, cached or not.
    /// The energy estimate needs this as a context length, not as a billable quantity.
    var contextRead: Int { input + cacheCreation + cacheRead }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            cacheCreation: lhs.cacheCreation + rhs.cacheCreation,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            output: lhs.output + rhs.output
        )
    }

    static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }
}

// MARK: - Entry

/// One deduplicated API response worth of tokens.
struct TokenLogEntry: Equatable, Sendable {
    let dedupKey: String
    let model: String
    let timestamp: Date?
    let usage: TokenUsage

    /// Energy scales with the product of context length and generated tokens, because every
    /// generated token re-reads the whole context. Measured on real traffic, treating cached tokens
    /// as a flat per-token cost understates the total by 34% and individual responses by up to 3.8×.
    var contextOutputProduct: Int { usage.contextRead * usage.output }
}

// MARK: - Totals

/// Aggregated token counts plus the bookkeeping needed to trust them.
///
/// `skippedDuplicates` and `unparsableLines` are surfaced rather than swallowed: both are large in
/// real data, so a caller seeing a suspicious number can tell which one produced it.
struct TokenTotals: Equatable, Sendable, Codable {
    var usage = TokenUsage()
    var requests = 0
    var byModel: [String: TokenUsage] = [:]
    var skippedDuplicates = 0
    var unparsableLines = 0
    /// Σ(context × output), carried separately because it cannot be recovered from the sums above.
    var contextOutputProduct = 0
}

// MARK: - Scan state

/// Deterministic 64-bit hash (FNV-1a).
///
/// Swift's `Hasher` is seeded per process, so `hashValue` must never be persisted: a dedup set
/// written on one launch would match nothing on the next, and every response would be recounted.
enum StableHash {
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// What a scan needs to remember so the next one can read only what was appended.
///
/// Storing hashes rather than the id strings keeps this at 8 bytes per response instead of ~40.
/// With ~32 000 responses in a 2^64 space the chance of a collision is around 3e-14, which is far
/// below the error already carried by the energy coefficients.
struct TokenScanState: Equatable, Codable, Sendable {
    /// Bytes already consumed per log file. Only whole lines are ever counted as consumed.
    var offsets: [String: UInt64] = [:]
    var seen: Set<UInt64> = []
    var totals = TokenTotals()
}

// MARK: - Accumulator

/// Accumulates log lines, collapsing responses it has already counted.
///
/// Deduplication is not optional. Claude Code rewrites a session's history into later files, so the
/// same response appears many times: on real logs, ~66 000 assistant lines carry only ~32 000
/// distinct responses, and summing the raw lines overstates output tokens by 2.76×.
struct TokenAccumulator {
    private(set) var totals: TokenTotals
    private var seen: Set<UInt64>

    init(state: TokenScanState = TokenScanState()) {
        totals = state.totals
        seen = state.seen
    }

    var seenHashes: Set<UInt64> { seen }

    /// Bytes that were not valid UTF-8, counted without going through `parse`.
    mutating func noteUnparsable() {
        totals.unparsableLines += 1
    }

    mutating func add(line: String) {
        switch TokenLogReader.parse(line: line) {
        case .entry(let entry):
            add(entry)
        case .notAnAssistantResponse:
            break
        case .unparsable:
            totals.unparsableLines += 1
        }
    }

    mutating func add(_ entry: TokenLogEntry) {
        guard seen.insert(StableHash.fnv1a(entry.dedupKey)).inserted else {
            totals.skippedDuplicates += 1
            return
        }
        totals.requests += 1
        totals.usage += entry.usage
        totals.byModel[entry.model, default: TokenUsage()] += entry.usage
        totals.contextOutputProduct += entry.contextOutputProduct
    }
}
