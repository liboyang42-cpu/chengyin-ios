import Foundation

/// Original task/trace facts associated with this immutable edit request, not current project metadata.
public struct ProjectEditPostProcessingReceipt: Codable, Equatable {
    public struct Audit: Codable, Equatable {
        public let taskID: Int
        public let association: String
        public let submissionRecordID: Int?
        public let snapshotSHA256: String
        public let state: String
        public let actions: [String]
    }
    public struct Media: Codable, Equatable {
        public let mediaSHA256: String
        public let traceSHA256: String?
        public let state: String
        public let risky: Bool?
    }
    public let protocolVersion: String
    public let requestID: String
    public let payloadSHA256: String
    public let spotCheckState: String
    public let audits: [Audit]
    public let media: [Media]
    public let creativeState: String
    /// Recovery only resumes unfinished original post-processing; it never submits a project again.
    public let canResume: Bool
    public static func label(_ code: String) -> String {
        switch code {
        case "PENDING": return "等待处理"
        case "FAILED": return "尚未完成，可继续"
        case "NOT_REQUIRED": return "本次无需处理"
        case "DEFERRED_DRAFT": return "草稿仅保留标记，未公开提审"
        case "RECORDED": return "原处理记录已保存"
        case "STALE_SOURCE": return "内容已变化，未继续旧请求处理"
        case "SUPERSEDED": return "已有后续投稿轮次"
        case "AWAITING_NEW_RECORD": return "等待原审核台后续记录"
        case "RECORDED_DECISION": return "已读回关联审核记录"
        case "WAITING", "PROCESSING": return "等待媒体审核回调"
        case "DONE": return "媒体回调已处理"
        case "RETRYABLE_CALLBACK": return "原回调队列等待恢复"
        case "IGNORED_STALE": return "旧媒体回调已忽略"
        case "MANUAL_REVIEW": return "需要原流程人工复核"
        case "NOT_CONFIGURED": return "送检服务尚未配置"
        case "REGISTERED": return "原送检回执已登记"
        case "WRITER_BUNDLE_SUBMISSION": return "本次组合提审"
        case "SPOT_CHECK_REUSED": return "复用原开放抽检单（未新提审）"
        case "SPOT_CHECK_CREATED": return "本次新增原抽检单"
        case "APPROVE": return "通过"
        case "REJECT": return "驳回"
        case "REVERT": return "原裁决已撤回"
        case "CANCEL": return "取消"
        case "ESCALATE": return "升级复核"
        default: return "状态暂不能确定，未重复发送"
        }
    }

}
