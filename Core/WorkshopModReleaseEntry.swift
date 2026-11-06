import Foundation

/// Parsed questify.mod manifest, then an external review, then one install.
/// The author's declaration is not a release. A licence is not copyright or a publish right.
/// The zip is not opened.
public struct WorkshopModReleaseEntry: Equatable {
    public private(set) var imports = WorkshopModuleImportEntry()
    public private(set) var freezeEntry = WorkshopPackageFreezeEntry()
    public private(set) var journey = WorkshopInstallJourneyEntry()
    public private(set) var released = false
    public let ownsCopyright = false
    public let publishRight = false

    public init() {}

    public mutating func submitManifest(_ object: [String: String], entry: String, originalRequestID: String) throws {
        try imports.importQmodManifest(object, entry: entry, originalRequestID: originalRequestID)
        released = false
    }

    public mutating func release(termsHash: String, reviewed: Bool) throws {
        guard imports.gate.phase == .reviewPending, let manifest = imports.gate.manifest,
              let requestID = imports.gate.originalRequestID else {
            throw WorkshopPackagePublishFailure.notReviewed
        }
        try freezeEntry.freeze(contentHash: manifest.contentHash, termsHash: termsHash,
                               versionLabel: manifest.version, originalRequestID: requestID, reviewed: reviewed)
        released = true
    }

    public mutating func install() throws {
        guard released, let manifest = imports.gate.manifest, let requestID = imports.gate.originalRequestID else {
            throw WorkshopInstallFailure.invalidGrant
        }
        try journey.hold(originalRequestID: requestID, versionLabel: manifest.version)
        try journey.install(originalRequestID: requestID)
    }

    public mutating func installAgain() throws {
        guard let requestID = imports.gate.originalRequestID else { throw WorkshopInstallFailure.invalidGrant }
        try journey.install(originalRequestID: requestID)
    }
}
