import Foundation

/// Imports one metadata manifest. Answers are rejected before preview.
/// qmod, binaries, and the missing original texts stay closed. The request id is not replaced.
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

    public mutating func importQmod(entry: String, originalRequestID: String) -> WorkshopModuleImportFailure {
        do {
            try gate.importFromNormalEntry(entry: entry, format: .unknownQmod, originalRequestID: originalRequestID)
            return .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal)
        } catch let error as WorkshopModuleImportFailure {
            return error
        } catch {
            return .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal)
        }
    }
}
