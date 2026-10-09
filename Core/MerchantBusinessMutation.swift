import Foundation

public enum MerchantAftercareDecision: String, CaseIterable { case agree = "AGREE", reject = "REJECT", evidence = "EVIDENCE" }
public enum MerchantReviewReplyAction: String, CaseIterable { case reply, update, delete, report }
public enum MerchantBusinessMutation: Equatable {
    case addNote(customer: MerchantCustomerID, content: String, correctsNoteID: Int?)
    case hideNote(customer: MerchantCustomerID, noteID: Int, expectedVersion: Int)
    case assignTag(customer: MerchantCustomerID, name: String, color: String)
    case removeTag(customer: MerchantCustomerID, tagID: Int)
    case batchTag(customers: [MerchantCustomerID], name: String, color: String)
    case aftercare(refund: MerchantRefundID, decision: MerchantAftercareDecision, content: String, evidenceKey: String?)
    case review(id: MerchantBusinessReviewID, version: Int, action: MerchantReviewReplyAction, content: String)
    case inviteOperator(role: String)
    case operatorRole(id: MerchantOperatorID, version: Int, role: String)
    case removeOperator(id: MerchantOperatorID, version: Int, reason: String)
    case revokeInvite(id: MerchantOperatorInviteID, version: Int, reason: String)
    public var titleKey: String {
        switch self {
        case .addNote(_, _, let correction): return correction == nil ? "merchant.business.addNote" : "merchant.business.correctNote"
        case .hideNote: return "merchant.business.hideNote"
        case .assignTag: return "merchant.business.assignTag"; case .removeTag: return "merchant.business.removeTag"
        case .batchTag: return "merchant.business.batchTag"; case .aftercare: return "merchant.business.respond"
        case .review(_, _, let action, _): return "merchant.business.review.\(action.rawValue)"
        case .inviteOperator: return "merchant.business.inviteOperator"; case .operatorRole: return "merchant.business.changeRole"
        case .removeOperator: return "merchant.business.removeOperator"; case .revokeInvite: return "merchant.business.revokeInvite"
        }
    }
    public var permissions: [String] {
        switch self {
        case .addNote, .hideNote, .assignTag, .removeTag, .batchTag: return ["merchant:crm:read", "merchant:crm:segment"]
        case .aftercare(_, let decision, _, _): return ["merchant:aftercare:read", decision == .evidence ? "merchant:aftercare:evidence" : "merchant:aftercare:decide"]
        case .review: return [] // The source row's explicit can* fields are checked below.
        case .inviteOperator, .operatorRole, .removeOperator, .revokeInvite: return ["merchant:operator:manage"]
        }
    }
    public var targetKey: String {
        switch self {
        case .addNote(let id, _, _), .hideNote(let id, _, _), .assignTag(let id, _, _), .removeTag(let id, _): return "customer:\(id.rawValue)"
        case .batchTag: return "customer-batch"
        case .aftercare(let id, _, _, _): return "refund:\(id.rawValue)"
        case .review(let id, _, _, _): return "review:\(id.rawValue)"
        case .inviteOperator: return "operator-invite"
        case .operatorRole(let id, _, _), .removeOperator(let id, _, _): return "operator:\(id.rawValue)"
        case .revokeInvite(let id, _, _): return "invite:\(id.rawValue)"
        }
    }
    public func request(requestID: String) throws -> MerchantBusinessRequest {
        guard requestID.range(of: #"^[A-Za-z0-9._:-]{6,64}$"#, options: .regularExpression) != nil else { throw MerchantBusinessFailure.invalid }
        let rid = MerchantBusinessValue.string(requestID)
        func text(_ value: String, min: Int, max: Int) throws -> String {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (min...max).contains(value.utf16.count) else { throw MerchantBusinessFailure.invalid }; return value
        }
        func tag(_ name: String, _ color: String) throws -> (String, String) {
            let name = try text(name, min: 1, max: 16), color = color.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard MerchantBusinessRecord.isColor(color) else { throw MerchantBusinessFailure.invalid }; return (name, color)
        }
        func version(_ value: Int) throws { guard value >= 0, value <= Int.max - 2 else { throw MerchantBusinessFailure.invalid } }
        switch self {
        case .addNote(let id, let content, let corrects):
            guard corrects == nil || corrects! > 0 else { throw MerchantBusinessFailure.invalid }
            return .json("api/merchant/crm/customers/\(id.rawValue)/notes", ["content": .string(try text(content, min: 1, max: 500)), "requestId": rid, "correctsNoteId": .optional(corrects)])
        case .hideNote(let id, let note, let expected):
            try version(expected); guard note > 0 else { throw MerchantBusinessFailure.invalid }
            return .json("api/merchant/crm/customers/\(id.rawValue)/notes/hide", ["noteId": .int(note), "expectedVersion": .int(expected), "requestId": rid])
        case .assignTag(let id, let name, let color):
            let values = try tag(name, color)
            return .json("api/merchant/crm/customers/\(id.rawValue)/tags", ["tagName": .string(values.0), "tagColor": .string(values.1), "requestId": rid])
        case .removeTag(let id, let tag):
            guard tag > 0 else { throw MerchantBusinessFailure.invalid }
            return .json("api/merchant/crm/customers/\(id.rawValue)/tags/remove", ["tagId": .int(tag), "requestId": rid])
        case .batchTag(let ids, let name, let color):
            guard !ids.isEmpty, ids.count <= 100, Set(ids).count == ids.count else { throw MerchantBusinessFailure.invalid }
            let values = try tag(name, color)
            return .json("api/merchant/crm/customers/tags/batch", ["customerMemberIds": .array(ids.map { .int($0.rawValue) }), "tagName": .string(values.0), "tagColor": .string(values.1), "requestId": rid])
        case .aftercare(let id, let decision, let content, let evidence):
            let content = try text(content, min: decision == .reject ? 1 : 0, max: 500)
            let evidence = evidence?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard decision != .evidence || !(evidence ?? "").isEmpty else { throw MerchantBusinessFailure.invalid }
            if let evidence, !evidence.isEmpty, evidence.range(of: #"^upload/merchant-aftercare-evidence/[0-9a-f]{32}\.(?:jpe?g|png|gif)$"#, options: .regularExpression) == nil { throw MerchantBusinessFailure.invalid }
            var fields: MerchantBusinessObject = ["decision": .string(decision.rawValue), "content": content.isEmpty ? .null : .string(content), "requestId": rid]
            if let evidence, !evidence.isEmpty { fields["evidenceKeys"] = .array([.string(evidence)]) }
            return .init(path: "api/merchant/aftercare/respond", query: ["refundId": String(id.rawValue)], body: .json(fields))
        case .review(let id, let expected, let action, let content):
            try version(expected)
            var fields: MerchantBusinessObject = ["reviewId": .int(id.rawValue), "expectedVersion": .int(expected), "requestId": rid]
            if action != .delete { fields[action == .report ? "reason" : "content"] = .string(try text(content, min: action == .report ? 2 : 1, max: 500)) }
            let path: String
            switch action { case .reply: path = "reply"; case .update: path = "reply/update"; case .delete: path = "reply/delete"; case .report: path = "manage/report" }
            return .json("api/merchant/reviews/\(path)", fields)
        case .inviteOperator(let role):
            guard MerchantBusinessAccess.employeeRoles.contains(role) else { throw MerchantBusinessFailure.invalid }
            return .json("api/merchant/operators/invite", ["roleCode": .string(role), "requestId": rid])
        case .operatorRole(let id, let current, let role):
            try version(current); guard MerchantBusinessAccess.employeeRoles.contains(role) else { throw MerchantBusinessFailure.invalid }
            return .json("api/merchant/operators/role", ["operatorId": .int(id.rawValue), "roleCode": .string(role), "version": .int(current), "requestId": rid])
        case .removeOperator(let id, let current, let reason):
            try version(current)
            return .json("api/merchant/operators/remove", ["operatorId": .int(id.rawValue), "version": .int(current), "reason": .string(try text(reason, min: 1, max: 200)), "requestId": rid])
        case .revokeInvite(let id, let current, let reason):
            try version(current)
            return .json("api/merchant/operators/invite/revoke", ["inviteId": .int(id.rawValue), "version": .int(current), "reason": .string(try text(reason, min: 1, max: 200)), "requestId": rid])
        }
    }
    /// The authorization is freshly fetched again at dispatch. Current server capability flags
    /// and exact entity/version survive confirmation; a role label alone grants nothing.
    public func validate(in document: MerchantBusinessDocument, access: MerchantBusinessAccess, roles: MerchantBusinessDocument? = nil) throws {
        try access.require(permissions)
        func find(_ kind: MerchantBusinessRecord.Kind, _ id: Int) throws -> MerchantBusinessObject {
            guard let row = document.rows.first(where: { $0.kind == kind && $0.id == String(id) }) else { throw MerchantBusinessFailure.conflict }; return row.fields
        }
        func customer(_ id: MerchantCustomerID) throws { guard document.query == .customer(id) else { throw MerchantBusinessFailure.conflict } }
        func roleAllowed(_ role: String) throws { guard roles?.rows.contains(where: { $0.kind == .role && $0.id == role }) == true else { throw MerchantBusinessFailure.denied } }
        switch self {
        case .addNote(let id, _, let note):
            try customer(id)
            if let note { guard document.rows.contains(where: { $0.kind == .timeline && ["NOTE", "NOTE_CORRECTION"].contains($0.fields.mbText("type") ?? "") && $0.fields["noteId"]?.integer == note }) else { throw MerchantBusinessFailure.conflict } }
        case .hideNote(let id, let note, let version):
            try customer(id)
            guard document.rows.contains(where: { $0.kind == .timeline && ["NOTE", "NOTE_CORRECTION"].contains($0.fields.mbText("type") ?? "") && $0.fields["noteId"]?.integer == note && $0.fields["noteVersion"]?.integer == version }) else { throw MerchantBusinessFailure.conflict }
        case .assignTag(let id, _, _): try customer(id)
        case .removeTag(let id, let tag): try customer(id); _ = try find(.tag, tag)
        case .batchTag(let ids, _, _):
            guard case .customers = document.query else { throw MerchantBusinessFailure.conflict }
            for id in ids { _ = try find(.customer, id.rawValue) }
        case .aftercare(let id, let decision, _, _):
            let roles = decision == .evidence ? ["MERCHANT_OWNER", "MERCHANT_MANAGER", "MERCHANT_FINANCE"] : ["MERCHANT_OWNER", "MERCHANT_MANAGER"]
            guard roles.contains(access.role) else { throw MerchantBusinessFailure.denied }
            guard document.query == .refund(id) else { throw MerchantBusinessFailure.conflict }
            let row = try find(.refund, id.rawValue)
            guard try row.mbBool("canRespond"), try row.mbStrings("allowedDecisions").contains(decision.rawValue) else { throw MerchantBusinessFailure.denied }
        case .review(let id, let version, let action, _):
            let row = try find(.review, id.rawValue)
            guard row["version"]?.integer == version else { throw MerchantBusinessFailure.conflict }
            let key = action == .reply ? "canReply" : action == .report ? "canReport" : "canEditReply"
            guard row[key]?.bool == true else { throw MerchantBusinessFailure.denied }
        case .inviteOperator(let role): try roleAllowed(role)
        case .operatorRole(let id, let version, let role):
            try roleAllowed(role); let row = try find(.operatorMember, id.rawValue)
            guard row["version"]?.integer == version, row.mbText("status") == "ACTIVE" else { throw MerchantBusinessFailure.conflict }
        case .removeOperator(let id, let version, _):
            let row = try find(.operatorMember, id.rawValue)
            guard row["version"]?.integer == version, row.mbText("status") == "ACTIVE" else { throw MerchantBusinessFailure.conflict }
        case .revokeInvite(let id, let version, _):
            let row = try find(.invite, id.rawValue)
            guard row["version"]?.integer == version, row.mbText("status") == "PENDING" else { throw MerchantBusinessFailure.conflict }
        }
    }
}
public struct MerchantBusinessReceipt: Equatable {
    public let message: String?
    public let data: MerchantBusinessValue
    /// An opinion response is never relabeled as an executed refund.
    public let refundActuallyConfirmed: Bool
    public init(mutation: MerchantBusinessMutation, message: String?, data: MerchantBusinessValue) throws {
        self.message = message; self.data = data
        let object = data.object ?? [:]
        var refunded = false
        switch mutation {
        case .aftercare(let id, let decision, _, _):
            guard try object.mbInt("id", minimum: 1) > 0, try object.mbInt("refundId", minimum: 1) == id.rawValue,
                  object.mbText("decision") == decision.rawValue, MerchantBusinessRecord.processing.contains(try object.mbRequiredText("processing")),
                  ["PENDING", "AGREE", "REJECT"].contains(try object.mbRequiredText("merchantOpinion")) else { throw MerchantBusinessFailure.malformed }
            refunded = try object.mbBool("refunded")
            guard refunded == (object.mbText("processing") == "REFUNDED") else { throw MerchantBusinessFailure.malformed }
        case .review(let id, _, let action, _):
            guard data.object != nil else { throw MerchantBusinessFailure.malformed }
            if action == .reply || action == .report {
                guard try object.mbInt("reviewId", minimum: 1) == id.rawValue else { throw MerchantBusinessFailure.malformed }
                _ = try object.mbBool("replayed")
                if action == .reply { guard object.mbText("status") == "VISIBLE" else { throw MerchantBusinessFailure.malformed }; _ = try object.mbInt("version") }
                else { guard object.mbText("status") == "PENDING_PLATFORM_REVIEW" else { throw MerchantBusinessFailure.malformed }; _ = try object.mbInt("auditTaskId", minimum: 1) }
            } // Source update/delete promises object only; do not invent correlation fields.
        case .inviteOperator(let role):
            let invite = try MerchantBusinessRecord(kind: .invite, fields: object.mbObject("invite"))
            guard invite.fields.mbText("roleCode") == role, invite.fields.mbText("status") == "PENDING", let token = object.mbText("token"), (16...256).contains(token.utf16.count) else { throw MerchantBusinessFailure.malformed }
        case .operatorRole(let id, let version, let role):
            let row = try Self.operatorReceipt(object, id: id.rawValue, version: version, kind: .operatorMember)
            if object.mbText("mutationState") == "EXACT_RESULT", row.fields.mbText("roleCode") != role || row.fields.mbText("status") != "ACTIVE" { throw MerchantBusinessFailure.malformed }
        case .removeOperator(let id, let version, _):
            let row = try Self.operatorReceipt(object, id: id.rawValue, version: version, kind: .operatorMember)
            guard row.fields.mbText("status") == "REVOKED" else { throw MerchantBusinessFailure.malformed }
        case .revokeInvite(let id, let version, _):
            let row = try Self.operatorReceipt(object, id: id.rawValue, version: version, kind: .invite)
            guard row.fields.mbText("status") == "REVOKED" else { throw MerchantBusinessFailure.malformed }
        case .batchTag: guard data.object != nil else { throw MerchantBusinessFailure.malformed }
        default: guard data != .null else { throw MerchantBusinessFailure.malformed }
        }
        refundActuallyConfirmed = refunded
    }
    private static func operatorReceipt(_ object: MerchantBusinessObject, id: Int, version: Int, kind: MerchantBusinessRecord.Kind) throws -> MerchantBusinessRecord {
        guard version >= 0, version <= Int.max - 2 else { throw MerchantBusinessFailure.malformed }
        let row = try MerchantBusinessRecord(kind: kind, fields: object)
        let actual = try object.mbInt("version")
        let state = object.mbText("mutationState")
        guard row.id == String(id), (state == "EXACT_RESULT" && actual == version + 1) || (state == "LATER_AUTHORITATIVE" && actual >= version + 2) else { throw MerchantBusinessFailure.malformed }
        return row
    }
}
