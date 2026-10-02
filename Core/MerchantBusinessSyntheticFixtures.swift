import Foundation

/// Synthetic IDs and text only. Never source from account/customer data for these fixtures.
public enum MerchantBusinessSyntheticFixtures {
    public static let access = ##"{"active":true,"merchant":{"id":610,"name":"Synthetic workshop"},"roleCode":"MERCHANT_OWNER","canManageOperators":true,"permissions":["merchant:basic:read","merchant:crm:read","merchant:crm:sensitive:read","merchant:crm:segment","merchant:aftercare:read","merchant:aftercare:respond","merchant:aftercare:decide","merchant:aftercare:evidence","merchant:finance:read","merchant:verify:record:read","merchant:verify","merchant:operator:manage"]}"##
    public static let customer = ##"{"summary":{"customerMemberId":61001,"displayName":"Example customer","arrivedCount":2,"pendingCount":1,"refundedCount":0,"paidAmount":null,"lastInteractionTime":"2026-09-30 16:00:00"},"systemTags":[{"code":"REPEAT","label":"Repeat visitor"}],"merchantTags":[{"id":900,"tagName":"Example tag","tagColor":"#2E6D5A"}],"timeline":[{"key":"note:901","type":"NOTE","title":"Example follow-up","description":"Synthetic note only","occurredAt":"2026-09-30 16:00:00","noteId":901,"noteVersion":0,"correctsNoteId":null}]}"##
    public static let customers = ##"{"rows":[{"memberId":61001,"name":"Example customer","phone":"138****0000","contactHint":"Contact requires current permission and consent","arrivedCount":2,"pendingCount":1,"refundedCount":0,"paidAmount":null,"lastAction":"Visit","tier":"repeat","sourceType":"TOPIC","lastTime":"2026-09-30 16:00:00"}],"total":1,"segmentCounts":{"all":1,"repeat":1,"new":0,"noted":1},"availableTags":[],"couponDeliveryStatus":"UNKNOWN","notificationDeliveryStatus":"UNKNOWN"}"##
    public static let refund = ##"{"refundId":62001,"refundNo":"EXAMPLE-REFUND","sourceType":"REGISTRATION","sourceId":92001,"refundAmount":"12.00","reason":"Synthetic request","processing":"WAITING_PLATFORM_REVIEW","merchantOpinion":"PENDING","canRespond":true,"allowedDecisions":["AGREE","REJECT","EVIDENCE"],"refundPolicyCode":"EXPLORE_END_100_0","refundPolicyVersion":1,"refundDeadline":"2026-10-05 18:00:00","responses":[]}"##
    public static let review = ##"{"id":63001,"rating":4,"content":"Synthetic review for native preview","imageUrls":[],"authorNickname":"Example visitor","verifiedRedemption":true,"status":"VISIBLE","merchantReply":null,"version":0,"canReply":true,"canReport":true,"canEditReply":false}"##
    public static let redemption = ##"{"recordKey":"redemption:64001","recordType":"redemption","recordId":"64001","topicName":"Example route","chapterName":"Example chapter","customerDisplayName":"Example visitor","verificationCodeTail":"0012","settlementAmount":null,"fulfillmentState":"ACTIVE","settlementState":"PENDING","settlementRoute":"COOP_ORDER","displayState":"PENDING_SETTLEMENT","refundState":"NONE","occurredAt":"2026-09-30 15:00:00"}"##
    public static let entry = ##"{"entryKey":"adjustment:65001","entryKind":"ADJUSTMENT","source":"COOP_ORDER","destination":"PERSONAL","signedAmount":"-12.00","displayState":"EXECUTED","occurredAt":"2026-09-30 15:00:00"}"##
    public static let batch = ##"{"batchId":"66001","periodYm":"2026-09","amountTotal":"0.00","netDirection":null,"paymentState":"PENDING","invoiceState":"UNKNOWN","holdState":"NONE","displayState":"PENDING","paidAt":null,"payVoucherNo":null}"##
    public static let operators = ##"{"operators":[{"id":67001,"nickname":"Example operator","roleCode":"MERCHANT_CHECKIN","status":"ACTIVE","acceptedAt":"2026-09-01 09:00:00","version":2}],"invites":[{"id":68001,"roleCode":"MERCHANT_MARKETING","status":"PENDING","expiresAt":"2026-10-08 09:00:00","version":0}]}"##
    public static let roles = ##"[{"roleCode":"MERCHANT_MANAGER","name":"Manager","permissions":["merchant:crm:read"]},{"roleCode":"MERCHANT_CHECKIN","name":"Check-in","permissions":["merchant:verify"]},{"roleCode":"MERCHANT_MARKETING","name":"Marketing","permissions":["merchant:marketing:write"]},{"roleCode":"MERCHANT_FINANCE","name":"Finance","permissions":["merchant:finance:read"]}]"##
    public static let overview = ##"{"personalArrivedThisMonthGross":"12.00","personalExecutedAdjustmentsThisMonth":"-12.00","personalArrivedThisMonthNet":"0.00","publicPayablePending":null,"adjustmentPending":"0.00","adjustmentPendingCount":2}"##
    public static func decode(_ raw: String) throws -> MerchantBusinessValue { try JSONDecoder().decode(MerchantBusinessValue.self, from: Data(raw.utf8)) }
    public static func payload(_ query: MerchantBusinessQuery) throws -> MerchantBusinessValue {
        func row(_ raw: String) throws -> MerchantBusinessValue { try decode(raw) }
        func page(_ raw: String) throws -> MerchantBusinessValue { .object(["rows": .array(query.page == 1 ? [try row(raw)] : []), "total": .int(1), "pageNum": .int(query.page), "pageSize": .int(20)]) }
        switch query {
        case .customers: return try decode(customers)
        case .customer: return try decode(customer)
        case .refund: return try decode(refund)
        case .aftercare(let bucket, _):
            var value = try decode(refund).object!; value["bucket"] = .string(bucket.rawValue); value["refunded"] = .bool(false)
            value.removeValue(forKey: "allowedDecisions"); value.removeValue(forKey: "responses")
            return .object(["bucket": .string(bucket.rawValue), "pageNum": .int(query.page), "pageSize": .int(20), "total": .int(1), "hasMore": .bool(false), "items": .array([.object(value)])])
        case .reviews: return .object(["mode": .string("manage"), "pageNum": .int(query.page), "pageSize": .int(20), "total": .int(1), "hasMore": .bool(false), "averageRating": .int(4), "items": .array([try row(review)])])
        case .overview: return try decode(overview)
        case .redemptions: return try page(redemption)
        case .entries: return try page(entry)
        case .batches: return try page(batch)
        case .batch: return .object(["batch": try row(batch), "earningEntries": .array([]), "adjustments": .array([try row(entry)])])
        case .redemption: return try decode(redemption)
        case .verificationRecords: return .array([.object(["id": .int(69001), "operatorName": .string("Example operator"), "verificationCodeTail": .string("0012"), "occurredAt": .string("2026-09-30 15:00:00")])])
        case .operators: return try decode(operators)
        case .roles: return try decode(roles)
        }
    }
}
