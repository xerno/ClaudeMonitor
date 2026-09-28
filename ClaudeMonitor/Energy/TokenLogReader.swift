import Foundation

/// Reads Claude Code's session logs (`~/.claude/projects/**/*.jsonl`, one JSON object per line).
///
/// Streams chunks: reading whole files into a `String` peaked at 173 MB resident.
enum TokenLogReader {
    enum ParseResult: Equatable {
        case entry(TokenLogEntry)
        case notAnAssistantResponse
        /// Expected in normal operation, not only on corruption.
        case unparsable
    }

    private static let assistantType = "assistant"
    private static let newline: UInt8 = 0x0A
    /// Every assistant response line contains it.
    private static let usageMarker = Data(#""usage""#.utf8)

    // MARK: - Scanning

    static func scan(directory: URL, state: TokenScanState = TokenScanState()) -> TokenScanState {
        var accumulator = TokenAccumulator(state: state)
        var offsets = state.offsets

        for file in logFiles(in: directory) {
            // Without the pool, Foundation temporaries from every file accumulate until the scan ends.
            autoreleasepool {
                let key = offsetKey(for: file)
                if let offset = readAppended(file: file, from: offsets[key] ?? 0, into: &accumulator) {
                    offsets[key] = offset
                }
            }
        }

        return TokenScanState(offsets: offsets, seen: accumulator.seenHashes, totals: accumulator.totals)
    }

    /// Normalised because `FileManager`'s enumerator yields `/private/var/...` while hand-built URLs
    /// read `/var/...`; `resolvingSymlinksInPath` strips `/private`, so both map to one key.
    /// Otherwise every lookup misses and each scan re-reads the whole archive.
    static func offsetKey(for file: URL) -> String {
        file.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// The offset only advances to a newline: a mid-line offset would resume inside a JSON object.
    static func readAppended(file: URL, from offset: UInt64, into accumulator: inout TokenAccumulator) -> UInt64? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        // A shrunk file was rewritten; the stored offset is stale.
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
            // The unterminated tail (mid-write, or no trailing newline) carries into the next chunk.
            carry = consumed == buffer.count
                ? Data()
                : Data(buffer[(buffer.startIndex + consumed)...])
        }
        return start
    }

    /// Returns bytes consumed, including the last newline.
    ///
    /// `memchr`/`memmem` instead of Swift byte loops, which took 3.7 s at `-O` but 91 s at `-Onone`
    /// (what `install.sh` builds by default).
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

        // `message.id` before `requestId`: present on more lines (23 assistant lines have no
        // requestId). `uuid` is the last resort.
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
    // `iterations` is deliberately not decoded: its sums match the top-level counts, so reading it
    // would double-count.

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
