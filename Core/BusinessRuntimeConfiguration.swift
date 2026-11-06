import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum BusinessRuntimeFeature: Hashable {
    case bankConsentRead, bankPrepare, bankCreate, stampUpload, stampCreate
    case imChannelAppealRead, imChannelAppealWrite, imChannelAppealReceipt
    case imChannelAttachmentPreview
    case imChannelPersonalStateRead, imChannelPersonalStateWrite, imChannelPersonalStateReceipt
    case imChannelRoleRead, imChannelRoleWrite, imChannelRoleReceipt, imChannelRoleMemberRead
    case imChannelModerationRead, imChannelModerationWrite, imChannelModerationReceipt
    case imChannelAuditRead, imChannelLifecycleAuditRead
    case imChannelMentionMemberRead, imChannelMentionRoleRead
    case imChainClose, imChainCreate, imChainJoin, imChainRead, imChainReceipt, imChainWithdraw, imChannelReportReceipt, imCheckinRank, imCheckinReceipt, imCheckinStatus, imCheckinWrite, imFilePreview, imFilePreviewStatus, imFileReceipt, imFileScan, imFileSend, imFileUpload, imFileUploadReceipt, imImageUploadReceipt, imOrdinaryMuteReceipt, imOrdinaryMuteState, imOrdinaryReadReceipt, imOrdinaryReadState, imOrdinarySendReceipt, imRouteReceipt, imRouteSend, imRouteShareRead, imStaticLocationReceipt, imStaticLocationSend, imVideoPolicy, imVideoPreview, imVideoPreviewStatus, imVideoReceipt, imVideoSend, imVideoUpload, imVideoUploadReceipt, imVoicePlayback, imVoicePlaybackStatus, imVoiceReceipt, imVoiceSend, imVoiceUpload, imVoiceUploadReceipt
    case imStart, imRead, imMute, imSend, imUpload
    case imDelete, imReport, imBlock, imUnblock, imUnreadTotal
    case imPollResult, imPollCreate, imPollVote, imPollClose, imPollCreateReceipt, clubChat
    case publishingRead, publishingWrite, projectRead, projectWrite, projectAuthorInputRead, directVerification
    case publishingAIQuota, publishingAITheme, publishingAIClub, publishingAITemplate
    case merchantDraftSelectionList, merchantDraftSelectionResolve
    case approvedTopicReleasePrepare, approvedTopicReleasePublish, approvedTopicReleaseStatus
    case approvedTopicReviewSources, approvedTopicReviewPrepare, approvedTopicReviewSubmit, approvedTopicReviewStatus, approvedTopicReviewCurrent
    case topicSelfPlayRead, topicSelfPlayCreate, topicSelfPlayPay, topicSelfPlayConsentRead, topicSelfPlayConsentWrite
}
public struct BusinessRuntimeRoute: Hashable {
    public let method: String
    public let path: String
    public init(method: String, path: String) throws {
        guard ["GET", "POST"].contains(method), path.hasPrefix("api/"),
              !path.contains(".."), !path.contains("?"), !path.contains("#"), !path.contains("%"), !path.contains("*") else { throw APIError.invalidConfiguration }
        self.method = method; self.path = path
    }
    public static func post(_ path: String) throws -> Self { try .init(method: "POST", path: path) }
    /// The original role mutations are the only non-GET/POST routes this catalog
    /// can construct. Construction is not issuance: configuration must still grant
    /// the exact route under imChannelRoleWrite, and the consumer must select it.
    public static func channelRoleMutation(method: String, path: String) throws -> Self {
        try .init(channelRoleMutationMethod: method, path: path)
    }
    private init(channelRoleMutationMethod method: String, path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4 || parts.count == 5,
              parts[0] == "api", parts[1] == "im",
              NativeChannelGovernanceNotice.positive(parts[3]) != nil else { throw APIError.invalidConfiguration }
        let roleMutation = parts.count == 4 && parts[2] == "roles" && ["PATCH", "DELETE"].contains(method)
        let membershipMutation = parts.count == 5 && method == "PUT" &&
            ((parts[2] == "members" && parts[4] == "roles") || (parts[2] == "roles" && parts[4] == "members"))
        guard roleMutation || membershipMutation else { throw APIError.invalidConfiguration }
        self.method = method; self.path = path
    }
}
public enum BankWithdrawalServerAction: Hashable { case confirm, reject }
/// Each feature receives its own exact method/path subset. No "all" mode exists.
public struct BusinessRuntimeConfiguration {
    public let market: RegionalMarket
    public let baseURL: URL
    public let namespace: String
    public let accountID: Int
    public let routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>]
    public let bankChallengeActions: Set<BankWithdrawalServerAction>
    public let stampImageOrigins: Set<String>
    public let imMediaOrigins: Set<String>
    public let imImageSelection: Bool
    public let stampCamera: Bool
    public let verificationCamera: Bool
    public let selfPlayPayment: Bool
    public let selfPlayExternalCheckoutApproved: Bool
    public init(market: RegionalMarket, baseURL: URL, namespace: String, accountID: Int,
                routes: [BusinessRuntimeFeature: Set<BusinessRuntimeRoute>] = [:],
                bankChallengeActions: Set<BankWithdrawalServerAction> = [], stampImageOrigins: Set<String> = [],
                imMediaOrigins: Set<String> = [], imImageSelection: Bool = false, stampCamera: Bool = false, verificationCamera: Bool = false, selfPlayPayment: Bool = false, selfPlayExternalCheckoutApproved: Bool = false) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard !namespace.isEmpty, accountID > 0, routes.allSatisfy({ feature, values in values.allSatisfy { feature.accepts($0) } }) else { throw APIError.invalidConfiguration }
        self.market = market; self.baseURL = baseURL; self.namespace = namespace; self.accountID = accountID
        self.routes = routes; self.bankChallengeActions = bankChallengeActions
        self.stampImageOrigins = stampImageOrigins; self.imMediaOrigins = imMediaOrigins
        self.imImageSelection = imImageSelection; self.stampCamera = stampCamera; self.verificationCamera = verificationCamera; self.selfPlayPayment = selfPlayPayment; self.selfPlayExternalCheckoutApproved = selfPlayExternalCheckoutApproved
    }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        market == .china && context.market == market && baseURL == context.baseURL &&
        namespace == context.session.namespace && accountID == context.session.accountID
    }
}
@MainActor public final class BusinessRuntimeTransport: HTTPTransport {
    private let configuration: BusinessRuntimeConfiguration
    private let captured: RuntimeDependencyContext
    private let routes: () -> Set<BusinessRuntimeRoute>
    private let current: () -> RuntimeDependencyContext?
    private let transport: any HTTPTransport
    public init(configuration: BusinessRuntimeConfiguration, captured: RuntimeDependencyContext,
                routes: @escaping () -> Set<BusinessRuntimeRoute>, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?) {
        self.configuration = configuration; self.captured = captured; self.routes = routes; self.transport = transport; self.current = current
    }
    public func permits(_ request: URLRequest) -> Bool {
        guard configuration.matches(captured), current() == captured,
              request.value(forHTTPHeaderField: "Authorization") == captured.session.token,
              let url = request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        parts.query = nil
        return routes().contains(where: { $0.method == request.httpMethod && captured.baseURL.appendingPathComponent($0.path) == parts.url })
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard permits(request) else { throw APIError.notConfigured }
        let result = try await transport.send(request)
        try Task.checkCancellation()
        guard current() == captured else { throw CancellationError() }
        return result
    }

}
@MainActor public struct BusinessRuntimeFactory {
    public let configuration: BusinessRuntimeConfiguration
    public let captured: RuntimeDependencyContext
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    public init?(configuration: BusinessRuntimeConfiguration?, api: APIConfiguration, transport: any HTTPTransport,
                 current: @escaping () -> RuntimeDependencyContext?) {
        guard let configuration, let captured = current(), configuration.matches(captured), api.baseURL == captured.baseURL else { return nil }
        self.configuration = configuration; self.captured = captured; self.transport = transport; self.current = current
    }
    public func routes(_ features: Set<BusinessRuntimeFeature>) -> Set<BusinessRuntimeRoute> {
        features.reduce(into: Set<BusinessRuntimeRoute>()) { $0.formUnion(configuration.routes[$1] ?? []) }
    }
    public func approval(_ features: Set<BusinessRuntimeFeature>) -> OperationEndpointApproval? {
        let paths = Set(routes(features).map(\.path)); guard !paths.isEmpty else { return nil }
        return try? OperationEndpointApproval(baseURL: captured.baseURL, namespace: captured.session.namespace, accountID: captured.session.accountID, paths: paths)
    }
    public func client(_ features: Set<BusinessRuntimeFeature>, additionalRoutes: @escaping () -> Set<BusinessRuntimeRoute> = { [] }) -> BusinessRuntimeTransport {
        let fixed = routes(features)
        let bankActions = configuration.bankChallengeActions
        return BusinessRuntimeTransport(configuration: configuration, captured: captured, routes: {
            let dynamic = additionalRoutes().filter { route in
                guard features == [.bankPrepare, .bankCreate], route.method == "POST" else { return false }
                let parts = route.path.split(separator: "/").map(String.init)
                guard parts.count == 5, Array(parts.prefix(3)) == ["api", "fund", "preflight"],
                      let id = Int(parts[3]), id > 0, parts[3] == String(id) else { return false }
                return (parts[4] == "confirm" && bankActions.contains(.confirm)) || (parts[4] == "reject" && bankActions.contains(.reject))
            }
            return fixed.union(dynamic)
        }, transport: transport, current: current)
    }
    public func permits(_ feature: BusinessRuntimeFeature) -> Bool { current() == captured && !(configuration.routes[feature] ?? []).isEmpty }
}

public extension BusinessRuntimeFeature {
    /// Source contract catalog constrains the meaning of every named feature.
    func accepts(_ route: BusinessRuntimeRoute) -> Bool {
        if self == .projectAuthorInputRead {
            return route.method == "GET" && route.path == NativeRuntimeStructureAuthorInputs.supportPath
                || route.method == "POST" && route.path == NativeRuntimeStructureAuthorInputs.templatePath
        }
        if self == .imPollCreateReceipt { return route.method == "GET" && route.path == "api/im/poll/create-receipt" }
        if self == .imChannelMentionRoleRead { return route.method == "GET" && route.path == "api/im/roles" }
        if self == .imChannelMentionMemberRead {
            let parts=route.path.split(separator:"/",omittingEmptySubsequences:false)
            return route.method == "GET" && parts.count == 4 && parts[0] == "api" && parts[1] == "channels"
                && NativeChannelGovernanceNotice.positive(String(parts[2])) != nil && parts[3] == "members"
        }
        if self == .imChannelAttachmentPreview {
            let prefix="api/im/message/", suffix="/attachment"
            guard route.method=="GET",route.path.hasPrefix(prefix),route.path.hasSuffix(suffix) else{return false}
            return Int(route.path.dropFirst(prefix.count).dropLast(suffix.count)).map { $0 > 0 } == true
        }
        if self == .imChannelPersonalStateReceipt {
            let prefix = "api/channels/member-state-requests/"
            return route.method == "GET" && route.path.hasPrefix(prefix) && UUID(uuidString: String(route.path.dropFirst(prefix.count))) != nil
        }
        if self == .imChannelPersonalStateRead || self == .imChannelPersonalStateWrite {
            let parts = route.path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count >= 3, parts[0] == "api", parts[1] == "channels", NativeChannelGovernanceNotice.positive(String(parts[2])) != nil else { return false }
            return self == .imChannelPersonalStateRead ? route.method == "GET" && parts.count == 3
                : route.method == "POST" && parts.count == 4 && parts[3] == "member-state"
        }
        if self == .imChannelRoleMemberRead {
            let parts = route.path.split(separator: "/", omittingEmptySubsequences: false)
            return route.method == "GET" && parts.count == 4 && parts[0] == "api" && parts[1] == "channels"
                && NativeChannelGovernanceNotice.positive(String(parts[2])) != nil && parts[3] == "members"
        }
        if self == .imChannelRoleRead { return route.method == "GET" && route.path == "api/im/roles" }
        if self == .imChannelRoleReceipt {
            let prefix = "api/channel-platform/governance/requests/"
            return route.method == "GET" && route.path.hasPrefix(prefix) && UUID(uuidString: String(route.path.dropFirst(prefix.count))) != nil
        }
        if self == .imChannelRoleWrite {
            if route.method == "POST" && route.path == "api/im/roles" { return true }
            let parts = route.path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count >= 4, parts[0] == "api", parts[1] == "im", NativeChannelGovernanceNotice.positive(String(parts[3])) != nil else { return false }
            if parts.count == 4 && parts[2] == "roles" { return ["PATCH", "DELETE"].contains(route.method) }
            return route.method == "PUT" && parts.count == 5
                && ((parts[2] == "members" && parts[4] == "roles") || (parts[2] == "roles" && parts[4] == "members"))
        }
        if self == .imChannelModerationRead { return route.method == "GET" && route.path == "api/im/moderation/actions" }
        if self == .imChannelModerationReceipt {
            let prefix = "api/channel-platform/governance/moderation/requests/"
            return route.method == "GET" && route.path.hasPrefix(prefix) && UUID(uuidString: String(route.path.dropFirst(prefix.count))) != nil
        }
        if self == .imChannelModerationWrite {
            guard route.method == "POST" else { return false }
            if ["api/im/moderation/timeout", "api/im/moderation/kick", "api/im/moderation/ban"].contains(route.path) { return true }
            let parts = route.path.split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 5 && parts[0] == "api" && parts[1] == "im" && parts[2] == "moderation"
                && NativeChannelGovernanceNotice.positive(String(parts[3])) != nil && parts[4] == "revoke"
        }
        if self == .imChannelAuditRead { return route.method == "GET" && route.path == "api/im/audit-log" }
        if self == .imChannelLifecycleAuditRead {
            let parts = route.path.split(separator: "/", omittingEmptySubsequences: false)
            return route.method == "GET" && parts.count == 4 && parts[0] == "api" && parts[1] == "channels"
                && NativeChannelGovernanceNotice.positive(String(parts[2])) != nil && parts[3] == "op-log"
        }
        // Catalog validation only. Actual requests still require an issued exact route.
        let parts = route.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        switch self {
        case .imChannelAppealRead:
            return route.method == "GET" && (route.path == "api/im/moderation/me" ||
                (parts.count == 4 && Array(parts.prefix(3)) == ["api", "im", "appeals"] && NativeChannelGovernanceNotice.positive(parts[3]) != nil))
        case .imChannelAppealWrite:
            return route.method == "POST" && (route.path == "api/im/appeals" ||
                (parts.count == 5 && Array(parts.prefix(3)) == ["api", "im", "appeals"] && NativeChannelGovernanceNotice.positive(parts[3]) != nil && ["evidence", "withdraw"].contains(parts[4])))
        case .imChannelAppealReceipt:
            return route.method == "GET" && parts.count == 6 &&
                Array(parts.prefix(5)) == ["api", "channel-platform", "governance", "moderation", "requests"] &&
                UUID(uuidString: parts[5])?.uuidString.lowercased() == parts[5]
        default: break
        }
        if self == .imCheckinStatus { return route.method == "GET" && route.path == "api/im/channel/checkin-status" }
        if self == .imCheckinWrite { return route.method == "POST" && route.path == "api/im/channel/checkin" }
        if self == .imCheckinRank { return route.method == "GET" && route.path == "api/im/channel/checkin-rank" }
        if self == .imCheckinReceipt { return route.method == "GET" && route.path == "api/im/channel/checkin-request" }
        if self == .imChainRead { return route.method == "GET" && route.path == "api/im/chain/info" }
        if self == .imChainReceipt { return route.method == "GET" && route.path == "api/im/interaction/request" }
        if self == .imChainCreate { return route.method == "POST" && route.path == "api/im/chain/create" }
        if self == .imChainJoin { return route.method == "POST" && route.path == "api/im/chain/join" }
        if self == .imChainWithdraw { return route.method == "POST" && route.path == "api/im/chain/withdraw" }
        if self == .imChainClose { return route.method == "POST" && route.path == "api/im/chain/close" }
        if self == .imFileUpload { return route.method == "POST" && route.path == "api/im/file/upload" }
        if self == .imFileUploadReceipt { return route.method == "GET" && route.path == "api/im/file/receipt" }
        if self == .imFileScan { return route.method == "POST" && route.path == "api/im/file/scan" }
        if self == .imFileSend { return route.method == "POST" && route.path == "api/im/send" }
        if self == .imFileReceipt { return route.method == "POST" && route.path == "api/im/send-receipt" }
        if self == .imFilePreview || self == .imFilePreviewStatus {
            let prefix = "api/im/file/message/", suffix = self == .imFilePreview ? "/preview" : "/authorization"
            guard route.method == "GET", route.path.hasPrefix(prefix), route.path.hasSuffix(suffix) else { return false }
            let middle = route.path.dropFirst(prefix.count).dropLast(suffix.count)
            return Int(middle).map { $0 > 0 } == true
        }
        if self == .imVideoUpload { return route.method == "POST" && route.path == "api/im/video/upload" }
        if self == .imVideoUploadReceipt { return route.method == "GET" && route.path == "api/im/video/receipt" }
        if self == .imVideoPolicy { return route.method == "GET" && route.path == "api/im/video/policy" }
        if self == .imVideoSend { return route.method == "POST" && route.path == "api/im/send" }
        if self == .imVideoReceipt { return route.method == "POST" && route.path == "api/im/send-receipt" }
        if self == .imVideoPreview || self == .imVideoPreviewStatus {
            let prefix = "api/im/video/message/", suffix = self == .imVideoPreview ? "/preview" : "/authorization"
            guard route.method == "GET", route.path.hasPrefix(prefix), route.path.hasSuffix(suffix) else { return false }
            let middle = route.path.dropFirst(prefix.count).dropLast(suffix.count)
            return Int(middle).map { $0 > 0 } == true
        }
        if self == .imVoiceUpload { return route.method == "POST" && route.path == "api/im/voice/upload" }
        if self == .imVoiceUploadReceipt { return route.method == "GET" && route.path == "api/im/voice/receipt" }
        if self == .imVoicePlaybackStatus {
            let prefix = "api/im/voice/message/", suffix = "/authorization"
            guard route.method == "GET", route.path.hasPrefix(prefix), route.path.hasSuffix(suffix) else { return false }
            let middle = route.path.dropFirst(prefix.count).dropLast(suffix.count)
            return Int(middle).map { $0 > 0 } == true
        }
        if self == .imVoicePlayback {
            let prefix = "api/im/voice/message/"
            return route.method == "GET" && route.path.hasPrefix(prefix) && Int(route.path.dropFirst(prefix.count)).map { $0 > 0 } == true
        }
        if self == .imVoiceSend { return route.method == "POST" && route.path == "api/im/send" }
        if self == .imVoiceReceipt { return route.method == "POST" && route.path == "api/im/send-receipt" }
        if self == .imRouteShareRead { return route.method == "POST" && route.path == "api/im/route-share-source" }
        if self == .imRouteSend { return route.method == "POST" && route.path == "api/im/send" }
        if self == .imRouteReceipt { return route.method == "POST" && route.path == "api/im/send-receipt" }
        if self == .imStaticLocationSend { return route.method == "POST" && route.path == "api/im/send" }
        if self == .imImageUploadReceipt { return route.method == "GET" && route.path == "api/common/uploadOSS/receipt" }
        if self == .imOrdinaryReadReceipt { return route.method == "GET" && route.path == "api/im/read-receipt" }
        if self == .imOrdinaryReadState { return route.method == "GET" && route.path == "api/im/read-state" }
        if self == .imOrdinaryMuteReceipt { return route.method == "GET" && route.path == "api/im/mute-receipt" }
        if self == .imOrdinaryMuteState { return route.method == "GET" && route.path == "api/im/mute-state" }
        if self == .imOrdinarySendReceipt { return route.method == "POST" && route.path == "api/im/send-receipt" }
        if self == .imStaticLocationReceipt { return route.method == "POST" && route.path == "api/im/send-receipt" }
        if self == .imChannelReportReceipt {
            let prefix = "api/channel-platform/governance/reports/requests/"
            guard route.method == "GET", route.path.hasPrefix(prefix) else { return false }
            let requestID = String(route.path.dropFirst(prefix.count))
            return UUID(uuidString: requestID) != nil
        }
        guard route.method == "POST" else { return false }
        let paths: Set<String>
        switch self {
        case .imChainClose, .imChainCreate, .imChainJoin, .imChainRead, .imChainReceipt, .imChainWithdraw, .imChannelReportReceipt, .imCheckinRank, .imCheckinReceipt, .imCheckinStatus, .imCheckinWrite, .imFilePreview, .imFilePreviewStatus, .imFileReceipt, .imFileScan, .imFileSend, .imFileUpload, .imFileUploadReceipt, .imImageUploadReceipt, .imOrdinaryMuteReceipt, .imOrdinaryMuteState, .imOrdinaryReadReceipt, .imOrdinaryReadState, .imOrdinarySendReceipt, .imRouteReceipt, .imRouteSend, .imRouteShareRead, .imStaticLocationReceipt, .imStaticLocationSend, .imVideoPolicy, .imVideoPreview, .imVideoPreviewStatus, .imVideoReceipt, .imVideoSend, .imVideoUpload, .imVideoUploadReceipt, .imVoicePlayback, .imVoicePlaybackStatus, .imVoiceReceipt, .imVoiceSend, .imVoiceUpload, .imVoiceUploadReceipt: return false // independently matched above
        case .imChannelAppealRead, .imChannelAppealWrite, .imChannelAppealReceipt: return false
        case .imChannelPersonalStateRead, .imChannelPersonalStateWrite, .imChannelPersonalStateReceipt: return false // own state has independent exact grants
        case .imChannelRoleRead, .imChannelRoleWrite, .imChannelRoleReceipt, .imChannelRoleMemberRead: return false // independent exact issuance; never borrow read/history authority
        case .imChannelModerationRead, .imChannelModerationWrite, .imChannelModerationReceipt: return false // exact issued routes only
        case .imChannelAuditRead, .imChannelLifecycleAuditRead: return false // exact issued route handled above
        case .bankConsentRead: paths = ["api/compliance/consents/latest"]
        case .bankPrepare: paths = ["api/fund/preflight/bank-withdrawal"]
        case .bankCreate: paths = ["api/withdrawal/create"]
        case .stampUpload, .imUpload: paths = ["api/common/uploadOSS"]
        case .stampCreate: paths = ["api/roam/stamp/create"]
        case .clubChat: paths = ["api/club/chat"]
        case .imPollCreateReceipt: return false // independent original create receipt GET
        case .imPollResult: paths = ["api/im/poll/result"]
        case .imPollCreate: paths = ["api/im/poll/create"]
        case .imPollVote: paths = ["api/im/poll/vote"]
        case .imPollClose: paths = ["api/im/poll/close"]
        case .imChannelMentionMemberRead, .imChannelMentionRoleRead: return false // independent exact original target reads
        case .imChannelAttachmentPreview: return false
        case .imStart: paths = ["api/im/start"]
        case .imRead: paths = ["api/im/read"]
        case .imMute: paths = ["api/im/mute"]
        case .imSend: paths = ["api/im/send", "api/im/send-receipt"]
        case .imDelete: paths = ["api/im/delete"]
        case .imReport: paths = ["api/im/report"]
        case .imBlock: paths = ["api/im/block"]
        case .imUnblock: paths = ["api/im/unblock"]
        case .imUnreadTotal: paths = ["api/im/unread-total"]
        case .publishingRead: paths = ["api/project/state-requests/context", "api/project/state-requests/read", "api/activity/create-requests/read", "api/publish/home", "api/publisher/identity/status", "api/category/list", "api/user/list", "api/template/my-list", "api/project/my", "api/ai/theme/draft/quota"]
        case .topicSelfPlayRead: paths = ["api/topic/info-to-user", "api/registration/info"]
        case .topicSelfPlayCreate: paths = ["api/registration/create"]
        case .topicSelfPlayPay: paths = ["api/registration/pay/app"]
        case .topicSelfPlayConsentRead: paths = ["api/compliance/consents/latest"]
        case .topicSelfPlayConsentWrite: paths = ["api/compliance/consents"]
        case .publishingAIQuota: paths = ["api/ai/theme/draft/quota"]
        case .publishingAITheme: paths = ["api/ai/theme/draft"]
        case .publishingAIClub: paths = ["api/ai/club/design"]
        case .publishingAITemplate: paths = ["api/ai/template/fill"]
        case .publishingWrite: paths = ["api/project/state-requests/submit", "api/activity/create-requests/submit", "api/activity/create-requests/resume-post-processing", "api/activity/publish", "api/topic/create", "api/topic/delete", "api/topic/update_user_status", "api/activity/delete", "api/activity/update_publish_status", "api/template/delete", "api/template/updateLibraryStatus"]
        case .approvedTopicReviewSources: paths = [ApprovedTopicReviewPath.sources]
        case .merchantDraftSelectionList: paths = [ProjectMerchantDraftPath.list]
        case .merchantDraftSelectionResolve: paths = [ProjectMerchantDraftPath.resolve]
        case .approvedTopicReviewPrepare: paths = [ApprovedTopicReviewPath.prepare]
        case .approvedTopicReviewSubmit: paths = [ApprovedTopicReviewPath.submit]
        case .approvedTopicReviewStatus: paths = [ApprovedTopicReviewPath.status]
        case .approvedTopicReviewCurrent: paths = [ApprovedTopicReviewPath.current]
        case .approvedTopicReleasePrepare: paths = [ApprovedTopicReleasePaths.prepare]
        case .approvedTopicReleasePublish: paths = [ApprovedTopicReleasePublicationPath.publish]
        case .approvedTopicReleaseStatus: paths = [ApprovedTopicReleasePublicationPath.status]
        case .projectAuthorInputRead: return false // Exact methods handled above.
        case .projectRead: paths = ["api/publish/home", "api/topic/edit-detail", ProjectEditRequestContract.readPath]
        case .projectWrite: paths = ["api/topic/create", "api/topic/update", "api/topic/v2/create", "api/topic/v2/update", ProjectEditRequestContract.submitPath, ProjectEditRequestContract.resumePostProcessingPath]
        case .directVerification: paths = ["api/merchant/access/me", "api/verify/groupcode/redeem", "api/coupon/verification", "api/registration/scan_dynamic_code", "api/registration/scan_qr_code", "api/registration/scan_qr_code_chapter", "api/registration/scan_qr_code_station", "api/verify/citynode/redeem"]
        }
        return paths.contains(route.path)
    }
}
