import Testing
import Foundation
@testable import ClaudeMonitor

/// A re-read of a file is invisible in the totals (dedup absorbs it), so tests assert on `skippedDuplicates`.
struct EnergyIncrementalScanTests {

    private func line(id: String, output: Int = 100, cacheRead: Int = 1000) -> String {
        """
        {"type":"assistant","requestId":"req_\(id)","uuid":"uuid-\(id)","timestamp":"2026-09-14T11:49:27.383Z",\
        "message":{"id":"msg_\(id)","model":"claude-opus-5","usage":{"input_tokens":1,\
        "cache_creation_input_tokens":0,"cache_read_input_tokens":\(cacheRead),"output_tokens":\(output)}}}
        """
    }

    /// Never torn down: swept at the start of the next run, so a failing test leaves its files for post-mortem.
    private func makeTempDirectory() throws -> URL {
        TestHistoryRoot.makeSubdirectory()
    }

    private func write(_ text: String, to file: URL) throws {
        try text.data(using: .utf8)!.write(to: file)
    }

    private func append(_ text: String, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: text.data(using: .utf8)!)
    }

    // MARK: - Offsets

    @Test func secondScanReadsOnlyWhatWasAppended() throws {
        let dir = try makeTempDirectory()
        let file = dir.appendingPathComponent("session.jsonl")
        try write(line(id: "A") + "\n", to: file)

        let first = TokenLogReader.scan(directory: dir)
        #expect(first.totals.requests == 1)
        #expect(first.totals.skippedDuplicates == 0)

        try append(line(id: "B") + "\n", to: file)
        let second = TokenLogReader.scan(directory: dir, state: first)

        #expect(second.totals.requests == 2)
        #expect(second.totals.skippedDuplicates == 0, "a non-zero count means the file was re-read from the start")
        #expect(second.totals.usage.output == 200)
    }

    @Test func scanWithNoNewBytesChangesNothing() throws {
        let dir = try makeTempDirectory()
        try write(line(id: "A") + "\n", to: dir.appendingPathComponent("s.jsonl"))

        let first = TokenLogReader.scan(directory: dir)
        let second = TokenLogReader.scan(directory: dir, state: first)
        #expect(second.totals == first.totals)
        #expect(second.offsets == first.offsets)
    }

    // MARK: - Partial lines

    /// Claude Code appends while the app reads, so a half-written final line is routine.
    @Test func partialFinalLineIsLeftForTheNextScanAndCountedOnce() throws {
        let dir = try makeTempDirectory()
        let file = dir.appendingPathComponent("s.jsonl")

        let whole = line(id: "B")
        let half = String(whole.prefix(whole.count / 2))
        try write(line(id: "A") + "\n" + half, to: file)

        let first = TokenLogReader.scan(directory: dir)
        #expect(first.totals.requests == 1)
        #expect(first.totals.unparsableLines == 0, "a partial tail must not be parsed at all, let alone counted as broken")

        try append(String(whole.dropFirst(whole.count / 2)) + "\n", to: file)
        let second = TokenLogReader.scan(directory: dir, state: first)

        #expect(second.totals.requests == 2)
        #expect(second.totals.skippedDuplicates == 0)
        #expect(second.totals.unparsableLines == 0)
    }

    @Test func offsetStopsAtTheLastNewlineNotTheEndOfFile() throws {
        let dir = try makeTempDirectory()
        let file = dir.appendingPathComponent("s.jsonl")
        let complete = line(id: "A") + "\n"
        try write(complete + "{\"type\":\"assistant\",\"message\":{\"usage\":{", to: file)

        let state = TokenLogReader.scan(directory: dir)
        #expect(state.offsets[TokenLogReader.offsetKey(for: file)] == UInt64(complete.utf8.count))
    }

    // MARK: - Rewritten files

    @Test func fileThatShrankIsReadFromTheStartAgain() throws {
        let dir = try makeTempDirectory()
        let file = dir.appendingPathComponent("s.jsonl")
        try write(line(id: "A") + "\n" + line(id: "B") + "\n", to: file)

        let first = TokenLogReader.scan(directory: dir)
        #expect(first.totals.requests == 2)

        try write(line(id: "C") + "\n", to: file)
        let second = TokenLogReader.scan(directory: dir, state: first)

        #expect(second.totals.requests == 3, "the stale offset pointed past the new end; it has to reset")
        #expect(second.offsets[TokenLogReader.offsetKey(for: file)] == UInt64((line(id: "C") + "\n").utf8.count))
    }

    // MARK: - Dedup across files

    /// Some duplicates span files, so per-file dedup is not enough.
    @Test func sameResponseInTwoFilesIsCountedOnce() throws {
        let dir = try makeTempDirectory()
        try write(line(id: "A") + "\n", to: dir.appendingPathComponent("one.jsonl"))
        try write(line(id: "A") + "\n", to: dir.appendingPathComponent("two.jsonl"))

        let state = TokenLogReader.scan(directory: dir)
        #expect(state.totals.requests == 1)
        #expect(state.totals.skippedDuplicates == 1)
    }

    @Test func nestedDirectoriesAreWalkedAndNonJsonlIgnored() throws {
        let dir = try makeTempDirectory()
        let nested = dir.appendingPathComponent("project/deeper")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try write(line(id: "A") + "\n", to: nested.appendingPathComponent("s.jsonl"))
        try write(line(id: "B") + "\n", to: dir.appendingPathComponent("notes.txt"))

        let state = TokenLogReader.scan(directory: dir)
        #expect(state.totals.requests == 1)
    }

    // MARK: - Persisted state

    /// `Hasher` is seeded per process, so dedup uses FNV-1a; pinned values catch a key that drifts between launches.
    @Test func dedupHashIsStableAcrossProcessesNotJustWithinOne() {
        #expect(StableHash.fnv1a("msg_ABC") == 12_345_039_227_892_135_049)
        #expect(StableHash.fnv1a("") == 14_695_981_039_346_656_037)
    }

    @Test func stateSurvivesARoundTripThroughJSON() throws {
        let dir = try makeTempDirectory()
        try write(line(id: "A") + "\n", to: dir.appendingPathComponent("s.jsonl"))
        let state = TokenLogReader.scan(directory: dir)

        let restored = try JSONDecoder().decode(TokenScanState.self, from: JSONEncoder().encode(state))
        #expect(restored == state)

        let again = TokenLogReader.scan(directory: dir, state: restored)
        #expect(again.totals.requests == 1)
        #expect(again.totals.skippedDuplicates == 0)
    }

    /// `FileManager`'s enumerator returns `/private/var/...` where a hand-built URL says `/var/...`;
    /// keyed on the raw path, every scan re-read everything and dedup hid it.
    @Test func offsetSurvivesTheDirectoryBeingSpelledDifferently() throws {
        let dir = try makeTempDirectory()
        try write(line(id: "A") + "\n", to: dir.appendingPathComponent("s.jsonl"))

        let viaPrivate = URL(fileURLWithPath: "/private" + dir.path)
        let first = TokenLogReader.scan(directory: viaPrivate)
        #expect(first.totals.requests == 1)

        let second = TokenLogReader.scan(directory: dir, state: first)
        #expect(second.totals.skippedDuplicates == 0, "the file was re-read, so the two spellings keyed differently")
        #expect(second.totals.requests == 1)
    }

    // MARK: - Product term

    /// Swapped-shape responses have equal column sums but different Σ(context × output).
    @Test func contextOutputProductIsAccumulatedNotDerivable() throws {
        let dir = try makeTempDirectory()
        try write(
            line(id: "A", output: 10, cacheRead: 1000) + "\n" + line(id: "B", output: 1000, cacheRead: 10) + "\n",
            to: dir.appendingPathComponent("s.jsonl")
        )
        let state = TokenLogReader.scan(directory: dir)
        // context = cacheRead + input (1): 1001×10 + 11×1000
        #expect(state.totals.contextOutputProduct == 21_010)
        let flat = state.totals.usage.contextRead * (state.totals.usage.output / state.totals.requests)
        #expect(flat != state.totals.contextOutputProduct, "a flat estimate must not coincide with the true product here")
    }
}
