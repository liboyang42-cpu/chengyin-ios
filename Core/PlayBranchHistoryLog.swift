import Foundation

/// Optional, bounded facts from the existing route-state response. This is not an
/// action ledger owned by the client; absent data must never be reconstructed.
public struct PlayBranchHistoryLog: Decodable, Equatable {
    public static let maximumEntries = 200
    public let entries: [PlayBranchHistoryEntry]
    public let sourceIndices: [Int]
    public let discardedEntryCount: Int

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        guard let count = container.count, count <= Self.maximumEntries else { throw APIError.malformedResponse }
        var entries: [PlayBranchHistoryEntry] = []
        var discarded = 0
        var indices: [Int] = []
        while !container.isAtEnd {
            // superDecoder advances past a bad row without decoding arbitrary nested payloads.
            let index = container.currentIndex
            let row = try container.superDecoder()
            if let entry = try? PlayBranchHistoryEntry(from: row) { entries.append(entry); indices.append(index) }
            else { discarded += 1 }
        }
        self.entries = entries; sourceIndices = indices; discardedEntryCount = discarded
    }
}

public struct PlayBranchHistoryEntry: Decodable, Equatable {
    public let fromNodeID: Int
    public let toNodeID: Int
    /// Kept for contract fidelity only. It is neither row identity nor a UI action.
    public let edgeID: String?
    public let recordedAt: PlayBranchHistoryTime?
    private enum CodingKeys: String, CodingKey { case fromNodeId, toNodeId, edgeId, at }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func nodeID(_ key: CodingKeys) throws -> Int {
            if let value = try? c.decode(Int.self, forKey: key), value > 0 { return value }
            if let value = try? c.decode(String.self, forKey: key), value.utf8.count <= 19,
               !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
               let id = Int(value), id > 0 { return id }
            throw APIError.malformedResponse
        }
        fromNodeID = try nodeID(.fromNodeId); toNodeID = try nodeID(.toNodeId)
        if let value = try? c.decode(String.self, forKey: .edgeId), !value.isEmpty,
           value.utf8.count <= 128, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            edgeID = value
        } else { edgeID = nil }
        recordedAt = try? c.decode(PlayBranchHistoryTime.self, forKey: .at)
    }
}

/// Numeric Date values are milliseconds, never guessed to be seconds. Zone-less
/// server dates stay verbatim; the device timezone is never applied to them.
public struct PlayBranchHistoryTime: Decodable, Equatable {
    public let displayText: String
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let milliseconds = try? c.decode(Int64.self), milliseconds > 0, milliseconds <= 253_402_300_799_999 {
            let date = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
            let formatter = Self.wallClockFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
            displayText = formatter.string(from: date)
            return
        }
        guard let text = try? c.decode(String.self), text.utf8.count <= 64 else { throw APIError.malformedResponse }
        if text.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil {
            let formatter = Self.wallClockFormatter()
            guard let date = formatter.date(from: text), formatter.string(from: date) == text,
                  date.timeIntervalSince1970 > 0 else { throw APIError.malformedResponse }
        } else {
            guard text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { throw APIError.malformedResponse }
            let wallText = String(text.prefix(19)).replacingOccurrences(of: "T", with: " ")
            let wallFormatter = Self.wallClockFormatter()
            guard let wallDate = wallFormatter.date(from: wallText), wallFormatter.string(from: wallDate) == wallText else { throw APIError.malformedResponse }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = text.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
            guard let date = formatter.date(from: text), date.timeIntervalSince1970 > 0,
                  date.timeIntervalSince1970 <= 253_402_300_799.999 else { throw APIError.malformedResponse }
        }
        displayText = text
    }
    private static func wallClockFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        return formatter
    }
}
