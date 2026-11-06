import Foundation

/// Mini-program `pages/merchant/citynode` display rules over the existing `city-node/list` payload.
/// Pure projection: no transport, no permission grant beyond what the source rows already state.
public enum MerchantCityNodeScalar {
    /// Mini `scalarText`: only a non-empty string or a number is displayable.
    public static func text(_ value: MerchantContentValue) -> String? {
        switch value {
        case .string(let v): return v.isEmpty ? nil : v
        case .integer(let v): return String(v)
        case .decimal(let v): return NSDecimalNumber(decimal: v).stringValue
        default: return nil
        }
    }
}

public enum MerchantCityNodeAudit: String, Equatable, Sendable { case reviewing, approved, rejected }
public enum MerchantCityNodeApplicationKind: String, Equatable, Sendable { case placement, claim }

public struct MerchantCityNodeRow: Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let isOnline: Bool
    public let templateTitle: String?
    public let tags: String?
    public let usesPosterCode: Bool
    public init?(_ row: MerchantContentValue) {
        guard let id = row["poiId"].safeInteger, id > 0, let name = MerchantCityNodeScalar.text(row["name"]) else { return nil }
        self.id = id; self.name = name
        isOnline = row["status"].safeInteger == 1
        templateTitle = MerchantCityNodeScalar.text(row["templateTitle"])
        tags = MerchantCityNodeScalar.text(row["tags"])
        // Mini shows the poster entry only for strict numeric validationMethod 4 (到店扫码).
        usesPosterCode = row["validationMethod"].safeInteger == 4
    }
}

public struct MerchantCityNodeApplicationRow: Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String?
    public let kind: MerchantCityNodeApplicationKind
    public let audit: MerchantCityNodeAudit
    public let auditReason: String?
    /// Display rule only. The existing command still revalidates via MerchantCityClaimWithdrawal.
    public let withdrawable: Bool
    public init?(_ row: MerchantContentValue) {
        guard let id = row["id"].safeInteger, id > 0 else { return nil }
        self.id = id
        name = MerchantCityNodeScalar.text(row["name"])
        let type = row["applicationType"].safeInteger, status = row["auditStatus"].safeInteger
        kind = type == 2 ? .claim : .placement
        // 3 is the platform's "taken into review" state; it is still pending, never a rejection.
        switch status { case 0, 3: audit = .reviewing; case 1: audit = .approved; default: audit = .rejected }
        auditReason = MerchantCityNodeScalar.text(row["auditReason"])
        withdrawable = type == 2 && status == 0
    }
}

public struct MerchantCityNodeHubProjection: Equatable {
    public let nodes: [MerchantCityNodeRow]
    public let applications: [MerchantCityNodeApplicationRow]
    public let quota: MerchantCityQuota
    public init(list: MerchantContentValue) {
        nodes = (list["nodes"].array ?? []).compactMap(MerchantCityNodeRow.init)
        applications = (list["applications"].array ?? []).compactMap(MerchantCityNodeApplicationRow.init)
        quota = MerchantCityQuota(catalog: list)
    }
    public var itemCount: Int { nodes.count + applications.count }
    public var isEmpty: Bool { nodes.isEmpty && applications.isEmpty }
    /// Mini empty-state CTA: only with known, available quota.
    public var showsEmptyPlacementAction: Bool { quota.canPlace }
}

public struct MerchantCityClaimableRow: Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let detail: String?
}
public enum MerchantCityClaimableProjection {
    /// All-or-nothing like the mini client: one unusable row makes the whole list unavailable.
    public static func rows(_ value: MerchantContentValue) -> [MerchantCityClaimableRow]? {
        guard let rows = value.array else { return nil }
        var result: [MerchantCityClaimableRow] = []
        for row in rows {
            guard let id = row["id"].safeInteger ?? row["poiId"].safeInteger, id > 0,
                  let name = MerchantCityNodeScalar.text(row["name"]) else { return nil }
            result.append(.init(id: id, name: name, detail: MerchantCityNodeScalar.text(row["description"]) ?? MerchantCityNodeScalar.text(row["cityCode"])))
        }
        return result
    }
}

/// `merchant:verify` lives only in the raw access permissions; MerchantAccess does not model it.
public enum MerchantCityNodeVerifyGrant {
    public static let permission = "merchant:verify"
    public static func allows(permissions: Set<String>, accessMerchantID: Int, contentMerchantID: Int?) -> Bool {
        guard let contentMerchantID, contentMerchantID > 0, accessMerchantID == contentMerchantID else { return false }
        return permissions.contains(permission)
    }
}

/// Writes need both the injected offline harness and the w2-19 gate path; production stays dormant.
public enum MerchantCityNodeWriteGate {
    public static let paths: Set<String> = ["api/merchant/city-node/claim", "api/merchant/city-node/claim/cancel",
                                            "api/merchant/city-node/offline", "api/merchant/city-node/save"]
    public static func enabled(permitsWrites: Bool, isOfflineExample: Bool, path: String,
                               gates: MerchantCityNPCParityGates = .disabled, market: RegionalMarket? = nil) -> Bool {
        guard permitsWrites, paths.contains(path) else { return false }
        if isOfflineExample { return true }
        guard gates.cityNodeWrites, let market else { return false }
        return gates.allows(path, market: market)
    }
}

/// `city-node/save` returns the application id either bare (`data: 92`) or as `{id}`.
public enum MerchantCityPlacementReceipt {
    public static func applicationID(_ data: MerchantContentValue) -> Int? {
        let id = data["id"].integer ?? data.integer
        guard let id, id > 0 else { return nil }
        return id
    }
    public static func contains(applicationID: Int, catalog: MerchantContentValue) -> Bool {
        (catalog["applications"].array ?? []).contains { $0["id"].integer == applicationID }
    }
    /// Uncertain-outcome readback: a pending placement proves nothing about which attempt created it.
    public static func hasPendingPlacement(_ catalog: MerchantContentValue) -> Bool {
        (catalog["applications"].array ?? []).contains { $0["applicationType"].safeInteger == 1 && [0, 3].contains($0["auditStatus"].safeInteger ?? -1) }
    }
}

/// Store coordinate from `api/merchant/info`; absent, non-finite or (0,0) means "no coordinate".
public struct MerchantCityNodeProfileAddress: Equatable {
    public let name: String
    public let address: String
    public let latitude: String
    public let longitude: String
    public init?(profile: MerchantContentValue) {
        guard let lat = MerchantCityNodeScalar.text(profile["locationLat"]), let lng = MerchantCityNodeScalar.text(profile["locationLng"]),
              let latValue = Double(lat), let lngValue = Double(lng), latValue.isFinite, lngValue.isFinite,
              (-90...90).contains(latValue), (-180...180).contains(lngValue), latValue != 0 || lngValue != 0 else { return nil }
        latitude = lat; longitude = lng
        name = profile["name"].text ?? ""; address = profile["address"].text ?? ""
    }
}

public struct MerchantCityNodeTemplateSummary: Equatable {
    public static let interactions = ["city_story_card", "hidden_menu", "photo_spot", "qr_checkin"]
    public let title: String?
    public let interaction: String?
    public let validationMethod: Int?
    public init(templateID: Int, templates: MerchantContentValue) {
        let row = (templates.array ?? []).first { $0["id"].integer == templateID } ?? .null
        title = MerchantCityNodeScalar.text(row["title"])
        interaction = row["interactionType"].text.flatMap { Self.interactions.contains($0) ? $0 : nil }
        validationMethod = row["validationMethod"].safeInteger.flatMap { (0...7).contains($0) ? $0 : nil }
    }
}

public enum MerchantCityNodeStationState: String, Equatable, Sendable { case done, doing, todo }
/// 配置玩法 / 确认店址 / 提交申请 / 平台审核. The review station is never marked done on the client.
public enum MerchantCityNodeTimeline {
    public static func states(templateReady: Bool, addressConfirmed: Bool, submitted: Bool) -> [MerchantCityNodeStationState] {
        let flags = [templateReady, addressConfirmed, submitted]
        let cursor = flags.firstIndex(of: false) ?? 3
        return (0..<4).map { index in
            if index < 3, flags[index] { return .done }
            return index == cursor ? .doing : .todo
        }
    }
}

/// Read-only, long-lived poster QR for an owned node. The raw `code` is never retained.
@MainActor public protocol MerchantCityNodePosterReading: AnyObject {
    func cityPosterCode(poiID: Int) async throws -> MerchantContentValue
}
public struct MerchantCityNodePosterCode: Equatable {
    public let imageURL: URL
    public let nodeName: String?
    public init(_ data: MerchantContentValue) throws {
        let raw = (data["qrcodeUrl"].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil else {
            throw MerchantContentFailure.malformed
        }
        imageURL = url; nodeName = MerchantCityNodeScalar.text(data["nodeName"])
    }
}
extension MerchantContentService: MerchantCityNodePosterReading {}
