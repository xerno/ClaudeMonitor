import Foundation

/// No `thinking` field on purpose: `output_tokens_details.thinking_tokens` is a subset of
/// `output_tokens`, so counting it separately would double-count.
///
/// `input`, `cacheCreation` and `cacheRead` are disjoint (`input_tokens` counts only uncached tokens).
struct TokenUsage: Equatable, Sendable, Codable {
    var input: Int = 0
    var cacheCreation: Int = 0
    var cacheRead: Int = 0
    var output: Int = 0

    var total: Int { input + cacheCreation + cacheRead + output }

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

struct TokenLogEntry: Equatable, Sendable {
    let dedupKey: String
    let model: String
    let timestamp: Date?
    let usage: TokenUsage

    /// Energy scales with context × output: every generated token re-reads the whole context.
    var contextOutputProduct: Int { usage.contextRead * usage.output }
}

// MARK: - Totals

struct TokenTotals: Equatable, Sendable, Codable {
    var usage = TokenUsage()
    var requests = 0
    var byModel: [String: TokenUsage] = [:]
    var skippedDuplicates = 0
    var unparsableLines = 0
    /// Σ(context × output); not recoverable from the sums above.
    var contextOutputProduct = 0
}

// MARK: - Scan state

/// `hashValue` is seeded per process, so it cannot back the persisted dedup set.
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

/// `seen` holds 64-bit hashes, not id strings: 8 bytes per response instead of ~40, with a
/// collision chance around 3e-14 at ~32 000 responses.
struct TokenScanState: Equatable, Codable, Sendable {
    /// Bytes consumed per log file; only ever ends after a newline.
    var offsets: [String: UInt64] = [:]
    var seen: Set<UInt64> = []
    var totals = TokenTotals()
}

// MARK: - Accumulator

/// Deduplicates because Claude Code rewrites a session's history into later files; summing raw
/// lines overstates output tokens by 2.76×.
struct TokenAccumulator {
    private(set) var totals: TokenTotals
    private var seen: Set<UInt64>

    init(state: TokenScanState = TokenScanState()) {
        totals = state.totals
        seen = state.seen
    }

    var seenHashes: Set<UInt64> { seen }

    /// For lines that are not valid UTF-8 and so never reach `parse`.
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
