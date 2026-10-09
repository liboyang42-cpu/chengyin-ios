import Foundation

public enum MerchantContentCommand: Codable, Equatable {
    case reviewCircle(topicID: Int, scope: String)
    case apply(chapterID: Int, message: String)
    case withdraw(applicationID: Int)
    case register(topicID: Int, nodeID: Int, draft: MerchantRegistrationContentDraft, cooperateDate: String)
    case updateRegistration(id: Int, topicID: Int, draft: MerchantRegistrationContentDraft)
    case cancelRegistration(id: Int)
    case invite(chapterID: Int, merchantMemberID: Int)
    case auditApplication(id: Int, approve: Bool, reason: String)
    case submitNode(chapterID: Int, draft: MerchantChapterContentDraft)
    case auditNode(nodeID: Int, approve: Bool, reason: String)
    case claim(poiID: Int), cancelClaim(poiID: Int), cityStatus(poiID: Int, online: Bool)
    case place(MerchantCityPlacementDraft)
    case saveNPC(nodeID: Int, name: String, avatar: String, greeting: String)
    case enrollVoice(nodeID: Int, voiceSample: String), resetVoice(nodeID: Int)
    case station(MerchantStationCommand)

    public var key: String {
        switch self { case .reviewCircle: return "reviewCircle"; case .apply: return "apply"; case .withdraw: return "withdraw"; case .register: return "register"
        case .updateRegistration: return "edit"; case .cancelRegistration: return "cancelRegistration"; case .invite: return "invite"
        case .auditApplication: return "auditApplication"; case .submitNode: return "submitNode"; case .auditNode: return "auditNode"
        case .claim: return "claim"; case .cancelClaim: return "cancelClaim"; case .cityStatus: return "cityStatus"; case .place: return "place"
        case .saveNPC: return "saveNPC"; case .enrollVoice: return "enrollVoice"; case .resetVoice: return "resetVoice"
        case .station(let c): return c.action.rawValue }
    }
    public var scopeKey: String {
        switch self {
        case .reviewCircle(let id, _): return "topic:\(id)"
        case .apply(let id, _), .submitNode(let id, _), .invite(let id, _): return "chapter:\(id)"
        case .withdraw(let id), .auditApplication(let id, _, _): return "application:\(id)"
        case .register(let id, _, _, _): return "registration-topic:\(id)"
        case .updateRegistration(let id, _, _), .cancelRegistration(let id): return "registration:\(id)"
        case .auditNode(let id, _, _), .saveNPC(let id, _, _, _), .enrollVoice(let id, _), .resetVoice(let id): return "node:\(id)"
        case .claim(let id), .cancelClaim(let id), .cityStatus(let id, _): return "poi:\(id)"
        case .place: return "city-placement"
        case .station(let c): return "game:\(c.activityID)"
        }
    }
    public struct Request: Equatable {
        public enum Body: Equatable { case json([String: MerchantContentValue]), form([String: String]) }
        public let path: String
        public let body: Body
    }
    public func request() throws -> Request {
        func positive(_ id: Int) throws { guard id > 0 else { throw MerchantContentFailure.invalid } }
        func json(_ path: String, _ fields: [String: MerchantContentValue]) -> Request { .init(path: path, body: .json(fields)) }
        func form(_ path: String, _ fields: [String: String]) -> Request { .init(path: path, body: .form(fields)) }
        switch self {
        case .reviewCircle(let id, let scope):
            try positive(id); guard scope == "MERCHANT" else { throw MerchantContentFailure.invalid }
            return json("api/circle-theme/instance/review", ["topicId": .integer(id), "scope": .string(scope)])
        case .apply(let id, let message):
            try positive(id); var f: [String: MerchantContentValue] = ["chapterId": .integer(id)]
            let m = message.trimmingCharacters(in: .whitespacesAndNewlines); if !m.isEmpty { f["message"] = .string(m) }
            return json("api/merchant/chapter-application/apply", f)
        case .withdraw(let id): try positive(id); return json("api/merchant/chapter-application/withdraw", ["applicationId": .integer(id)])
        case .register(let topic, let node, let draft, let time):
            try positive(topic); try positive(node); var f = try draft.fields()
            f["topicId"] = .integer(topic); f["nodeId"] = .integer(node); f["mode"] = .integer(1)
            if !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { f["cooperateDate"] = .string(time.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return json("api/registration/merchant/create", f)
        case .updateRegistration(let id, let topic, let draft):
            try positive(id); try positive(topic); var f = try draft.fields(); f["id"] = .integer(id); f["topicId"] = .integer(topic)
            return json("api/registration/merchant/update", f)
        case .cancelRegistration(let id): try positive(id); return form("api/registration/merchant/cancel", ["id": String(id)])
        case .invite(let chapter, let member):
            try positive(chapter); try positive(member)
            return json("api/merchant/chapter-application/invite", ["chapterId": .integer(chapter), "merchantMemberId": .integer(member)])
        case .auditApplication(let id, let approve, let reason):
            try positive(id); guard approve || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MerchantContentFailure.invalid }; return json("api/merchant/chapter-application/audit", ["id": .integer(id), "approve": .bool(approve), "reason": .string(reason)])
        case .submitNode(let chapter, let draft): return json("api/merchant/chapter-node/submit", try draft.fields(chapterID: chapter))
        case .auditNode(let node, let approve, let reason):
            try positive(node); guard approve || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MerchantContentFailure.invalid }; var f = ["nodeId": String(node), "approve": approve ? "true" : "false"]
            if !reason.isEmpty { f["reason"] = reason }; return form("api/merchant/chapter-node/audit", f)
        case .claim(let id): try positive(id); return form("api/merchant/city-node/claim", ["poiId": String(id)])
        case .cancelClaim(let id): try positive(id); return form("api/merchant/city-node/claim/cancel", ["poiId": String(id)])
        case .cityStatus(let id, let online): try positive(id); return form("api/merchant/city-node/offline", ["poiId": String(id), "status": online ? "1" : "0"])
        case .place(let draft): return form("api/merchant/city-node/save", try draft.fields())
        case .saveNPC(let id, let name, let avatar, let greeting):
            try positive(id); guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !avatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MerchantContentFailure.invalid }
            return form("api/merchant/chapter-node/npc/save", ["nodeId": String(id), "name": name, "avatar": avatar, "greeting": greeting])
        case .enrollVoice(let id, let sample):
            try positive(id); guard !sample.isEmpty else { throw MerchantContentFailure.invalid }
            return form("api/merchant/chapter-node/npc/voice/enroll", ["nodeId": String(id), "voiceSample": sample])
        case .resetVoice(let id): try positive(id); return form("api/merchant/chapter-node/npc/voice/reset", ["nodeId": String(id)])
        case .station(let c): return json("api/game/session/command", try c.fields())
        }
    }
    /// Validate against a freshly authorized projection, not a role inferred from account or entry intent.
    public func validate(against snapshot: MerchantContentSnapshot) throws {
        _ = try request()
        func need(_ condition: Bool) throws { guard condition else { throw MerchantContentFailure.denied } }
        func row(_ id: Int) -> MerchantContentValue? { snapshot.rows.first { $0["id"].integer == id } }
        switch self {
        case .reviewCircle(let id, _):
            try need(snapshot.query == .project(topicID: id) && snapshot.value["host"].object != nil && !(snapshot.value["topic"]["circleThemeCode"].text ?? "").isEmpty)
        case .apply(let id, _):
            guard case .chapters = snapshot.query else { throw MerchantContentFailure.invalid }
            try need(snapshot.value["mode"].text == "chapters" && (snapshot.value["chapters"].array ?? []).contains { $0["id"].integer == id })
        case .withdraw(let id):
            try need(snapshot.query == .applications)
            guard let r = row(id) else { throw MerchantContentFailure.denied }
            try need(r["status"].integer == 0 && r["source"].integer == 0)
        case .register(let topic, let node, _, _):
            try need(snapshot.query == .chapters(topicID: topic) && snapshot.value["mode"].text == "registration" && snapshot.value["registered"].flag != true)
            let chapters = snapshot.value["topic"]["chaptersList"].array ?? []
            try need(chapters.flatMap { $0["nodes"].array ?? [] }.contains { $0["id"].integer == node })
        case .updateRegistration(let id, let topic, _):
            try need(snapshot.query == .registration(id: id) && snapshot.value["id"].integer == id && snapshot.value["topicId"].integer == topic)
            try need([0, 2].contains(snapshot.value["status"].integer ?? -1) && snapshot.value["auditStatus"].integer != 1)
        case .cancelRegistration(let id):
            try need(snapshot.query == .registration(id: id) && snapshot.value["id"].integer == id)
            // An absent award state is unknown, not proof that cancellation is allowed.
            try need([0, 1, 2].contains(snapshot.value["status"].integer ?? -1) && snapshot.value["auditStatus"].integer.map { $0 != 1 } == true)
        case .invite(let chapter, let member):
            guard case .invitable = snapshot.query else { throw MerchantContentFailure.invalid }
            // The wrapper has no chapter/merchant ownership join; never derive memberId from merchantId.
            try need(snapshot.rows.contains { $0["chapterId"].integer == chapter && $0["memberId"].integer == member })
        case .auditApplication(let id, _, _):
            guard case .ownerApplications = snapshot.query else { throw MerchantContentFailure.invalid }
            try need(row(id)?["status"].integer == 0)
        case .submitNode(let chapter, let draft):
            try need(snapshot.query == .nodeAuthoring(chapterID: chapter))
            try need((snapshot.value["applications"].array ?? []).contains { $0["chapterId"].integer == chapter && [0, 1].contains($0["status"].integer ?? -1) })
            try need((snapshot.value["templates"].array ?? []).contains { $0["id"].integer == draft.templateID })
        case .auditNode(let id, _, _):
            guard case .pendingNodes = snapshot.query else { throw MerchantContentFailure.invalid }; try need(row(id) != nil)
        case .claim(let id):
            guard case .claimable = snapshot.query else { throw MerchantContentFailure.invalid }
            try need(snapshot.rows.contains { ($0["poiId"].integer ?? $0["id"].integer) == id })
            let catalog = snapshot.value["catalog"]
            if let max = catalog["max"].integer, max > 0, let used = catalog["used"].integer { try need(used < max) }
        case .cancelClaim(let id):
            try need(MerchantCityClaimWithdrawal(poiID: id, snapshot: snapshot) != nil)
        case .cityStatus(let id, _):
            try need(snapshot.query == .city && (snapshot.value["nodes"].array ?? []).contains { ($0["poiId"].integer ?? $0["id"].integer) == id })
        case .place(let draft):
            try need(snapshot.query == .cityPlacement)
            try need(MerchantCityQuota(catalog: snapshot.value["catalog"]).canPlace)
            try need((snapshot.value["templates"].array ?? []).contains { $0["id"].integer == draft.templateID })
        case .saveNPC(let id, _, _, _), .enrollVoice(let id, _), .resetVoice(let id): try need(snapshot.query == .npc(nodeID: id))
        case .station(let command):
            try need(snapshot.query == .game(activityID: command.activityID))
            let p = try MerchantStationProjection(snapshot.value)
            try need(p.revision == command.expectedRevision && p.allows(command.action, nodeID: command.nodeID))
            try command.validate(projection: p)
        }
    }
}
