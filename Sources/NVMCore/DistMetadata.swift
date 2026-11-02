import Foundation
import zlib

/// One entry of https://nodejs.org/dist/index.json — the same metadata index
/// nvm itself reads. Used only to ENRICH the table (date, npm, per-version LTS,
/// security); every mutation still goes through nvm shell calls.
public struct DistEntry: Sendable, Decodable, Encodable {
    public let version: String
    public let date: String
    public let npm: String?
    public let lts: LTSStatus
    public let security: Bool

    public var ltsCodename: String? {
        if case .named(let name) = lts { return name }
        return nil
    }

    public var releaseDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: date)
    }

    enum CodingKeys: String, CodingKey { case version, date, npm, lts, security }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        date = try container.decode(String.self, forKey: .date)
        npm = try container.decodeIfPresent(String.self, forKey: .npm)
        lts = (try? container.decode(LTSStatus.self, forKey: .lts)) ?? .none
        security = (try? container.decode(Bool.self, forKey: .security)) ?? false
    }
}

public enum LTSStatus: Sendable, Equatable {
    case none
    case yes
    case named(String)
}

extension LTSStatus: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .none; return }
        if let name = try? container.decode(String.self), !name.isEmpty { self = .named(name); return }
        if let flag = try? container.decode(Bool.self) { self = flag ? .yes : .none; return }
        self = .none
    }
}

extension LTSStatus: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .none: try container.encode(false)
        case .yes: try container.encode(true)
        case .named(let name): try container.encode(name)
        }
    }
}

public enum DistFetchError: Error, Sendable {
    case http(Int)
}

public enum DistFetcher {
    public static let indexURL = URL(string: "https://nodejs.org/dist/index.json")!

    /// gzip-requested download (~600 KB over the wire vs ~5 MB raw). Setting
    /// Accept-Encoding by hand disables URLSession's auto-decompression, so we
    /// inflate the gzip magic bytes ourselves; an already-decoded body also works.
    public static func fetch() async throws -> [DistEntry] {
        var request = URLRequest(url: indexURL)
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw DistFetchError.http(http.statusCode)
        }
        let json = gunzipped(data) ?? data
        return try JSONDecoder().decode([DistEntry].self, from: json)
    }

    static func gunzipped(_ data: Data) -> Data? {
        guard data.count > 2, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else { return nil }

        var source = [UInt8](data)
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output = [UInt8]()
        output.reserveCapacity(source.count * 6)
        var consumed = 0
        while true {
            let capacity = 1 << 16
            var buffer = [UInt8](repeating: 0, count: capacity)
            let status: Int32 = source.withUnsafeMutableBytes { sourcePtr in
                buffer.withUnsafeMutableBytes { outPtr in
                    let input = sourcePtr.bindMemory(to: UInt8.self).baseAddress!.advanced(by: consumed)
                    let output = outPtr.bindMemory(to: UInt8.self).baseAddress!
                    stream.next_in = input
                    stream.avail_in = uInt(sourcePtr.count - consumed)
                    stream.next_out = output
                    stream.avail_out = uInt(capacity)
                    return inflate(&stream, Z_NO_FLUSH)
                }
            }
            output.append(contentsOf: buffer[0..<(capacity - Int(stream.avail_out))])
            consumed = Int(stream.total_in)
            if status == Z_STREAM_END { return Data(output) }
            guard status == Z_OK, stream.avail_out == 0 else { return nil }
        }
    }
}

/// On-disk cache so launch renders from local data instantly and works offline.
public struct DistCacheSnapshot: Sendable {
    public let fetchedAt: Date
    public let entries: [DistEntry]
}

public final class DistIndexStore: Sendable {
    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("dist-index.json")
    }

    public func load() -> DistCacheSnapshot? {
        struct Wire: Decodable { let fetchedAt: Date; let entries: [DistEntry] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let wire = try? decoder.decode(Wire.self, from: data) else { return nil }
        return DistCacheSnapshot(fetchedAt: wire.fetchedAt, entries: wire.entries)
    }

    public func save(_ entries: [DistEntry], fetchedAt: Date) {
        struct Wire: Encodable { let fetchedAt: Date; let entries: [DistEntry] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Wire(fetchedAt: fetchedAt, entries: entries)) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
