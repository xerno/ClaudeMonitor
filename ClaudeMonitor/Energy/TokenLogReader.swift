import Foundation

/// Reads Claude Code's session logs (`~/.claude/projects/**/*.jsonl`, one JSON object per line).
///
/// Reads incrementally. A full scan of the archive takes seconds and, done naively — whole file into
/// a `String` — peaks at 173 MB resident, which is not acceptable in a menu bar app. Streaming fixed
/// size chunks with an `autoreleasepool` per file, and remembering a byte offset per file, brings a
/// repeat scan down to reading only what was appended.
enum TokenLogReader {
    enum ParseResult: Equatable {
        case entry(TokenLogEntry)
        /// A well-formed line that is not an assistant response — user turns, attachments, session
        /// metadata. Fifteen of the sixteen line types in real logs.
        case notAnAssistantResponse
        /// Unreadable JSON. Expected in normal operation, not only on corruption: Claude Code
        /// appends to these files while the app reads them.
        case unparsable
    }

    private static let assistantType = "assistant"
    private static let newline: UInt8 = 0x0A
    /// `"usage"` — the marker every assistant response carries and nothing cheap else does.
    private static let usageMarker = Data(#""usage""#.utf8)

    // MARK: - Scanning

    /// Reads everything appended since `state` was produced and returns the updated state.
    static func scan(directory: URL, state: TokenScanState = TokenScanState()) -> TokenScanState {
        var accumulator = TokenAccumulator(state: state)
        var offsets = state.offsets

        for file in logFiles(in: directory) {
            // Without this pool the Foundation temporaries from 1000+ files accumulate until the
            // whole scan finishes, which is what drives peak memory rather than any single file.
            autoreleasepool {
                let key = offsetKey(for: file)
                if let offset = readAppended(file: file, from: offsets[key] ?? 0, into: &accumulator) {
                    offsets[key] = offset
                }
            }
        }

        return TokenScanState(offsets: offsets, seen: accumulator.seenHashes, totals: accumulator.totals)
    }

    /// The key a file's byte offset is stored under.
    ///
    /// Normalising is not cosmetic. `FileManager`'s enumerator hands back `/private/var/...` while a
    /// URL built by hand from the same directory reads `/var/...`, and `resolvingSymlinksInPath`
    /// strips `/private` rather than adding it — so the two spellings never match. Left unnormalised,
    /// every offset lookup misses and the whole archive is silently re-read on each scan.
    static func offsetKey(for file: URL) -> String {
        file.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Returns the new offset, or nil when the file could not be opened.
    ///
    /// The offset only ever advances to a newline. Committing a mid-line offset would resume in the
    /// middle of a JSON object and corrupt every later read of that file.
    static func readAppended(file: URL, from offset: UInt64, into accumulator: inout TokenAccumulator) -> UInt64? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        // A file that shrank was rewritten, so the remembered offset means nothing.
        var start = offset > size ? 0 : offset
        guard start < size else { return start }
        try? handle.seek(toOffset: start)

        var carry = Data()
        while let chunk = try? handle.read(upToCount: Constants.Energy.chunkSize), !chunk.isEmpty {
            var buffer: Data
            if carry.isEmpty {
                buffer = chunk
            } else {
                buffer = carry
                buffer.append(chunk)
            }

            let consumed = consumeLines(in: buffer, into: &accumulator)
            start += UInt64(consumed)
            // Whatever follows the last newline is an unterminated line: either mid-write, or a file
            // that does not end in one. Rebasing into a fresh Data keeps the next chunk contiguous.
            carry = consumed == buffer.count
                ? Data()
                : Data(buffer[(buffer.startIndex + consumed)...])
        }
        return start
    }

    /// Feeds every complete line in `buffer` to `accumulator`, returning bytes consumed including
    /// the final newline.
    ///
    /// Newline and marker searches go through `memchr`/`memmem` rather than Swift loops on purpose.
    /// The release build hid how expensive per-byte Swift is: this scan took 3.7 s built with `-O`
    /// and 91 s with `-Onone`, which is what `install.sh` produces by default, so the app burned a
    /// minute and a half of CPU on its first scan. Pushing the search into libc removes the
    /// difference instead of relying on the optimiser to erase it.
    private static func consumeLines(in buffer: Data, into accumulator: inout TokenAccumulator) -> Int {
        var consumed = 0
        usageMarker.withUnsafeBytes { needle in
            guard let needleBase = needle.baseAddress, !needle.isEmpty else { return }
            buffer.withUnsafeBytes { hay in
                guard let hayBase = hay.baseAddress else { return }
                let total = hay.count
                var cursor = 0
                while cursor < total {
                    guard let hit = memchr(hayBase + cursor, Int32(newline), total - cursor) else { break }
                    let lineStart = hayBase + cursor
                    let length = UnsafeRawPointer(hit) - lineStart
                    if length > 0, memmem(lineStart, length, needleBase, needle.count) != nil {
                        if let text = String(bytes: UnsafeRawBufferPointer(start: lineStart, count: length), encoding: .utf8) {
                            accumulator.add(line: text)
                        } else {
                            accumulator.noteUnparsable()
                        }
                    }
                    cursor += length + 1
                    consumed = cursor
                }
            }
        }
        return consumed
    }

    static func logFiles(in directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == Constants.Energy.logFileExtension }
    }

    // MARK: - Parsing

    static func parse(line: String) -> ParseResult {
        guard line.contains(#""usage""#) else { return .notAnAssistantResponse }
        guard let data = line.data(using: .utf8),
              let decoded = try? JSONDecoder.iso8601WithFractionalSeconds.decode(RawLine.self, from: data)
        else { return .unparsable }
        return result(for: decoded)
    }

    private static func result(for decoded: RawLine) -> ParseResult {
        guard decoded.type == assistantType,
              let message = decoded.message,
              let usage = message.usage else { return .notAnAssistantResponse }

        // `message.id` is the primary key rather than `requestId`: it is present on strictly more
        // lines (31 331 distinct ids vs 31 307 request ids, and 23 assistant lines carry no
        // requestId at all). `uuid` is the last resort so a response is never counted twice merely
        // because both ids were missing.
        guard let key = message.id ?? decoded.requestId ?? decoded.uuid else { return .unparsable }

        return .entry(TokenLogEntry(
            dedupKey: key,
            model: message.model ?? "unknown",
            timestamp: decoded.timestamp,
            usage: TokenUsage(
                input: usage.inputTokens ?? 0,
                cacheCreation: usage.cacheCreationInputTokens ?? 0,
                cacheRead: usage.cacheReadInputTokens ?? 0,
                output: usage.outputTokens ?? 0
            )
        ))
    }

    // MARK: - Wire format
    //
    // Only the fields the energy estimate needs. `iterations`, `output_tokens_details`,
    // `cache_creation`, `service_tier` and `speed` are deliberately not decoded: `iterations` never
    // held more than one element in real logs and its sums matched the top-level counts, so reading
    // it could only ever double-count.

    private struct RawLine: Decodable {
        let type: String?
        let requestId: String?
        let uuid: String?
        let timestamp: Date?
        let message: RawMessage?
    }

    private struct RawMessage: Decodable {
        let id: String?
        let model: String?
        let usage: RawUsage?
    }

    private struct RawUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}
