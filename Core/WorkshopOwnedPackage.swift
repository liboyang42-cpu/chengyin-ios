import Foundation

/// Proposed immutable-metadata read. Frozen terms are display data, never operation capabilities.
public struct WorkshopOwnedPackage: Decodable, Equatable {
    public enum Availability: String, Decodable { case metadataOnly = "PACKAGE_METADATA_ONLY", notEnabled = "NOT_ENABLED", unavailable = "UNAVAILABLE" }
    public struct Limit: Decodable, Equatable {
        public let unlimited: Bool
        public let maximum: Int64
        private enum CodingKeys: String, CodingKey { case unlimited, maximum }
        public init(from decoder: Decoder) throws {
            try WorkshopOwnedWire.exactKeys(decoder, ["unlimited", "maximum"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            unlimited = try c.decode(Bool.self, forKey: .unlimited); maximum = try c.decode(Int64.self, forKey: .maximum)
            guard maximum >= 0, !unlimited || maximum == 0 else { throw WorkshopOwnedIssue.malformed }
        }
    }
    public struct Metadata: Decodable, Equatable {
        public enum Permission: String, Decodable { case allowed = "ALLOWED", prohibited = "PROHIBITED" }
        public enum Adaptation: String, Decodable { case bindResourcesOnly = "BIND_RESOURCES_ONLY", localAdaptation = "LOCAL_ADAPTATION" }
        public let versionLabel: String
        public let validUntil: String
        public let schemaVersion: Int
        public let contentHash: String
        public let termsVersion: String
        public let termsHash: String
        public let commercialUse: Permission
        public let adaptation: Adaptation
        public let translation: Permission
        public let allowedRegions: [String]
        public let themeLimit: Limit
        public let merchantLimit: Limit
        public let runLimit: Limit
        public let requiredBindingCount: Int
        private enum CodingKeys: String, CodingKey {
            case versionLabel, validUntil, schemaVersion, contentHash, termsVersion, termsHash, commercialUse, adaptation, translation
            case updates, redistribution, allowedRegions, themeLimit, merchantLimit, runLimit, requiredBindingCount
        }
        public init(from decoder: Decoder) throws {
            try WorkshopOwnedWire.exactKeys(decoder, ["versionLabel", "validUntil", "schemaVersion", "contentHash", "termsVersion", "termsHash", "commercialUse", "adaptation", "translation", "updates", "redistribution", "allowedRegions", "themeLimit", "merchantLimit", "runLimit", "requiredBindingCount"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            versionLabel = try c.decode(String.self, forKey: .versionLabel); validUntil = try c.decode(String.self, forKey: .validUntil)
            schemaVersion = try c.decode(Int.self, forKey: .schemaVersion); contentHash = try c.decode(String.self, forKey: .contentHash)
            termsVersion = try c.decode(String.self, forKey: .termsVersion); termsHash = try c.decode(String.self, forKey: .termsHash)
            commercialUse = try c.decode(Permission.self, forKey: .commercialUse); adaptation = try c.decode(Adaptation.self, forKey: .adaptation)
            translation = try c.decode(Permission.self, forKey: .translation)
            themeLimit = try c.decode(Limit.self, forKey: .themeLimit); merchantLimit = try c.decode(Limit.self, forKey: .merchantLimit); runLimit = try c.decode(Limit.self, forKey: .runLimit)
            requiredBindingCount = try c.decode(Int.self, forKey: .requiredBindingCount)
            guard Self.text(versionLabel), Self.text(termsVersion), WorkshopOwnedWire.timestamp(validUntil), schemaVersion == 1,
                  Self.hash(contentHash), Self.hash(termsHash), (0...64).contains(requiredBindingCount),
                  try c.decode(String.self, forKey: .updates) == "EXACT_PURCHASED_VERSION", try c.decode(String.self, forKey: .redistribution) == "PROHIBITED" else { throw WorkshopOwnedIssue.malformed }
            var values = try c.nestedUnkeyedContainer(forKey: .allowedRegions)
            var regions: [String] = [], seen = Set<String>()
            while !values.isAtEnd {
                guard regions.count < 64 else { throw WorkshopOwnedIssue.malformed }
                let region = try values.decode(String.self)
                guard Self.text(region), seen.insert(region).inserted else { throw WorkshopOwnedIssue.malformed }
                regions.append(region)
            }
            guard !regions.isEmpty else { throw WorkshopOwnedIssue.malformed }; allowedRegions = regions
        }
        private static func hash(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
        private static func text(_ value: String) -> Bool {
            !value.isEmpty && value.utf16.count <= 128 && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
                && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format }
        }
    }
    public let claimId: String
    public let checkedAt: String
    public let availability: Availability
    public let packageInfo: Metadata?
    private enum CodingKeys: String, CodingKey { case schema, scope, claimId, checkedAt, availability, purchasedLibraryStatus, contentUseStatus, manifestStatus, editorStatus, packageInfo }
    public init(from decoder: Decoder) throws {
        try WorkshopOwnedWire.exactKeys(decoder, ["schema", "scope", "claimId", "checkedAt", "availability", "purchasedLibraryStatus", "contentUseStatus", "manifestStatus", "editorStatus", "packageInfo"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claimId = try c.decode(String.self, forKey: .claimId); checkedAt = try c.decode(String.self, forKey: .checkedAt)
        availability = try c.decode(Availability.self, forKey: .availability); packageInfo = try c.decodeIfPresent(Metadata.self, forKey: .packageInfo)
        guard WorkshopOwnedWire.identifier(claimId), WorkshopOwnedWire.timestamp(checkedAt), (availability == .metadataOnly) == (packageInfo != nil),
              try c.decode(String.self, forKey: .schema) == "workshop-package-v1", try c.decode(String.self, forKey: .scope) == "FREE_INDIVIDUAL_ONLY",
              try c.decode(String.self, forKey: .purchasedLibraryStatus) == "NOT_AVAILABLE", try c.decode(String.self, forKey: .contentUseStatus) == "UNAVAILABLE",
              try c.decode(String.self, forKey: .manifestStatus) == "NOT_AVAILABLE", try c.decode(String.self, forKey: .editorStatus) == "POST_INSTALL_POLICY_UNAVAILABLE" else { throw WorkshopOwnedIssue.malformed }
    }
}
