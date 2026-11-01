import Foundation

/// C11 data-deletion evidence TABLE of existing-writer dispositions.
/// Not a cleaner and not DDL. Retention windows are recorded only, not executed.
/// Empty current projection is not “never existed”.
public enum DataDeletionEvidenceTable {
    public enum Disposition: String, Equatable, Sendable {
        case removed = "REMOVED"
        case anonymizedRetained = "ANONYMIZED_RETAINED"
        case retainedLegal = "RETAINED_LEGAL"
        case retentionWindow = "RETENTION_WINDOW"
    }

    public static let browseDays = 180
    public static let eventDays = 365
    public static let npcChatDays = 90
    public static let npcChatRequestHours = 48
    public static let roamLocationDays = 30
    public static let executesCleanup = false
    public static let writesDDL = false
    /// Empty current projection is not “never existed”.
    public static let emptyCurrentProjectionIsNeverExisted = false

    public struct Row: Equatable, Sendable {
        public var requestKind: String
        public var artifact: String
        public var disposition: Disposition
        public var existingWriter: String
        public var note: String
        public var retentionDays: Int?
        public var retentionHours: Int?

        public var removed: Bool { disposition == .removed }
        public var retained: Bool {
            disposition == .anonymizedRetained || disposition == .retainedLegal
        }
    }

    public static let rows: [Row] = buildTable()

    public static var removed: [Row] { rows.filter(\.removed) }
    public static var retained: [Row] { rows.filter(\.retained) }

    public static func byRequestKind(_ requestKind: String?) -> [Row] {
        guard let kind = SupportUntrusted.requestID(requestKind) else { return [] }
        return rows.filter { $0.requestKind == kind }
    }

    public static func require(_ artifact: String) -> Row? {
        rows.first { $0.artifact == artifact }
    }

    private static func buildTable() -> [Row] {
        var rows: [Row] = []
        func add(
            _ kind: String,
            _ artifact: String,
            _ disposition: Disposition,
            _ writer: String,
            _ note: String,
            days: Int? = nil,
            hours: Int? = nil
        ) {
            rows.append(Row(
                requestKind: kind,
                artifact: artifact,
                disposition: disposition,
                existingWriter: writer,
                note: note,
                retentionDays: days,
                retentionHours: hours
            ))
        }
        add("ACCOUNT_DEREGISTER", "member_identity", .removed, "deleteMemberIdentity",
            "实名姓名+身份证密文无留存理由")
        add("ACCOUNT_DEREGISTER", "member_address", .removed, "deleteMemberAddresses",
            "收货地址整行删除")
        add("ACCOUNT_DEREGISTER", "app_session", .removed, "appSessionRegistryService.revokeAll",
            "注销后旧登录态全部撤销")
        add("ACCOUNT_DEREGISTER", "community_post_actions", .removed, "deleteAccountPostActions",
            "点赞等动作行删除")
        add("ACCOUNT_DEREGISTER", "community_comment_actions", .removed, "deleteAccountCommentActions",
            "评论动作行删除")
        add("ACCOUNT_DEREGISTER", "community_mutes", .removed, "deleteAccountMutes",
            "屏蔽关系删除")
        add("ACCOUNT_DEREGISTER", "notifications", .removed, "deleteAccountNotifications",
            "通知本体删除")
        add("ACCOUNT_DEREGISTER", "notification_preferences", .removed, "deleteAccountNotificationPreferences",
            "通知偏好删除")
        add("ACCOUNT_DEREGISTER", "mentions", .removed, "deleteAccountMentions",
            "提及行删除")
        add("ACCOUNT_DEREGISTER", "ums_member", .anonymizedRetained, "anonymizeMember",
            "会员行保留、PII 剥离、delFlag=2")
        add("ACCOUNT_DEREGISTER", "oms_order", .anonymizedRetained, "anonymizeOrders",
            "订单行保留以便资金对账，不删金额")
        add("ACCOUNT_DEREGISTER", "cms_registration", .anonymizedRetained, "anonymizeRegistrations",
            "报名行保留、联系方式剥离")
        add("ACCOUNT_DEREGISTER", "member_withdrawal", .anonymizedRetained, "anonymizeMemberWithdrawal",
            "银行卡提现行保留、姓名卡号剥离")
        add("ACCOUNT_DEREGISTER", "cash_withdraw", .anonymizedRetained, "anonymizeCashWithdraw",
            "微信提现行保留、openid 剥离")
        add("ACCOUNT_DEREGISTER", "community_post_authors", .anonymizedRetained, "anonymizeAccountPostAuthors",
            "历史帖作者匿名，正文按治理规则另处理")
        add("ACCOUNT_DEREGISTER", "business_audit_event", .retainedLegal, "BusinessAuditEvent append-only",
            "原 request 审计不可删，支持台回查用")
        add("ACCOUNT_DEREGISTER", "club_edition_compensation_terms", .retainedLegal, "freezeTermsForSale immutable",
            "开售冻结补偿条款不随注销改写")
        add("ACCOUNT_DEREGISTER", "audit_record", .retainedLegal, "AuditRecord review trail",
            "审核裁决原记录不删")
        add("RETENTION_CLEANUP", "tms_browse_record", .retentionWindow, "cleanBrowseRecords",
            "浏览记录含 IP/UA，默认 180 天", days: browseDays)
        add("RETENTION_CLEANUP", "biz_event_log", .retentionWindow, "cleanBizEventLogs",
            "行为事件默认 365 天", days: eventDays)
        add("RETENTION_CLEANUP", "npc_chat_log", .retentionWindow, "cleanNpcChatLogs",
            "NPC 原文默认 90 天", days: npcChatDays)
        add("RETENTION_CLEANUP", "npc_chat_request", .retentionWindow, "cleanNpcChatRequests",
            "幂等终态 48 小时，不替代 npc_chat_log", hours: npcChatRequestHours)
        add("RETENTION_CLEANUP", "roam_location", .retentionWindow, "cleanRoamLocations",
            "漫游详细位置 30 天，聚合 XP/距离保留", days: roamLocationDays)
        return rows
    }
}
