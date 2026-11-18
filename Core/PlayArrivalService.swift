import Foundation
import Observation

/// What one `/api/play/arrive` request carries. A station tap after the run started has
/// no coordinates; a start check or free-exploration visit carries one GCJ-02 fix.
public struct PlayArrivalReading: Codable, Equatable {
    public let longitude: Double?
    public let latitude: Double?
    public let accuracyMeters: Double?
    public static let tap = PlayArrivalReading(longitude: nil, latitude: nil, accuracyMeters: nil)
    private init(longitude: Double?, latitude: Double?, accuracyMeters: Double?) {
        self.longitude = longitude; self.latitude = latitude; self.accuracyMeters = accuracyMeters
    }
    /// CoreLocation is WGS-84; only an explicitly projected GCJ-02 fix is sent.
    public init(gcj02 fix: RoamDeviceFix) throws {
        guard fix.datum == .gcj02 else { throw APIError.invalidRequest }
        self.init(longitude: fix.coordinate.longitude, latitude: fix.coordinate.latitude, accuracyMeters: fix.accuracyMeters)
        guard isValid else { throw APIError.invalidRequest }
    }
    public var isLocated: Bool { longitude != nil && latitude != nil }
    public var isValid: Bool {
        if longitude == nil, latitude == nil { return accuracyMeters == nil }
        guard let longitude, let latitude, longitude.isFinite, latitude.isFinite,
              abs(longitude) <= 180, abs(latitude) <= 90 else { return false }
        return accuracyMeters.map { $0.isFinite && $0 >= 0 } ?? true
    }
}

/// Machine-readable arrival refusal (`errorCode`), from the server or the local precheck.
public struct PlayArrivalRejection: Equatable {
    public enum Reason: String, Equatable, CaseIterable {
        case tooFar = "ARRIVE_TOO_FAR", accuracyLow = "ARRIVE_ACCURACY_LOW"
        case locationMissing = "ARRIVE_LOCATION_MISSING", scanRequired = "VISIT_SCAN_REQUIRED"
    }
    public let reason: Reason
    /// Rounded to 10 m. Present for a free-exploration TOO_FAR or a local precheck.
    public let distanceMeters: Int?
    /// Verbatim server text, never instructions or navigation.
    public let message: String?
    /// True when no request was sent because the shared policy already failed.
    public let checkedLocally: Bool
    public init(local reason: Reason, distance: Double?) {
        self.reason = reason; distanceMeters = distance.flatMap(PlayArrivalPolicy.roundedDistanceMeters)
        message = nil; checkedLocally = true
    }
    init?(envelope: PlayWireValue) {
        let data = envelope["data"]
        guard let raw = envelope["errorCode"].text ?? data["errorCode"].text, let reason = Reason(rawValue: raw) else { return nil }
        self.reason = reason
        let distance = envelope["distanceMeters"].double ?? data["distanceMeters"].double
        distanceMeters = distance.flatMap(PlayArrivalPolicy.roundedDistanceMeters)
        message = envelope["msg"].text; checkedLocally = false
    }
    /// arrival-policy v2: these four are refusals checked before any arrival is recorded,
    /// so the exact journal may be cleared and the player may try again later.
    public var provesNoCommit: Bool {
        switch reason { case .tooFar, .accuracyLow, .locationMissing, .scanRequired: return true }
    }
}

/// The coordinator's definitive result for one exact arrival review.
public struct PlayArrivalDispatchOutcome: Equatable {
    let reviewID: UUID
    public let nodeID: Int
    public let rejection: PlayArrivalRejection?
}

/// F08 「我已到达」 and FE-STORY place visits. Location is read once, prechecked with
/// `PlayArrivalPolicy`, then written through the coordinator's durable completion path,
/// which stays behind the default-off classic-completion grant. An unknown result is
/// re-read, never re-sent.
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayArrivalService {
    public enum Kind: Equatable { case stationTap, start, freeVisit }
    public enum Phase: Equatable {
        case idle, locating, submitting, succeeded, rejected(PlayArrivalRejection), unknown, unavailable, locationUnavailable
    }
    public private(set) var phase: Phase = .idle
    public private(set) var nodeID: Int?
    private let runtime: PlayExperienceCoordinator
    private let location: (any RoamDeviceLocationProviding)?
    private let now: () -> Date
    @ObservationIgnored private var generation: UInt64 = 0

    public init(runtime: PlayExperienceCoordinator, location: (any RoamDeviceLocationProviding)?, now: @escaping () -> Date = Date.init) {
        self.runtime = runtime; self.location = location; self.now = now
    }

    public var isBusy: Bool { phase == .locating || phase == .submitting }

    /// Which arrival the node offers now; nil hides the control. Never infers a write grant.
    public func offer(for nodeID: Int) -> Kind? {
        guard let snapshot = runtime.snapshot, snapshot.availability == .active,
              let node = snapshot.visibleNodes.first(where: { $0.id == nodeID }),
              !snapshot.isDone(node), !snapshot.isLocked(node), node.done == false else { return nil }
        switch runtime.gameplayMode {
        case .cityOrientation?:
            let task = PlayNodeTask.resolve(mode: snapshot.result.mode, node: node)
            let needsArrival = task == .arrive || (task == .answer && node.needGPS == true && node.needScan != true && node.arrived != true)
            guard needsArrival else { return nil }
            return Self.runStarted(snapshot) ? .stationTap : .start
        case .freeExploration?:
            guard snapshot.isStoryLocked(node), node.visitCheck != .scan, node.visitCheck != .online,
                  FreeExplorationPresentation.evidenceTask(for: node, in: snapshot) == .merchantScan else { return nil }
            return .freeVisit
        case nil: return nil
        }
    }

    /// The server checks the start geofence only while the run has no progress yet.
    static func runStarted(_ snapshot: PlaySnapshot) -> Bool {
        if let done = snapshot.displayedDoneCount, done > 0 { return true }
        return snapshot.visibleNodes.contains { snapshot.isDone($0) || $0.arrived == true }
    }

    public func arrive(nodeID: Int, context: PlayInteractionContext?) async {
        // An unknown result is re-read first; it is never re-sent from here.
        guard !isBusy, phase != .unknown, let kind = offer(for: nodeID) else { return }
        generation &+= 1; let request = generation; self.nodeID = nodeID
        guard runtime.canSubmitArrival else { phase = .unavailable; return }
        var reading = PlayArrivalReading.tap
        if kind != .stationTap {
            guard let location else { phase = .locationUnavailable; return }
            phase = .locating
            let fix: RoamDeviceFix
            do {
                let raw = try await location.currentFix()
                fix = try RuntimeLocationProjection.gcj02ArrivalFix(raw, now: now())
            }
            catch { if request == generation { phase = .locationUnavailable }; return }
            guard request == generation else { return }
            guard offer(for: nodeID) == kind, let node = runtime.snapshot?.visibleNodes.first(where: { $0.id == nodeID }) else { phase = .idle; return }
            if let latitude = node.latitude, let longitude = node.longitude {
                let distance = PlayArrivalPolicy.distanceMeters(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
                                                                toLatitude: latitude, toLongitude: longitude)
                let verdict = kind == .start
                    ? PlayArrivalPolicy.start(distanceMeters: distance, accuracyMeters: fix.accuracyMeters)
                    : PlayArrivalPolicy.visit(distanceMeters: distance, accuracyMeters: fix.accuracyMeters, configuredRadiusMeters: node.visitRadius)
                switch verdict {
                case .pass: break
                case .tooFar: phase = .rejected(.init(local: .tooFar, distance: distance)); return
                case .accuracyLow: phase = .rejected(.init(local: .accuracyLow, distance: nil)); return
                }
            }
            // Missing place coordinates: the server remains the only judge.
            do { reading = try PlayArrivalReading(gcj02: fix) } catch { phase = .locationUnavailable; return }
        }
        let review: PlayCompletionReview
        do { review = try runtime.review(nodeID: nodeID, evidence: .arrival(reading), context: context) }
        catch { phase = .unavailable; return }
        phase = .submitting
        await runtime.submit(review)
        if runtime.phase == .reviewing { runtime.cancelReview() }
        guard request == generation else { return }
        if let outcome = runtime.arrivalOutcome, outcome.reviewID == review.id {
            phase = outcome.rejection.map(Phase.rejected) ?? .succeeded; return
        }
        if runtime.unresolved { phase = .unknown; await reread() } else { phase = .unavailable }
    }

    /// Unknown outcome: read authoritative progress again. Never re-sends the arrival.
    public func reread() async {
        guard phase == .unknown, let nodeID else { return }
        let request = generation
        await runtime.load()
        guard request == generation, !runtime.unresolved else { return }
        guard let snapshot = runtime.snapshot, let node = snapshot.result.nodes.first(where: { $0.id == nodeID }) else { phase = .idle; return }
        let landed = snapshot.result.mode == 2 ? snapshot.isVisited(node) || node.arrived == true : snapshot.isDone(node) || node.arrived == true
        phase = landed ? .succeeded : .idle
    }

    public func cancel() {
        generation &+= 1
        if phase == .locating { location?.stop() }
        if phase != .unknown { phase = .idle }
    }
}
