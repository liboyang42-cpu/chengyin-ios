import Foundation

/// Pure self-contained value types auditing bidirectional route translation between WeChat Mini-Program
/// page paths (`pages/roam/index`, `pages/merchant/store/index`, `pages/club/detail/index`, `pages/play/index`,
/// `pages/coop/list/index`) and native iOS `questify://` / Universal Link routes while preserving required
/// query parameters (`cityCode`, `merchantId`, `clubId`, `projectId`, `topicId`).
public struct MiniProgramPathRouteMapping: Sendable, Equatable, Identifiable {
    public let id: String
    public let miniProgramPath: String
    public let nativeUniversalLinkPath: String
    public let preservesQueryParametersLosslessly: Bool
    public let rejectsUnknownOrUnallowedHost: Bool

    public init(
        id: String,
        miniProgramPath: String,
        nativeUniversalLinkPath: String,
        preservesQueryParametersLosslessly: Bool = true,
        rejectsUnknownOrUnallowedHost: Bool = true
    ) {
        self.id = id
        self.miniProgramPath = miniProgramPath
        self.nativeUniversalLinkPath = nativeUniversalLinkPath
        self.preservesQueryParametersLosslessly = preservesQueryParametersLosslessly
        self.rejectsUnknownOrUnallowedHost = rejectsUnknownOrUnallowedHost
    }

    public var isCompliant: Bool {
        !miniProgramPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !nativeUniversalLinkPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preservesQueryParametersLosslessly
            && rejectsUnknownOrUnallowedHost
    }
}

public struct DeepLinkToMiniProgramPathTranslatorAudit: Sendable, Equatable {
    public static let requiredPreservedQueryKeys: [String] = [
        "cityCode", "merchantId", "clubId", "projectId", "topicId"
    ]

    public static let canonicalMappings: [MiniProgramPathRouteMapping] = [
        MiniProgramPathRouteMapping(
            id: "route-roam-index",
            miniProgramPath: "pages/roam/index",
            nativeUniversalLinkPath: "/roam"
        ),
        MiniProgramPathRouteMapping(
            id: "route-merchant-store",
            miniProgramPath: "pages/merchant/store/index",
            nativeUniversalLinkPath: "/merchant/store"
        ),
        MiniProgramPathRouteMapping(
            id: "route-club-detail",
            miniProgramPath: "pages/club/detail/index",
            nativeUniversalLinkPath: "/club/detail"
        ),
        MiniProgramPathRouteMapping(
            id: "route-play-index",
            miniProgramPath: "pages/play/index",
            nativeUniversalLinkPath: "/play"
        ),
        MiniProgramPathRouteMapping(
            id: "route-coop-list",
            miniProgramPath: "pages/coop/list/index",
            nativeUniversalLinkPath: "/coop/list"
        )
    ]

    public let mappings: [MiniProgramPathRouteMapping]

    public init(mappings: [MiniProgramPathRouteMapping] = DeepLinkToMiniProgramPathTranslatorAudit.canonicalMappings) {
        self.mappings = mappings
    }

    public static func evaluate(
        mappings: [MiniProgramPathRouteMapping] = canonicalMappings
    ) -> (totalMappings: Int, compliantMappings: Int, isPathTranslatorReady: Bool) {
        let total = mappings.count
        let compliant = mappings.filter(\.isCompliant).count
        let ready = total > 0 && compliant == total
        return (
            totalMappings: total,
            compliantMappings: compliant,
            isPathTranslatorReady: ready
        )
    }
}
