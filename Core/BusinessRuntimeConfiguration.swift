import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum BusinessRuntimeFeature: Hashable {
    case bankConsentRead, bankPrepare, bankCreate, stampUpload, stampCreate
    case imStart, imRead, imMute, imSend, imUpload
    case imPollResult, imPollCreate, imPollVote, imPollClose, clubChat
    case publishingRead, publishingWrite, projectRead, projectWrite, directVerification
    case publishingAIQuota, publishingAITheme, publishingAIClub, publishingAITemplate
    case approvedTopicReleasePrepare, approvedTopicReleasePublish, approvedTopicReleaseStatus
    case approvedTopicReviewPrepare, approvedTopicReviewSubmit, approvedTopicReviewStatus, approvedTopicReviewCurrent
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
        guard route.method == "POST" else { return false }
        let paths: Set<String>
        switch self {
        case .bankConsentRead: paths = ["api/compliance/consents/latest"]
        case .bankPrepare: paths = ["api/fund/preflight/bank-withdrawal"]
        case .bankCreate: paths = ["api/withdrawal/create"]
        case .stampUpload, .imUpload: paths = ["api/common/uploadOSS"]
        case .stampCreate: paths = ["api/roam/stamp/create"]
        case .clubChat: paths = ["api/club/chat"]
        case .imPollResult: paths = ["api/im/poll/result"]
        case .imPollCreate: paths = ["api/im/poll/create"]
        case .imPollVote: paths = ["api/im/poll/vote"]
        case .imPollClose: paths = ["api/im/poll/close"]
        case .imStart: paths = ["api/im/start"]
        case .imRead: paths = ["api/im/read"]
        case .imMute: paths = ["api/im/mute"]
        case .imSend: paths = ["api/im/send"]
        case .publishingRead: paths = ["api/publish/home", "api/publisher/identity/status", "api/category/list", "api/user/list", "api/template/my-list", "api/project/my", "api/ai/theme/draft/quota"]
        case .topicSelfPlayRead: paths = ["api/topic/info-to-user", "api/registration/info"]
        case .topicSelfPlayCreate: paths = ["api/registration/create"]
        case .topicSelfPlayPay: paths = ["api/registration/pay/app"]
        case .topicSelfPlayConsentRead: paths = ["api/compliance/consents/latest"]
        case .topicSelfPlayConsentWrite: paths = ["api/compliance/consents"]
        case .publishingAIQuota: paths = ["api/ai/theme/draft/quota"]
        case .publishingAITheme: paths = ["api/ai/theme/draft"]
        case .publishingAIClub: paths = ["api/ai/club/design"]
        case .publishingAITemplate: paths = ["api/ai/template/fill"]
        case .publishingWrite: paths = ["api/activity/publish", "api/topic/create", "api/topic/delete", "api/topic/update_user_status", "api/activity/delete", "api/activity/update_publish_status", "api/template/delete", "api/template/updateLibraryStatus"]
        case .approvedTopicReviewPrepare: paths = [ApprovedTopicReviewPath.prepare]
        case .approvedTopicReviewSubmit: paths = [ApprovedTopicReviewPath.submit]
        case .approvedTopicReviewStatus: paths = [ApprovedTopicReviewPath.status]
        case .approvedTopicReviewCurrent: paths = [ApprovedTopicReviewPath.current]
        case .approvedTopicReleasePrepare: paths = [ApprovedTopicReleasePaths.prepare]
        case .approvedTopicReleasePublish: paths = [ApprovedTopicReleasePublicationPath.publish]
        case .approvedTopicReleaseStatus: paths = [ApprovedTopicReleasePublicationPath.status]
        case .projectRead: paths = ["api/publish/home", "api/topic/edit-detail"]
        case .projectWrite: paths = ["api/topic/create", "api/topic/update", "api/topic/v2/create", "api/topic/v2/update"]
        case .directVerification: paths = ["api/merchant/access/me", "api/verify/groupcode/redeem", "api/coupon/verification", "api/registration/scan_dynamic_code", "api/registration/scan_qr_code", "api/registration/scan_qr_code_chapter", "api/registration/scan_qr_code_station", "api/verify/citynode/redeem"]
        }
        return paths.contains(route.path)
    }
}
