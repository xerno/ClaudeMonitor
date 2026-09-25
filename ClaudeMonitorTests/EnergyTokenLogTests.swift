import Testing
import Foundation
@testable import ClaudeMonitor

/// Token accounting from Claude Code's session logs. The whole energy estimate is built on these
/// numbers, and the failure mode is silent: a wrong total still renders as a plausible reading.
struct EnergyTokenLogTests {

    // A real assistant line, trimmed to the fields that matter but keeping the shapes that caused
    // trouble: `iterations` mirroring the top-level counts, and `thinking_tokens` inside
    // `output_tokens_details`. Both must be ignored.
    private let assistantLine = """
    {"type":"assistant","requestId":"req_ABC","uuid":"uuid-1","timestamp":"2026-09-14T11:49:27.383Z",\
    "isSidechain":false,"message":{"id":"msg_ABC","model":"claude-opus-5","role":"assistant",\
    "usage":{"input_tokens":2,"cache_creation_input_tokens":63195,"cache_read_input_tokens":27949,\
    "output_tokens":197,"output_tokens_details":{"thinking_tokens":76},\
    "cache_creation":{"ephemeral_1h_input_tokens":63195,"ephemeral_5m_input_tokens":0},\
    "service_tier":"standard","iterations":[{"input_tokens":2,"output_tokens":197,\
    "cache_read_input_tokens":27949,"cache_creation_input_tokens":63195,"type":"message","model":null}],\
    "speed":"standard"}}}
    """

    private func entry(from line: String) throws -> TokenLogEntry {
        guard case .entry(let entry) = TokenLogReader.parse(line: line) else {
            throw TestFailure.notAnEntry
        }
        return entry
    }

    private enum TestFailure: Error { case notAnEntry }

    // MARK: - Parsing

    @Test func parsesTheFourTokenCountsFromARealLine() throws {
        let parsed = try entry(from: assistantLine)
        #expect(parsed.usage.input == 2)
        #expect(parsed.usage.cacheCreation == 63195)
        #expect(parsed.usage.cacheRead == 27949)
        #expect(parsed.usage.output == 197)
        #expect(parsed.model == "claude-opus-5")
        #expect(parsed.dedupKey == "msg_ABC")
    }

    /// `thinking_tokens` (76) sits inside `output_tokens` (197). Adding it would report 273.
    @Test func thinkingTokensAreNotCountedOnTopOfOutput() throws {
        let parsed = try entry(from: assistantLine)
        #expect(parsed.usage.output == 197)
        #expect(parsed.usage.total == 2 + 63195 + 27949 + 197)
    }

    /// `iterations` repeats the same counts. Reading it would double every number on the line.
    @Test func iterationsAreNotAddedToTheTopLevelCounts() throws {
        let parsed = try entry(from: assistantLine)
        #expect(parsed.usage.cacheRead == 27949, "27949 doubled to 55898 would mean iterations leaked in")
    }

    @Test func timestampIsParsedWithFractionalSeconds() throws {
        let parsed = try entry(from: assistantLine)
        let expected = try Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse("2026-09-14T11:49:27.383Z")
        #expect(parsed.timestamp == expected)
    }

    // MARK: - Lines that are not responses

    @Test func nonAssistantLinesAreSkippedNotCountedAsBroken() {
        let userLine = #"{"type":"user","message":{"role":"user","content":"hi"}}"#
        #expect(TokenLogReader.parse(line: userLine) == .notAnAssistantResponse)
    }

    @Test func assistantLineWithoutUsageIsSkipped() {
        let line = #"{"type":"assistant","message":{"id":"msg_X","model":"claude-opus-5"}}"#
        #expect(TokenLogReader.parse(line: line) == .notAnAssistantResponse)
    }

    /// Claude Code appends while the app reads, so a half-written final line is normal traffic.
    @Test func truncatedLineIsReportedAsUnparsableRatherThanCrashing() {
        let truncated = String(assistantLine.dropLast(40))
        #expect(TokenLogReader.parse(line: truncated) == .unparsable)
    }

    @Test func accumulatorCountsUnparsableLinesWithoutDerailingTheTotals() {
        var acc = TokenAccumulator()
        acc.add(line: String(assistantLine.dropLast(40)))
        acc.add(line: assistantLine)
        #expect(acc.totals.unparsableLines == 1)
        #expect(acc.totals.requests == 1)
        #expect(acc.totals.usage.output == 197)
    }

    // MARK: - Deduplication

    /// The headline risk: raw summing overstates output tokens by 2.76× on real logs.
    @Test func sameResponseSeenTwiceIsCountedOnce() {
        var acc = TokenAccumulator()
        acc.add(line: assistantLine)
        acc.add(line: assistantLine)
        #expect(acc.totals.requests == 1)
        #expect(acc.totals.skippedDuplicates == 1)
        #expect(acc.totals.usage.output == 197, "394 would mean the duplicate was summed in")
        #expect(acc.totals.usage.cacheRead == 27949)
    }

    @Test func differentResponsesBothCount() {
        var acc = TokenAccumulator()
        acc.add(line: assistantLine)
        acc.add(line: assistantLine.replacingOccurrences(of: "msg_ABC", with: "msg_DEF"))
        #expect(acc.totals.requests == 2)
        #expect(acc.totals.skippedDuplicates == 0)
        #expect(acc.totals.usage.output == 394)
    }

    /// 23 assistant lines in the real logs carry no requestId, so the key has to fall through.
    @Test func dedupFallsBackToRequestIdThenUuidWhenMessageIdIsMissing() throws {
        let noMessageId = """
        {"type":"assistant","requestId":"req_ONLY","uuid":"uuid-9","message":{"model":"claude-opus-5",\
        "usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        #expect(try entry(from: noMessageId).dedupKey == "req_ONLY")

        let uuidOnly = """
        {"type":"assistant","uuid":"uuid-9","message":{"model":"claude-opus-5",\
        "usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        #expect(try entry(from: uuidOnly).dedupKey == "uuid-9")
    }

    // MARK: - Per-model split

    /// Energy per token differs by model size, so the totals have to stay separable by model.
    @Test func totalsAreSplitPerModel() {
        var acc = TokenAccumulator()
        acc.add(line: assistantLine)
        acc.add(line: assistantLine
            .replacingOccurrences(of: "msg_ABC", with: "msg_SON")
            .replacingOccurrences(of: "claude-opus-5", with: "claude-sonnet-5"))
        #expect(acc.totals.byModel["claude-opus-5"]?.output == 197)
        #expect(acc.totals.byModel["claude-sonnet-5"]?.output == 197)
        #expect(acc.totals.usage.output == 394)
    }

    @Test func missingModelIsLabelledRatherThanDropped() throws {
        let noModel = """
        {"type":"assistant","uuid":"u1","message":{"id":"msg_NM",\
        "usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
        #expect(try entry(from: noModel).model == "unknown")
    }

    // MARK: - Arithmetic

    @Test func usageAddsFieldwise() {
        let a = TokenUsage(input: 1, cacheCreation: 2, cacheRead: 3, output: 4)
        let b = TokenUsage(input: 10, cacheCreation: 20, cacheRead: 30, output: 40)
        #expect(a + b == TokenUsage(input: 11, cacheCreation: 22, cacheRead: 33, output: 44))
        #expect((a + b).total == 110)
    }

    @Test func emptyUsageIsZero() {
        #expect(TokenUsage().total == 0)
        #expect(TokenAccumulator().totals == TokenTotals())
    }
}
