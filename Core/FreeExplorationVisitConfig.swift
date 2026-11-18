import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// FE-STORY 7.10: one free-exploration place's 「到访方式」 as the author sees it.
/// `GET /api/free-explore/visit-config?topicId=` row. Unknown checks are rejected, never GPS by guess.
public struct FreeExplorationVisitConfigRow: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let chapterID: Int?
    public let visitCheck: PlayVisitCheck
    /// Server radius for GPS places; nil means the server default (300 m).
    public let visitRadius: Int?
    public let hasCoordinates: Bool
    public init(raw: PlayWireValue) throws {
        guard let id = raw["nodeId"].tolerantInteger, id > 0,
              let check = raw["visitCheck"].text.flatMap({ PlayVisitCheck(rawValue: $0.uppercased()) }),
              let coordinates = raw["hasCoordinates"].bool else { throw FreeExplorationVisitConfigError.malformed }
        self.id = id; name = raw["name"].text; chapterID = raw["chapterId"].tolerantInteger
        visitCheck = check; hasCoordinates = coordinates
        if raw["visitRadius"] == .null { visitRadius = nil }
        else {
            guard let radius = raw["visitRadius"].tolerantInteger, radius > 0 else { throw FreeExplorationVisitConfigError.malformed }
            visitRadius = radius
        }
    }
    /// The radius the editor shows: the server's value, or the 300 m default for GPS.
    public var effectiveRadius: Int? { visitCheck == .gps ? PlayArrivalPolicy.visitRadiusMeters(configured: visitRadius) : nil }
}

/// One author edit. GPS takes 300 / 400 / 500 m; scan and online carry no radius.
public struct FreeExplorationVisitConfigChange: Equatable {
    public static let radiusChoices = [300, 400, 500]
    public let nodeID: Int
    public let visitCheck: PlayVisitCheck
    public let visitRadius: Int?
    public init(nodeID: Int, visitCheck: PlayVisitCheck, visitRadius: Int?) throws {
        guard nodeID > 0 else { throw FreeExplorationVisitConfigError.malformed }
        switch visitCheck {
        case .gps:
            guard let visitRadius, Self.radiusChoices.contains(visitRadius) else { throw FreeExplorationVisitConfigError.radiusInvalid }
        case .scan, .online:
            guard visitRadius == nil else { throw FreeExplorationVisitConfigError.radiusInvalid }
        }
        self.nodeID = nodeID; self.visitCheck = visitCheck; self.visitRadius = visitRadius
    }
    /// Exact JSON body `{nodeId, visitCheck, visitRadius}`; a non-GPS radius is sent as null.
    public var body: [String: PlayWireValue] {
        ["nodeId": .int(nodeID), "visitCheck": .string(visitCheck.rawValue), "visitRadius": visitRadius.map { PlayWireValue.int($0) } ?? PlayWireValue.null]
    }
}

public enum FreeExplorationVisitConfigError: Error, Equatable {
    /// Machine-readable server refusals (nothing was changed).
    case radiusInvalid, gpsCoordinatesRequired, checkInvalid, forbidden
    /// Local states: writes are off in this build, the account changed, or the reply was not this contract.
    case disabled, unauthorized, malformed
    /// Another refusal; the server text is shown verbatim and never followed.
    case rejected(String?)
    /// The request may have reached the server. Read again; never re-send automatically.
    case unknownResult
    init?(errorCode: String?) {
        switch errorCode {
        case "VISIT_RADIUS_INVALID"?: self = .radiusInvalid
        case "VISIT_GPS_COORD_REQUIRED"?: self = .gpsCoordinatesRequired
        case "VISIT_CHECK_INVALID"?: self = .checkInvalid
        default: return nil
        }
    }
    public var localizationKey: String {
        switch self {
        case .radiusInvalid: return "feVisitConfig.error.radius"
        case .gpsCoordinatesRequired: return "feVisitConfig.error.coordinates"
        case .checkInvalid: return "feVisitConfig.error.check"
        case .forbidden: return "feVisitConfig.error.forbidden"
        case .disabled: return "feVisitConfig.disabled"
        case .unauthorized: return "feVisitConfig.error.signIn"
        case .malformed, .rejected: return "feVisitConfig.error.failed"
        case .unknownResult: return "feVisitConfig.unknown"
        }
    }
}

/// Author-side visit configuration. Reads need only a token; every write additionally needs
/// `authorWrites`, which compositions derive from the existing author-write (project write)
/// grant and which defaults to off. One request per tap; there is no retry or queue.
@MainActor public final class FreeExplorationVisitConfigService {
    public static let path = "api/free-explore/visit-config"
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let token: () -> String?
    public let authorWrites: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport, authorWrites: Bool = false, token: @escaping () -> String?) {
        self.configuration = configuration; self.transport = transport; self.authorWrites = authorWrites; self.token = token
    }
    public func load(topicID: Int) async throws -> [FreeExplorationVisitConfigRow] {
        guard topicID > 0, let token = token(), AuthRequestBuilder.isValidToken(token) else { throw FreeExplorationVisitConfigError.unauthorized }
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(Self.path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "topicId", value: String(topicID))]
        guard let url = components.url else { throw FreeExplorationVisitConfigError.malformed }
        var request = URLRequest(url: url); request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        let (data, status): (Data, Int)
        do { (data, status) = try await transport.send(request) } catch { throw FreeExplorationVisitConfigError.malformed }
        let payload = try Self.decode(data, status: status, write: false)
        guard let rows = payload.array else { throw FreeExplorationVisitConfigError.malformed }
        let values = try rows.map(FreeExplorationVisitConfigRow.init(raw:))
        guard Set(values.map(\.id)).count == values.count else { throw FreeExplorationVisitConfigError.malformed }
        return values
    }
    /// Local prechecks mirror the server's codes so an obviously refused request is not sent.
    public func save(_ change: FreeExplorationVisitConfigChange, current: FreeExplorationVisitConfigRow) async throws {
        guard authorWrites else { throw FreeExplorationVisitConfigError.disabled }
        guard change.nodeID == current.id else { throw FreeExplorationVisitConfigError.malformed }
        if change.visitCheck == .gps, !current.hasCoordinates { throw FreeExplorationVisitConfigError.gpsCoordinatesRequired }
        guard let token = token(), AuthRequestBuilder.isValidToken(token) else { throw FreeExplorationVisitConfigError.unauthorized }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(Self.path)); request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.timeoutInterval = 20
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(change.body)
        let (data, status): (Data, Int)
        do { (data, status) = try await transport.send(request) } catch { throw FreeExplorationVisitConfigError.unknownResult }
        _ = try Self.decode(data, status: status, write: true)
    }
    static func decode(_ data: Data, status: Int, write: Bool) throws -> PlayWireValue {
        let envelope = try? JSONDecoder().decode(PlayWireValue.self, from: data)
        let code = envelope?["code"].tolerantInteger
        if status == 401 || code == 401 { throw FreeExplorationVisitConfigError.unauthorized }
        if status == 403 || code == 403 { throw FreeExplorationVisitConfigError.forbidden }
        // Anything but a well-formed business reply cannot prove a write was refused.
        guard (200..<300).contains(status), let envelope, let code else {
            throw write ? FreeExplorationVisitConfigError.unknownResult : FreeExplorationVisitConfigError.malformed
        }
        guard code == 200 else {
            let errorCode = envelope["errorCode"].text ?? envelope["data"]["errorCode"].text ?? envelope["msg"].text
            throw FreeExplorationVisitConfigError(errorCode: errorCode) ?? .rejected(envelope["msg"].text)
        }
        return envelope["data"]
    }
}

/// Screen state for the per-place 「到访方式」 editor. An unknown save re-reads the list and
/// never re-sends; nothing is applied locally until the server's list confirms it.
@available(macOS 14.0, *)
@MainActor @Observable public final class FreeExplorationVisitConfigModel {
    public enum Phase: Equatable { case idle, loading, ready, failed(FreeExplorationVisitConfigError) }
    public enum SaveState: Equatable { case saving, saved, failed(FreeExplorationVisitConfigError), unknown }
    public private(set) var phase: Phase = .idle
    public private(set) var rows: [FreeExplorationVisitConfigRow] = []
    public private(set) var saves: [Int: SaveState] = [:]
    public let topicID: Int
    private let service: FreeExplorationVisitConfigService
    @ObservationIgnored private var generation: UInt64 = 0
    public init(topicID: Int, service: FreeExplorationVisitConfigService) { self.topicID = topicID; self.service = service }
    public var canWrite: Bool { service.authorWrites && phase == .ready && !saves.values.contains(.saving) && !saves.values.contains(.unknown) }
    public func load() async {
        generation &+= 1; let request = generation
        phase = .loading
        do {
            let value = try await service.load(topicID: topicID)
            guard request == generation else { return }
            rows = value; phase = .ready
            // A fresh list resolves any earlier unknown save.
            saves = saves.filter { $0.value != .unknown && $0.value != .saving }
        } catch {
            guard request == generation else { return }
            phase = .failed(error as? FreeExplorationVisitConfigError ?? .malformed)
        }
    }
    public func save(nodeID: Int, visitCheck: PlayVisitCheck, visitRadius: Int?) async {
        guard canWrite, let row = rows.first(where: { $0.id == nodeID }) else { return }
        let change: FreeExplorationVisitConfigChange
        do { change = try .init(nodeID: nodeID, visitCheck: visitCheck, visitRadius: visitCheck == .gps ? (visitRadius ?? PlayArrivalPolicy.visitDefaultRadiusMeters) : nil) }
        catch { saves[nodeID] = .failed(error as? FreeExplorationVisitConfigError ?? .malformed); return }
        let request = generation
        saves[nodeID] = .saving
        do {
            try await service.save(change, current: row)
            guard request == generation else { return }
            saves[nodeID] = .saved
            await load()
            saves[nodeID] = .saved
        } catch {
            guard request == generation else { return }
            let failure = error as? FreeExplorationVisitConfigError ?? .unknownResult
            if failure == .unknownResult { saves[nodeID] = .unknown; await reread() }
            else { saves[nodeID] = .failed(failure) }
        }
    }
    /// Unknown save: read the list again. The edit is never re-sent from here.
    public func reread() async {
        let unknown = saves.filter { $0.value == .unknown }.map(\.key)
        await load()
        if phase != .ready { for id in unknown { saves[id] = .unknown } }
    }
}
