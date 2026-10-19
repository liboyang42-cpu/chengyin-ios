import Foundation
import Observation

/// The nearby source uses merchant row id for row identity and memberId for the public home.
public struct NearbyMerchantRow: Identifiable, Equatable {
    public let id: Int
    public let memberID: Int?
    public let name: String
    public let address: String?
    public let distance: Double?
    /// Source `pages/coop/nearby`: only unregistered leads the server marks callable show a call action.
    public let phone: String?
    /// Rows the server marks `coopOpen == 0` are not offered (source filter).
    public let cooperationClosed: Bool
    public var callablePhone: String? { memberID == nil ? phone : nil }
    public init(_ value: CoopFlowJSON) throws {
        guard let id = value["id"].integer, id > 0, let name = value["name"].text, !name.isEmpty else { throw CoopFlowFailure.malformed }
        self.id = id; self.name = name; address = value["address"].text
        memberID = value["memberId"].integer.flatMap { $0 > 0 ? $0 : nil }
        distance = value["distance"].text.flatMap(Double.init).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let dial = value["phone"].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        phone = value["canCall"].flag == true && !dial.isEmpty ? dial : nil
        cooperationClosed = value["coopOpen"].integer == 0
    }
    /// Distance ascending with unknown distances last; server order breaks ties.
    public static func ordered(_ rows: [NearbyMerchantRow]) -> [NearbyMerchantRow] {
        rows.filter { !$0.cooperationClosed }.enumerated().sorted { lhs, rhs in
            switch (lhs.element.distance, rhs.element.distance) {
            case let (l?, r?): return l != r ? l < r : lhs.offset < rhs.offset
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}

@available(macOS 14.0, *)
@MainActor @Observable public final class NearbyMerchantCoordinator {
    /// Navigation owns an explicit result selection, independent of the rendered row.
    public struct PublicHomeSelection: Hashable, Identifiable {
        public let id: UUID
        public let target: PublicMerchantHomeTarget
        fileprivate let rowID: Int
        fileprivate let generation: UInt64
    }
    public enum Phase: Equatable { case idle, unavailable, consentRequired, locating, loading, ready, locationFailed, failed }
    public private(set) var phase: Phase = .idle
    private var storedRows: [NearbyMerchantRow] = []
    private var owner: CoopFlowSession?
    private var generation: UInt64 = 0
    private let reader: any CoopFlowReading
    private let location: any RoamDeviceLocationProviding
    private let approved: () -> Bool
    private let now: () -> Date
    public var available: Bool { reader.session != nil && approved() }
    public var rows: [NearbyMerchantRow] { owner != nil && reader.session == owner && approved() ? storedRows : [] }
    public var isBusy: Bool { phase == .locating || phase == .loading }
    public func publicHomeSelection(rowID: Int) -> PublicHomeSelection? {
        guard phase == .ready, available,
              let row = rows.first(where: { $0.id == rowID }),
              let memberID = row.memberID, let ownerID = PublicMerchantOwnerID(memberID) else { return nil }
        return .init(id: UUID(), target: .ownerMemberID(ownerID), rowID: rowID, generation: generation)
    }
    public func isCurrent(_ selection: PublicHomeSelection) -> Bool {
        guard phase == .ready, available, selection.generation == generation,
              let row = rows.first(where: { $0.id == selection.rowID }),
              let memberID = row.memberID, let ownerID = PublicMerchantOwnerID(memberID) else { return false }
        return selection.target == .ownerMemberID(ownerID)
    }
    public init(reader: any CoopFlowReading, location: any RoamDeviceLocationProviding,
                approved: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        self.reader = reader; self.location = location; self.approved = approved; self.now = now
    }
    /// Only the explicit location-and-search action calls this method. Opening is inert.
    public func search(purposeAccepted: Bool) async {
        guard !isBusy else { return }
        guard purposeAccepted else { phase = .consentRequired; return }
        guard available, let session = reader.session else { phase = .unavailable; return }
        generation &+= 1; let stamp = generation
        owner = nil; storedRows = []; phase = .locating
        defer {
            if stamp == generation {
                location.stop()
                if Task.isCancelled || !approved() || reader.session != session {
                    storedRows = []; owner = nil; phase = .idle
                }
            }
        }
        do {
            let fix = try await location.currentFix()
            guard !Task.isCancelled, stamp == generation, approved(), reader.session == session else { return }
            let converted = try RuntimeLocationProjection.gcj02(fix, now: now())
            phase = .loading
            let result = try await reader.read(.nearby(longitude: converted.coordinate.longitude, latitude: converted.coordinate.latitude))
            guard !Task.isCancelled, stamp == generation, approved(), reader.session == session else { return }
            guard let values = result.rows else { throw CoopFlowFailure.malformed }
            let rows = try values.map(NearbyMerchantRow.init)
            guard Set(rows.map(\.id)).count == rows.count else { throw CoopFlowFailure.malformed }
            storedRows = NearbyMerchantRow.ordered(rows); owner = session; phase = .ready
        } catch {
            guard !Task.isCancelled, stamp == generation, approved(), reader.session == session else { return }
            phase = phase == .locating ? .locationFailed : .failed
        }
    }
    public func cancel() {
        generation &+= 1; location.stop(); storedRows = []; owner = nil; phase = .idle
    }
}
