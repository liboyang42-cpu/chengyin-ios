import Foundation

/// Invented fixture records only. Never read from accounts or production services.
public enum ClubGovernanceFixtures {
    public static let scope = ClubGovernanceScope(clubID: 81, topicID: 91, activityID: 101, seriesID: 111, memberID: 704, registrationID: 121, campaignID: 131, nodeID: 141, chapterID: 151)
    public static func json(_ text: String) -> ClubGovernanceValue { (try? JSONDecoder().decode(ClubGovernanceValue.self, from: Data(text.utf8))) ?? .null }
    public static let permissions = json(#"{"active":true,"club":{"id":81},"roleCodes":["CLUB_OWNER"],"canManageRoles":true,"permissions":["club:write","club:content:manage","club:member:approve","club:member:manage","club:role:manage","club:notify:send","club:activity:manage","club:event:operate","club:event:checkin","club:member:list:read","club:finance:read"],"eventAccesses":[{"activityId":101,"topicId":91,"roleCodes":["EVENT_CHECKIN"],"permissions":["club:event:checkin"]}]}"#)
    public static func value(_ read: ClubGovernanceRead, scope: ClubGovernanceScope = ClubGovernanceFixtures.scope) -> ClubGovernanceValue {
        switch read {
        case .access: return permissions
        case .hostStatus: return json(#"{"registered":true,"accountRole":"player","accountID":701}"#)
        case .members: return json(#"[{"memberId":701,"nickname":"Fixture owner","isOwner":true,"role":1},{"memberId":704,"nickname":"Fixture member","isOwner":false,"role":0}]"#)
        case .stats: return json(#"{"clubId":81,"topicCount":1,"participants":8,"completed":6,"overallRate":75,"topics":[{"topicId":91,"name":"Fixture topic","participants":8,"completed":6,"completionRate":75}]}"#)
        case .customerCount: return json(#"{"total":1}"#)
        case .customers: return json(#"{"total":1,"monthNew":1,"canEdit":true,"items":[{"memberId":704,"displayName":"Fixture customer","verifiedCount":2,"pendingCount":1,"phoneText":"Hidden","remark":"Fixture note"}]}"#)
        case .customer: return json(#"{"summary":{"memberId":704,"displayName":"Fixture customer","arrivedCount":2,"pendingCount":1,"refundedCount":0,"paidAmount":null,"phoneText":"Hidden"},"records":[{"key":"r121","topicId":91,"title":"Fixture session","statusCode":"PENDING"}],"tags":["Fixture"],"remark":"Local fixture","canEdit":true}"#)
        case .checkin: return json(#"{"registrationId":121,"displayName":"Fixture customer","statusCode":"PENDING","statusText":"Pending","railStep":1,"phoneText":"Hidden","paidAmountText":"Not visible","canRefund":false}"#)
        case .settlement: return json(#"{"settledAmountStatus":"unverified","settledAmountText":null,"unverifiedSettledCount":1,"topics":[{"id":201,"topicId":91,"name":"Fixture settlement","status":"settled","amountStatus":"unverified","amountText":null,"originalAmountText":"Source amount","executedAdjustmentText":"Source adjustment","netAmountText":"Source net","arrivedText":"Source arrivals","paidText":"Source payments"}]}"#)
        case .eventTopics, .topics: return json(#"[{"id":91,"name":"Fixture topic","signupCount":8}]"#)
        case .series: return .array([value(.seriesDetail)])
        case .seriesDetail: return json(#"{"id":111,"clubId":81,"topicId":91,"defaultLeadMemberId":704,"version":3,"recurrenceType":"WEEKLY","defaultCapacity":12,"waitlistEnabled":true,"offerMinutes":60,"futureDates":["2026-10-08","2026-10-15"]}"#)
        case .occurrences: return json(#"[{"occurrenceId":112,"activityId":101,"occurrenceAt":"2026-10-08 09:00:00","status":"ACTIVE","signupCount":null,"refundedCount":null,"editable":false,"lockReason":"Count pending"}]"#)
        case .occurrenceStatus: return json(#"{"activityId":101,"occurrenceStatus":"ACTIVE","activityCancelled":false,"publishStatus":1,"cancelReason":""}"#)
        case .roster: return json(#"{"registered":[{"memberId":704,"nickname":"Fixture attendee","correctionVersion":2,"state":"REGISTERED"}],"waitlist":[],"arrived":[],"noShow":[],"phoneIncluded":false}"#)
        case .bans: return json(#"[{"id":161,"clubId":81,"targetMemberId":704,"targetNickname":"Fixture member","version":2,"sourceType":"CLUB","status":"ACTIVE","banReason":"Fixture reason","expiresAt":"2026-10-08 09:00:00"}]"#)
        case .cases: return json(#"[{"id":171,"clubId":81,"caseType":"REPORT","targetType":"CLUB","targetId":81,"status":"PENDING","version":0,"reason":"Fixture report"}]"#)
        case .roles:
            if let activityID = scope.activityID {
                return json("{\"roles\":[{\"roleCode\":\"EVENT_CHECKIN\",\"name\":\"Check-in\",\"scopeType\":\"EVENT\",\"permissions\":[]}],\"assignments\":[{\"id\":181,\"targetMemberId\":704,\"memberName\":\"Fixture member\",\"roleCode\":\"EVENT_CHECKIN\",\"scopeType\":\"EVENT\",\"scopeId\":\(activityID),\"version\":2}]}")
            }
            return json(#"{"roles":[{"roleCode":"CLUB_OPERATOR","name":"Operator","scopeType":"CLUB","permissions":[]}],"assignments":[{"id":181,"targetMemberId":704,"memberName":"Fixture member","roleCode":"CLUB_OPERATOR","scopeType":"CLUB","scopeId":81,"version":2}]}"#)
        case .audienceCounts: return json(#"{"counts":{"ALL_MEMBERS":8,"ADMINS":1,"REGISTERED":8,"WAITLIST":null,"NO_SHOW":0,"INACTIVE":null}}"#)
        case .notificationPreview: return json(#"{"recipientCount":8,"phoneIncluded":false,"inApp":"AVAILABLE","wechatSubscription":"UNAVAILABLE"}"#)
        case .notificationStatus: return json(#"{"id":131,"totalCount":8,"successCount":5,"failedCount":1}"#)
        case .topicOverview: return json(#"{"id":91,"name":"Fixture club story","status":"running","storyReady":true,"activityList":[{"id":101,"name":"Fixture session"}],"chaptersList":[{"id":151,"title":"Fixture chapter","description":"A synthetic route story","totalTime":20,"nodes":[{"id":141,"name":"Fixture station","description":"Station description","cmsMemberTemplate":{"id":142,"title":"Fixture puzzle","validationMethod":1,"validationMethodStr":"Text answer"}}]}]}"#)
        case .topicSettings: return json(#"{"topicName":"Fixture topic","coopOpen":false,"pinned":false,"memberOnly":true,"canManage":true,"chapters":[{"chapterId":151,"name":"Fixture chapter","recruiting":false,"merchantCount":0,"finishTime":""}]}"#)
        case .topicCustomers: return json(#"{"soldCount":1,"pendingCount":1,"verifiedCount":0,"sessions":[{"timeText":"Fixture time","rows":[{"key":"r121","displayName":"Fixture attendee","phoneText":"Hidden","statusCode":"pending"}]}]}"#)
        case .topicStats: return json(#"{"canDirect":true,"canManageSessions":true,"canViewVerify":true,"nodeCount":1,"sessionHeadcount":8,"pendingVerifyCount":3,"verifiedByMeCount":2}"#)
        case .recruit: return json(#"{"nodes":[{"nodeId":141,"name":"Fixture station","merchantName":"Fixture merchant","state":"OPEN"}]}"#)
        case .nodeAnswer: return json(#"{"question":"Fixture question","answerReveal":"Fixture answer","hints":["Fixture hint"],"feedbackText":"Fixture feedback"}"#)
        case .editions: return json(#"[{"topicId":91,"topicName":"Fixture edition","executingClubId":81,"startDate":"2026-10-08"}]"#)
        case .dissolutionBlockers: return json(#"{"deposits":[],"settlements":[]}"#)
        case .leaderboard: return json(#"[{"memberId":704,"nickname":"Fixture member","score":7,"clearCount":1,"mileage":2,"durationMin":30,"hostedCount":0,"pace":null,"completionDuration":null}]"#)
        case .feed: return json(#"{"clubCount":1,"rows":[{"id":191,"clubId":81,"content":"Synthetic club update","nickname":"Fixture member"}]}"#)
        case .posts: return value(.feed)["rows"]
        case .registrations: return json(#"{"omsTicketList":[{"name":"Fixture ticket","totalInventory":12,"cmsRegistrationList":[{"id":121,"memberId":704,"nickname":"Fixture attendee","paymentStatus":2,"verificationStatus":0}]}]}"#)
        }
    }
    public static func command(_ mutation: ClubGovernanceMutation, scope: ClubGovernanceScope = ClubGovernanceFixtures.scope) throws -> ClubGovernanceCommand {
        var draft = ClubGovernanceFormDraft(operation: mutation, scope: scope)
        // Every non-empty required value is synthetic. No real person or target is used.
        switch mutation {
        case .hostApply: draft.text["leaderName"] = "Fixture host"; draft.text["phone"] = "SYNTHETIC"
        case .saveCustomer: draft.text["remark"] = "Fixture note"
        case .createSeries, .updateSeries:
            draft = .init(operation: mutation, scope: scope, seed: value(.seriesDetail).object ?? [:]); draft.text["startDate"] = "2026-10-08"; draft.text["defaultLeadMemberId"] = "704"
        case .ban: draft = .init(operation: mutation, scope: scope, seed: ["targetMemberId": .integer(704)]); draft.text["reason"] = "Fixture reason"; draft.text["expiresAt"] = "2026-10-08 09:00:00"
        case .transferOwner: draft = .init(operation: mutation, scope: scope, seed: ["targetMemberId": .integer(704)]); draft.text["reason"] = "Fixture reason"
        case .unban: draft = .init(operation: mutation, scope: scope, seed: ["banId": .integer(161), "version": .integer(2)]); draft.text["reason"] = "Fixture reason"
        case .revokeRole: draft = .init(operation: mutation, scope: scope, seed: ["assignmentId": .integer(181), "version": .integer(2)]); draft.text["reason"] = "Fixture reason"
        case .correctAttendance: draft = .init(operation: mutation, scope: scope, seed: ["expectedVersion": .integer(2)]); draft.text["reason"] = "Fixture reason"
        case .assignRole: draft.text["targetMemberId"] = "704"
        case .sendNotification: draft.text["title"] = "Fixture title"; draft.text["content"] = "Fixture content"
        case .report, .appeal, .cancelOccurrence: draft.text["reason"] = "Fixture reason"
        case .reportHours: draft.text["actualHours"] = "1.5"
        case .submitEvidence: draft.text["evidenceHash"] = String(repeating: "a", count: 64)
        case .dissolve: draft.flags["dissolveConfirmed"] = true; draft.flags["memberConsequencesConfirmed"] = true
        default: break
        }
        return try draft.command()
    }
    public static func receipt(_ mutation: ClubGovernanceMutation) -> ClubGovernanceValue {
        switch mutation {
        case .createSeries, .updateSeries: return json(#"{"id":111}"#)
        case .correctAttendance: return json(#"{"id":211}"#)
        case .cancelOccurrence: return json(#"{"activityId":101,"refundStatus":"ACCEPTED_WITH_MANUAL_REVIEW"}"#)
        case .sendNotification, .retryNotification: return value(.notificationStatus)
        case .saveTopicSettings: return value(.topicSettings)
        case .endTopic: return json(#"{"refundedOrders":1,"manualOrders":2,"failedSessions":["Fixture failed session"]}"#)
        case .issueGroupCode: return json(#"{"qrcodeUrl":"https://example.com/synthetic.png","code":"SYNTHETIC-NONREDEEMABLE","ttlMs":60000}"#)
        default: return .null
        }
    }
}

@MainActor public final class ClubGovernanceFixtureAccess: ClubGovernanceAccess {
    public var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
    public var isConfigured = true
    public var storageNamespace = "synthetic"
    public var allowsOfflineWrites = true
    public var permissionValue = ClubGovernanceFixtures.permissions
    public var readFailure: ClubGovernanceFailure?
    public var writeFailure: ClubGovernanceFailure?
    public var onRead: (() -> Void)?
    public var onSend: (() -> Void)?
    public var overrideValue: [ClubGovernanceRead: ClubGovernanceValue] = [:]
    public private(set) var sent: [ClubGovernanceCommand] = []
    public init() {}
    public func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
        guard isConfigured else { throw ClubGovernanceFailure.notConfigured }; guard identity != nil else { throw ClubGovernanceFailure.signedOut }
        _ = try operation.fields(scope: scope, options: options)
        onRead?(); if let readFailure { throw readFailure }
        let permissions = scope.clubID == nil ? nil : try ClubGovernancePermissions(value: permissionValue, scope: scope)
        if let permissions { guard permissions.allows(operation.permission, scope: scope) || ([.audienceCounts, .notificationPreview, .notificationStatus].contains(operation) && permissions.allows("club:event:operate", scope: scope)) else { throw ClubGovernanceFailure.forbidden } }
        let raw = overrideValue[operation] ?? (operation == .access ? permissionValue : ClubGovernanceFixtures.value(operation, scope: scope))
        let value = try ClubGovernanceValidation.validate(raw, operation: operation, scope: scope)
        return .init(operation: operation, scope: scope, permissions: permissions, value: value)
    }
    public func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
        guard allowsOfflineWrites else { throw ClubGovernanceFailure.notConfigured }; guard self.identity == review.identity, storageNamespace == review.storageNamespace else { throw ClubGovernanceFailure.staleReview }
        let command = review.command
        sent.append(command); onSend?(); if let writeFailure { throw writeFailure }
        return ClubGovernanceFixtures.receipt(command.operation)
    }
}
