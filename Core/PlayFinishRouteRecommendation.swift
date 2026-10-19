import Foundation

/// Mini-program `pages/play/finish-route-recommendation.js` + `index.js
/// loadFinishRouteRecommendation` (附近下一程 on the finish sheet).
/// Gated by the server feature `finishNearbyRoute` (default false). The origin is the
/// most recently completed node's server coordinate; the App never samples device
/// location for this card (the mini-program's `_loc` branch is not ported).
public struct PlayFinishOrigin: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init?(latitude: Double?, longitude: Double?) {
        guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude), latitude != 0 || longitude != 0 else { return nil }
        self.latitude = latitude; self.longitude = longitude
    }

    /// `resolveOrigin` without the device-location branch: done nodes with a coordinate,
    /// newest `doneAt` first; equal or missing `doneAt` keeps server order.
    public static func resolve(_ nodes: [(done: Bool, latitude: Double?, longitude: Double?, doneAt: Double?)]) -> PlayFinishOrigin? {
        let completed = nodes.enumerated().compactMap { index, node -> (Int, Double, PlayFinishOrigin)? in
            guard node.done, let origin = PlayFinishOrigin(latitude: node.latitude, longitude: node.longitude) else { return nil }
            return (index, node.doneAt ?? 0, origin)
        }
        return completed.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.first?.2
    }

    public static func resolve(nodes: [PlayNode]) -> PlayFinishOrigin? {
        resolve(nodes.map { (done: $0.done == true, latitude: $0.latitude, longitude: $0.longitude, doneAt: nil) })
    }
}

/// One `api/activity/list` row, only the fields the card reads.
public struct PlayFinishRouteRow: Decodable, Equatable, Sendable {
    public let id: Int
    public let name: String?
    public let imgUrl: String?
    public let topicId: Int?
    public let distance: Double?
    public let addressName: String?
    public let address: String?
    /// Wire spelling `minAmout`.
    public let minAmout: Decimal?
    private enum CodingKeys: String, CodingKey { case id, name, imgUrl, topicId, distance, addressName, address, minAmout }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try c.playInt(.id), id > 0 else { throw APIError.malformedResponse }
        self.id = id
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        imgUrl = try? c.decodeIfPresent(String.self, forKey: .imgUrl)
        topicId = try? c.playInt(.topicId)
        distance = c.playCoordinate(.distance)
        addressName = try? c.decodeIfPresent(String.self, forKey: .addressName)
        address = try? c.decodeIfPresent(String.self, forKey: .address)
        minAmout = (try? c.decodeIfPresent(Decimal.self, forKey: .minAmout)) ?? (try? c.decodeIfPresent(String.self, forKey: .minAmout)).flatMap { Decimal(string: $0) }
    }
}

public struct PlayFinishRouteCard: Equatable, Sendable {
    public enum Price: Equatable, Sendable {
        /// ¥N 起
        case from(Decimal)
        /// 免费 (server amount 0, never inferred from a missing price)
        case free
    }
    public let activityID: Int
    /// nil → 附近路线
    public let title: String?
    public let coverURL: String?
    public let distanceMeters: Double?
    public let address: String?
    public let price: Price?

    /// `pickCandidate`: first row that is neither the current activity nor the current topic.
    public static func pick(_ rows: [PlayFinishRouteRow], currentActivityID: Int?, currentTopicID: Int?) -> PlayFinishRouteCard? {
        guard let row = rows.first(where: { row in
            (currentActivityID.map { row.id != $0 } ?? true) && (currentTopicID.map { row.topicId != $0 } ?? true)
        }) else { return nil }
        let title = row.name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let cover = row.imgUrl?.split(separator: ",", omittingEmptySubsequences: false).first.map(String.init).flatMap { $0.isEmpty ? nil : $0 }
        let address = [row.addressName, row.address].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        let price: Price? = row.minAmout.map { $0 > 0 ? .from($0) : .free }
        return PlayFinishRouteCard(activityID: row.id, title: title, coverURL: cover, distanceMeters: row.distance.flatMap { $0 >= 0 ? $0 : nil }, address: address, price: price)
    }

    /// `utils/geo.js distanceText`: ≥1000 m → one decimal km, else whole metres.
    public static func distanceParts(_ meters: Double) -> (value: String, kilometres: Bool) {
        meters >= 1000 ? (String(format: "%.1f", meters / 1000), true) : (String(Int(meters.rounded())), false)
    }
}

extension PlayExperienceService {
    /// `POST api/activity/list {is_my:0, sort_type:1, pageNum:1, pageSize:5, longitude, latitude}`.
    public func finishRouteRows(origin: PlayFinishOrigin, token: String) async throws -> [PlayFinishRouteRow] {
        let fields = ["is_my": "0", "sort_type": "1", "pageNum": "1", "pageSize": "5",
                      "longitude": String(origin.longitude), "latitude": String(origin.latitude)]
        let raw = try await request("api/activity/list", form: fields, capability: .reads, token: token)
        return (raw["rows"].array ?? []).compactMap { try? $0.decoded(PlayFinishRouteRow.self) }
    }
}

public protocol PlayFinishRouteReading: AnyObject {
    @MainActor func rows(origin: PlayFinishOrigin) async throws -> [PlayFinishRouteRow]
}

@available(macOS 14.0, *)
@MainActor @Observable public final class PlayFinishRouteRecommendationCoordinator {
    public private(set) var card: PlayFinishRouteCard?
    public private(set) var isVisible = false
    private let featureEnabled: Bool
    private let reader: (any PlayFinishRouteReading)?
    private let currentActivityID: Int?
    private let currentTopicID: Int?
    private var epoch: UInt64 = 0

    /// `featureEnabled` is the server `finishNearbyRoute` flag; absent means false.
    public init(featureEnabled: Bool, reader: (any PlayFinishRouteReading)?, currentActivityID: Int?, currentTopicID: Int?) {
        self.featureEnabled = featureEnabled; self.reader = reader
        self.currentActivityID = currentActivityID; self.currentTopicID = currentTopicID
    }

    /// Finish sheet opened. Failures and empty pages simply show no card.
    public func show(origin: PlayFinishOrigin?, isPreview: Bool = false) async {
        epoch &+= 1; let request = epoch
        isVisible = true; card = nil
        guard featureEnabled, !isPreview, let reader, let origin else { return }
        guard let rows = try? await reader.rows(origin: origin), request == epoch, isVisible else { return }
        card = PlayFinishRouteCard.pick(rows, currentActivityID: currentActivityID, currentTopicID: currentTopicID)
    }

    /// Finish sheet hidden: late responses are dropped.
    public func hide() { epoch &+= 1; isVisible = false; card = nil }
}
