import Foundation

/// Imports one metadata manifest or a questify.mod manifest.
/// Answers and authority fields are rejected before preview.
/// A nameless blob still has no archive bytes. The request id is not replaced.
public struct WorkshopModuleImportEntry: Equatable {
    public private(set) var gate = WorkshopModuleImportGate()
    public init() {}

    public mutating func importMetadata(_ object: [String: String], entry: String, originalRequestID: String) throws {
        try WorkshopModuleImportGate.inspect(object)
        if gate.originalRequestID == originalRequestID, gate.entry == entry { return }
        try gate.importFromNormalEntry(entry: entry, format: .metadataManifestV1, originalRequestID: originalRequestID)
        try gate.validate(object)
        try gate.previewMetadataOnly()
        try gate.markReviewPending()
    }

    /// Parses the supplied manifest. It does not open a zip or keep file bytes.
    public mutating func importQmodManifest(_ object: [String: String], entry: String, originalRequestID: String) throws {
        try WorkshopModuleImportGate.inspect(object)
        let forbidden = ["reviewed", "approved", "ownerRole", "rewardBudget"]
        guard !forbidden.contains(where: { object[$0] != nil }),
              object["formatVersion"] == "1.0", object["kind"] == "questify.mod",
              object["entrypoint"] == "content.json",
              let packageID = object["packageId"], packageID == entry,
              let version = object["packageVersion"], Self.semver(version),
              let hash = object["contentHash"], WorkshopModuleImportGate.sha256Hex(hash),
              let schema = object["schemaVersion"],
              let path = object["filePath"], path == "content.json",
              !path.contains(".."), !path.contains("\\"), !path.contains("://"),
              let digest = object["fileSha256"], WorkshopModuleImportGate.sha256Hex(digest),
              let bytes = object["fileBytes"], let count = Int(bytes), count > 0 else {
            throw WorkshopModuleImportFailure.invalidManifest
        }
        try importMetadata(["id": packageID, "version": version, "contentHash": hash, "schemaVersion": schema],
                           entry: entry, originalRequestID: originalRequestID)
    }

    public mutating func importQmod(entry: String, originalRequestID: String) -> WorkshopModuleImportFailure {
        do {
            try gate.importFromNormalEntry(entry: entry, format: .unknownQmod, originalRequestID: originalRequestID)
            return .waitingSource(capability: WorkshopModuleSourceInventory.qmodCandidateBinaries)
        } catch let error as WorkshopModuleImportFailure {
            if case .waitingSource(let capability) = error, capability == WorkshopModuleSourceInventory.qmodOriginal {
                return .waitingSource(capability: WorkshopModuleSourceInventory.qmodCandidateBinaries)
            }
            return error
        } catch {
            return .waitingSource(capability: WorkshopModuleSourceInventory.qmodCandidateBinaries)
        }
    }

    private static func semver(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber) && !(part.count > 1 && part.hasPrefix("0"))
        }
    }
}
