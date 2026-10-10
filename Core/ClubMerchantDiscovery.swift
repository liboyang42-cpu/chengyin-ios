import Foundation
import Observation

/// P045's already-loaded merchant directory. Position is a presentation identity only;
/// merchant row IDs are never substituted for owner-member IDs or invitation grants.
public struct ClubMerchantDiscoveryRow: Equatable, Identifiable {
    public let id: Int
    public let fields: [String]
    public var name: String { fields[0].isEmpty ? fields[1] : fields[0] }
    public var activityTypes: String { fields[2] }
    public var address: String { fields[3] }
    public var city: String { fields[4] }
    public init(value: CoopFlowJSON, index: Int) throws {
        guard case .object = value else { throw CoopFlowFailure.malformed }
        fields = try ["name", "merchantName", "suitActivityTypes", "address", "city"].map { key in
            switch value[key] {
            case .null: return ""
            case .string(let text): return text
            default: throw CoopFlowFailure.malformed
            }
        }
        id = index
    }
}

/// Literal ECMAScript trim + toLowerCase + indexOf for the source's nullable text fields.
/// Do not use localized/fuzzy search, canonical equivalence, word splitting or sorting.
public struct ClubMerchantKeyword: Equatable {
    public let value: String
    private let needle: [UInt16]
    private static let whitespace = CharacterSet(charactersIn:
        "\u{0009}\u{000B}\u{000C}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{202F}\u{205F}\u{3000}\u{FEFF}\u{000A}\u{000D}\u{2028}\u{2029}")
    public init(_ query: String) {
        value = query.trimmingCharacters(in: Self.whitespace).lowercased()
        needle = Array(value.utf16)
    }
    public func filter(_ rows: [ClubMerchantDiscoveryRow]) -> [ClubMerchantDiscoveryRow] {
        guard !needle.isEmpty else { return rows }
        return rows.filter { row in
            let hay = Array(row.fields.joined(separator: " ").lowercased().utf16)
            guard hay.count >= needle.count else { return false }
            return (0...(hay.count - needle.count)).contains { start in
                hay[start..<(start + needle.count)].elementsEqual(needle)
            }
        }
    }
}

public struct ClubMerchantDiscoveryContext: Equatable {
    public let clubID: Int
    public let isOwner: Bool
    public let identity: ClubReadIdentity
    public let clubReaderID: ObjectIdentifier
    public let directoryReaderID: ObjectIdentifier
    public let session: CoopFlowSession?
    public let configured: Bool
    @MainActor public init(club: ClubRecord, clubReader: any ClubReading, reader: any CoopFlowReading) {
        clubID = club.id; isOwner = club.isOwner; identity = clubReader.clubIdentity
        clubReaderID = ObjectIdentifier(clubReader); directoryReaderID = ObjectIdentifier(reader)
        session = reader.session; configured = clubReader.isClubConfigured
    }
    public var canRead: Bool {
        isOwner && clubID > 0 && configured && identity.isSignedIn &&
            identity.accountID == session?.accountID && identity.epoch == session?.epoch
    }
    @MainActor fileprivate func matches(clubReader: any ClubReading, reader: any CoopFlowReading) -> Bool {
        canRead && clubReader.isClubConfigured && identity == clubReader.clubIdentity &&
            clubReaderID == ObjectIdentifier(clubReader) && directoryReaderID == ObjectIdentifier(reader) && session == reader.session
    }
}

/// A screen owns an exact rendered context, a visible-period permit and a read generation.
/// Context binding intentionally changes no observed properties during SwiftUI rendering.
/// This immediately fences old callbacks before the replacement .task/onDisappear runs.
@MainActor @Observable public final class ClubMerchantDiscoveryModel {
    public enum Phase: Equatable { case idle, loading, ready, failed, denied }
    public struct Permit: Equatable {
        fileprivate let context: ClubMerchantDiscoveryContext
        fileprivate let visibility: UUID
    }
    private var storedPhase: Phase = .idle
    private var storedRows: [ClubMerchantDiscoveryRow] = []
    private var storedKeyword = ""
    private var keywordRevision: UInt64 = 0
    @ObservationIgnored private var boundContext: ClubMerchantDiscoveryContext?
    @ObservationIgnored private var visibility: UUID?
    @ObservationIgnored private var generation = UUID()
    public init() {}
    public func bind(_ context: ClubMerchantDiscoveryContext) {
        guard boundContext != context else { return }
        boundContext = context; visibility = nil; generation = UUID()
    }
    public func activate(_ context: ClubMerchantDiscoveryContext) -> Permit? {
        guard !Task.isCancelled, boundContext == context, context.canRead else { return nil }
        if visibility == nil {
            visibility = UUID(); generation = UUID()
            storedKeyword = ""; storedRows = []; storedPhase = .idle
        }
        return permit(in: context)
    }
    public func permit(in context: ClubMerchantDiscoveryContext) -> Permit? {
        guard boundContext == context, context.canRead, let visibility else { return nil }
        return .init(context: context, visibility: visibility)
    }
    public func phase(in context: ClubMerchantDiscoveryContext) -> Phase {
        // Track the phase even before activation; otherwise the initial SwiftUI body
        // observes no phase property and may never redraw when its first read finishes.
        let phase = storedPhase
        return permit(in: context) != nil ? phase : .idle
    }
    public func keyword(in context: ClubMerchantDiscoveryContext) -> String {
        _ = keywordRevision
        return permit(in: context) != nil ? storedKeyword : ""
    }
    public func rows(in context: ClubMerchantDiscoveryContext) -> [ClubMerchantDiscoveryRow] {
        _ = keywordRevision
        guard phase(in: context) == .ready else { return [] }
        return ClubMerchantKeyword(storedKeyword).filter(storedRows)
    }
    public func hasLoadedRows(in context: ClubMerchantDiscoveryContext) -> Bool {
        phase(in: context) == .ready && !storedRows.isEmpty
    }
    public func setKeyword(_ value: String, permit: Permit?) {
        guard let permit, accepts(permit) else { return }
        storedKeyword = value
        // Swift String equality is canonical; a code-unit-different query must still redraw.
        keywordRevision &+= 1
    }
    public func leave(_ context: ClubMerchantDiscoveryContext) {
        guard boundContext == context else { return }
        visibility = nil; generation = UUID()
        storedRows = []; storedKeyword = ""; storedPhase = .idle
    }
    private func accepts(_ permit: Permit) -> Bool {
        boundContext == permit.context && visibility == permit.visibility && permit.context.canRead
    }
    public func load(clubReader: any ClubReading, reader: any CoopFlowReading, permit: Permit) async {
        // A delayed retry from a previous visibility must not even reset current state.
        guard !Task.isCancelled, accepts(permit), permit.context.matches(clubReader: clubReader, reader: reader) else { return }
        generation = UUID(); let request = generation
        storedRows = []; storedPhase = .loading
        let current = { [self] in
            accepts(permit) && generation == request && permit.context.matches(clubReader: clubReader, reader: reader)
        }
        defer { if generation == request, accepts(permit), storedPhase == .loading { storedPhase = .idle } }
        do {
            // Owner status is re-read through the existing guarded club reader before dispatch.
            let club = try await clubReader.clubDetail(id: permit.context.clubID, isCurrent: current)
            guard !Task.isCancelled, current() else { return }
            guard club.id == permit.context.clubID, club.isOwner else { storedPhase = .denied; return }
            let value = try await reader.read(.merchants(name: nil), isCurrent: current)
            guard !Task.isCancelled, current() else { return }
            guard let raw = value.rows else { throw CoopFlowFailure.malformed }
            let rows = try raw.enumerated().map { try ClubMerchantDiscoveryRow(value: $0.element, index: $0.offset) }
            storedRows = rows; storedPhase = .ready
        } catch {
            guard !Task.isCancelled, current() else { return }
            storedPhase = .failed
        }
    }
}
