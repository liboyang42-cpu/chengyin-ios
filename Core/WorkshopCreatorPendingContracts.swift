import Foundation

/// Immutable paid proposal input. Construct only from explicitly supplied author choices;
/// retaining or decoding this command is not permission to dispatch it or to declare consent.
public struct WorkshopCreatorPendingCommand: Codable, Equatable {
    public let requestId: String, sourceTemplateId: Int64
    public let expectedTemplateHash, expectedPackageContentHash, termsDocument: String
    public let commercialUse, adaptation, translation, allowedRegions, buyerKinds: String
    public let themeLimit, merchantLimit, runLimit, priceMinor: Int64
    public let currency, expiresAt, useDuration, updates, redistribution, copyrightOwnership, acquisition: String
    enum CodingKeys: String, CodingKey, CaseIterable {
        case requestId, sourceTemplateId, expectedTemplateHash, expectedPackageContentHash, termsDocument
        case commercialUse, adaptation, translation, allowedRegions, buyerKinds, themeLimit, merchantLimit, runLimit
        case priceMinor, currency, expiresAt, useDuration, updates, redistribution, copyrightOwnership, acquisition
    }
    public init(preview: WorkshopCreatorPreview, termsDocument: String, commercialUse: String, adaptation: String,
                translation: String, allowedRegions: String, buyerKinds: String, themeLimit: Int64, merchantLimit: Int64,
                runLimit: Int64, priceMinor: Int64, currency: String, expiresAt: String,
                requestId: String = UUID().uuidString.lowercased(), now: Date = Date()) throws {
        self.requestId = requestId; sourceTemplateId = preview.sourceTemplateId
        expectedTemplateHash = preview.templateHash; expectedPackageContentHash = preview.packageContentHash
        self.termsDocument = termsDocument; self.commercialUse = commercialUse; self.adaptation = adaptation
        self.translation = translation; self.allowedRegions = allowedRegions; self.buyerKinds = buyerKinds
        self.themeLimit = themeLimit; self.merchantLimit = merchantLimit; self.runLimit = runLimit
        self.priceMinor = priceMinor; self.currency = currency; self.expiresAt = expiresAt
        useDuration = "PERPETUAL_PURCHASED_VERSION"; updates = "EXACT_PURCHASED_VERSION"; redistribution = "PROHIBITED"
        copyrightOwnership = "RETAINED_BY_CREATOR"; acquisition = "PAID"
        try validate(); guard let end = WorkshopCreatorPendingWire.date(expiresAt), now.timeIntervalSince1970.isFinite,
              end > now, end.timeIntervalSince(now) <= 30 * 86_400 else { throw WorkshopCreatorConsentIssue.invalid }
        _ = try data()
    }
    public init(from decoder: Decoder) throws {
        try WorkshopCreatorWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try c.decode(String.self, forKey: .requestId); sourceTemplateId = try c.decode(Int64.self, forKey: .sourceTemplateId)
        expectedTemplateHash = try c.decode(String.self, forKey: .expectedTemplateHash); expectedPackageContentHash = try c.decode(String.self, forKey: .expectedPackageContentHash)
        termsDocument = try c.decode(String.self, forKey: .termsDocument); commercialUse = try c.decode(String.self, forKey: .commercialUse)
        adaptation = try c.decode(String.self, forKey: .adaptation); translation = try c.decode(String.self, forKey: .translation)
        allowedRegions = try c.decode(String.self, forKey: .allowedRegions); buyerKinds = try c.decode(String.self, forKey: .buyerKinds)
        themeLimit = try c.decode(Int64.self, forKey: .themeLimit); merchantLimit = try c.decode(Int64.self, forKey: .merchantLimit)
        runLimit = try c.decode(Int64.self, forKey: .runLimit); priceMinor = try c.decode(Int64.self, forKey: .priceMinor)
        currency = try c.decode(String.self, forKey: .currency); expiresAt = try c.decode(String.self, forKey: .expiresAt)
        useDuration = try c.decode(String.self, forKey: .useDuration); updates = try c.decode(String.self, forKey: .updates)
        redistribution = try c.decode(String.self, forKey: .redistribution); copyrightOwnership = try c.decode(String.self, forKey: .copyrightOwnership)
        acquisition = try c.decode(String.self, forKey: .acquisition)
        try validate(); _ = try data() // Historical recovery can be expired; it is not current source eligibility.
    }
    private func validate() throws {
        guard WorkshopCreatorWire.uuid(requestId), sourceTemplateId > 0,
              [expectedTemplateHash, expectedPackageContentHash].allSatisfy(WorkshopCreatorWire.hash),
              WorkshopCreatorPendingWire.document(termsDocument), WorkshopCreatorPendingWire.permission(commercialUse),
              WorkshopCreatorPendingWire.adaptation(adaptation), WorkshopCreatorPendingWire.permission(translation),
              WorkshopCreatorPendingWire.regions(WorkshopCreatorPendingWire.csv(allowedRegions)),
              WorkshopCreatorPendingWire.buyers(WorkshopCreatorPendingWire.csv(buyerKinds)),
              [themeLimit, merchantLimit, runLimit].allSatisfy({ $0 >= -1 }), priceMinor > 0,
              WorkshopCreatorPendingWire.currency(currency), WorkshopCreatorPendingWire.date(expiresAt) != nil,
              useDuration == "PERPETUAL_PURCHASED_VERSION", updates == "EXACT_PURCHASED_VERSION", redistribution == "PROHIBITED",
              copyrightOwnership == "RETAINED_BY_CREATOR", acquisition == "PAID" else { throw WorkshopCreatorConsentIssue.malformed }
    }
    public var termsDocumentHash: String { WorkshopCreatorWire.sha(Data(termsDocument.utf8)) }
    public func matches(preview: WorkshopCreatorPreview) -> Bool {
        sourceTemplateId == preview.sourceTemplateId && expectedTemplateHash == preview.templateHash && expectedPackageContentHash == preview.packageContentHash
    }
    func data() throws -> Data {
        let value = try WorkshopCreatorWire.encode(self)
        guard value.count <= WorkshopCreatorPendingWire.maximumRequest else { throw WorkshopCreatorConsentIssue.invalid }; return value
    }
    public static func == (a: Self, b: Self) -> Bool {
        guard let left = try? a.data(), let right = try? b.data() else { return false }; return left == right
    }
}

/// Recovery metadata is not evidence that the source is currently eligible, even when nonexpired.
public struct WorkshopCreatorPendingMetadata: Decodable, Equatable, Identifiable {
    public let targetId, revision: String
    public let sourceTemplateId: Int64
    public let templateHash, packageContentHash, moduleId, versionId, offerVersion, termsVersion, termsDocumentHash: String
    public let expiresAt, createdAt: String
    public let expiresAtDate, createdAtDate: Date
    public var id: String { targetId }
    public static let state = "UNREVIEWED_AUTHOR_PROPOSAL"
    public static let copyrightOwnership = "RETAINED_BY_CREATOR"
    static let keys: Set<String> = ["schema", "targetId", "revision", "sourceTemplateId", "templateHash", "packageContentHash", "moduleId", "versionId", "offerVersion", "termsVersion", "termsDocumentHash", "expiresAt", "createdAt", "state", "packageReviewed", "listed", "licenseIssued", "copyrightOwnership"]
    private enum CodingKeys: String, CodingKey {
        case schema, targetId, revision, sourceTemplateId, templateHash, packageContentHash, moduleId, versionId, offerVersion
        case termsVersion, termsDocumentHash, expiresAt, createdAt, state, packageReviewed, listed, licenseIssued, copyrightOwnership
    }
    public init(from decoder: Decoder) throws { try self.init(from: decoder, exactKeys: Self.keys) }
    fileprivate init(from decoder: Decoder, exactKeys: Set<String>) throws {
        try WorkshopCreatorWire.keys(decoder, exactKeys)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-creator-pending-package-v1",
              try c.decode(String.self, forKey: .state) == Self.state,
              try c.decode(String.self, forKey: .copyrightOwnership) == Self.copyrightOwnership,
              try c.decode(Bool.self, forKey: .packageReviewed) == false,
              try c.decode(Bool.self, forKey: .listed) == false, try c.decode(Bool.self, forKey: .licenseIssued) == false else { throw WorkshopCreatorConsentIssue.malformed }
        targetId = try c.decode(String.self, forKey: .targetId); revision = try c.decode(String.self, forKey: .revision)
        sourceTemplateId = try c.decode(Int64.self, forKey: .sourceTemplateId)
        templateHash = try c.decode(String.self, forKey: .templateHash); packageContentHash = try c.decode(String.self, forKey: .packageContentHash)
        moduleId = try c.decode(String.self, forKey: .moduleId); versionId = try c.decode(String.self, forKey: .versionId)
        offerVersion = try c.decode(String.self, forKey: .offerVersion); termsVersion = try c.decode(String.self, forKey: .termsVersion)
        termsDocumentHash = try c.decode(String.self, forKey: .termsDocumentHash)
        expiresAt = try c.decode(String.self, forKey: .expiresAt); createdAt = try c.decode(String.self, forKey: .createdAt)
        guard WorkshopCreatorWire.uuid(targetId), sourceTemplateId > 0,
              [revision, templateHash, packageContentHash, termsDocumentHash].allSatisfy(WorkshopCreatorWire.hash),
              moduleId == "member-template:\(sourceTemplateId)", versionId == "creator-package:\(targetId):\(revision)",
              offerVersion == "creator-offer:\(targetId):\(revision)", termsVersion == "creator-terms:\(targetId)",
              let end = WorkshopCreatorPendingWire.date(expiresAt), let start = WorkshopCreatorPendingWire.date(createdAt),
              start < end, end.timeIntervalSince(start) <= 30 * 86_400 + 0.000002 else { throw WorkshopCreatorConsentIssue.malformed }
        expiresAtDate = end; createdAtDate = start
    }
    public func isUnexpired(now: Date = Date()) -> Bool { now.timeIntervalSince1970.isFinite && createdAtDate <= now && now < expiresAtDate }
    public func matches(command: WorkshopCreatorPendingCommand) -> Bool {
        sourceTemplateId == command.sourceTemplateId && templateHash == command.expectedTemplateHash && packageContentHash == command.expectedPackageContentHash &&
        termsDocumentHash == command.termsDocumentHash && WorkshopCreatorPendingWire.instantMicros(expiresAt) == WorkshopCreatorPendingWire.instantMicros(command.expiresAt)
    }
}

public struct WorkshopCreatorPendingPage: Decodable, Equatable {
    public let sourceTemplateId: Int64, items: [WorkshopCreatorPendingMetadata], hasMore: Bool, nextCursor: String?
    private enum CodingKeys: String, CodingKey { case schema, sourceTemplateId, items, hasMore, nextCursor }
    public init(from decoder: Decoder) throws {
        try WorkshopCreatorWire.keys(decoder, ["schema", "sourceTemplateId", "items", "hasMore", "nextCursor"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == "w18-creator-pending-package-list-v1" else { throw WorkshopCreatorConsentIssue.malformed }
        sourceTemplateId = try c.decode(Int64.self, forKey: .sourceTemplateId); hasMore = try c.decode(Bool.self, forKey: .hasMore)
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
        var input = try c.nestedUnkeyedContainer(forKey: .items), result: [WorkshopCreatorPendingMetadata] = []
        while !input.isAtEnd {
            guard result.count < 20 else { throw WorkshopCreatorConsentIssue.malformed }
            let item = try input.decode(WorkshopCreatorPendingMetadata.self)
            guard item.sourceTemplateId == sourceTemplateId, result.last.map({ $0.targetId < item.targetId }) ?? true else { throw WorkshopCreatorConsentIssue.malformed }
            result.append(item)
        }
        guard sourceTemplateId > 0, hasMore == (nextCursor != nil), !hasMore || (result.count == 20 && nextCursor == result.last?.targetId) else { throw WorkshopCreatorConsentIssue.malformed }
        items = result
    }
    public func matches(sourceTemplateId: Int64, afterTargetId: String?, now: Date = Date()) -> Bool {
        self.sourceTemplateId == sourceTemplateId && items.allSatisfy { item in item.isUnexpired(now: now) && (afterTargetId.map { $0 < item.targetId } ?? true) }
    }
}

public struct WorkshopCreatorPendingOffer: Decodable, Equatable {
    public struct Seller: Decodable, Equatable {
        public let kind: String, entityId: Int64
        private enum CodingKeys: String, CodingKey { case kind, entityId }
        public init(from decoder: Decoder) throws {
            try WorkshopCreatorWire.keys(decoder, ["kind", "entityId"]); let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decode(String.self, forKey: .kind); entityId = try c.decode(Int64.self, forKey: .entityId)
            guard kind == "INDIVIDUAL", entityId > 0 else { throw WorkshopCreatorConsentIssue.malformed }
        }
    }
    public struct Limit: Decodable, Equatable {
        public let unlimited: Bool, maximum: Int64
        private enum CodingKeys: String, CodingKey { case unlimited, maximum }
        public init(from decoder: Decoder) throws {
            try WorkshopCreatorWire.keys(decoder, ["unlimited", "maximum"]); let c = try decoder.container(keyedBy: CodingKeys.self)
            unlimited = try c.decode(Bool.self, forKey: .unlimited); maximum = try c.decode(Int64.self, forKey: .maximum)
            guard maximum >= 0, !unlimited || maximum == 0 else { throw WorkshopCreatorConsentIssue.malformed }
        }
    }
    public struct Terms: Decodable, Equatable {
        public let useDuration, termsVersion, termsHash, termsDocumentHash, termsDocumentReference: String
        public let commercialUse, adaptation, translation, updates, redistribution: String
        public let allowedRegions: [String], themeLimit: Limit, merchantLimit: Limit, runLimit: Limit
        private enum CodingKeys: String, CodingKey, CaseIterable {
            case useDuration, termsVersion, termsHash, termsDocumentHash, termsDocumentReference, commercialUse
            case adaptation, translation, updates, redistribution, allowedRegions, themeLimit, merchantLimit, runLimit
        }
        public init(from decoder: Decoder) throws {
            // publicThemeUseConsent is deliberately absent. Null or non-null references both fail.
            try WorkshopCreatorWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self)
            useDuration = try c.decode(String.self, forKey: .useDuration); termsVersion = try c.decode(String.self, forKey: .termsVersion)
            termsHash = try c.decode(String.self, forKey: .termsHash); termsDocumentHash = try c.decode(String.self, forKey: .termsDocumentHash)
            termsDocumentReference = try c.decode(String.self, forKey: .termsDocumentReference); commercialUse = try c.decode(String.self, forKey: .commercialUse)
            adaptation = try c.decode(String.self, forKey: .adaptation); translation = try c.decode(String.self, forKey: .translation)
            updates = try c.decode(String.self, forKey: .updates); redistribution = try c.decode(String.self, forKey: .redistribution)
            allowedRegions = try c.decode([String].self, forKey: .allowedRegions); themeLimit = try c.decode(Limit.self, forKey: .themeLimit)
            merchantLimit = try c.decode(Limit.self, forKey: .merchantLimit); runLimit = try c.decode(Limit.self, forKey: .runLimit)
            guard useDuration == "PERPETUAL_PURCHASED_VERSION", [termsHash, termsDocumentHash].allSatisfy(WorkshopCreatorWire.hash),
                  WorkshopCreatorWire.identifier(termsVersion), termsDocumentReference.hasPrefix("creator-pending:"),
                  WorkshopCreatorWire.uuid(String(termsDocumentReference.dropFirst("creator-pending:".count))),
                  WorkshopCreatorPendingWire.permission(commercialUse), WorkshopCreatorPendingWire.adaptation(adaptation),
                  WorkshopCreatorPendingWire.permission(translation), updates == "EXACT_PURCHASED_VERSION", redistribution == "PROHIBITED",
                  WorkshopCreatorPendingWire.regions(allowedRegions) else { throw WorkshopCreatorConsentIssue.malformed }
            guard snapshotHash() == termsHash else { throw WorkshopCreatorConsentIssue.malformed }
        }
        /// Exact Java DataOutputStream v2 digest, including full text hash and every proposed restriction.
        private func snapshotHash() -> String {
            var data = Data()
            for text in ["W18-license-terms-snapshot-v2", useDuration, termsVersion, termsDocumentHash, termsDocumentReference, commercialUse, adaptation, translation, updates, redistribution] {
                WorkshopCreatorPendingWire.append(text, to: &data)
            }
            WorkshopCreatorPendingWire.appendInteger(UInt64(allowedRegions.count), bytes: 4, to: &data)
            for region in allowedRegions.sorted() { WorkshopCreatorPendingWire.append(region, to: &data) }
            for limit in [themeLimit, merchantLimit, runLimit] {
                data.append(limit.unlimited ? 1 : 0); WorkshopCreatorPendingWire.appendInteger(UInt64(limit.maximum), bytes: 8, to: &data)
            }
            return WorkshopCreatorWire.sha(data)
        }
    }
    public let offerId, offerVersion, moduleId, acquisition, currency: String
    public let seller: Seller, buyerKinds: [String], priceMinor: Int64, terms: Terms
    private enum CodingKeys: String, CodingKey, CaseIterable { case offerId, offerVersion, moduleId, seller, buyerKinds, acquisition, priceMinor, currency, terms }
    public init(from decoder: Decoder) throws {
        try WorkshopCreatorWire.keys(decoder, Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self)
        offerId = try c.decode(String.self, forKey: .offerId); offerVersion = try c.decode(String.self, forKey: .offerVersion)
        moduleId = try c.decode(String.self, forKey: .moduleId); seller = try c.decode(Seller.self, forKey: .seller)
        buyerKinds = try c.decode([String].self, forKey: .buyerKinds); acquisition = try c.decode(String.self, forKey: .acquisition)
        priceMinor = try c.decode(Int64.self, forKey: .priceMinor); currency = try c.decode(String.self, forKey: .currency); terms = try c.decode(Terms.self, forKey: .terms)
        guard offerId.hasPrefix("creator-offer:"), WorkshopCreatorWire.uuid(String(offerId.dropFirst("creator-offer:".count))),
              [offerVersion, moduleId].allSatisfy(WorkshopCreatorWire.identifier), WorkshopCreatorPendingWire.buyers(buyerKinds),
              acquisition == "PAID", priceMinor > 0, WorkshopCreatorPendingWire.currency(currency),
              String(offerId.dropFirst("creator-offer:".count)) == String(terms.termsDocumentReference.dropFirst("creator-pending:".count)) else { throw WorkshopCreatorConsentIssue.malformed }
    }
}

public struct WorkshopCreatorPendingDetail: Decodable, Equatable {
    public let metadata: WorkshopCreatorPendingMetadata
    public let termsDocument, packageSourceJson, disclosureVersion, disclosureHash, disclosureText: String
    public let omittedPlanningMetadata: [String], proposedOffer: WorkshopCreatorPendingOffer
    public let textFields: [String: String]
    private enum CodingKeys: String, CodingKey { case termsDocument, packageSourceJson, omittedPlanningMetadata, proposedOffer, disclosureVersion, disclosureHash, disclosureText }
    public init(from decoder: Decoder) throws {
        metadata = try WorkshopCreatorPendingMetadata(from: decoder, exactKeys: WorkshopCreatorPendingMetadata.keys.union(["termsDocument", "packageSourceJson", "omittedPlanningMetadata", "proposedOffer", "disclosureVersion", "disclosureHash", "disclosureText"]))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        termsDocument = try c.decode(String.self, forKey: .termsDocument); packageSourceJson = try c.decode(String.self, forKey: .packageSourceJson)
        omittedPlanningMetadata = try c.decode([String].self, forKey: .omittedPlanningMetadata); proposedOffer = try c.decode(WorkshopCreatorPendingOffer.self, forKey: .proposedOffer)
        disclosureVersion = try c.decode(String.self, forKey: .disclosureVersion); disclosureHash = try c.decode(String.self, forKey: .disclosureHash)
        disclosureText = try c.decode(String.self, forKey: .disclosureText)
        guard WorkshopCreatorPendingWire.document(termsDocument), WorkshopCreatorWire.sha(Data(termsDocument.utf8)) == metadata.termsDocumentHash,
              packageSourceJson.utf8.count <= 262_144, WorkshopCreatorWire.sha(Data(packageSourceJson.utf8)) == metadata.packageContentHash,
              proposedOffer.moduleId == metadata.moduleId, proposedOffer.offerVersion == metadata.offerVersion,
              proposedOffer.terms.termsVersion == metadata.termsVersion, proposedOffer.terms.termsDocumentHash == metadata.termsDocumentHash,
              disclosureVersion == WorkshopCreatorDisclosure.version, disclosureHash == WorkshopCreatorDisclosure.hash,
              WorkshopCreatorWire.same(disclosureText, WorkshopCreatorDisclosure.text) else { throw WorkshopCreatorConsentIssue.malformed }
        // Reuse the accepted exact source projection parser instead of introducing a looser copy.
        let previewObject: [String: Any] = ["schema": "w18-creator-public-use-preview-v1", "sourceTemplateId": metadata.sourceTemplateId,
            "templateHash": metadata.templateHash, "packageContentHash": metadata.packageContentHash, "packageSourceJson": packageSourceJson,
            "omittedPlanningMetadata": omittedPlanningMetadata, "disclosureVersion": disclosureVersion, "disclosureHash": disclosureHash,
            "disclosureText": disclosureText, "state": "EXPLICIT_CREATOR_CONFIRMATION_REQUIRED", "packageReviewed": false]
        let preview = try WorkshopCreatorWire.decode(WorkshopCreatorPreview.self, data: JSONSerialization.data(withJSONObject: previewObject))
        textFields = preview.textFields
    }
    public func matches(preview: WorkshopCreatorPreview, now: Date = Date()) -> Bool {
        metadata.isUnexpired(now: now) && metadata.sourceTemplateId == preview.sourceTemplateId && metadata.templateHash == preview.templateHash &&
        metadata.packageContentHash == preview.packageContentHash && WorkshopCreatorWire.same(packageSourceJson, preview.packageSourceJson) &&
        Set(omittedPlanningMetadata) == Set(preview.omittedPlanningMetadata) && disclosureVersion == preview.disclosureVersion &&
        disclosureHash == preview.disclosureHash && WorkshopCreatorWire.same(disclosureText, preview.disclosureText)
    }
    public func declarationTarget(preview: WorkshopCreatorPreview, now: Date = Date()) throws -> WorkshopCreatorDeclarationTarget {
        guard matches(preview: preview, now: now), let target = UUID(uuidString: metadata.targetId) else { throw WorkshopCreatorConsentIssue.stale }
        return try WorkshopCreatorDeclarationTarget(sourceTemplateId: metadata.sourceTemplateId, moduleId: metadata.moduleId,
            versionId: metadata.versionId, offerVersion: metadata.offerVersion, termsVersion: metadata.termsVersion,
            termsDocument: termsDocument, termsDocumentHash: metadata.termsDocumentHash, expiresAt: metadata.expiresAtDate, revision: target)
    }
    public static func == (a: Self, b: Self) -> Bool {
        a.metadata == b.metadata && a.proposedOffer == b.proposedOffer && a.omittedPlanningMetadata == b.omittedPlanningMetadata &&
        zip([a.termsDocument, a.packageSourceJson, a.disclosureVersion, a.disclosureHash, a.disclosureText],
            [b.termsDocument, b.packageSourceJson, b.disclosureVersion, b.disclosureHash, b.disclosureText]).allSatisfy { WorkshopCreatorWire.same($0.0, $0.1) }
    }
}

enum WorkshopCreatorPendingWire {
    static let maximumRequest = 131_072
    static func document(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 65_536 &&
        !value.unicodeScalars.contains { scalar in (scalar.value <= 31 || (127...159).contains(scalar.value)) && ![9, 10, 13].contains(scalar.value) }
    }
    static func permission(_ value: String) -> Bool { ["ALLOWED", "PROHIBITED"].contains(value) }
    static func adaptation(_ value: String) -> Bool { ["BIND_RESOURCES_ONLY", "LOCAL_ADAPTATION"].contains(value) }
    static func csv(_ value: String) -> [String] { value.utf8.count <= 2048 ? value.components(separatedBy: ",") : [] }
    static func regions(_ values: [String]) -> Bool {
        !values.isEmpty && values.count <= 32 && Set(values).count == values.count && values.allSatisfy {
            (1...32).contains($0.utf8.count) && $0.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45 }
        }
    }
    static func buyers(_ values: [String]) -> Bool { !values.isEmpty && values.count <= 3 && Set(values).count == values.count && values.allSatisfy { ["INDIVIDUAL", "ORGANIZATION", "MERCHANT"].contains($0) } }
    static func currency(_ value: String) -> Bool { value.utf8.count == 3 && value.utf8.allSatisfy { (65...90).contains($0) } }
    static func date(_ value: String) -> Date? {
        guard let micros = instantMicros(value) else { return nil }
        return Date(timeIntervalSince1970: Double(micros) / 1_000_000)
    }
    /// Parse exact integer microseconds rather than Foundation's fractional-second rounding.
    static func instantMicros(_ value: String) -> Int64? {
        guard value.utf8.count <= 40, value.range(of: #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})\z"#, options: .regularExpression) != nil else { return nil }
        let bytes = Array(value.utf8)
        func integer(_ start: Int, _ count: Int) -> Int { Int(String(decoding: bytes[start..<(start + count)], as: UTF8.self))! }
        let year = integer(0, 4), month = integer(5, 2), day = integer(8, 2)
        let hour = integer(11, 2), minute = integer(14, 2), second = integer(17, 2)
        guard year >= 1, (1...12).contains(month), hour < 24, minute < 60, second < 60 else { return nil }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day > 0, day <= days[month - 1] else { return nil }
        var index = 19, fraction: Int64 = 0
        if bytes[index] == 46 {
            index += 1; let start = index
            while index < bytes.count, (48...57).contains(bytes[index]) { fraction = fraction * 10 + Int64(bytes[index] - 48); index += 1 }
            for _ in (index - start)..<6 { fraction *= 10 }
        }
        var offset = 0
        if bytes[index] != 90 {
            let offsetHours = integer(index + 1, 2), offsetMinutes = integer(index + 4, 2)
            guard offsetHours <= 18, offsetMinutes < 60, offsetHours < 18 || offsetMinutes == 0 else { return nil }
            offset = (offsetHours * 60 + offsetMinutes) * 60 * (bytes[index] == 45 ? -1 : 1)
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)) else { return nil }
        let whole = Int64(date.timeIntervalSince1970) - Int64(offset)
        return whole * 1_000_000 + fraction
    }
    static func appendInteger(_ value: UInt64, bytes: Int, to data: inout Data) {
        for shift in stride(from: (bytes - 1) * 8, through: 0, by: -8) { data.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
    static func append(_ value: String, to data: inout Data) { let bytes = Data(value.utf8); appendInteger(UInt64(bytes.count), bytes: 4, to: &data); data.append(bytes) }
    /// ContentDraftJSON rejects duplicate keys and malformed Unicode; the lexical pass additionally
    /// disallows floating/exponent numeric spellings that JSONDecoder may coerce to Int64.
    static func decode<T: Decodable>(_ type: T.Type, data: Data, maximum: Int = 1_048_576) throws -> T {
        guard data.count <= maximum else { throw WorkshopCreatorConsentIssue.malformed }
        var inString = false, escaped = false, number = false
        for byte in data {
            if inString { if escaped { escaped = false } else if byte == 92 { escaped = true } else if byte == 34 { inString = false } }
            else if byte == 34 { inString = true; number = false }
            else if number {
                if byte == 46 || byte == 101 || byte == 69 { throw WorkshopCreatorConsentIssue.malformed }
                if !(48...57).contains(byte) { number = false }
            } else if byte == 45 || (48...57).contains(byte) { number = true }
        }
        return try WorkshopCreatorWire.decode(type, data: data, maximum: maximum)
    }
}
