import Foundation

public struct NativeWebhookEditorDraft: Equatable, Sendable {
    public var name: String
    public var url: String = ""
    public var replaceURL = false
    public var avatarURL: String
    public var events: Set<String>
    public var allowedIPs: String
    public var rateLimit: String
    public var active: Bool
    public init(resource: NativeWebhookResource? = nil) {
        name = resource?.name ?? ""; avatarURL = resource?.avatarURL ?? ""
        events = Set(resource?.events ?? []); allowedIPs = resource?.allowedIPs?.joined(separator: "\n") ?? ""
        rateLimit = resource?.rateLimitPerMinute.map(String.init) ?? ""
        active = resource?.status != .paused // e74 creates enabled resources; no local grant follows from this default.
    }
    public func change(family: NativeWebhookFamily, context: NativeWebhookContext, original: NativeWebhookResource?,
                       requestID: NativeWebhookRequestID) throws -> NativeWebhookChange {
        let scope = context.binding.scope
        var value = NativeWebhookChange(requestID: requestID, ownerType: "CLUB", ownerID: scope.ownerID.requestNumber,
            channelID: scope.channelID.requestNumber, name: name, status: active ? .active : .paused, revision: original?.revision)
        if family == .subscription {
            value.url = original == nil || replaceURL ? url : nil
            value.events = original?.events.map { Set($0) == events ? $0 : events.sorted() } ?? events.sorted()
        } else {
            guard let rate = Int(rateLimit), (1...300).contains(rate) else { throw NativeWebhookClientError.invalidInput("RATE_LIMIT_RANGE") }
            value.rateLimitPerMinute = rate
            value.allowedIPs = allowedIPs.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            value.avatarURL = avatarURL.isEmpty ? nil : avatarURL
        }
        return value
    }
}

public struct NativeWebhookConfirmation: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let message: String
    public let requestID: NativeWebhookRequestID
    public init(title: String, message: String, requestID: NativeWebhookRequestID) {
        id = UUID(); self.title = title; self.message = message; self.requestID = requestID
    }
}
public enum NativeWebhookPhase: Equatable, Sendable { case dormant, loading, ready, empty, denied, unknown, unavailable, revoked }
public enum NativeWebhookPresentation {
    public static func delivery(_ state: NativeWebhookDeliveryState) -> String {
        switch state {
        case .pending: return "排队中"; case .inflight: return "投递中"; case .sent: return "已送达"
        case .failed: return "投递失败"; case .dead: return "已进入死信"; case .unknown: return "结果未知"; case .cancelled: return "已取消"
        }
    }
    public static func inbound(_ state: NativeWebhookInboundState) -> String {
        switch state {
        case .pendingReview: return "原图片已提交，等待原审核，不代表已接受"
        case .received: return "已接收，尚未确认消息结果"; case .accepted: return "消息已接受"
        case .rejected: return "已拒绝"; case .blocked: return "已阻止"; case .rateLimited: return "已限流"; case .unknown: return "结果未知"
        }
    }
    public static func error(_ error: NativeWebhookClientError) -> String {
        switch error {
        case .sourceUnavailable(let code): return "当前来源尚不可用（\(code)）"
        case .scopeChanged: return "账号、频道或授权已变化，请返回频道重新进入。"
        case .invalidWire: return "响应内容不完整，未确认结果。"
        case .invalidInput(let code): return "请检查输入（\(code)）"
        case .originalInputRequired: return "请重新输入原操作的完整 URL，以匹配原请求后恢复。"
        case .denied(let code, _): return "当前没有管理权限（\(code)）"
        case .conflict(let code, _): return "原请求或版本冲突（\(code)），请回读核对，不会覆盖。"
        case .rejected(_, let code, _): return "请求被拒绝（\(code)）"
        case .resultUnknown: return "操作结果未知。请恢复原请求并回读资源，不要新建相同操作。"
        case .cancelled: return "操作已取消。"
        }
    }
}
