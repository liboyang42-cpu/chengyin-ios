import Foundation

/// Immutable server projection. The full object is retained for field-preserving review and equality;
/// screens render a domain whitelist, never arbitrary JSON or guessed zero money.
public struct MerchantBusinessRecord: Equatable, Identifiable {
    public enum Kind: String { case customer, refund, review, redemption, entry, batch, verification, operatorMember, invite, role, timeline, tag, response }
    public let kind: Kind
    public let id: String
    public let fields: MerchantBusinessObject
    public var title: String {
        if kind == .refund {
            let number = fields.mbText("refundNo")?.trimmingCharacters(in: .whitespacesAndNewlines)
            return number.flatMap { $0.isEmpty ? nil : $0 } ?? "#\(id)"
        }
        for key in ["displayName", "name", "nickname", "refundNo", "authorNickname", "topicName", "title", "tagName", "periodYm"] {
            if let value = fields.mbText(key) { return value }
        }
        return "#\(id)"
    }
    public init(kind: Kind, fields: MerchantBusinessObject) throws {
        self.kind = kind; self.fields = fields
        switch kind {
        case .customer:
            id = String(try fields.mbInt(fields["memberId"] == nil ? "customerMemberId" : "memberId", minimum: 1))
            for key in ["arrivedCount", "pendingCount", "refundedCount"] { _ = try fields.mbInt(key) }
            _ = try MerchantBusinessMoney(fields["paidAmount"])
            if fields["memberId"] != nil {
                _ = try fields.mbRequiredText("name"); _ = try fields.mbRequiredText("lastAction")
                guard ["pending", "abnormal", "dormant", "repeat", "new"].contains(fields.mbText("tier") ?? ""),
                      ["TOPIC", "ACTIVITY", "MIXED"].contains(fields.mbText("sourceType") ?? "") else { throw MerchantBusinessFailure.malformed }
            }
        case .refund:
            id = String(try fields.mbInt("refundId", minimum: 1))
            guard Self.processing.contains(try fields.mbRequiredText("processing")),
                  ["PENDING", "AGREE", "REJECT"].contains(try fields.mbRequiredText("merchantOpinion")) else { throw MerchantBusinessFailure.malformed }
            _ = try MerchantBusinessMoney(fields["refundAmount"])
            for key in ["customerNickname", "activityTitle"] {
                if let value = fields[key], value != .null, value.string == nil { throw MerchantBusinessFailure.malformed }
            }
            let canRespond = try fields.mbBool("canRespond")
            if let refunded = fields["refunded"]?.bool, refunded != (fields.mbText("processing") == "REFUNDED") { throw MerchantBusinessFailure.malformed }
            if fields["allowedDecisions"] != nil {
                let decisions = try fields.mbStrings("allowedDecisions")
                guard canRespond == !decisions.isEmpty, Set(decisions).count == decisions.count,
                      decisions.allSatisfy({ ["AGREE", "REJECT", "EVIDENCE"].contains($0) }) else { throw MerchantBusinessFailure.malformed }
                for response in try fields.mbObjects("responses") {
                    guard try response.mbInt("refundId", minimum: 1) == Int(id) else { throw MerchantBusinessFailure.malformed }
                    _ = try MerchantBusinessRecord(kind: .response, fields: response)
                }
            }
        case .review:
            id = String(try fields.mbInt("id", minimum: 1)); _ = try fields.mbInt("version")
            guard (1...5).contains(try fields.mbInt("rating")), ["VISIBLE", "PENDING_REVIEW", "HIDDEN"].contains(try fields.mbRequiredText("status")) else { throw MerchantBusinessFailure.malformed }
            _ = try fields.mbBool("verifiedRedemption")
            let reply = try fields.mbBool("canReply"), report = try fields.mbBool("canReport")
            guard (!reply || fields.mbText("status") == "VISIBLE" && fields.mbText("merchantReply") == nil),
                  (!report || fields.mbText("status") == "VISIBLE") else { throw MerchantBusinessFailure.malformed }
            let images = try fields.mbStrings("imageUrls")
            guard images.count <= 9, images.allSatisfy(Self.safeHTTPS) else { throw MerchantBusinessFailure.malformed }
        case .redemption:
            id = try fields.mbRequiredText("recordKey")
            guard Self.redemptionRecordID(id) != nil else { throw MerchantBusinessFailure.malformed }
            _ = try MerchantBusinessMoney(fields["settlementAmount"], strictString: true)
        case .entry:
            id = try fields.mbRequiredText("entryKey")
            _ = try MerchantBusinessMoney(fields["signedAmount"], strictString: true)
        case .batch:
            id = String(try fields.mbInt("batchId", minimum: 1))
            _ = try MerchantBusinessMoney(fields["amountTotal"], strictString: true)
        case .operatorMember, .invite:
            id = String(try fields.mbInt("id", minimum: 1)); _ = try fields.mbInt("version")
            guard MerchantBusinessAccess.employeeRoles.contains(try fields.mbRequiredText("roleCode")) else { throw MerchantBusinessFailure.malformed }
            let allowed = kind == .invite ? ["PENDING", "ACCEPTED", "EXPIRED", "REVOKED"] : ["ACTIVE", "REVOKED"]
            guard allowed.contains(try fields.mbRequiredText("status")) else { throw MerchantBusinessFailure.malformed }
            _ = try fields.mbRequiredText(kind == .invite ? "expiresAt" : "acceptedAt")
        case .role:
            id = try fields.mbRequiredText("roleCode")
            guard MerchantBusinessAccess.employeeRoles.contains(id) else { throw MerchantBusinessFailure.malformed }
            _ = try fields.mbStrings("permissions")
        case .timeline:
            id = try fields.mbRequiredText("key")
            guard ["NOTE", "NOTE_CORRECTION", "ARRIVED", "REFUNDED", "REGISTERED", "CAMPAIGN"].contains(try fields.mbRequiredText("type")) else { throw MerchantBusinessFailure.malformed }
        case .tag:
            id = String(try fields.mbInt("id", minimum: 1)); _ = try fields.mbRequiredText("tagName")
            guard Self.isColor(try fields.mbRequiredText("tagColor")) else { throw MerchantBusinessFailure.malformed }
        case .response:
            id = String(try fields.mbInt("id", minimum: 1)); _ = try fields.mbInt("refundId", minimum: 1)
            guard ["AGREE", "REJECT", "EVIDENCE"].contains(try fields.mbRequiredText("decision")) else { throw MerchantBusinessFailure.malformed }
        case .verification:
            // This source wrapper has no stronger shape guarantee; no fabricated detail ID.
            id = fields["id"]?.numberText ?? fields.mbText("recordKey") ?? UUID().uuidString
        }
    }
    public var destination: MerchantBusinessQuery? {
        switch kind {
        case .customer: return (Int(id).flatMap { try? MerchantCustomerID($0) }).map(MerchantBusinessQuery.customer)
        case .refund: return (Int(id).flatMap { try? MerchantRefundID($0) }).map(MerchantBusinessQuery.refund)
        case .batch: return (Int(id).flatMap { try? MerchantBatchID($0) }).map(MerchantBusinessQuery.batch)
        case .redemption: return Self.redemptionRecordID(id).map { .redemption(recordID: $0) }
        default: return nil
        }
    }
    public static let processing = ["WAITING_PLATFORM_REVIEW", "PLATFORM_REJECTED", "REFUND_PROCESSING", "MANUAL_REFUND_PENDING", "MANUAL_REFUND_REVIEW", "REFUNDED", "UNKNOWN"]
    public static func isColor(_ value: String) -> Bool { value.range(of: #"^#[0-9A-F]{6}$"#, options: .regularExpression) != nil }
    public static func safeHTTPS(_ value: String) -> Bool { guard let url = URLComponents(string: value) else { return false }; return url.scheme == "https" && !(url.host ?? "").isEmpty && url.user == nil && url.password == nil }
    public static func redemptionRecordID(_ key: String) -> String? {
        guard key.hasPrefix("redemption:") else { return nil }
        let value = String(key.dropFirst("redemption:".count))
        guard !value.isEmpty, value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil, value.contains(where: { $0 != "0" }) else { return nil }
        return value
    }
}
public struct MerchantBusinessSection: Equatable, Identifiable {
    public let id: String
    public let rows: [MerchantBusinessRecord]
    public init(_ id: String, rows: [MerchantBusinessRecord]) throws {
        guard Set(rows.map(\.id)).count == rows.count else { throw MerchantBusinessFailure.malformed }
        self.id = id; self.rows = rows
    }
}
/// Presentation-only predicates over an already validated, currently loaded page.
/// They never change server queries, totals, capabilities or mutation baselines.
public enum MerchantReviewFilter: String, CaseIterable, Hashable {
    case all, pending, low, photos
    public func matches(_ row: MerchantBusinessRecord) -> Bool {
        guard row.kind == .review else { return false }
        switch self {
        case .all: return true
        case .pending: return row.fields["canReply"]?.bool == true && row.fields.mbText("merchantReply") == nil
        case .low: return (row.fields["rating"]?.integer).map { $0 <= 3 } ?? false
        case .photos: return !(row.fields["imageUrls"]?.array ?? []).isEmpty
        }
    }
}

public struct MerchantBusinessListFilters: Equatable {
    public var review: MerchantReviewFilter = .all
    public var aftercareKeyword = ""
    public init() {}
    public func rows(in section: MerchantBusinessSection, query: MerchantBusinessQuery) -> [MerchantBusinessRecord] {
        switch query {
        case .reviews: return section.rows.filter(review.matches)
        case .aftercare:
            let keyword = aftercareKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !keyword.isEmpty else { return section.rows }
            return section.rows.filter { row in
                guard row.kind == .refund else { return false }
                let values = [row.title] + Self.aftercareSearchKeys.dropFirst().compactMap { row.fields.mbText($0) }
                return values.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains(keyword) }
            }
        default: return section.rows
        }
    }
    public func isActive(for query: MerchantBusinessQuery) -> Bool {
        switch query {
        case .reviews: return review != .all
        case .aftercare: return !aftercareKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return false
        }
    }
    // Whitelist is intentionally narrower than the full refund payload.
    public static let aftercareSearchKeys = ["refundNo", "customerNickname", "activityTitle", "reason"]
}

/// Ephemeral read-only projection of consecutive aftercare pages. Never supplied to
/// mutation validation or persisted. The coordinator keeps its exact server snapshot.
public struct MerchantAftercareLoadedPages: Equatable {
    public let scope: MerchantBusinessScope
    public let authorizationGeneration: UUID?
    public let access: MerchantBusinessAccess
    public let bucket: MerchantAftercareBucket
    public private(set) var page: Int
    public private(set) var hasMore: Bool
    public private(set) var rows: [MerchantBusinessRecord]
    public init(snapshot: MerchantBusinessSnapshot, scope: MerchantBusinessScope, authorizationGeneration: UUID?) throws {
        guard case .aftercare(let bucket, let page) = snapshot.document.query, page == 1 else { throw MerchantBusinessFailure.stale }
        self.scope = scope; self.authorizationGeneration = authorizationGeneration
        access = snapshot.access; self.bucket = bucket; self.page = page
        hasMore = snapshot.document.hasMore; rows = snapshot.document.rows
    }
    public func matches(scope: MerchantBusinessScope?, authorizationGeneration: UUID?, access: MerchantBusinessAccess) -> Bool {
        self.scope == scope && self.authorizationGeneration == authorizationGeneration && self.access == access
    }
    public mutating func append(_ snapshot: MerchantBusinessSnapshot, scope: MerchantBusinessScope, authorizationGeneration: UUID?) throws {
        guard matches(scope: scope, authorizationGeneration: authorizationGeneration, access: snapshot.access),
              case .aftercare(let bucket, let page) = snapshot.document.query,
              self.bucket == bucket, hasMore, page == self.page + 1 else { throw MerchantBusinessFailure.stale }
        // Offset pagination can repeat an ID. Keep its original position with the
        // latest validated fields, so SwiftUI never displays duplicate identities.
        var indices = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        for row in snapshot.document.rows {
            if let index = indices[row.id] { rows[index] = row }
            else { indices[row.id] = rows.count; rows.append(row) }
        }
        self.page = page; hasMore = snapshot.document.hasMore
    }
}

public struct MerchantBusinessDocument: Equatable {
    public let query: MerchantBusinessQuery
    public let sections: [MerchantBusinessSection]
    public let summary: MerchantBusinessObject
    public let total: Int?
    public let hasMore: Bool
    public let payload: MerchantBusinessValue
    public var rows: [MerchantBusinessRecord] { sections.flatMap(\.rows) }
    public var customerDetail: MerchantCustomerDetailPresentation? {
        guard case .customer(let id) = query else { return nil }
        return try? .init(customerID: id, payload: payload)
    }
    public var aftercareProgress: MerchantAftercareProgress? {
        guard case .refund(let id) = query, let fields = payload.object else { return nil }
        return try? MerchantAftercareProgress(refundID: id.rawValue, fields: fields)
    }
    public init(query: MerchantBusinessQuery, payload: MerchantBusinessValue) throws {
        _ = try query.request()
        self.query = query; self.payload = payload
        var sections: [MerchantBusinessSection] = [], summary: MerchantBusinessObject = [:], total: Int?, more = false
        func records(_ values: [MerchantBusinessObject], _ kind: MerchantBusinessRecord.Kind) throws -> [MerchantBusinessRecord] { try values.map { try .init(kind: kind, fields: $0) } }
        func section(_ title: String, _ values: [MerchantBusinessObject], _ kind: MerchantBusinessRecord.Kind) throws -> MerchantBusinessSection { try .init(title, rows: records(values, kind)) }
        let object = payload.object ?? [:]
        switch query {
        case .customers:
            total = try object.mbInt("total")
            let rows = try records(object.mbObjects("rows"), .customer)
            guard rows.count <= 20, rows.count <= total! else { throw MerchantBusinessFailure.malformed }
            sections = [try .init("customers", rows: rows)]; summary = object["segmentCounts"]?.object ?? [:]
            more = query.page * 20 < total!
            if more && rows.isEmpty { throw MerchantBusinessFailure.malformed }
        case .customer(let id):
            let detail = try MerchantCustomerDetailPresentation(customerID: id, payload: payload)
            // Participation is a dedicated grouped projection. Only note and
            // campaign records remain in the generic action-bearing section;
            // the exact raw timeline stays in payload above for confirmations.
            sections = [try .init("customer", rows: [detail.customer]), try .init("tags", rows: detail.merchantTags),
                        try .init("timeline", rows: detail.history.map(\.record))]
        case .aftercare, .reviews:
            let isAftercare: Bool
            if case .aftercare = query { isAftercare = true } else { isAftercare = false }
            // Separate check avoids binding assumptions about unrelated query cases.
            if isAftercare, case .aftercare(let requested, _) = query {
                guard object.mbText("bucket") == requested.rawValue else { throw MerchantBusinessFailure.malformed }
            } else { guard object.mbText("mode") == "manage", object["eligibility"] == nil || object["eligibility"] == .null else { throw MerchantBusinessFailure.malformed } }
            let page = try object.mbInt("pageNum", minimum: 1), size = try object.mbInt("pageSize", minimum: 1)
            total = try object.mbInt("total"); more = try object.mbBool("hasMore")
            let rawRows = try object.mbObjects("items")
            guard page == query.page, size == 20 else { throw MerchantBusinessFailure.malformed }
            let through = (page - 1) * size + rawRows.count
            guard rawRows.count <= size, through <= total!, more == (through < total!), !(more && rawRows.isEmpty) else { throw MerchantBusinessFailure.malformed }
            if isAftercare, case .aftercare(let requested, _) = query {
                guard rawRows.allSatisfy({ $0.mbText("bucket") == requested.rawValue && $0["refunded"]?.bool != nil }) else { throw MerchantBusinessFailure.malformed }
            }
            sections = [try section(isAftercare ? "aftercare" : "reviews", rawRows, isAftercare ? .refund : .review)]
            if let average = object["averageRating"] {
                if average != .null {
                    guard case .number(let value) = average, value >= 1, value <= 5 else { throw MerchantBusinessFailure.malformed }
                }
                summary["averageRating"] = average
            }
            if !isAftercare {
                for key in Self.reviewMetricKeys {
                    let value = object[key] ?? .null
                    if value != .null {
                        guard case .number = value, let count = value.integer, count >= 0,
                              key != "replyRatePct" || count <= 100 else { throw MerchantBusinessFailure.malformed }
                    }
                    // Missing is unknown, never a local count or a guessed zero.
                    summary[key] = value
                }
            }
        case .refund(let id):
            guard try object.mbInt("refundId", minimum: 1) == id.rawValue else { throw MerchantBusinessFailure.malformed }
            _ = try MerchantAftercareProgress(refundID: id.rawValue, fields: object)
            sections = [try section("refund", [object], .refund), try section("responses", object.mbObjects("responses"), .response)]
        case .overview:
            guard payload.object != nil else { throw MerchantBusinessFailure.malformed }
            for key in Self.overviewMoneyKeys { _ = try MerchantBusinessMoney(object[key], strictString: true) }
            summary = object
        case .redemptions, .entries, .batches:
            total = try object.mbInt("total")
            let kind: MerchantBusinessRecord.Kind
            if case .redemptions = query { kind = .redemption }
            else if case .entries = query { kind = .entry } else { kind = .batch }
            if kind != .redemption {
                guard try object.mbInt("pageNum", minimum: 1) == query.page, try object.mbInt("pageSize", minimum: 1) == 20 else { throw MerchantBusinessFailure.malformed }
            }
            let rows = try records(object.mbObjects("rows"), kind)
            guard rows.count <= 20, rows.count <= total! else { throw MerchantBusinessFailure.malformed }
            summary = object["summary"]?.object ?? [:]; more = query.page * 20 < total!
            guard !(more && rows.isEmpty) else { throw MerchantBusinessFailure.malformed }
            sections = [try .init(kind.rawValue, rows: rows)]
        case .batch(let id):
            let batch = try object.mbObject("batch")
            guard try batch.mbInt("batchId", minimum: 1) == id.rawValue else { throw MerchantBusinessFailure.malformed }
            sections = [try section("batch", [batch], .batch), try section("earnings", object.mbObjects("earningEntries"), .entry), try section("adjustments", object.mbObjects("adjustments"), .entry)]
        case .redemption(let id):
            guard object.mbText("recordKey") == "redemption:\(id)" else { throw MerchantBusinessFailure.malformed }
            if let returned = object["recordId"]?.numberText, returned != id { throw MerchantBusinessFailure.malformed }
            if let type = object.mbText("recordType"), type != "redemption" { throw MerchantBusinessFailure.malformed }
            sections = [try section("redemption", [object], .redemption)]
        case .verificationRecords:
            let values = try (payload.array ?? object.mbArray("rows"))
            let objects = try values.map { guard let value = $0.object else { throw MerchantBusinessFailure.malformed }; return value }
            sections = [try section("verifications", objects, .verification)]
        case .operators:
            sections = [try section("operators", object.mbObjects("operators"), .operatorMember), try section("invites", object.mbObjects("invites"), .invite)]
        case .roles:
            guard let values = payload.array else { throw MerchantBusinessFailure.malformed }
            sections = [try section("roles", values.map { guard let value = $0.object else { throw MerchantBusinessFailure.malformed }; return value }, .role)]
        }
        self.sections = sections; self.summary = summary; self.total = total; self.hasMore = more
    }
    public static let reviewMetricKeys = ["pendingReplyCount", "monthNewCount", "replyRatePct"]
    public static let overviewMoneyKeys = ["personalArrivedThisMonthGross", "personalExecutedAdjustmentsThisMonth", "personalArrivedThisMonthNet", "publicPayablePending", "adjustmentPending"]
}
