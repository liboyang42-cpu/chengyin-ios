import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mini-program app.js loadFeatureFlags: POST /api/config/features (anonymous, token optional,
/// 6 s timeout) on every launch, after sign-in and when the account changes. Only an exact
/// JSON true enables a flag; anything else stays off. A response that arrives after the
/// account or token changed is discarded.
public struct LaunchFeatureFlags: Equatable {
    public static let knownKeys = ["drops", "roamDemoPois", "finishNearbyRoute", "clubMembership", "roamNpcEvent", "roamNpcChat",
                                   "shopNpcChat", "shopNpcVoice", "shopNpcVoiceAvailable", "merchantNpcChat", "communityPostRead", "communityPostWrite"]
    public let enabled: Set<String>
    public static let allOff = LaunchFeatureFlags(enabled: [])
    public init(enabled: Set<String>) { self.enabled = enabled.intersection(Self.knownKeys) }
    public func isOn(_ key: String) -> Bool { enabled.contains(key) }

    public static func decode(_ data: Data) throws -> LaunchFeatureFlags {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = root["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID(), code.intValue == 200 else {
            throw APIError.malformedResponse
        }
        guard let values = root["data"] as? [String: Any] else { return .allOff }
        let on = values.compactMap { key, value -> String? in
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), number.boolValue else { return nil }
            return key
        }
        return LaunchFeatureFlags(enabled: Set(on))
    }
}

public enum LaunchFeatureFlagsOutcome: Equatable {
    case loaded(LaunchFeatureFlags)
    /// Endpoint not on the reviewed allowlist, no configuration, or a failed/late read: all flags off.
    case unavailable
}

public enum LaunchFeatureFlagsMountState: Equatable {
    case unmountedAllowlistPending
    case loaded([String: Bool])
    case failed

    public func isEnabled(_ flag: String) -> Bool {
        guard case let .loaded(flags) = self, LaunchFeatureFlags.knownKeys.contains(flag) else {
            return false
        }
        return flags[flag] == true
    }

    public var statusNotice: String {
        switch self {
        case .unmountedAllowlistPending:
            return "功能开关待接入白名单"
        case .loaded:
            return "功能开关已加载"
        case .failed:
            return "功能开关加载失败，已回退默认关闭"
        }
    }

    public static func fromOutcome(_ outcome: LaunchFeatureFlagsOutcome, approved: Bool = false) -> LaunchFeatureFlagsMountState {
        guard approved else { return .unmountedAllowlistPending }
        switch outcome {
        case let .loaded(flags):
            var values: [String: Bool] = [:]
            for key in LaunchFeatureFlags.knownKeys {
                values[key] = flags.isOn(key)
            }
            return .loaded(values)
        case .unavailable:
            return .failed
        }
    }
}

public struct PrivacyGuideSummaryItem: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct PrivacyGuideSummaryPresentation: Equatable {
    public static let defaultItems: [PrivacyGuideSummaryItem] = [
        PrivacyGuideSummaryItem(
            id: "collection_scope",
            title: "信息收集范围",
            detail: "仅在提供剧本组局、漫游打卡与账号安全服务所必需的范围内收集基础账号信息。"
        ),
        PrivacyGuideSummaryItem(
            id: "permission_usage",
            title: "权限使用说明",
            detail: "位置、相册与通知等系统权限仅在对应功能触发时申请，拒绝授权不影响基础浏览。"
        ),
        PrivacyGuideSummaryItem(
            id: "revoke_and_deregister",
            title: "撤回同意与注销入口",
            detail: "可随时在设置与隐私保护页面撤回位置、营销授权或发起账号注销申请。"
        )
    ]

    public let items: [PrivacyGuideSummaryItem]
    public let pendingBundledSourceNotice: String

    public init(
        items: [PrivacyGuideSummaryItem] = PrivacyGuideSummaryPresentation.defaultItems,
        pendingBundledSourceNotice: String = "完整隐私保护指引正文待法务终稿内置，当前展示核心合规摘要。"
    ) {
        self.items = items
        self.pendingBundledSourceNotice = pendingBundledSourceNotice
    }
}

public final class LaunchFeatureFlagsReader {
    public static let path = "api/config/features"
    private let configuration: APIConfiguration?
    private let transport: HTTPTransport?
    private let approved: Bool
    private let currentIdentity: () -> String?

    /// `approved` must come from the reviewed per-market endpoint allowlist; it is false today.
    public init(configuration: APIConfiguration?, transport: HTTPTransport?, approved: Bool, currentIdentity: @escaping () -> String?) {
        self.configuration = configuration; self.transport = transport; self.approved = approved; self.currentIdentity = currentIdentity
    }

    public static func request(baseURL: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 6)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, AuthRequestBuilder.isValidToken(token) { request.setValue(token, forHTTPHeaderField: "Authorization") }
        return request
    }

    public func load(token: String?) async -> LaunchFeatureFlagsOutcome {
        guard approved, let configuration, let transport else { return .unavailable }
        let identity = currentIdentity()
        do {
            let (data, status) = try await transport.send(Self.request(baseURL: configuration.baseURL, token: token))
            guard status == 200, currentIdentity() == identity else { return .unavailable }
            return .loaded(try LaunchFeatureFlags.decode(data))
        } catch { return .unavailable }
    }
}
