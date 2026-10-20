import Foundation

/// Mini-program subpackageA/pages/myproject (C6): one manager with topic / activity / template tabs.
/// Topic and activity rows come from the existing `api/project/my` read; the template tab is the
/// separate `api/template/my-list` own-shelf and never reuses project rows.
public enum MyProjectTab: String, CaseIterable, Equatable, Hashable, Sendable {
    case topic, activity, template

    /// Legacy `type=` query mapping: club_activity → activity, template → template, everything else → topic.
    public init(legacyType: String?) {
        switch legacyType {
        case "club_activity": self = .activity
        case "template": self = .template
        default: self = .topic
        }
    }
    public var localizationKey: String { "myProject.tab." + rawValue }
}

/// Where tapping a project card leads. Presentation only; no route grants a write.
public enum MyProjectCardRoute: Equatable, Sendable {
    /// Draft / rejected topic → professional editor (`publish/fabu?id=`).
    case topicEditor(Int)
    /// Pending / rejected activity the caller may edit → activity editor (`publish/activity?id=`).
    case activityEditor(Int)
    case activityDetail(Int)
    /// Published topic → host project home (`topic/merchantinfo?topicId=`).
    case projectHome(Int)
}

/// Long-press list-management actions. The mini-program writes these directly; iOS only shows which
/// ones would apply and keeps every mutation disabled until a reviewed endpoint allowlist exists.
public enum MyProjectRowOperation: String, CaseIterable, Equatable, Sendable {
    case viewApplies, edit, toggle, cancel, delete
    public var localizationKey: String { "myProject.op." + rawValue }
}

public struct MyProjectCardPresentation: Equatable, Sendable {
    public let roleKey: String
    public let pending: Bool
    public let online: Bool
    public let operations: [MyProjectRowOperation]
    public let toggleKey: String
    public let route: MyProjectCardRoute?
}

public enum MyProjectListPresentation {
    public static let loadCap = 200
    private static let pendingRanks = ["rejected": 0, "draft": 1, "pending": 2]

    public static func pendingRank(_ state: String?) -> Int { state.flatMap { pendingRanks[$0] } ?? 9 }

    /// Rejected > draft > pending first, everything else keeps the server order (stable).
    public static func sorted(_ rows: [CreatorContentProject]) -> [CreatorContentProject] {
        rows.enumerated().sorted { lhs, rhs in
            let l = pendingRank(lhs.element.state), r = pendingRank(rhs.element.state)
            return l == r ? lhs.offset < rhs.offset : l < r
        }.map(\.element)
    }

    public static func rows(for tab: MyProjectTab, in all: [CreatorContentProject]) -> [CreatorContentProject] {
        guard tab != .template else { return [] }
        return sorted(all.filter { $0.bizType == tab.rawValue })
    }

    /// The only co-host shape in this list is the activity generated after winning someone else's topic.
    public static func roleKey(bizType: String, ownerType: String?) -> String {
        bizType == "activity" && ownerType == "merchant" ? "myProject.role.coHost" : "myProject.role.host"
    }

    public static func emptyKeys(for tab: MyProjectTab, canPublishActivity: Bool) -> (title: String, detail: String?) {
        switch tab {
        case .topic: return ("myProject.empty.topic", "myProject.empty.topicDetail")
        case .activity: return canPublishActivity ? ("myProject.empty.activity", "myProject.empty.activityPublish") : ("myProject.empty.activity", nil)
        case .template: return ("myProject.empty.template", "myProject.empty.templateDetail")
        }
    }

    /// Mini `_showAccept`: only topic cards with an acceptance state other than `selfRun` show its text.
    public static func acceptanceText(_ p: CreatorContentProject) -> String? {
        guard p.bizType == "topic", let status = p.acceptStatus, !status.isEmpty, status != "selfRun",
              let text = p.acceptStatusText, !text.isEmpty else { return nil }
        return text
    }

    /// Mini empty CTA: topic → 去发布; activity → 发布单场活动 only for those who may publish; template has none.
    public static func emptyCTAKey(for tab: MyProjectTab, canPublishActivity: Bool) -> String? {
        switch tab {
        case .topic: return "myProject.cta.topic"
        case .activity: return canPublishActivity ? "myProject.cta.activity" : nil
        case .template: return nil
        }
    }

    public static func card(
        _ p: CreatorContentProject,
        canEditActivity: Bool = true,
        merchantScopeAccess: MyProjectMerchantScopeAccess = .init()
    ) -> MyProjectCardPresentation {
        let state = p.state ?? ""
        let online = state == "running" || state == "notStarted"
        let merchantActivity = p.ownerType == "merchant" && p.bizType == "activity"
        let sold = p.bizType == "activity" && p.signupCount > 0
        let publishedActivity = p.bizType == "activity" && ["running", "notStarted", "offline", "pending", "rejected"].contains(state)
        let allowWrite = !merchantScopeAccess.isBrowseOnly
        let canEdit = allowWrite && !merchantActivity && publishedActivity
        let canToggle = allowWrite && !merchantActivity && (online || state == "offline")
        let canDelete = allowWrite && !merchantActivity && ["draft", "offline", "rejected", "completed"].contains(state)
        let canCancel = allowWrite && (p.bizType == "topic"
            ? (p.ownerType != "club" && (online || state == "offline"))
            : (!merchantActivity && sold && (online || state == "offline")))
        let accepted = p.acceptStatus == "clubAccepted" || p.acceptStatus == "merchantAccepted"
        let canViewApplies = p.bizType == "topic" && (p.acceptStatus == "clubOpen" || p.acceptStatus == "merchantOpen" || accepted)
        var ops: [MyProjectRowOperation] = []
        if canViewApplies { ops.append(.viewApplies) }
        if canEdit { ops.append(.edit) }
        if canToggle { ops.append(.toggle) }
        if canCancel { ops.append(.cancel) }
        if canDelete { ops.append(.delete) }
        return .init(roleKey: roleKey(bizType: p.bizType, ownerType: p.ownerType), pending: pendingRanks[state] != nil,
                     online: online, operations: ops, toggleKey: state == "offline" ? "myProject.op.toggleOn" : "myProject.op.toggleOff",
                     route: resolveRoute(p, canEditActivity: canEdit && canEditActivity, merchantScopeAccess: merchantScopeAccess))
    }

    public static func resolveRoute(
        _ p: CreatorContentProject,
        canEditActivity: Bool = true,
        merchantScopeAccess: MyProjectMerchantScopeAccess = .init()
    ) -> MyProjectCardRoute? {
        let merchantActivity = p.ownerType == "merchant" && p.bizType == "activity"
        let publishedActivity = p.bizType == "activity" && ["running", "notStarted", "offline", "pending", "rejected"].contains(p.state ?? "")
        let allowEdit = !merchantScopeAccess.isBrowseOnly && !merchantActivity && publishedActivity && canEditActivity
        return route(p, canEdit: allowEdit, allowTopicEditor: !merchantScopeAccess.isBrowseOnly)
    }

    static func route(_ p: CreatorContentProject, canEdit: Bool, allowTopicEditor: Bool = true) -> MyProjectCardRoute? {
        guard p.sourceID > 0 else { return nil }
        switch p.bizType {
        case "topic":
            if p.state == "draft" || p.state == "rejected" {
                return allowTopicEditor ? .topicEditor(p.sourceID) : .projectHome(p.sourceID)
            }
            return .projectHome(p.sourceID)
        case "activity":
            return canEdit && (p.state == "pending" || p.state == "rejected") ? .activityEditor(p.sourceID) : .activityDetail(p.sourceID)
        default: return nil
        }
    }

    /// Mini `whenText`: "8月23日 19:20—21:00"; cross-day shows both days; missing start hides the line.
    /// A 00:00 clock is treated as "no clock"; a single-day row without both clocks reads "全天".
    public static func whenText(start: String?, end: String?, chinese: Bool) -> String? {
        let s = (start ?? "").trimmingCharacters(in: .whitespaces), e = (end ?? "").trimmingCharacters(in: .whitespaces)
        guard let sd = day(s, chinese: chinese) else { return nil }
        let ed = day(e, chinese: chinese)
        if let ed, ed != sd { return sd + " – " + ed }
        let sc = clock(s), ec = clock(e)
        if let sc, let ec { return sd + " " + sc + "—" + ec }
        return sd + (sc.map { " " + $0 } ?? (chinese ? " 全天" : " all day"))
    }

    private static func day(_ value: String, chinese: Bool) -> String? {
        let parts = value.prefix(10).split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        if chinese { return "\(month)月\(day)日" }
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(names[month - 1]) \(day)"
    }

    private static func clock(_ value: String) -> String? {
        guard value.count >= 16 else { return nil }
        let chars = Array(value)
        guard chars[10] == "T" || chars[10] == " " else { return nil }
        let hh = String(chars[11...12]), mm = String(chars[14...15])
        guard chars[13] == ":", Int(hh) != nil, Int(mm) != nil, !(hh == "00" && mm == "00") else { return nil }
        return hh + ":" + mm
    }
}

/// Merchant scope (`scope=MERCHANT`) + `merchant/access/me` project-manage gate for `subpackageA/pages/myproject`.
public struct MyProjectMerchantScopeAccess: Equatable, Sendable {
    public static let projectManagePermission = "merchant:project:manage"
    public static let browseOnlyNoticeText = "当前岗位仅可查看门店项目，需项目管理权限才能发布或修改"

    public let isMerchantScope: Bool
    public let canManageProjects: Bool

    public init(isMerchantScope: Bool = false, canManageProjects: Bool = true) {
        self.isMerchantScope = isMerchantScope
        self.canManageProjects = isMerchantScope ? canManageProjects : true
    }

    public init(scope: String?, merchantAccess: MerchantMarketingAccess?) {
        let normalized = (scope ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isMerchant = normalized == "MERCHANT"
        let hasManage = merchantAccess.map { $0.active && $0.permissions.contains(Self.projectManagePermission) } ?? false
        self.init(isMerchantScope: isMerchant, canManageProjects: isMerchant ? hasManage : true)
    }

    public var isBrowseOnly: Bool { isMerchantScope && !canManageProjects }
    public var browseOnlyNotice: String? { isBrowseOnly ? Self.browseOnlyNoticeText : nil }
}

/// AI Quick Publishing (`pages/publish/simple`) max-3-points and per-point POI confirmation state helper.
public struct QuickPublishPointValidation: Equatable, Sendable {
    public static let minimumPoints = 1
    public static let maximumPoints = 3

    public struct PointState: Equatable, Sendable {
        public let id: UUID
        public let index: Int
        public let hasName: Bool
        public let isPOIConfirmed: Bool
        public var isReady: Bool { hasName && isPOIConfirmed }
    }

    public let points: [PointState]

    public init(nodes: [QuickPublishNode]) {
        self.points = nodes.enumerated().map { index, node in
            let hasName = !node.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isConfirmed: Bool
            if let place = node.confirmedPlace {
                isConfirmed = !place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && place.latitude.isFinite
                    && place.longitude.isFinite
            } else {
                isConfirmed = false
            }
            return PointState(id: node.id, index: index, hasName: hasName, isPOIConfirmed: isConfirmed)
        }
    }

    public init(draft: QuickPublishDraft) {
        self.init(nodes: draft.nodes)
    }

    public var count: Int { points.count }
    public var canAddPoint: Bool { points.count < Self.maximumPoints }
    public var exceedsMaximumPoints: Bool { points.count > Self.maximumPoints }
    public var isCountWithinBounds: Bool { (Self.minimumPoints...Self.maximumPoints).contains(points.count) }
    public var unconfirmedPointIDs: [UUID] { points.filter { !$0.isPOIConfirmed }.map(\.id) }
    public var allPOIsConfirmed: Bool { !points.isEmpty && points.allSatisfy(\.isPOIConfirmed) }
    public var isValid: Bool { isCountWithinBounds && points.allSatisfy(\.isReady) }

    public func isPOIConfirmed(for id: UUID) -> Bool {
        points.first(where: { $0.id == id })?.isPOIConfirmed ?? false
    }
}
