import Foundation

/// Minimal restore-response schema. Historical receipt metadata is never a licence or capability.
/// Decodable-only by design: this transient read response must not enter a mutation or journal hash.
public struct InstalledDraftModules: Decodable, Equatable {
    public enum Availability: String, Decodable { case historical = "HISTORICAL_RECEIPTS_ONLY", notEnabled = "NOT_ENABLED", ownerOnly = "OWNER_ONLY" }
    public enum Binding: String, Decodable { case exact = "EXACT_REVISION", stale = "STALE_BINDING", unverifiable = "BINDING_UNVERIFIABLE" }
    public struct Receipt: Decodable, Equatable {
        public let installationId: Int64
        public let targetDraftId: Int64
        public let installedTargetVersion: Int64
        public let installedAt: String
        public let versionId: String
        public let contentHash: String
        public let termsHash: String
        public let installedTargetPayloadHash: String?
        public let binding: Binding
        private enum CodingKeys: String, CodingKey {
            case installationId, targetDraftId, installedTargetVersion, installedAt, versionId
            case contentHash, termsHash, installedTargetPayloadHash, binding, evidenceKind
        }
        public init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            installationId = try box.decode(Int64.self, forKey: .installationId)
            targetDraftId = try box.decode(Int64.self, forKey: .targetDraftId)
            installedTargetVersion = try box.decode(Int64.self, forKey: .installedTargetVersion)
            installedAt = try box.decode(String.self, forKey: .installedAt)
            versionId = try box.decode(String.self, forKey: .versionId)
            contentHash = try box.decode(String.self, forKey: .contentHash)
            termsHash = try box.decode(String.self, forKey: .termsHash)
            installedTargetPayloadHash = try box.decodeIfPresent(String.self, forKey: .installedTargetPayloadHash)
            binding = try box.decode(Binding.self, forKey: .binding)
            guard installationId > 0, targetDraftId > 0, installedTargetVersion > 0,
                  box.contains(.installedTargetPayloadHash),
                  !versionId.isEmpty, versionId.utf16.count <= 512,
                  Self.validHash(contentHash), Self.validHash(termsHash),
                  installedAt.utf8.count <= 40,
                  installedAt.range(of: #"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?Z\z"#, options: .regularExpression) != nil,
                  try box.decode(String.self, forKey: .evidenceKind) == "HISTORICAL_INSTALLATION" else {
                throw ContentDraftIssue.malformed
            }
            if binding == .unverifiable {
                guard installedTargetPayloadHash == nil else { throw ContentDraftIssue.malformed }
            } else {
                guard let hash = installedTargetPayloadHash, Self.validHash(hash) else { throw ContentDraftIssue.malformed }
            }
        }
        private static func validHash(_ value: String) -> Bool {
            value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }
    public let availability: Availability
    public let receipts: [Receipt]
    public let hasMore: Bool
    private enum CodingKeys: String, CodingKey {
        case availability, receipts, hasMore, contentUseStatus, textPreviewAllowed, editingAllowed
        case exportAllowed, publicationAllowed, executionAllowed, commercialUseAllowed
    }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        availability = try box.decode(Availability.self, forKey: .availability)
        hasMore = try box.decode(Bool.self, forKey: .hasMore)
        guard try box.decode(String.self, forKey: .contentUseStatus) == "POST_INSTALL_POLICY_UNAVAILABLE" else { throw ContentDraftIssue.malformed }
        for flag in [CodingKeys.textPreviewAllowed, .editingAllowed, .exportAllowed, .publicationAllowed, .executionAllowed, .commercialUseAllowed] {
            guard try box.decode(Bool.self, forKey: flag) == false else { throw ContentDraftIssue.malformed }
        }
        var values = try box.nestedUnkeyedContainer(forKey: .receipts)
        var decoded: [Receipt] = [], seen = Set<Int64>()
        while !values.isAtEnd {
            guard decoded.count < 50 else { throw ContentDraftIssue.malformed }
            let receipt = try values.decode(Receipt.self)
            guard seen.insert(receipt.installationId).inserted else { throw ContentDraftIssue.malformed }
            decoded.append(receipt)
        }
        guard !hasMore || decoded.count == 50,
              availability == .historical || (decoded.isEmpty && !hasMore) else { throw ContentDraftIssue.malformed }
        receipts = decoded
    }
    func matches(_ record: ContentDraftRecord) -> Bool {
        receipts.allSatisfy { receipt in
            guard receipt.targetDraftId == record.id else { return false }
            let exact = receipt.installedTargetVersion == record.version && receipt.installedTargetPayloadHash == record.payloadHash
            switch receipt.binding {
            case .exact: return exact
            case .stale: return !exact
            case .unverifiable: return receipt.installedTargetPayloadHash == nil
            }
        }
    }
}

/// UI receives only an inert subset. It cannot see payloads, module identity, hashes, rights or source fields.
public struct OwnerDraftInstalledReceipts: Equatable {
    public enum State: String { case omitted, invalid, notEnabled, ownerOnly, historical }
    public struct Row: Equatable, Identifiable {
        public let id: Int64
        public let draftVersion: Int64
        public let installedTime: String
        public let binding: InstalledDraftModules.Binding
    }
    public let state: State
    public let rows: [Row]
    public let hasMore: Bool
    init(record: ContentDraftRecord) {
        guard let modules = record.installedModules else {
            state = record.installedModulesInvalid ? .invalid : .omitted; rows = []; hasMore = false; return
        }
        guard modules.matches(record) else { state = .invalid; rows = []; hasMore = false; return }
        switch modules.availability {
        case .historical: state = .historical
        case .notEnabled: state = .notEnabled
        case .ownerOnly: state = .ownerOnly
        }
        rows = modules.receipts.map { .init(id: $0.installationId, draftVersion: $0.installedTargetVersion, installedTime: $0.installedAt, binding: $0.binding) }
        hasMore = modules.hasMore
    }
}
