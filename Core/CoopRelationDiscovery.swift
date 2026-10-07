import Foundation
import Observation

/// Display-only context. It cannot carry an invitation scope, recipient grant or terms.
public struct CoopRelationDisplayContext: Hashable {
    public let topicID: Int?
    public let topicName: String?
    public let chapterID: Int?
    public init(topicID: Int? = nil, topicName: String? = nil, chapterID: Int? = nil) {
        let topic = topicID.flatMap { $0 > 0 ? $0 : nil }
        self.topicID = topic
        self.topicName = topic == nil ? nil : Self.text(topicName)
        self.chapterID = topic == nil ? nil : chapterID.flatMap { $0 > 0 ? $0 : nil }
    }
    private static func text(_ value: String?) -> String? {
        value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}
public enum CoopRelationDiscoveryKind: String, CaseIterable, Hashable { case merchants, clubs }
public enum CoopRelationProfileRoute: Hashable {
    case merchant(PublicMerchantOwnerID)
    case club(Int)
}
public struct CoopRelationDiscoveryRow: Equatable, Identifiable {
    /// Response position, not a globally interchangeable business identity.
    public let id: Int
    public let kind: CoopRelationDiscoveryKind
    public let rowID: Int?
    public let ownerMemberID: PublicMerchantOwnerID?
    public let name: String
    public let address: String?
    public let city: String?
    public let category: String?
    public let cover: String?
    public let logo: String?
    public var route: CoopRelationProfileRoute? {
        guard let rowID else { return nil }
        switch kind {
        case .merchants: return ownerMemberID.map(CoopRelationProfileRoute.merchant)
        case .clubs: return .club(rowID)
        }
    }
    init?(value: CoopFlowJSON, kind: CoopRelationDiscoveryKind, index: Int) {
        guard case .object = value, let name = Self.text(value["name"]) else { return nil }
        id = index; self.kind = kind; self.name = name
        rowID = value["id"].integer.flatMap { $0 > 0 ? $0 : nil }
        ownerMemberID = kind == .merchants ? value["memberId"].integer.flatMap(PublicMerchantOwnerID.init) : nil
        address = Self.text(value["address"]); city = Self.text(value["city"])
        category = value["sysCategoryList"].rows?.compactMap { Self.text($0["categoryName"]) }.first
        cover = Self.text(value[kind == .merchants ? "coverImage" : "cover"])
        logo = Self.text(value["logo"])
    }
    private static func text(_ value: CoopFlowJSON) -> String? {
        guard let text = value.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
public struct CoopRelationDiscovery: Equatable {
    public let merchants: [CoopRelationDiscoveryRow]
    public let clubs: [CoopRelationDiscoveryRow]
    public let invalidMerchantCount: Int
    public let invalidClubCount: Int
    public init(_ value: CoopFlowJSON) throws {
        guard value["relations"].rows != nil,
              let merchants = value["discovery"]["merchants"].rows,
              let clubs = value["discovery"]["clubs"].rows else { throw CoopFlowFailure.malformed }
        self.merchants = merchants.enumerated().compactMap { CoopRelationDiscoveryRow(value: $0.element, kind: .merchants, index: $0.offset) }
        self.clubs = clubs.enumerated().compactMap { CoopRelationDiscoveryRow(value: $0.element, kind: .clubs, index: $0.offset) }
        invalidMerchantCount = merchants.count - self.merchants.filter { $0.route != nil }.count
        invalidClubCount = clubs.count - self.clubs.filter { $0.route != nil }.count
    }
    public func rows(_ kind: CoopRelationDiscoveryKind) -> [CoopRelationDiscoveryRow] { kind == .merchants ? merchants : clubs }
    public func hasInvalidRows(_ kind: CoopRelationDiscoveryKind) -> Bool { (kind == .merchants ? invalidMerchantCount : invalidClubCount) > 0 }
}
public struct CoopRelationProfileScope: Hashable {
    public let merchantScope: UUID
    public let clubIdentity: ClubReadIdentity
    public let sessionRevision: UInt64
    public let contentRevision: UInt64
    public init(merchantScope: UUID, clubIdentity: ClubReadIdentity, sessionRevision: UInt64, contentRevision: UInt64) {
        self.merchantScope = merchantScope; self.clubIdentity = clubIdentity
        self.sessionRevision = sessionRevision; self.contentRevision = contentRevision
    }
}
public struct CoopRelationProfileSelection: Identifiable, Hashable {
    public let id = UUID()
    public let route: CoopRelationProfileRoute
    public let displayContext: CoopRelationDisplayContext
    fileprivate let row: CoopRelationDiscoveryRow
    fileprivate let snapshotID: UUID
    fileprivate let destinationScope: CoopRelationProfileScope
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One accepted snapshot per exact reader/session. Refresh never leaves selectable stale cards.
@MainActor @Observable public final class CoopRelationDiscoveryModel {
    public private(set) var value: CoopRelationDiscovery?
    public private(set) var isLoading = false
    public private(set) var failed = false
    private var generation = UUID()
    private var snapshotID = UUID()
    private var loadedSession: CoopFlowSession?
    private var loadedReader: ObjectIdentifier?
    public init() {}
    public func isCurrent(reader: any CoopFlowReading) -> Bool {
        !isLoading && !failed && value != nil && reader.session != nil &&
            loadedSession == reader.session && loadedReader == ObjectIdentifier(reader)
    }
    public func selection(row: CoopRelationDiscoveryRow, reader: any CoopFlowReading,
                          scope: CoopRelationProfileScope, context: CoopRelationDisplayContext) -> CoopRelationProfileSelection? {
        guard isCurrent(reader: reader), value?.rows(row.kind).contains(row) == true, let route = row.route else { return nil }
        return .init(route: route, displayContext: context, row: row, snapshotID: snapshotID, destinationScope: scope)
    }
    public func isCurrent(_ selection: CoopRelationProfileSelection, reader: any CoopFlowReading,
                          scope: CoopRelationProfileScope, context: CoopRelationDisplayContext) -> Bool {
        isCurrent(reader: reader) && selection.snapshotID == snapshotID && selection.destinationScope == scope &&
            selection.displayContext == context && selection.row.route == selection.route &&
            value?.rows(selection.row.kind).contains(selection.row) == true
    }
    public func invalidate() {
        generation = UUID(); snapshotID = UUID(); value = nil; loadedSession = nil; loadedReader = nil
        isLoading = false; failed = false
    }
    public func leaveScreen() {
        generation = UUID()
        if isLoading { invalidate() }
    }
    public func load(reader: any CoopFlowReading, isCurrent: @escaping () -> Bool = { true }) async {
        // A canceled caller can outlive a newer read; it must not clear that state.
        guard !Task.isCancelled else { return }
        invalidate()
        guard isCurrent(), let session = reader.session else { return }
        let stamp = generation, identity = ObjectIdentifier(reader)
        isLoading = true
        // Only this generation owns its loading flag, including rejected/canceled replies.
        defer { if stamp == generation { isLoading = false } }
        do {
            let result = try CoopRelationDiscovery(await reader.read(.relations, isCurrent: { stamp == self.generation && isCurrent() }))
            guard !Task.isCancelled, isCurrent(), stamp == generation, reader.session == session else { return }
            value = result; loadedSession = session; loadedReader = identity; isLoading = false
        } catch {
            guard !Task.isCancelled, isCurrent(), stamp == generation, reader.session == session else { return }
            failed = true; isLoading = false
        }
    }
}
