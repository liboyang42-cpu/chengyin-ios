import Foundation

/// Reform plan v9 §26–27 / W18.4 and decision M11 (purchased theme or play pack is
/// used permanently). A purchase grants persistent use of the purchased version; it
/// does not lapse with a subscription, is not resale/redistribution, and does not
/// promise every future version for free. Upgrades are an explicit, previewed choice
/// that produces a NEW local draft; installed releases and running runs keep the old
/// version. Client contract only: CompareModVersions/UpgradeInstallDraft are not
/// reviewed endpoints, so this type never sends anything.
public enum WorkshopUpgradeIssue: Error, Equatable { case invalid, sameVersion, notNewer, licenseUnknown, notCovered, unconfirmed }

/// M11 use term for a purchased version, derived only from the verified license record.
public struct WorkshopPurchasedUseTerm: Equatable, Sendable {
    public let licenseId, moduleId, purchasedVersionId: String
    /// Always true for a verified PERPETUAL_PURCHASED_VERSION record; subscriptions do not end it.
    public let survivesSubscriptionEnd: Bool
    /// Redistribution/resale is never implied by persistent use.
    public let permitsRedistribution: Bool
    public init(_ item: WorkshopPurchasedItem) throws {
        // WorkshopPurchasedItem only decodes PERPETUAL_PURCHASED_VERSION / EXACT_PURCHASED_VERSION /
        // redistribution PROHIBITED records, so persistent use is a decoded fact, not a client default.
        guard item.status != .revoked else { throw WorkshopUpgradeIssue.invalid }
        licenseId = item.licenseId; moduleId = item.moduleId; purchasedVersionId = item.purchasedVersionId
        survivesSubscriptionEnd = true; permitsRedistribution = false
    }
}

public struct WorkshopModVersionRef: Equatable, Sendable {
    public let moduleId, versionId, packageVersion, contentHash: String
    public let capabilities: Set<String>
    public init(moduleId: String, versionId: String, packageVersion: String, contentHash: String, capabilities: Set<String>) throws {
        guard ReformWire.id(moduleId), ReformWire.id(versionId), QmodManifest.strictSemver(packageVersion), ReformWire.sha256(contentHash), capabilities.count <= 32 else { throw WorkshopUpgradeIssue.invalid }
        self.moduleId = moduleId; self.versionId = versionId; self.packageVersion = packageVersion; self.contentHash = contentHash; self.capabilities = capabilities
    }
    var semver: [Int] { packageVersion.split(separator: ".").compactMap { Int($0) } }
}

/// The buyer-facing preview. Building it is safe; it changes nothing.
public struct WorkshopUpgradePreview: Equatable, Sendable {
    public enum Coverage: Equatable, Sendable { case covered, requiresNewPurchase, unknown }
    public let installed: WorkshopModVersionRef
    public let candidate: WorkshopModVersionRef
    public let addedCapabilities: Set<String>
    public let removedCapabilities: Set<String>
    /// Server fact from the license check; unknown blocks the upgrade.
    public let coverage: Coverage
    /// Running runs and published releases always keep the installed version.
    public var pinsExistingRuns: Bool { true }
    /// New capabilities need the theme to go back through review before publication.
    public var requiresReview: Bool { true }

    public init(installed: WorkshopModVersionRef, candidate: WorkshopModVersionRef, coverage: Coverage) throws {
        guard installed.moduleId == candidate.moduleId else { throw WorkshopUpgradeIssue.invalid }
        guard installed.versionId != candidate.versionId, installed.contentHash != candidate.contentHash else { throw WorkshopUpgradeIssue.sameVersion }
        guard installed.semver.lexicographicallyPrecedes(candidate.semver) else { throw WorkshopUpgradeIssue.notNewer }
        self.installed = installed; self.candidate = candidate; self.coverage = coverage
        addedCapabilities = candidate.capabilities.subtracting(installed.capabilities)
        removedCapabilities = installed.capabilities.subtracting(candidate.capabilities)
    }
}

/// The explicit decision. Only a confirmed, covered preview yields an upgrade-draft request.
public struct WorkshopUpgradeDraftRequest: Equatable, Sendable {
    public let licenseId, fromVersionId, toVersionId, toContentHash, requestId: String
    public init(term: WorkshopPurchasedUseTerm, preview: WorkshopUpgradePreview, confirmedByBuyer: Bool, requestId: String = UUID().uuidString) throws {
        guard confirmedByBuyer else { throw WorkshopUpgradeIssue.unconfirmed }
        guard term.moduleId == preview.installed.moduleId, term.purchasedVersionId == preview.installed.versionId, ReformWire.requestID(requestId) else { throw WorkshopUpgradeIssue.invalid }
        switch preview.coverage {
        case .covered: break
        case .requiresNewPurchase: throw WorkshopUpgradeIssue.notCovered
        case .unknown: throw WorkshopUpgradeIssue.licenseUnknown
        }
        licenseId = term.licenseId; fromVersionId = preview.installed.versionId; toVersionId = preview.candidate.versionId
        toContentHash = preview.candidate.contentHash; self.requestId = requestId
    }
}
