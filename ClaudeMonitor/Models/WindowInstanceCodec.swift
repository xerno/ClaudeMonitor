import Foundation

/// On-disk format v3: binary delta + zigzag varint, uncompressed (48% smaller and ~150x faster
/// than the lzma'd JSON v1). The CRC32 makes a truncated or corrupted file fail with a typed
/// error instead of decoding into partial data.
///
/// Layout (little-endian):
/// 1. Magic: 4 ASCII bytes ("CMH2")
/// 2. Format version: UInt16 (3)
/// 3. Metadata length: UInt32, then that many bytes of JSON (id, resetsAt, firstObservedAt, events)
/// 4. Sample count: UInt32
/// 5. Sample payload: first sample as absolute epoch seconds (uvarint) + absolute utilization
///    (uvarint); each later sample as zigzag varints of the timestamp and utilization deltas.
/// 6. CRC32: UInt32 over fields 2-5, i.e. everything between the magic and this field.
enum WindowInstanceCodecError: Error, Equatable, Sendable {
    case magicMismatch
    case versionMismatch(UInt16)
    case truncated
    case crcMismatch
    case trailingBytes
    case varintTooLong
}

/// Identity-agnostic: the caller attaches `storageIdentity` from the filename.
struct DecodedWindowInstance: Sendable {
    let id: UUID
    let resetsAt: Date?
    let firstObservedAt: Date
    let events: [UsageEvent]
    let samples: [UtilizationSample]
}

enum WindowInstanceCodec {
    static let magic: [UInt8] = Array("CMH2".utf8)
    static let formatVersion: UInt16 = 3
    private static let legacyV2FormatVersion: UInt16 = 2

    private struct Metadata: Codable {
        let id: UUID
        let resetsAt: Date?
        let firstObservedAt: Date
        let events: [UsageEvent]
    }

    // MARK: - Encode

    static func encode(
        id: UUID,
        resetsAt: Date?,
        firstObservedAt: Date,
        events: [UsageEvent],
        samples: [UtilizationSample]
    ) throws -> Data {
        let metadata = Metadata(id: id, resetsAt: resetsAt, firstObservedAt: firstObservedAt, events: events)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let metadataBytes = try encoder.encode(metadata)

        var payload = Data()
        var previous: UtilizationSample?
        for sample in samples {
            let epoch = Int64(sample.timestamp.timeIntervalSince1970)
            if let previous {
                let prevEpoch = Int64(previous.timestamp.timeIntervalSince1970)
                appendUVarint(zigzagEncode(epoch - prevEpoch), to: &payload)
                appendUVarint(zigzagEncode(Int64(sample.utilization - previous.utilization)), to: &payload)
            } else {
                appendUVarint(UInt64(epoch), to: &payload)
                appendUVarint(UInt64(sample.utilization), to: &payload)
            }
            previous = sample
        }

        var body = Data()
        appendLittleEndian(formatVersion, to: &body)
        appendLittleEndian(UInt32(metadataBytes.count), to: &body)
        body.append(metadataBytes)
        appendLittleEndian(UInt32(samples.count), to: &body)
        body.append(payload)

        var file = Data()
        file.append(contentsOf: magic)
        file.append(body)
        appendLittleEndian(CRC32.checksum(body), to: &file)
        return file
    }

    // MARK: - Decode

    /// Data without the magic is legacy v1: a bare `[[epoch,util],...]` JSON array, optionally
    /// LZMA-compressed.
    static func decode(_ data: Data) throws -> DecodedWindowInstance {
        if data.count >= 4, Array(data.prefix(4)) == magic {
            return try decodeV2OrV3(data)
        }
        return try decodeLegacy(data)
    }

    private static func decodeV2OrV3(_ data: Data) throws -> DecodedWindowInstance {
        guard data.count >= 6 else { throw WindowInstanceCodecError.truncated }
        let versionStart = data.index(data.startIndex, offsetBy: 4)
        let versionEnd = data.index(versionStart, offsetBy: 2)
        let version = try readLittleEndian(UInt16.self, data.subdata(in: versionStart..<versionEnd))

        if version == legacyV2FormatVersion {
            return try decodeLayoutV2(data, offsetAfterVersion: 6)
        }
        if version == formatVersion {
            return try decodeLayoutV3(data)
        }
        throw WindowInstanceCodecError.versionMismatch(version)
    }

    /// v2: the CRC (stored before the payload) covers only metadata + payload, so a corrupted
    /// `sampleCount` silently truncates the samples. Still read, or existing user history would be lost.
    private static func decodeLayoutV2(_ data: Data, offsetAfterVersion: Int) throws -> DecodedWindowInstance {
        var offset = offsetAfterVersion

        func readBytes(_ count: Int) throws -> Data {
            guard count >= 0, offset + count <= data.count else { throw WindowInstanceCodecError.truncated }
            let start = data.index(data.startIndex, offsetBy: offset)
            let end = data.index(start, offsetBy: count)
            offset += count
            return data.subdata(in: start..<end)
        }

        let metaLen = Int(try readLittleEndian(UInt32.self, readBytes(4)))
        let metadataBytes = try readBytes(metaLen)

        let sampleCount = Int(try readLittleEndian(UInt32.self, readBytes(4)))
        let storedCRC = try readLittleEndian(UInt32.self, readBytes(4))

        let payloadStart = data.index(data.startIndex, offsetBy: offset)
        let payload = data.subdata(in: payloadStart..<data.endIndex)

        guard CRC32.checksum(metadataBytes + payload) == storedCRC else {
            throw WindowInstanceCodecError.crcMismatch
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let metadata = try decoder.decode(Metadata.self, from: metadataBytes)

        var payloadOffset = 0
        let samples = try decodeSamples(count: sampleCount, from: payload, offset: &payloadOffset)

        return DecodedWindowInstance(
            id: metadata.id,
            resetsAt: metadata.resetsAt,
            firstObservedAt: metadata.firstObservedAt,
            events: metadata.events,
            samples: samples
        )
    }

    private static func decodeLayoutV3(_ data: Data) throws -> DecodedWindowInstance {
        guard data.count >= 4 + 4 else { throw WindowInstanceCodecError.truncated }
        let bodyStart = data.index(data.startIndex, offsetBy: 4)
        let crcFieldStart = data.index(data.endIndex, offsetBy: -4)
        guard bodyStart <= crcFieldStart else { throw WindowInstanceCodecError.truncated }
        let body = data.subdata(in: bodyStart..<crcFieldStart)
        let storedCRC = try readLittleEndian(UInt32.self, data.subdata(in: crcFieldStart..<data.endIndex))

        guard CRC32.checksum(body) == storedCRC else {
            throw WindowInstanceCodecError.crcMismatch
        }

        var offset = 0
        func readBytes(_ count: Int) throws -> Data {
            guard count >= 0, offset + count <= body.count else { throw WindowInstanceCodecError.truncated }
            let start = body.index(body.startIndex, offsetBy: offset)
            let end = body.index(start, offsetBy: count)
            offset += count
            return body.subdata(in: start..<end)
        }

        let version = try readLittleEndian(UInt16.self, readBytes(2))
        guard version == formatVersion else { throw WindowInstanceCodecError.versionMismatch(version) }

        let metaLen = Int(try readLittleEndian(UInt32.self, readBytes(4)))
        let metadataBytes = try readBytes(metaLen)

        let sampleCount = Int(try readLittleEndian(UInt32.self, readBytes(4)))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let metadata = try decoder.decode(Metadata.self, from: metadataBytes)

        let payload = try readBytes(body.count - offset)
        var payloadOffset = 0
        let samples = try decodeSamples(count: sampleCount, from: payload, offset: &payloadOffset)
        guard payloadOffset == payload.count else { throw WindowInstanceCodecError.trailingBytes }

        return DecodedWindowInstance(
            id: metadata.id,
            resetsAt: metadata.resetsAt,
            firstObservedAt: metadata.firstObservedAt,
            events: metadata.events,
            samples: samples
        )
    }

    private static func decodeSamples(count: Int, from payload: Data, offset: inout Int) throws -> [UtilizationSample] {
        var samples: [UtilizationSample] = []
        samples.reserveCapacity(count)
        var lastEpoch: Int64 = 0
        var lastUtil = 0
        for i in 0..<count {
            if i == 0 {
                lastEpoch = Int64(try readUVarint(payload, at: &offset))
                lastUtil = Int(try readUVarint(payload, at: &offset))
            } else {
                lastEpoch += zigzagDecode(try readUVarint(payload, at: &offset))
                lastUtil += Int(zigzagDecode(try readUVarint(payload, at: &offset)))
            }
            samples.append(UtilizationSample(utilization: lastUtil, timestamp: Date(timeIntervalSince1970: Double(lastEpoch))))
        }
        return samples
    }

    private static func decodeLegacy(_ data: Data) throws -> DecodedWindowInstance {
        let jsonData: Data
        if let decompressed = try? (data as NSData).decompressed(using: .lzma) as Data {
            jsonData = decompressed
        } else {
            jsonData = data
        }
        guard let samples = UsageHistory.decodeCompact(jsonData) else {
            throw WindowInstanceCodecError.truncated
        }
        return DecodedWindowInstance(
            id: UUID(),
            resetsAt: nil,
            firstObservedAt: samples.first?.timestamp ?? Date(),
            events: [],
            samples: samples
        )
    }

    // MARK: - Varint helpers

    private static func appendUVarint(_ value: UInt64, to data: inout Data) {
        var v = value
        while true {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            data.append(byte)
            if v == 0 { break }
        }
    }

    /// A UInt64 needs at most 10 varint bytes (10 * 7 >= 64). A longer chain is corruption; past
    /// it `<< shift` yields 0 and would silently drop bits.
    private static let maxVarintBytes = 10

    private static func readUVarint(_ data: Data, at offset: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var bytesRead = 0
        while true {
            guard offset < data.count else { throw WindowInstanceCodecError.truncated }
            guard bytesRead < maxVarintBytes else { throw WindowInstanceCodecError.varintTooLong }
            let byte = data[data.startIndex + offset]
            offset += 1
            bytesRead += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return result
    }

    private static func zigzagEncode(_ value: Int64) -> UInt64 {
        UInt64(bitPattern: (value << 1) ^ (value >> 63))
    }

    private static func zigzagDecode(_ value: UInt64) -> Int64 {
        Int64(bitPattern: value >> 1) ^ -Int64(bitPattern: value & 1)
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func readLittleEndian<T: FixedWidthInteger>(_ type: T.Type, _ bytes: Data) throws -> T {
        guard bytes.count == MemoryLayout<T>.size else { throw WindowInstanceCodecError.truncated }
        var value: T = 0
        _ = withUnsafeMutableBytes(of: &value) { dest in
            bytes.copyBytes(to: dest, count: MemoryLayout<T>.size)
        }
        return T(littleEndian: value)
    }
}

/// Standard CRC-32 (IEEE 802.3).
enum CRC32 {
    private static let table: [UInt32] = (0...255).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
