#if DEBUG
import Foundation

/// Synthetic local fixture bytes only. No production registration, default grant, network or rights.
/// Fixture transports must retain one createdAt per command so retries/readbacks are immutable.
@MainActor enum WorkshopCreatorPendingFixtureData {
    static func timestamp(_ date: Date) -> String {
        let seconds = floor(date.timeIntervalSince1970)
        let fraction = min(999_999, max(0, Int((date.timeIntervalSince1970 - seconds) * 1_000_000)))
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let whole = formatter.string(from: Date(timeIntervalSince1970: seconds))
        return String(whole.dropLast()) + String(format: ".%06dZ", fraction)
    }
    static func envelope(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 200, "data": value], options: [.sortedKeys])
    }
    static func preview(sourceTemplateId: Int64 = 901) throws -> [String: Any] {
        guard sourceTemplateId > 0 else { throw WorkshopCreatorConsentIssue.invalid }
        let package = #"{"schema":"w18-member-text-v1","title":"Synthetic creator original","description":"合成原创文本","merchantGuide":"Synthetic guide, unchanged.\nSecond line.","bindings":{}}"#
        return ["schema": "w18-creator-public-use-preview-v1", "sourceTemplateId": sourceTemplateId,
            "templateHash": WorkshopCreatorWire.sha(Data("fixture-template:\(sourceTemplateId):\(package)".utf8)),
            "packageContentHash": WorkshopCreatorWire.sha(Data(package.utf8)), "packageSourceJson": package,
            "omittedPlanningMetadata": ["categoryId", "players"], "disclosureVersion": WorkshopCreatorDisclosure.version,
            "disclosureHash": WorkshopCreatorDisclosure.hash, "disclosureText": WorkshopCreatorDisclosure.text,
            "state": "EXPLICIT_CREATOR_CONFIRMATION_REQUIRED", "packageReviewed": false]
    }
    static func metadata(_ command: WorkshopCreatorPendingCommand, createdAt: Date = Date()) throws -> [String: Any] {
        let id = targetId(command), revision = WorkshopCreatorWire.sha(try command.data()), created = timestamp(createdAt)
        let result: [String: Any] = ["schema": "w18-creator-pending-package-v1", "targetId": id, "revision": revision,
            "sourceTemplateId": command.sourceTemplateId, "templateHash": command.expectedTemplateHash,
            "packageContentHash": command.expectedPackageContentHash, "moduleId": "member-template:\(command.sourceTemplateId)",
            "versionId": "creator-package:\(id):\(revision)", "offerVersion": "creator-offer:\(id):\(revision)",
            "termsVersion": "creator-terms:\(id)", "termsDocumentHash": command.termsDocumentHash,
            "expiresAt": command.expiresAt, "createdAt": created, "state": "UNREVIEWED_AUTHOR_PROPOSAL",
            "packageReviewed": false, "listed": false, "licenseIssued": false, "copyrightOwnership": "RETAINED_BY_CREATOR"]
        _ = try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingMetadata.self, data: JSONSerialization.data(withJSONObject: result))
        return result
    }
    static func detail(_ command: WorkshopCreatorPendingCommand, owner: Int64 = 7, createdAt: Date = Date()) throws -> [String: Any] {
        guard owner > 0 else { throw WorkshopCreatorConsentIssue.invalid }
        var value = try metadata(command, createdAt: createdAt)
        let preview = try self.preview(sourceTemplateId: command.sourceTemplateId)
        guard preview["templateHash"] as? String == command.expectedTemplateHash,
              preview["packageContentHash"] as? String == command.expectedPackageContentHash else { throw WorkshopCreatorConsentIssue.invalid }
        let id = targetId(command), revision = WorkshopCreatorWire.sha(try command.data())
        value["termsDocument"] = command.termsDocument
        for field in ["packageSourceJson", "omittedPlanningMetadata", "disclosureVersion", "disclosureHash", "disclosureText"] { value[field] = preview[field] }
        value["proposedOffer"] = ["offerId": "creator-offer:\(command.requestId)", "offerVersion": "creator-offer:\(id):\(revision)",
            "moduleId": "member-template:\(command.sourceTemplateId)", "seller": ["kind": "INDIVIDUAL", "entityId": owner] as [String: Any],
            "buyerKinds": WorkshopCreatorPendingWire.csv(command.buyerKinds), "acquisition": "PAID", "priceMinor": command.priceMinor,
            "currency": command.currency, "terms": terms(command)] as [String: Any]
        _ = try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingDetail.self, data: JSONSerialization.data(withJSONObject: value))
        return value
    }
    static func page(sourceTemplateId: Int64 = 901, items: [[String: Any]], hasMore: Bool = false, nextCursor: String? = nil) throws -> [String: Any] {
        let sorted = items.sorted { left, right in
            let leftId = (left["targetId"] as? String) ?? ""
            let rightId = (right["targetId"] as? String) ?? ""
            return leftId < rightId
        }
        let result: [String: Any] = ["schema": "w18-creator-pending-package-list-v1", "sourceTemplateId": sourceTemplateId,
            "items": sorted, "hasMore": hasMore, "nextCursor": nextCursor.map { $0 as Any } ?? NSNull()]
        _ = try WorkshopCreatorPendingWire.decode(WorkshopCreatorPendingPage.self, data: JSONSerialization.data(withJSONObject: result))
        return result
    }
    private static func targetId(_ command: WorkshopCreatorPendingCommand) -> String {
        let hex = Array(WorkshopCreatorWire.sha(Data("fixture-target:\(command.requestId)".utf8)).prefix(32))
        return String(hex[0..<8]) + "-" + String(hex[8..<12]) + "-4" + String(hex[13..<16]) + "-8" + String(hex[17..<20]) + "-" + String(hex[20..<32])
    }
    private static func terms(_ command: WorkshopCreatorPendingCommand) -> [String: Any] {
        let id = targetId(command), regions = WorkshopCreatorPendingWire.csv(command.allowedRegions)
        let fields = ["W18-license-terms-snapshot-v2", command.useDuration, "creator-terms:\(id)", command.termsDocumentHash,
            "creator-pending:\(command.requestId)", command.commercialUse, command.adaptation, command.translation, command.updates, command.redistribution]
        var bytes = Data()
        for field in fields { WorkshopCreatorPendingWire.append(field, to: &bytes) }
        WorkshopCreatorPendingWire.appendInteger(UInt64(regions.count), bytes: 4, to: &bytes)
        for region in regions.sorted() { WorkshopCreatorPendingWire.append(region, to: &bytes) }
        for limit in [command.themeLimit, command.merchantLimit, command.runLimit] {
            bytes.append(limit == -1 ? 1 : 0); WorkshopCreatorPendingWire.appendInteger(UInt64(max(0, limit)), bytes: 8, to: &bytes)
        }
        func limit(_ value: Int64) -> [String: Any] { ["unlimited": value == -1, "maximum": max(0, value)] }
        return ["useDuration": command.useDuration, "termsVersion": "creator-terms:\(id)", "termsHash": WorkshopCreatorWire.sha(bytes),
            "termsDocumentHash": command.termsDocumentHash, "termsDocumentReference": "creator-pending:\(command.requestId)",
            "commercialUse": command.commercialUse, "adaptation": command.adaptation, "translation": command.translation,
            "updates": command.updates, "redistribution": command.redistribution, "allowedRegions": regions,
            "themeLimit": limit(command.themeLimit), "merchantLimit": limit(command.merchantLimit), "runLimit": limit(command.runLimit)]
    }
}
#endif
