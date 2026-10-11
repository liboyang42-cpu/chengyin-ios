import Foundation

/// A saved earned name is the only authority for a medal card. Do not infer an award
/// from distance, shop counts, a current badge catalogue or a fallback threshold.
public struct RoamMedalShareSelection: Equatable, Identifiable {
    public enum Kind: String, CaseIterable { case journey, shop }
    /// Deliberately excludes route, POIs, photo references, account and server identifiers.
    public struct Card: Equatable {
        public let kind: Kind
        public let name: String
        public let recordedAt: Date?
    }
    public let record: RoamHistoryRecord
    public let card: Card
    public var id: Kind { card.kind }
    public init?(record: RoamHistoryRecord, kind: Kind) {
        let raw = kind == .journey ? record.medal : record.shopMedalName
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.record = record
        card = Card(kind: kind, name: raw, recordedAt: record.recordedAt)
    }
    public static func selections(for record: RoamHistoryRecord) -> [Self] {
        Kind.allCases.compactMap { Self(record: record, kind: $0) }
    }
}

/// Captured when the share presentation is created, not after an account changes.
/// Rechecks the complete stored record after an OS permission prompt, before any save.
@MainActor public struct RoamMedalShareAuthority {
    private let readerID: ObjectIdentifier
    private let scopeKey: String
    private let epoch: UInt64
    private let selection: RoamMedalShareSelection
    public init?(selection: RoamMedalShareSelection, reader: any RoamExperienceReading) {
        guard reader.isConfigured, let identity = reader.identity else { return nil }
        readerID = ObjectIdentifier(reader); scopeKey = identity.scope.storageKey
        epoch = identity.epoch; self.selection = selection
    }
    public func matchesOwner(_ reader: any RoamExperienceReading) -> Bool {
        guard reader.isConfigured, ObjectIdentifier(reader) == readerID,
              let identity = reader.identity else { return false }
        return identity.scope.storageKey == scopeKey && identity.epoch == epoch
    }
    public func isCurrent(_ reader: any RoamExperienceReading) -> Bool {
        guard matchesOwner(reader), let records = try? reader.history(), matchesOwner(reader) else { return false }
        let matching = records.filter { $0.ts == selection.record.ts }
        return matching.count == 1 && matching.first == selection.record
    }
}
