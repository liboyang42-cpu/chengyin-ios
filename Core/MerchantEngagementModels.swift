import Foundation

public struct MerchantSavedSegment: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let filter: MerchantCRMFilter?
    public let source: MerchantBusinessObject
    public init(_ fields: MerchantBusinessObject) throws {
        id = try fields.mbInt("id", minimum: 1); name = fields.mbText("name"); source = fields
        filter = try fields["filter"]?.object.map { try MerchantCRMFilter(savedFields: $0) }
    }
}
public struct MerchantCampaignCoupon: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public init(_ fields: MerchantBusinessObject) throws { id = try fields.mbInt("id", minimum: 1); name = fields.mbText("name") }
}
public struct MerchantAudiencePreview: Equatable {
    public enum Kind: String { case campaign, broadcast }
    public let kind: Kind
    /// Missing counts are unknown, not zero. Broadcast source requires all nine fields.
    public let counts: [String: Int]
    public let source: MerchantBusinessObject
    public static let campaignKeys = ["totalCount", "recipientLimit", "consentedCount", "frequencyLimitedCount", "deliverableCount"]
    public static let broadcastKeys = ["audienceCount", "consentedCount", "noConsentCount", "frequencyLimitedCount", "deliverableCount", "recipientLimit", "merchantDailyLimit", "merchantDailyUsed", "merchantDailyRemaining"]
    public init(kind: Kind, fields: MerchantBusinessObject) throws {
        self.kind = kind; source = fields
        let keys = kind == .broadcast ? Self.broadcastKeys : Self.campaignKeys
        var values: [String: Int] = [:]
        for key in keys {
            if fields[key] != nil && fields[key] != .null { values[key] = try fields.mbInt(key) }
            else if kind == .broadcast { throw MerchantBusinessFailure.malformed }
        }
        if kind == .broadcast { values["filterTotalCount"] = fields["filterTotalCount"]?.integer.flatMap { $0 >= 0 ? $0 : nil } ?? values["audienceCount"] }
        counts = values
    }
    public var isComplete: Bool { (kind == .campaign ? Self.campaignKeys : Self.broadcastKeys).allSatisfy { counts[$0] != nil } }
    public var canSend: Bool { isComplete && (counts["deliverableCount"] ?? 0) > 0 && (kind != .broadcast || (counts["merchantDailyRemaining"] ?? 0) > 0) }
}
public struct MerchantCampaignRecipient: Equatable, Identifiable {
    public let id: String
    public let source: MerchantBusinessObject
    public init(_ fields: MerchantBusinessObject, index: Int) throws {
        if let raw = fields["recipientId"], raw != .null { guard let value = raw.integer, value > 0 else { throw MerchantBusinessFailure.malformed }; id = "recipient:\(value)" }
        else { id = "source-row:\(index)" }
        source = fields
    }
}
public struct MerchantCampaignTask: Equatable, Identifiable {
    public let id: Int
    public let status: String?
    public let title: String?
    public let channel: MerchantCampaignChannel?
    public let counts: [String: Int]
    public let recipients: [MerchantCampaignRecipient]
    public let source: MerchantBusinessObject
    public static let countKeys = ["recipientCount", "deliveredCount", "noConsentCount", "frequencySkippedCount", "failedCount", "retryableCount"]
    public init(_ fields: MerchantBusinessObject, expectedID: Int? = nil) throws {
        id = try fields.mbInt("id", minimum: 1)
        guard expectedID == nil || expectedID == id else { throw MerchantBusinessFailure.malformed }
        source = fields; status = fields.mbText("status"); title = fields.mbText("title"); channel = fields.mbText("channel").flatMap(MerchantCampaignChannel.init(rawValue:))
        var values: [String: Int] = [:]
        for key in Self.countKeys where fields[key] != nil && fields[key] != .null { values[key] = try fields.mbInt(key) }
        counts = values
        let rows = try fields["recipients"] == nil ? [] : fields.mbObjects("recipients")
        recipients = try rows.enumerated().map { try .init($0.element, index: $0.offset) }
        guard Set(recipients.map(\.id)).count == recipients.count else { throw MerchantBusinessFailure.malformed }
    }
    public var canDispatch: Bool { status == "READY" && channel != nil && counts["recipientCount"] != nil }
    public var canRetry: Bool { status == "PARTIAL_FAILED" && channel != nil && (counts["retryableCount"] ?? 0) > 0 }
}
public struct MerchantBroadcastReceipt: Equatable {
    public let id: Int
    public let status: String
    public let counts: [String: Int]
    public init(_ fields: MerchantBusinessObject) throws {
        id = try fields.mbInt("id", minimum: 1); status = try fields.mbRequiredText("status")
        guard ["SUCCESS", "PARTIAL_FAILED", "FAILED"].contains(status) else { throw MerchantBusinessFailure.malformed }
        var values: [String: Int] = [:]
        for key in ["audienceCount", "consentedCount", "noConsentCount", "frequencySkippedCount", "deliveredCount", "failedCount"] { values[key] = try fields.mbInt(key) }
        counts = values
    }
}
public struct MerchantExportTask: Equatable, Identifiable {
    public let id: Int
    public let status: String
    public let rowCount: Int?
    public let errorMessage: String?
    public init(_ fields: MerchantBusinessObject, expectedID: Int? = nil) throws {
        id = try fields.mbInt("id", minimum: 1); status = try fields.mbRequiredText("status")
        guard expectedID == nil || expectedID == id, ["PENDING", "RUNNING", "SUCCESS", "FAILED", "EXPIRED"].contains(status) else { throw MerchantBusinessFailure.malformed }
        if fields["rowCount"] != nil && fields["rowCount"] != .null { rowCount = try fields.mbInt("rowCount") } else { rowCount = nil }
        guard status != "SUCCESS" || rowCount != nil else { throw MerchantBusinessFailure.malformed }
        errorMessage = fields.mbText("errorMessage")
    }
    public var isRunning: Bool { status == "PENDING" || status == "RUNNING" }
    public var isDownloadable: Bool { status == "SUCCESS" }
}
/// Memory only. Poll responses never replace this one-time creation token.
public struct MerchantExportTicket: Equatable {
    public let task: MerchantExportTask
    let downloadToken: String?
    public init(creation fields: MerchantBusinessObject) throws {
        task = try .init(fields); downloadToken = fields.mbText("downloadToken")
        if let token = downloadToken { guard AuthRequestBuilder.isValidToken(token) else { throw MerchantBusinessFailure.malformed } }
    }
    func updating(_ task: MerchantExportTask) throws -> Self {
        guard self.task.id == task.id else { throw MerchantBusinessFailure.malformed }
        return .init(task: task, downloadToken: downloadToken)
    }
    private init(task: MerchantExportTask, downloadToken: String?) { self.task = task; self.downloadToken = downloadToken }
    public var canDownload: Bool { task.isDownloadable && downloadToken != nil }
}
public struct MerchantContactReceipt {
    public let customerID: MerchantCustomerID
    public let purpose: MerchantContactPurpose
    let phone: String
    init(customerID: MerchantCustomerID, purpose: MerchantContactPurpose, fields: MerchantBusinessObject) throws {
        let phone = try fields.mbRequiredText("phone").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty, !phone.contains("*"), !phone.contains("\n"), !phone.contains("\r") else { throw MerchantBusinessFailure.malformed }
        self.customerID = customerID; self.purpose = purpose; self.phone = phone
    }
}
public enum MerchantEngagementPayload: Equatable {
    case segments([MerchantSavedSegment]), coupons([MerchantCampaignCoupon]), campaigns([MerchantCampaignTask]), campaign(MerchantCampaignTask)
    case audience(MerchantAudiencePreview), exportStatus(MerchantExportTask), customer(MerchantBusinessDocument)
    public init(query: MerchantEngagementQuery, value: MerchantBusinessValue) throws {
        func objects() throws -> [MerchantBusinessObject] {
            guard let array = value.array else { throw MerchantBusinessFailure.malformed }
            return try array.map { guard let object = $0.object else { throw MerchantBusinessFailure.malformed }; return object }
        }
        func object() throws -> MerchantBusinessObject { guard let object = value.object else { throw MerchantBusinessFailure.malformed }; return object }
        switch query {
        case .segments:
            let rows = try objects().map(MerchantSavedSegment.init); guard Set(rows.map(\.id)).count == rows.count else { throw MerchantBusinessFailure.malformed }; self = .segments(rows)
        case .coupons:
            let rows = try objects().map(MerchantCampaignCoupon.init); guard Set(rows.map(\.id)).count == rows.count else { throw MerchantBusinessFailure.malformed }; self = .coupons(rows)
        case .campaigns:
            let rows = try objects().map { try MerchantCampaignTask($0) }; guard Set(rows.map(\.id)).count == rows.count else { throw MerchantBusinessFailure.malformed }; self = .campaigns(rows)
        case .campaign(let id): self = .campaign(try .init(object(), expectedID: id))
        case .campaignPreview: self = .audience(try .init(kind: .campaign, fields: object()))
        case .broadcastPreview: self = .audience(try .init(kind: .broadcast, fields: object()))
        case .exportStatus(let id): self = .exportStatus(try .init(object(), expectedID: id))
        case .customer(let id): self = .customer(try .init(query: .customer(id), payload: value))
        }
    }
}
public enum MerchantEngagementReceipt {
    case savedSegment, campaignCreated(MerchantCampaignTask), campaignDispatched(MerchantCampaignTask), campaignRetried(MerchantCampaignTask)
    case broadcast(MerchantBroadcastReceipt), exportCreated(MerchantExportTicket), contact(MerchantContactReceipt), invitationAccepted(MerchantBusinessRecord)
    case exportDownloaded(taskID: Int, bytes: Data), evidenceUploaded(refundID: MerchantRefundID, selectionID: UUID, MerchantAftercareEvidenceReceipt)
    init(command: MerchantEngagementCommand, value: MerchantBusinessValue) throws {
        guard let fields = value.object else { throw MerchantBusinessFailure.malformed }
        switch command {
        case .saveSegment: self = .savedSegment
        case .createCampaign: self = .campaignCreated(try .init(fields))
        case .dispatchCampaign(let id): self = .campaignDispatched(try .init(fields, expectedID: id))
        case .retryCampaign(let id): self = .campaignRetried(try .init(fields, expectedID: id))
        case .broadcast: self = .broadcast(try .init(fields))
        case .createExport: self = .exportCreated(try .init(creation: fields))
        case .contact(let id, let purpose): self = .contact(try .init(customerID: id, purpose: purpose, fields: fields))
        case .downloadExport, .uploadEvidence: throw MerchantBusinessFailure.invalid
        case .acceptInvitation:
            let member = try MerchantBusinessRecord(kind: .operatorMember, fields: fields)
            guard member.fields.mbText("status") == "ACTIVE" else { throw MerchantBusinessFailure.malformed }; self = .invitationAccepted(member)
        }
    }
}
