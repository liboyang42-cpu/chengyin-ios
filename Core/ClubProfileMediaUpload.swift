import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ClubProfileMediaField: String, CaseIterable { case logo, cover
    var businessType: String { self == .logo ? "image_1_1" : "image_16_9" }
    func accepts(_ image: RetainedSelectedImage) -> Bool {
        self == .logo ? image.width == image.height : image.width * 9 == image.height * 16
    }
}
public enum ClubProfileMediaFailure: Error { case disabled, stale, invalid, locked, notSent, rejected, revoked, unknown; case reviewPending(Int64, String) }
/// Issued separately for this feature. A club-post/profile-avatar approval grants nothing here.
public struct ClubProfileMediaApproval: Equatable {
    public let endpoint: OperationEndpointApproval
    public let revision: UUID
    public let approvedOrigins: Set<String>
    public let album: Bool
    public let camera: Bool
    public let assetRead: Bool
    public let assetRetry: Bool
    public init(endpoint: OperationEndpointApproval, revision: UUID, approvedOrigins: Set<String>, album: Bool = false, camera: Bool = false, assetRead: Bool = false, assetRetry: Bool = false) throws {
        guard endpoint.paths == [ClubProfileMediaService.path], !approvedOrigins.isEmpty else { throw APIError.invalidConfiguration }
        self.endpoint = endpoint; self.revision = revision; self.approvedOrigins = approvedOrigins; self.album = album; self.camera = camera; self.assetRead = assetRead; self.assetRetry = assetRetry
    }
}
/// The approved adapter must call forward at its synchronous URLSession/task start, after
/// all suspensions. No generic HTTPTransport fallback and no implicit network creation.
@MainActor public final class ClubProfileMediaDispatchAuthorization {
    private let request: URLRequest
    private let current: () -> Bool
    public private(set) var didForward = false
    init(request: URLRequest, current: @escaping () -> Bool) { self.request = request; self.current = current }
    public func forward(_ request: URLRequest, start: () throws -> Void) throws {
        guard !didForward, self.request == request, isCurrent else { throw ClubProfileMediaFailure.notSent }
        didForward = true; try start()
    }
    var isCurrent: Bool { !Task.isCancelled && current() }
}
@MainActor public protocol ClubProfileMediaDispatching: AnyObject {
    var isConfigured: Bool { get }
    func send(_ request: URLRequest, authorization: ClubProfileMediaDispatchAuthorization) async throws -> (Data, Int)
}
@MainActor public struct ClubProfileMediaRuntime {
    public let upload: any ClubProfileMediaDispatching
    public let save: any ClubProfileMediaDispatching
    public let journal: any OperationPendingListing
    public let approval: () -> ClubProfileMediaApproval?
    public init(upload: any ClubProfileMediaDispatching, save: any ClubProfileMediaDispatching,
                journal: any OperationPendingListing, approval: @escaping () -> ClubProfileMediaApproval?) {
        self.upload = upload; self.save = save; self.journal = journal; self.approval = approval
    }
}
public struct ClubProfileMediaScope: Equatable {
    public let identity: ClubReadIdentity
    public let target: ClubOperationsTarget
    public let source: ClubOperationsProfile?
    public let revision: UInt64
    public let approvalID: UUID
    public let ownerID: UUID
}
/// Only this upload owner can mint a receipt. It is an upload ACK, not a profile save,
/// moderation result, or a permanent guarantee of the current actor's rights.
public struct ClubProfileMediaReceipt: Equatable {
    public let id: UUID
    public let field: ClubProfileMediaField
    public let scope: ClubProfileMediaScope
    public let reference: String
    private let live: @MainActor () -> Bool
    fileprivate init(id: UUID, field: ClubProfileMediaField, scope: ClubProfileMediaScope, reference: String, live: @escaping @MainActor () -> Bool) {
        self.id = id; self.field = field; self.scope = scope; self.reference = reference; self.live = live
    }
    public static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.field == b.field && a.scope == b.scope && a.reference == b.reference }
    @MainActor func isCurrent() -> Bool { live() }
}
@MainActor public final class ClubProfileMediaService {
    public nonisolated static let path = "api/common/uploadOSS"
    private let configuration: APIConfiguration
    private let runtime: ClubProfileMediaRuntime
    private let session: () -> ClubOperationsSession?
    private let revision: () -> UInt64
    public init(configuration: APIConfiguration, runtime: ClubProfileMediaRuntime,
                session: @escaping () -> ClubOperationsSession?, revision: @escaping () -> UInt64) {
        self.configuration = configuration; self.runtime = runtime; self.session = session; self.revision = revision
    }
    public func scope(snapshot: ClubOperationsSnapshot, identity: ClubReadIdentity, ownerID: UUID) -> ClubProfileMediaScope? {
        guard let session = session(), session.identity == identity, let approval = runtime.approval(),
              runtime.upload.isConfigured, runtime.save.isConfigured,
              let account = identity.accountID,
              approval.endpoint.allows(configuration: configuration, namespace: session.storageNamespace, accountID: account, path: Self.path),
              (snapshot.target == .create ? snapshot.canCreate : snapshot.profile?.club.canGovern == true) else { return nil }
        return .init(identity: identity, target: snapshot.target, source: snapshot.profile, revision: revision(), approvalID: approval.revision, ownerID: ownerID)
    }
    public func isCurrent(_ scope: ClubProfileMediaScope) -> Bool {
        guard let session = session(), session.identity == scope.identity, revision() == scope.revision,
              let account = scope.identity.accountID, let approval = runtime.approval(), approval.revision == scope.approvalID,
              runtime.upload.isConfigured, runtime.save.isConfigured else { return false }
        return approval.endpoint.allows(configuration: configuration, namespace: session.storageNamespace, accountID: account, path: Self.path)
    }
    public func permitsAlbum(_ scope: ClubProfileMediaScope) -> Bool { isCurrent(scope) && runtime.approval()?.album == true }
    public func permitsCamera(_ scope: ClubProfileMediaScope) -> Bool { isCurrent(scope) && runtime.approval()?.camera == true }
    private func key(_ target: ClubOperationsTarget, field: ClubProfileMediaField) -> String {
        let id: String; switch target { case .create: id = "new"; case .club(let value): id = String(value) }
        return "club.profile.media:\(id):\(field.rawValue)"
    }
    public func upload(_ image: RetainedSelectedImage, field: ClubProfileMediaField, scope: ClubProfileMediaScope,
                       ownerCurrent: @escaping () -> Bool) async throws -> ClubProfileMediaReceipt {
        guard isCurrent(scope), ownerCurrent(), field.accepts(image), let captured = session(), let approval = runtime.approval() else { throw ClubProfileMediaFailure.notSent }
        let record = OperationPendingRecord(ownerKey: configuration.baseURL.absoluteString + "|" + captured.ownerKey, targetKey: key(scope.target, field: field))
        guard try pendingAsset(scope: scope, field: field) == nil else { throw ClubProfileMediaFailure.locked }
        guard try runtime.journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == nil else { throw ClubProfileMediaFailure.locked }
        let boundary = "ClubProfile-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\n\(field.businessType)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"club.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(image.jpeg); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(Self.path))
        request.httpMethod = "POST"; request.httpBody = body; request.httpShouldHandleCookies = false
        request.timeoutInterval = 30; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(captured.token, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let current = { [weak self] in
            guard let self else { return false }
            return self.session() == captured && self.runtime.approval() == approval && self.isCurrent(scope) && ownerCurrent()
        }
        let authorization = ClubProfileMediaDispatchAuthorization(request: request, current: current)
        try runtime.journal.write(record)
        do {
            let (data, status) = try await runtime.upload.send(request, authorization: authorization)
            guard authorization.didForward, authorization.isCurrent, data.count <= 65536 else { throw ClubProfileMediaFailure.unknown }
            let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
            if status == 401 || status == 403 || envelope?.code == 401 || envelope?.code == 403 {
                // Auth revocation is not proof that a forwarded upload never executed.
                // Keep the original durable lock; no automatic retransmission.
                throw ClubProfileMediaFailure.revoked
            }
            // fixed58 ApiCommonController.badUploadRequest is exactly HTTP400/code400.
            // For these image bizTypes AppUploadService throws UploadRejectedException
            // in prepareOssUpload/verifyContentSecurity, before photoOwnerUploader.
            // Do not generalize this to business500, storage exceptions or all 4xx.
            if status == 400, envelope?.code == 400 {
                try runtime.journal.clear(record); throw ClubProfileMediaFailure.rejected
            }
            guard status == 200, envelope?.code == 200, let value = envelope, let asset = value.assetId, asset > 0,
                  let reviewState = value.reviewState, ["APPROVED", "HOLD", "REJECTED", "UNAVAILABLE"].contains(reviewState) else { throw ClubProfileMediaFailure.unknown }
            if reviewState != "APPROVED" {
                // Store only original asset identity. A future open reads this same asset,
                // never retransmits the file or borrows another account's review result.
                let pending = OperationPendingRecord(operationID: record.operationID, ownerKey: record.ownerKey,
                    targetKey: record.targetKey + ":asset:" + String(asset), acknowledgedSteps: 1)
                try runtime.journal.write(pending); try runtime.journal.clear(record)
                throw ClubProfileMediaFailure.reviewPending(asset, reviewState)
            }
            guard let raw = value.url.map(Self.secureReference),
                  raw.utf8.count <= 8192, raw.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }),
                  let url = URL(string: raw), RetainedImageOrigin.accepts(url, origins: approval.approvedOrigins) else { throw ClubProfileMediaFailure.unknown }
            // ACK URL is memory-only; an interrupted or unknown attempt remains locked on restart.
            var acknowledged = record; acknowledged.acknowledgedSteps = 1; try runtime.journal.write(acknowledged)
            try runtime.journal.clear(acknowledged)
            return .init(id: record.operationID, field: field, scope: scope, reference: raw, live: current)
        } catch {
            if !authorization.didForward { try? runtime.journal.clear(record); throw ClubProfileMediaFailure.notSent }
            if case ClubProfileMediaFailure.rejected = error { throw error }
            if case ClubProfileMediaFailure.revoked = error { throw error }
            if case ClubProfileMediaFailure.reviewPending = error { throw error }
            throw ClubProfileMediaFailure.unknown
        }
    }
    func validate(_ command: ClubOperationsCommand, identity: ClubReadIdentity) throws {
        for receipt in command.profileMediaReceipts {
            guard receipt.scope.identity == identity, isCurrent(receipt.scope), receipt.isCurrent() else { throw ClubOperationsBlock.changed }
        }
    }
    func sendSave(_ request: URLRequest, command: ClubOperationsCommand, identity: ClubReadIdentity,
                  current: @escaping () -> Bool) async throws -> (Data, Int) {
        try validate(command, identity: identity)
        let authorization = ClubProfileMediaDispatchAuthorization(request: request) { [weak self] in
            guard let self, current(), (try? self.validate(command, identity: identity)) != nil else { return false }
            return true
        }
        do {
            let result = try await runtime.save.send(request, authorization: authorization)
            guard authorization.didForward, authorization.isCurrent else { throw ClubProfileMediaFailure.unknown }
            return result
        } catch {
            throw authorization.didForward ? ClubActionWriteError.outcomeUnknown(.transport) : ClubActionWriteError.notSent(.invalidRequest)
        }
    }
    public func pendingAsset(scope: ClubProfileMediaScope, field: ClubProfileMediaField) throws -> Int64? {
        guard isCurrent(scope), let session = session() else { throw ClubProfileMediaFailure.stale }
        let prefix = key(scope.target, field: field) + ":asset:"
        let rows = try runtime.journal.pendingRecords(ownerKey: configuration.baseURL.absoluteString + "|" + session.ownerKey).filter { $0.targetKey.hasPrefix(prefix) }
        guard rows.count <= 1 else { throw ClubProfileMediaFailure.locked }
        guard let row = rows.first else { return nil }
        guard let id = OwnMediaPage.identifier(String(row.targetKey.dropFirst(prefix.count))), (1...3).contains(row.acknowledgedSteps) else { throw ClubProfileMediaFailure.locked }
        return id
    }
    public func permitsReview(_ scope: ClubProfileMediaScope, retry: Bool) -> Bool {
        isCurrent(scope) && runtime.approval()?.assetRead == true && (!retry || runtime.approval()?.assetRetry == true)
    }
    /// Original GET asset/{id}; deliberate POST asset/{id}/retry only after a fresh
    /// REJECTED/UNAVAILABLE read. No invented upload receipt/reconciliation endpoint.
    public func review(field: ClubProfileMediaField, scope: ClubProfileMediaScope, retry: Bool,
                       ownerCurrent: @escaping () -> Bool) async throws -> ClubProfileMediaReceipt {
        guard permitsReview(scope, retry: retry), ownerCurrent(), let captured = session(), let approval = runtime.approval(),
              let asset = try pendingAsset(scope: scope, field: field) else { throw ClubProfileMediaFailure.disabled }
        let owner = configuration.baseURL.absoluteString + "|" + captured.ownerKey
        let target = key(scope.target, field: field) + ":asset:" + String(asset)
        guard var record = try runtime.journal.pending(ownerKey: owner, targetKey: target) else { throw ClubProfileMediaFailure.locked }
        let current = { [weak self] in
            guard let self else { return false }
            return self.session() == captured && self.runtime.approval() == approval && self.isCurrent(scope) && ownerCurrent()
        }
        func request(_ method: String, suffix: String = "") -> URLRequest {
            var value = URLRequest(url: configuration.baseURL.appendingPathComponent("api/media/asset/\(asset)" + suffix))
            value.httpMethod = method; value.httpShouldHandleCookies = false; value.cachePolicy = .reloadIgnoringLocalCacheData; value.timeoutInterval = 30
            value.setValue(captured.token, forHTTPHeaderField: "Authorization"); value.setValue("application/json", forHTTPHeaderField: "Accept"); return value
        }
        func read() async throws -> Asset {
            let req = request("GET"), auth = ClubProfileMediaDispatchAuthorization(request: request("GET"), current: current)
            let (data, status) = try await runtime.upload.send(req, authorization: auth)
            guard auth.didForward, auth.isCurrent, status == 200, data.count <= 65536,
                  let row = try? JSONDecoder().decode(AssetEnvelope.self, from: data), row.code == 200,
                  row.data.assetId == asset, row.data.mediaType == "IMAGE" else { throw ClubProfileMediaFailure.unknown }
            return row.data
        }
        var value = try await read()
        if retry {
            guard ["REJECTED", "UNAVAILABLE"].contains(value.reviewState), record.acknowledgedSteps != 2 else { throw ClubProfileMediaFailure.locked }
            record.acknowledgedSteps = 2; try runtime.journal.write(record)
            let req = request("POST", suffix: "/retry"), auth = ClubProfileMediaDispatchAuthorization(request: request("POST", suffix: "/retry"), current: current)
            do {
                let (data, status) = try await runtime.upload.send(req, authorization: auth)
                guard auth.didForward, auth.isCurrent, status == 200, data.count <= 65536,
                      let row = try? JSONDecoder().decode(AssetEnvelope.self, from: data), row.code == 200,
                      row.data.assetId == asset, row.data.mediaType == "IMAGE", row.data.reviewState == "HOLD" else { throw ClubProfileMediaFailure.unknown }
                record.acknowledgedSteps = 3; try runtime.journal.write(record); value = row.data
            } catch {
                if !auth.didForward { record.acknowledgedSteps = 1; try? runtime.journal.write(record) }
                throw ClubProfileMediaFailure.unknown
            }
        }
        guard ["APPROVED", "HOLD", "REJECTED", "UNAVAILABLE"].contains(value.reviewState) else { throw ClubProfileMediaFailure.unknown }
        guard value.reviewState == "APPROVED" else { throw ClubProfileMediaFailure.reviewPending(asset, value.reviewState) }
        guard current(), let raw = value.url.map(Self.secureReference), raw.utf8.count <= 8192, raw.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }),
              let url = URL(string: raw), RetainedImageOrigin.accepts(url, origins: approval.approvedOrigins) else { throw ClubProfileMediaFailure.unknown }
        // If process termination followed saving the asset identity but preceded clearing
        // the upload slot, the original asset ID is sufficient to finish that local step.
        if let upload = try runtime.journal.pending(ownerKey: owner, targetKey: key(scope.target, field: field)) {
            guard upload.operationID == record.operationID else { throw ClubProfileMediaFailure.locked }; try runtime.journal.clear(upload)
        }
        try runtime.journal.clear(record)
        return .init(id: record.operationID, field: field, scope: scope, reference: raw, live: current)
    }
    private static func secureReference(_ raw: String) -> String {
        raw.replacingOccurrences(of: "^http://([a-z0-9-]+\\.oss-[a-z0-9-]+\\.aliyuncs\\.com)(/)", with: "https://$1$2", options: [.regularExpression, .caseInsensitive])
    }
    private struct Envelope: Decodable {
        let code: Int; let url: String?; let reviewState: String?; let assetId: Int64?
        enum CodingKeys: String, CodingKey { case code, url, reviewState, assetId }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code); url = try c.decodeIfPresent(String.self, forKey: .url); reviewState = try c.decodeIfPresent(String.self, forKey: .reviewState)
            assetId = (try? c.decode(Int64.self, forKey: .assetId)) ?? (try? c.decode(String.self, forKey: .assetId)).flatMap(OwnMediaPage.identifier)
        }
    }
    private struct AssetEnvelope: Decodable { let code: Int; let data: Asset }
    private struct Asset: Decodable {
        let assetId: Int64; let reviewState: String; let mediaType: String; let url: String?
        enum CodingKeys: String, CodingKey { case assetId, reviewState, mediaType, url }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let id = (try? c.decode(Int64.self, forKey: .assetId)) ?? (try? c.decode(String.self, forKey: .assetId)).flatMap(OwnMediaPage.identifier), id > 0 else { throw ClubProfileMediaFailure.invalid }
            assetId = id; reviewState = try c.decode(String.self, forKey: .reviewState); mediaType = try c.decode(String.self, forKey: .mediaType); url = try c.decodeIfPresent(String.self, forKey: .url)
        }
    }
}
