import Foundation
/// Owner-bound source snapshot. Does not assert that any cleanup has executed.
public struct AccountDeregistrationImpact: Decodable, Equatable {
    public struct Item: Decodable, Equatable, Identifiable {
        public let key: String, value: String, source: String, effect: String
        public var id: String { key }
    }
    public let schemaVersion: Int, actorId: Int
    public let revision: String
    public let items: [Item], unknownCoverage: [String]
    public static func validRevision(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    public var confirmable: Bool { unknownCoverage.isEmpty && !items.contains { $0.value == "UNKNOWN" } }
    public func valid(for actor: Int) -> Bool {
        schemaVersion == 1 && actorId == actor && Self.validRevision(revision) && !items.isEmpty
        && items.count <= 128 && Set(items.map(\.key)).count == items.count
        && items.allSatisfy { !$0.key.isEmpty && !$0.source.isEmpty && !$0.effect.isEmpty && !$0.value.isEmpty }
    }
}
