import Foundation

public enum ClubGovernanceValidation {
    static func require(_ condition: Bool) throws { if !condition { throw ClubGovernanceFailure.malformed } }
    static func rows(_ value: ClubGovernanceValue) throws -> [ClubGovernanceValue] {
        guard let rows = value.array, rows.allSatisfy({ $0.object != nil }) else { throw ClubGovernanceFailure.malformed }; return rows
    }
    static func positive(_ value: ClubGovernanceValue) -> Bool { (value.int ?? 0) > 0 }
    static func count(_ value: ClubGovernanceValue) -> Bool { (value.int ?? -1) >= 0 }
    static func nonempty(_ value: ClubGovernanceValue) -> Bool { !(value.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    static func version(_ value: ClubGovernanceValue) -> Bool { if case .integer(let n) = value { return n >= 0 }; return false }
    static func unique(_ rows: [ClubGovernanceValue], key: String) throws {
        let keys = rows.compactMap { $0[key].int }; try require(keys.count == rows.count && Set(keys).count == rows.count && keys.allSatisfy { $0 > 0 })
    }
    public static func validate(_ value: ClubGovernanceValue, operation: ClubGovernanceRead, scope: ClubGovernanceScope) throws -> ClubGovernanceValue {
        var accepted = value
        switch operation {
        case .access: _ = try ClubGovernancePermissions(value: value, scope: scope)
        case .members:
            let list = try rows(value); try unique(list, key: "memberId")
        case .hostStatus: try require(value["registered"].bool != nil)
        case .stats:
            try require(value["clubId"].int == scope.clubID && count(value["topicCount"]) && count(value["participants"]) && count(value["completed"]) && (value["overallRate"].number ?? -1) >= 0)
            let list = try rows(value["topics"]); try unique(list, key: "topicId")
            for row in list { try require(count(row["participants"]) && count(row["completed"]) && (row["completionRate"].number ?? -1) >= 0) }
        case .customerCount: try require(count(value["total"]))
        case .customers:
            try require(count(value["total"]) && count(value["monthNew"]))
            let list = try rows(value["items"]); try unique(list, key: "memberId")
            for row in list { try require(count(row["verifiedCount"]) && count(row["pendingCount"])) }
        case .customer:
            let summary = value["summary"]
            try require(summary["memberId"].int == scope.memberID && count(summary["arrivedCount"]) && count(summary["pendingCount"]) && count(summary["refundedCount"]))
            if summary["paidAmount"] != .null && summary["paidAmount"] != .string("") { try require((summary["paidAmount"].number ?? -1) >= 0) }
            for row in try rows(value["records"]) { try require(nonempty(row["key"]) && ["VERIFIED", "PENDING", "CONTACTED", "REFUNDED", "REGISTERED"].contains(row["statusCode"].string ?? "")) }
            guard let tags = value["tags"].array else { throw ClubGovernanceFailure.malformed }
            try require(tags.allSatisfy { nonempty($0) || nonempty($0["name"]) })
        case .checkin:
            try require(value["registrationId"].int == scope.registrationID && value["railStep"].int != nil && ["REFUNDED", "REVIEWED", "VERIFIED", "CONTACTED", "PENDING"].contains(value["statusCode"].string ?? ""))
        case .settlement: try validateSettlement(value)
        case .eventTopics, .topics:
            let list = try rows(value); try unique(list, key: "id")
        case .series:
            let list = try rows(value); try unique(list, key: "id"); for row in list { try series(row, scope: scope) }
        case .seriesDetail: try series(value, scope: scope); try require(value["id"].int == scope.seriesID)
        case .occurrences:
            for row in try rows(value) {
                if row["activityId"] != .null { try require(positive(row["activityId"])) }
                if row["occurrenceId"] != .null { try require(positive(row["occurrenceId"])) }
                for key in ["signupCount", "refundedCount"] where row[key] != .null { try require(count(row[key])) }
            }
        case .occurrenceStatus:
            try require(value["activityId"].int == scope.activityID)
            let status = value["occurrenceStatus"].string
            try require((status == "ACTIVE" && value["activityCancelled"] == .bool(false) && value["publishStatus"] == .integer(1)) || (status == "CANCELLED" && value["activityCancelled"] == .bool(true) && value["publishStatus"] == .integer(0)))
        case .roster:
            try require(value["phoneIncluded"] == .bool(false))
            for bucket in ["registered", "waitlist", "arrived", "noShow"] {
                let list = try rows(value[bucket]); try unique(list, key: "memberId")
                // Missing correctionVersion remains unknown; cannot create a correction review.
                for row in list where row["correctionVersion"] != .null { try require(version(row["correctionVersion"])) }
            }
        case .bans:
            let list = try rows(value); try unique(list, key: "id")
            for row in list {
                try require(row["clubId"].int == scope.clubID && positive(row["targetMemberId"]) && version(row["version"]) && ["ACTIVE", "UNBANNED", "EXPIRED"].contains(row["status"].string ?? "") && ["CLUB", "PLATFORM"].contains(row["sourceType"].string ?? "") && nonempty(row["banReason"]))
                if row["sourceType"] == .string("CLUB") { try require(nonempty(row["expiresAt"])) }
            }
        case .cases:
            let list = try rows(value); try unique(list, key: "id")
            for row in list {
                try require(row["clubId"].int == scope.clubID && version(row["version"]) && positive(row["targetId"]) && ["PENDING", "APPROVED", "REJECTED"].contains(row["status"].string ?? ""))
                try require((row["caseType"] == .string("APPEAL") && row["targetType"] == .string("BAN")) || (row["caseType"] == .string("REPORT") && ["CLUB", "ACTIVITY", "MEMBER"].contains(row["targetType"].string ?? "")))
            }
        case .roles:
            let allowed = scope.activityID == nil ? ClubGovernancePermissions.assignableClubRoles : ClubGovernancePermissions.assignableEventRoles
            let roles = try rows(value["roles"]).filter { allowed.contains($0["roleCode"].string ?? "") }
            let assignments = try rows(value["assignments"]).filter { allowed.contains($0["roleCode"].string ?? "") }
            let kind = scope.activityID == nil ? "CLUB" : "EVENT", id = scope.activityID ?? scope.clubID
            try require(!roles.isEmpty)
            for row in roles { try require(allowed.contains(row["roleCode"].string ?? "") && row["scopeType"] == .string(kind) && nonempty(row["name"]) && row["permissions"].array != nil) }
            try unique(assignments, key: "id")
            for row in assignments { try require(positive(row["targetMemberId"]) && version(row["version"]) && allowed.contains(row["roleCode"].string ?? "") && row["scopeType"] == .string(kind) && row["scopeId"].int == id) }
        var scoped = value.object ?? [:]; scoped["roles"] = .array(roles); scoped["assignments"] = .array(assignments); accepted = .object(scoped)
        case .audienceCounts:
            guard let counts = value["counts"].object else { throw ClubGovernanceFailure.malformed }
            for count in counts.values { try require(count == .null || Self.count(count)) }
        case .notificationPreview:
            try require(count(value["recipientCount"]) && value["phoneIncluded"] == .bool(false) && value["inApp"] == .string("AVAILABLE") && value["wechatSubscription"] == .string("UNAVAILABLE"))
        case .notificationStatus: try campaign(value, expectedID: scope.campaignID)
        case .topicOverview:
            try require(value["id"].int == scope.topicID && (nonempty(value["name"]) || nonempty(value["title"])))
            if value["activityList"] != .null { let list = try rows(value["activityList"]); try unique(list, key: "id") }
            if value["chaptersList"] != .null { _ = try rows(value["chaptersList"]) }
        case .topicSettings:
            try require(value.object != nil)
            // Missing booleans are not interpreted as permission or toggle state.
            for key in ["coopOpen", "pinned", "memberOnly", "canManage"] { try require(value[key].bool != nil) }
            _ = try rows(value["chapters"])
        case .topicCustomers:
            try require(value.object != nil); _ = try rows(value["sessions"])
        case .topicStats:
            try require(value.object != nil)
            for key in ["nodeCount", "sessionHeadcount", "pendingVerifyCount", "verifiedByMeCount"] { try require(count(value[key])) }
        case .recruit: _ = try rows(value["nodes"])
        case .nodeAnswer: try require(value.object != nil); if value["hints"] != .null { try require(value["hints"].array?.allSatisfy { $0.string != nil } == true) }
        case .editions:
            let list = try rows(value); try unique(list, key: "topicId")
            for row in list where row["executingClubId"] != .null { try require(row["executingClubId"].int == scope.clubID) }
        case .dissolutionBlockers:
            for key in ["deposits", "settlements"] { let list = try rows(value[key]); try unique(list, key: "id") }
        case .leaderboard:
            let list = try rows(value); try unique(list, key: "memberId")
            for row in list { for key in ["pace", "completionDuration"] where row[key] != .null { try require((row[key].number ?? -1) >= 0) } }
        case .feed:
            try require(count(value["clubCount"])); let list = try rows(value["rows"]); try unique(list, key: "id")
        case .posts: let list = try rows(value); try unique(list, key: "id")
        case .registrations: _ = try ClubEnrollmentRoster(value: value, scope: scope)
        }
        return sanitize(accepted, roster: operation == .roster, publicProjection: operation == .topicOverview)
    }
    static func series(_ value: ClubGovernanceValue, scope: ClubGovernanceScope) throws {
        try require(positive(value["id"]) && value["clubId"].int == scope.clubID && positive(value["topicId"]) && positive(value["defaultLeadMemberId"]) && version(value["version"]) && ["ONCE", "WEEKLY", "CUSTOM_DATES"].contains(value["recurrenceType"].string ?? "") && value["waitlistEnabled"].bool != nil && (5...1440).contains(value["offerMinutes"].int ?? 0))
        if value["defaultCapacity"] != .null { try require((1...10000).contains(value["defaultCapacity"].int ?? 0)) }
    }
    static func campaign(_ value: ClubGovernanceValue, expectedID: Int? = nil) throws {
        try require(positive(value["id"]) && count(value["totalCount"]) && count(value["successCount"]) && count(value["failedCount"]))
        if let expectedID { try require(value["id"].int == expectedID) }
        // The remainder may still be pending. A receipt is not proof of delivery.
        try require((value["successCount"].int ?? 0) + (value["failedCount"].int ?? 0) <= (value["totalCount"].int ?? 0))
    }
    static func validateSettlement(_ value: ClubGovernanceValue) throws {
        let status = value["settledAmountStatus"].string, missing = value["unverifiedSettledCount"].int
        try require(missing != nil && (missing ?? -1) >= 0)
        try require((status == "verified" && nonempty(value["settledAmountText"]) && missing == 0) || (status == "unverified" && value["settledAmountText"] == .null && (missing ?? 0) > 0))
        let topics = try rows(value["topics"]); try unique(topics, key: "id")
        var counted = 0
        for row in topics {
            try require(positive(row["topicId"]) && ["settled", "pending", "void"].contains(row["status"].string ?? ""))
            for key in ["name", "originalAmountText", "executedAdjustmentText", "netAmountText", "arrivedText", "paidText"] { try require(nonempty(row[key])) }
            if row["amountStatus"] == .string("unverified") { try require(row["status"] == .string("settled") && row["amountText"] == .null); counted += 1 }
            else { try require(row["amountStatus"] == .string("verified") && nonempty(row["amountText"])) }
        }
        try require(counted == missing)
    }
    /// Drop raw contact/auth fields recursively. CRM only consumes phoneText.
    /// Protected answers are fetched independently, never inferred from public templates.
    static func sanitize(_ value: ClubGovernanceValue, roster: Bool = false, publicProjection: Bool = false) -> ClubGovernanceValue {
        switch value {
        case .object(let object):
            let forbidden = Set(["phone", "mobile", "phoneNumber", "idCard", "token", "accessToken", "password"] + (roster ? ["phoneText"] : []) + (publicProjection ? ["answer", "answerReveal", "hints", "feedbackText", "secret", "secretStory"] : []))
            return .object(object.filter { !forbidden.contains($0.key) }.mapValues { sanitize($0, roster: roster, publicProjection: publicProjection) })
        case .array(let values): return .array(values.map { sanitize($0, roster: roster, publicProjection: publicProjection) })
        default: return value
        }
    }
}

extension ClubGovernanceCommand {
    public func validateReview(_ snapshot: ClubGovernanceSnapshot, accountID: Int) throws {
        guard snapshot.operation == operation.reviewRead, snapshot.scope == scope else { throw ClubGovernanceFailure.targetChanged }
        if operation != .hostApply { guard let p = snapshot.permissions else { throw ClubGovernanceFailure.forbidden }; try authorize(p) }
        let value = snapshot.value
        switch operation {
        case .hostApply: guard value["registered"] == .bool(true), value["accountID"].int == accountID, !["merchant", "club"].contains(value["accountRole"].string ?? "merchant") else { throw ClubGovernanceFailure.forbidden }
        case .saveCustomer: guard value["canEdit"] == .bool(true) else { throw ClubGovernanceFailure.forbidden }
        case .createSeries: guard (value.array ?? []).contains(where: { $0["id"].int == scope.topicID }) else { throw ClubGovernanceFailure.targetChanged }
        case .updateSeries: guard value["version"] == fields["expectedVersion"], value["topicId"].int == scope.topicID else { throw ClubGovernanceFailure.staleReview }
        case .cancelOccurrence: guard value["activityCancelled"] == .bool(false) else { throw ClubGovernanceFailure.staleReview }
        case .correctAttendance:
            let members = ["registered", "waitlist", "arrived", "noShow"].flatMap { value[$0].array ?? [] }
            guard members.contains(where: { $0["memberId"].int == scope.memberID && $0["correctionVersion"] == fields["expectedVersion"] }) else { throw ClubGovernanceFailure.staleReview }
        case .ban, .transferOwner:
            guard let id = fields["targetMemberId"]?.int, id != accountID, (value.array ?? []).contains(where: { $0["memberId"].int == id && $0["isOwner"] == .bool(false) }) else { throw ClubGovernanceFailure.forbidden }
        case .unban:
            guard (value.array ?? []).contains(where: { $0["id"] == fields["banId"] && $0["version"] == fields["version"] && $0["sourceType"] == .string("CLUB") && $0["status"] == .string("ACTIVE") }) else { throw ClubGovernanceFailure.staleReview }
        case .assignRole: guard (value["roles"].array ?? []).contains(where: { $0["roleCode"] == fields["roleCode"] }) else { throw ClubGovernanceFailure.forbidden }
        case .revokeRole: guard (value["assignments"].array ?? []).contains(where: { $0["id"] == fields["assignmentId"] && $0["version"] == fields["version"] }) else { throw ClubGovernanceFailure.staleReview }
        case .sendNotification: guard (value["recipientCount"].int ?? 0) > 0 else { throw ClubGovernanceFailure.invalidRequest }
        case .retryNotification: guard (value["failedCount"].int ?? 0) > 0 else { throw ClubGovernanceFailure.invalidRequest }
        case .saveTopicSettings, .endTopic, .chapterRecruit, .chapterFinish:
            guard value["canManage"] == .bool(true) else { throw ClubGovernanceFailure.forbidden }
            if let chapterID = scope.chapterID { guard (value["chapters"].array ?? []).contains(where: { $0["chapterId"].int == chapterID }) else { throw ClubGovernanceFailure.targetChanged } }
        case .reportHours, .submitEvidence: guard (value.array ?? []).contains(where: { $0["topicId"].int == scope.topicID && $0["executingClubId"].int == scope.clubID }) else { throw ClubGovernanceFailure.targetChanged }
        case .issueGroupCode: guard (value["activityList"].array ?? []).contains(where: { $0["id"].int == scope.activityID }) else { throw ClubGovernanceFailure.targetChanged }
        case .dissolve: guard value["deposits"].array?.isEmpty == true && value["settlements"].array?.isEmpty == true else { throw ClubGovernanceFailure.forbidden }
        case .report, .appeal: break
        }
    }
    func authorize(_ permissions: ClubGovernancePermissions) throws {
        var required = operation.permission
        if operation == .sendNotification, ["REGISTERED", "WAITLIST", "NO_SHOW"].contains(fields["audienceType"]?.string ?? "") { required = "club:event:operate" }
        guard permissions.allows(required, scope: scope) else { throw ClubGovernanceFailure.forbidden }
    }
}
