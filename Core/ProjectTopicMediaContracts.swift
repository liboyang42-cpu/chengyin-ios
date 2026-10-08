import Foundation
import CryptoKit

/// Local selection constraints only. None of these types grants an upload, ownership,
/// moderation, topic-edit, or publication capability.
public enum ProjectTopicMediaKind: String, Codable, Equatable, Hashable { case image, video }
public enum ProjectTopicMediaFailure: Error, Equatable {
    case policyUnavailable, invalidPolicy, contextUnavailable, changedContext, changedPolicy
    case invalidReference, noSelection, tooManyItems, mixedKinds, unsupportedType
    case byteLimit, dimensionLimit, durationLimit, inspectionUnavailable, invalidInspection
    case changedSource, invalidRecord
}

public struct ProjectTopicMediaPolicy: Equatable {
    public enum Mixing: Equatable { case singleKind, mixed }
    public struct KindLimit: Equatable {
        public let kind: ProjectTopicMediaKind
        public let mimeTypes: Set<String>
        public let maximumBytes, maximumWidth, maximumHeight, maximumPixels: UInt64
        public let maximumDurationMilliseconds: UInt64?
        public init(kind: ProjectTopicMediaKind, mimeTypes: Set<String>, maximumBytes: UInt64,
                    maximumWidth: UInt64, maximumHeight: UInt64, maximumPixels: UInt64,
                    maximumDurationMilliseconds: UInt64?) throws {
            guard !mimeTypes.isEmpty, mimeTypes.allSatisfy({ ProjectTopicMediaPolicy.validMIME($0, kind: kind) }),
                  maximumBytes > 0, maximumWidth > 0, maximumHeight > 0, maximumPixels > 0,
                  kind == .image ? maximumDurationMilliseconds == nil : (maximumDurationMilliseconds ?? 0) > 0 else {
                throw ProjectTopicMediaFailure.invalidPolicy
            }
            self.kind = kind; self.mimeTypes = mimeTypes; self.maximumBytes = maximumBytes
            self.maximumWidth = maximumWidth; self.maximumHeight = maximumHeight; self.maximumPixels = maximumPixels
            self.maximumDurationMilliseconds = maximumDurationMilliseconds
        }
    }
    public let id: UUID
    public let revision: UInt64
    public let maximumItems, maximumTotalBytes: UInt64
    public let mixing: Mixing
    public let kinds: [KindLimit]
    /// Every business limit must be supplied. There is no image/video policy fallback.
    public init(id: UUID, revision: UInt64, maximumItems: UInt64, maximumTotalBytes: UInt64,
                mixing: Mixing, kinds: [KindLimit]) throws {
        guard maximumItems > 0, maximumTotalBytes > 0, !kinds.isEmpty,
              Set(kinds.map(\.kind)).count == kinds.count else { throw ProjectTopicMediaFailure.invalidPolicy }
        self.id = id; self.revision = revision; self.maximumItems = maximumItems
        self.maximumTotalBytes = maximumTotalBytes; self.mixing = mixing; self.kinds = kinds
    }
    func limit(_ kind: ProjectTopicMediaKind) -> KindLimit? { kinds.first { $0.kind == kind } }
    var inspectionByteCeiling: UInt64 { min(maximumTotalBytes, kinds.map(\.maximumBytes).max() ?? 0) }
    static func validMIME(_ value: String, kind: ProjectTopicMediaKind) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == kind.rawValue, !parts[1].isEmpty else { return false }
        return parts[1].utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || [43, 45, 46].contains($0) }
    }
    func validate(_ item: ProjectTopicMediaFacts) throws {
        guard let rule = limit(item.kind), rule.mimeTypes.contains(item.mimeType) else { throw ProjectTopicMediaFailure.unsupportedType }
        guard item.byteCount > 0, item.byteCount <= rule.maximumBytes, item.byteCount <= maximumTotalBytes else { throw ProjectTopicMediaFailure.byteLimit }
        guard item.width > 0, item.height > 0, item.width <= rule.maximumWidth, item.height <= rule.maximumHeight,
              item.width <= rule.maximumPixels / item.height else { throw ProjectTopicMediaFailure.dimensionLimit }
        switch item.kind {
        case .image: guard item.durationMilliseconds == nil else { throw ProjectTopicMediaFailure.durationLimit }
        case .video:
            guard let duration = item.durationMilliseconds, let limit = rule.maximumDurationMilliseconds,
                  duration > 0, duration <= limit else { throw ProjectTopicMediaFailure.durationLimit }
        }
        guard ProjectTopicMediaFacts.validDigest(item.contentSHA256) else { throw ProjectTopicMediaFailure.invalidInspection }
    }
    func validate(_ items: [ProjectTopicMediaFacts]) throws {
        guard !items.isEmpty else { throw ProjectTopicMediaFailure.noSelection }
        guard UInt64(items.count) <= maximumItems else { throw ProjectTopicMediaFailure.tooManyItems }
        guard Set(items.map { $0.reference.id }).count == items.count else { throw ProjectTopicMediaFailure.invalidReference }
        if mixing == .singleKind, Set(items.map(\.kind)).count != 1 { throw ProjectTopicMediaFailure.mixedKinds }
        var total: UInt64 = 0
        for item in items {
            try validate(item)
            guard item.byteCount <= maximumTotalBytes - total else { throw ProjectTopicMediaFailure.byteLimit }
            total += item.byteCount
        }
    }
}

public struct ProjectTopicMediaContext: Equatable {
    public let session: ProjectEditSession
    public let identity: ProjectEditDraftIdentity
    public let product: ProjectEditProduct
    public let owner: ProjectEditOwner
    public let publishMode: String
    public let editScope: ProjectEditScope
    public let draftRevision: UInt64
    public let visit: UUID
    public init(session: ProjectEditSession, identity: ProjectEditDraftIdentity, product: ProjectEditProduct,
                owner: ProjectEditOwner, publishMode: String, editScope: ProjectEditScope,
                draftRevision: UInt64, visit: UUID) throws {
        guard Self.validIdentity(identity), publishMode == "pro", editScope == .full else { throw ProjectTopicMediaFailure.contextUnavailable }
        self.session = session; self.identity = identity; self.product = product; self.owner = owner
        self.publishMode = publishMode; self.editScope = editScope; self.draftRevision = draftRevision; self.visit = visit
    }
    static func validIdentity(_ value: ProjectEditDraftIdentity) -> Bool {
        if let topic = value.topicID { return topic > 0 && value.draftUUID == nil }
        return value.draftUUID.flatMap(UUID.init(uuidString:)) != nil
    }
    static func sameIdentity(_ a: ProjectEditDraftIdentity, _ b: ProjectEditDraftIdentity) -> Bool {
        guard a.topicID == b.topicID else { return false }
        switch (a.draftUUID, b.draftUUID) {
        case (nil, nil): return true
        case (.some(let left), .some(let right)): return left.utf8.elementsEqual(right.utf8)
        default: return false
        }
    }
    public static func == (a: Self, b: Self) -> Bool {
        a.session.accountID == b.session.accountID && a.session.epoch == b.session.epoch &&
        a.session.viewerRevision == b.session.viewerRevision && a.session.configurationRevision == b.session.configurationRevision &&
        a.session.storageNamespace.utf8.elementsEqual(b.session.storageNamespace.utf8) &&
        sameIdentity(a.identity, b.identity) && a.product == b.product && a.owner == b.owner &&
        a.publishMode == b.publishMode && a.editScope == b.editScope && a.draftRevision == b.draftRevision && a.visit == b.visit
    }
}

/// An opaque app-managed reference. It contains neither a path nor a network URL.
/// Picker filenames, extensions and claimed dimensions are not inspection evidence.
public struct ProjectTopicMediaLocalReference: Codable, Equatable, Hashable {
    public let id: UUID
    public let revision: UUID
    public init(id: UUID, revision: UUID) { self.id = id; self.revision = revision }
}

/// Historical/display facts are serializable; decoding them does NOT verify any file.
public struct ProjectTopicMediaFacts: Codable, Equatable {
    public let reference: ProjectTopicMediaLocalReference
    public let kind: ProjectTopicMediaKind
    public let mimeType: String
    public let byteCount, width, height: UInt64
    public let durationMilliseconds: UInt64?
    public let contentSHA256: String
    static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

public struct ProjectTopicMediaInspectionRequest: Equatable {
    public let id: UUID
    public let ticketID: UUID
    public let context: ProjectTopicMediaContext
    public let reference: ProjectTopicMediaLocalReference
    public let policy: ProjectTopicMediaPolicy
    let budget: ProjectTopicMediaInspectionBudget
    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.ticketID == b.ticketID && a.context == b.context &&
        a.reference == b.reference && a.policy == b.policy && a.budget === b.budget
    }
}

/// One ticket owns one aggregate read budget. A rejected chunk permanently poisons
/// this budget, even if a broken inspector catches the consumer's thrown error.
final class ProjectTopicMediaInspectionBudget {
    private let lock = NSLock()
    private let maximum: UInt64
    private var count: UInt64 = 0
    private var started: Set<UUID> = []
    private var failure: ProjectTopicMediaFailure?
    init(maximum: UInt64) { self.maximum = maximum }
    func begin(_ request: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        guard started.insert(request).inserted else { failure = .invalidInspection; throw ProjectTopicMediaFailure.invalidInspection }
    }
    func consume(_ size: UInt64) throws {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        guard size > 0, count <= maximum, size <= maximum - count else {
            failure = .byteLimit; throw ProjectTopicMediaFailure.byteLimit
        }
        count += size
    }
    func invalidate(_ reason: ProjectTopicMediaFailure) { lock.lock(); defer { lock.unlock() }; if failure == nil { failure = reason } }
    func check() throws { lock.lock(); defer { lock.unlock() }; if let failure { throw failure } }
}

/// These assertions belong to a trusted, independently tested native inspector,
/// never to the picker or imported JSON. Core independently hashes/counts its byte stream.
public struct ProjectTopicMediaInspectionReport {
    public enum Check: Hashable {
        case regularAppManagedFile, containerRecognized, metadataDecoded
        case imageDecoded, videoTrackInspected, durationMeasured
    }
    public let requestID: UUID
    public let reference: ProjectTopicMediaLocalReference
    public let kind: ProjectTopicMediaKind
    public let mimeType: String
    public let byteCount, width, height: UInt64
    public let durationMilliseconds: UInt64?
    public let decodedContentSHA256: String
    public let checks: Set<Check>
    public init(requestID: UUID, reference: ProjectTopicMediaLocalReference, kind: ProjectTopicMediaKind,
                mimeType: String, byteCount: UInt64, width: UInt64, height: UInt64,
                durationMilliseconds: UInt64?, decodedContentSHA256: String, checks: Set<Check>) {
        self.requestID = requestID; self.reference = reference; self.kind = kind; self.mimeType = mimeType
        self.byteCount = byteCount; self.width = width; self.height = height; self.durationMilliseconds = durationMilliseconds
        self.decodedContentSHA256 = decodedContentSHA256; self.checks = checks
    }
}

public protocol ProjectTopicMediaInspecting {
    /// Open only this request's app-managed, owner-scoped regular file. Enforce the
    /// supplied ceiling before allocation and on every read. Stream its complete
    /// original bytes; inspect the same stable bytes using real image/container/track
    /// APIs; return their matching digest. Do not fetch URLs or trust picker metadata.
    /// No production implementation exists in this pure Core increment.
    func inspect(_ request: ProjectTopicMediaInspectionRequest,
                 consume: (Data) throws -> Void) throws -> ProjectTopicMediaInspectionReport
}

/// Not Codable and no public initializer: a decoded historical descriptor cannot
/// be supplied to finishInspection as fresh evidence. This is still local evidence,
/// dependent on the inspector contract, never server ownership or moderation proof.
public struct ProjectTopicMediaInspectionEvidence {
    public let request: ProjectTopicMediaInspectionRequest
    public let facts: ProjectTopicMediaFacts
    private init(request: ProjectTopicMediaInspectionRequest, facts: ProjectTopicMediaFacts) { self.request = request; self.facts = facts }
    public static func inspect(_ request: ProjectTopicMediaInspectionRequest,
                               using inspector: (any ProjectTopicMediaInspecting)?) throws -> Self {
        guard let inspector else { throw ProjectTopicMediaFailure.inspectionUnavailable }
        try request.budget.begin(request.id)
        var hash = SHA256(), count: UInt64 = 0
        let ceiling = request.policy.inspectionByteCeiling
        let report = try inspector.inspect(request) { chunk in
            guard !chunk.isEmpty else { request.budget.invalidate(.invalidInspection); throw ProjectTopicMediaFailure.invalidInspection }
            let size = UInt64(chunk.count)
            guard count <= ceiling, size <= ceiling - count else { request.budget.invalidate(.byteLimit); throw ProjectTopicMediaFailure.byteLimit }
            try request.budget.consume(size)
            count += size; hash.update(data: chunk)
        }
        try request.budget.check()
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard report.requestID == request.id, report.reference == request.reference, count > 0,
              count == report.byteCount, digest == report.decodedContentSHA256 else { throw ProjectTopicMediaFailure.invalidInspection }
        let common: Set<ProjectTopicMediaInspectionReport.Check> = [.regularAppManagedFile, .containerRecognized, .metadataDecoded]
        let required = report.kind == .image ? common.union([.imageDecoded]) : common.union([.videoTrackInspected, .durationMeasured])
        guard report.checks == required else { throw ProjectTopicMediaFailure.invalidInspection }
        let facts = ProjectTopicMediaFacts(reference: request.reference, kind: report.kind, mimeType: report.mimeType,
                                          byteCount: count, width: report.width, height: report.height,
                                          durationMilliseconds: report.durationMilliseconds, contentSHA256: digest)
        try request.policy.validate(facts)
        return .init(request: request, facts: facts)
    }
}

/// Metadata-only local recovery. There are no upload receipts or remote wire keys.
public struct ProjectTopicMediaLocalRecord: Encodable, Equatable {
    public let schemaVersion: Int
    public let accountID: Int
    public let namespace: String
    public let identity: ProjectEditDraftIdentity
    public let product: ProjectEditProduct
    public let owner: ProjectEditOwner
    public let items: [ProjectTopicMediaFacts]
    init(context: ProjectTopicMediaContext, items: [ProjectTopicMediaFacts]) {
        schemaVersion = 1; accountID = context.session.accountID; namespace = context.session.storageNamespace
        identity = context.identity; product = context.product; owner = context.owner; self.items = items
    }
    private struct Wire: Decodable {
        let schemaVersion: Int, accountID: Int
        let namespace: String
        let identity: ProjectEditDraftIdentity
        let product: ProjectEditProduct
        let owner: ProjectEditOwner
        let items: [ProjectTopicMediaFacts]
    }
    private init(_ wire: Wire) {
        schemaVersion = wire.schemaVersion; accountID = wire.accountID; namespace = wire.namespace
        identity = wire.identity; product = wire.product; owner = wire.owner; items = wire.items
    }
    func matches(_ context: ProjectTopicMediaContext) -> Bool {
        accountID == context.session.accountID && namespace.utf8.elementsEqual(context.session.storageNamespace.utf8) &&
        ProjectTopicMediaContext.sameIdentity(identity, context.identity) && product == context.product && owner == context.owner
    }
    func validateShape() throws {
        guard schemaVersion == 1, accountID > 0, !namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ProjectTopicMediaContext.validIdentity(identity),
              !items.isEmpty, Set(items.map { $0.reference.id }).count == items.count else { throw ProjectTopicMediaFailure.invalidRecord }
        for item in items {
            guard ProjectTopicMediaFacts.validDigest(item.contentSHA256), item.byteCount > 0, item.width > 0, item.height > 0,
                  ProjectTopicMediaPolicy.validMIME(item.mimeType, kind: item.kind),
                  item.kind == .image ? item.durationMilliseconds == nil : (item.durationMilliseconds ?? 0) > 0 else {
                throw ProjectTopicMediaFailure.invalidRecord
            }
        }
    }
    public func encoded() throws -> Data { try validateShape(); return try JSONEncoder().encode(self) }
    /// Strict duplicate-key parsing precedes typed decode. Roundtrip equality refuses
    /// unknown fields anywhere, rather than dropping newer records during recovery.
    public static func decode(_ data: Data, maximumRecordBytes: Int) throws -> Self {
        do {
            guard maximumRecordBytes > 0, !data.isEmpty, data.count <= maximumRecordBytes else { throw ProjectTopicMediaFailure.invalidRecord }
            guard let text = String(data: data, encoding: .utf8) else { throw ProjectTopicMediaFailure.invalidRecord }
            let original = try ContentDraftJSON.parse(text)
            let value = Self(try JSONDecoder().decode(Wire.self, from: data))
            try value.validateShape()
            let retained = try ContentDraftJSON.parse(String(decoding: value.encoded(), as: UTF8.self))
            guard original == retained else { throw ProjectTopicMediaFailure.invalidRecord }
            return value
        } catch { throw ProjectTopicMediaFailure.invalidRecord }
    }
}
