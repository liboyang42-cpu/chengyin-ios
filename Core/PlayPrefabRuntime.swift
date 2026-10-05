import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Raw-file upload adapter for the source play_api.dart /common/uploadOSS contract.
/// No local file is opened, no camera is launched and no URLSession is constructed here.
extension PlayExperienceService {
    public func uploadPlayPhoto(bytes: Data, mimeType: String, token: String) async throws -> String {
        guard enabled.contains(.mediaUpload) else { throw PlayExperienceError.disabled }
        guard AuthRequestBuilder.isValidToken(token), !bytes.isEmpty, bytes.count <= 10 * 1024 * 1024,
              ["image/jpeg", "image/png", "image/webp"].contains(mimeType) else { throw APIError.invalidRequest }
        let extensionName = mimeType == "image/png" ? "png" : mimeType == "image/webp" ? "webp" : "jpg"
        var boundary = "PlayPhoto-" + UUID().uuidString
        while bytes.range(of: Data(boundary.utf8)) != nil { boundary = "PlayPhoto-" + UUID().uuidString }
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"play-photo.\(extensionName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8)
        body.append(bytes); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/common/uploadOSS"))
        request.httpMethod = "POST"; request.timeoutInterval = 30; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"); request.httpBody = body
        try Task.checkCancellation(); let (data, status) = try await transport.send(request); try Task.checkCancellation()
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: data)
        if status == 401 || raw["code"].tolerantInteger == 401 { throw PlayExperienceError.unauthorized }
        guard (200..<300).contains(status) else { throw PlayExperienceError.unknownResult }
        guard let code = raw["code"].tolerantInteger else { throw PlayExperienceError.malformed }
        guard code == 200 else { throw PlayExperienceError.rejected(code, raw["msg"].text) }
        guard let url = raw["url"].text, Self.validHTTPS(url) else { throw PlayExperienceError.malformed }
        return url // Source ordinary play upload returns top-level url, not data.url.
    }
}

/// Source narrative engine is reused; preview storage is deliberately NEVER read here.
/// The runtime envelope is bound to account, deployment namespace and activity/topic.
public struct PlayPrefabRuntimeRecord: Codable, Equatable {
    public var story: PrefabPreviewState
    public let owner: String
    public let scopeComponent: String
    public var hallPhotoURL: String?
    public var pendingPhotoNodeID: Int?
    public var pendingArrivalNodeID: Int?
    public var pendingUploadKey: String?
    public init(story: PrefabPreviewState = .init(), owner: String, scopeComponent: String) {
        // Incoming local preview content may carry fabricated photo/synced values.
        var clean = story; clean.photos = [:]; clean.profile.avatar = ""; clean.synced = false
        self.story = clean; self.owner = owner; self.scopeComponent = scopeComponent
        hallPhotoURL = nil; pendingPhotoNodeID = nil; pendingArrivalNodeID = nil; pendingUploadKey = nil
    }
}
@MainActor public final class PlayPrefabRuntimeStore {
    private let storage: any TemplateAuthoringStorage
    public init(storage: any TemplateAuthoringStorage) { self.storage = storage }
    public static func owner(_ session: PlayExperienceSession) -> String { "\(session.namespace.utf8.count):\(session.namespace):\(session.accountID)" }
    public static func scope(_ scope: PlaySessionScope) -> String { scope.fields.keys.first! + ":" + String(scope.id) }
    public static func key(_ session: PlayExperienceSession, _ scope: PlaySessionScope) -> String {
        "prefab-runtime.v1." + Data((owner(session) + ":" + Self.scope(scope)).utf8).base64EncodedString()
    }
    public func load(session: PlayExperienceSession, scope: PlaySessionScope) throws -> PlayPrefabRuntimeRecord? {
        guard let data = try storage.read(Self.key(session, scope)) else { return nil }
        var record = try JSONDecoder().decode(PlayPrefabRuntimeRecord.self, from: data)
        guard record.owner == Self.owner(session), record.scopeComponent == Self.scope(scope),
              record.hallPhotoURL.map(PlayExperienceService.validHTTPS) ?? true else { throw PlayExperienceError.malformed }
        // Restored local flags are not proof. Fresh source readback must confirm sync.
        record.story.synced = false; return record
    }
    public func save(_ record: PlayPrefabRuntimeRecord, session: PlayExperienceSession, scope: PlaySessionScope) throws {
        guard record.owner == Self.owner(session), record.scopeComponent == Self.scope(scope) else { throw PlayExperienceError.staleSession }
        try storage.write(JSONEncoder().encode(record), key: Self.key(session, scope))
    }
}
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayPrefabRuntimeCoordinator {
    public let scope: PlaySessionScope
    public private(set) var record: PlayPrefabRuntimeRecord?
    public private(set) var station: PlayNode?
    public private(set) var phase = "idle"
    public private(set) var issue: PlayExperienceError?
    private let service: PlayExperienceService
    private let provider: any PlayDeviceProviding
    private let store: PlayPrefabRuntimeStore
    private let currentSession: () -> PlayExperienceSession?
    private var owner: PlayExperienceSession?
    private var generation: UInt64 = 0
    public init(scope: PlaySessionScope, service: PlayExperienceService, provider: any PlayDeviceProviding,
                store: PlayPrefabRuntimeStore, currentSession: @escaping () -> PlayExperienceSession?) {
        self.scope = scope; self.service = service; self.provider = provider; self.store = store; self.currentSession = currentSession
    }
    public var canCapturePhoto: Bool { provider.supported.contains(.photo) }
    public var canCapture: Bool { canCapturePhoto && provider.supported.contains(.location) }
    public func load() async {
        guard phase != "submitting", phase != "uploading", let session = currentSession() else { return }
        if let owner, owner != session { record = nil; station = nil; phase = "stale"; return }
        owner = session; generation &+= 1; let generation = generation; phase = "loading"; issue = nil
        do {
            let document = try await service.nodes(scope: scope, token: session.token); try check(session, generation)
            guard PrefabPreviewState.isPrefabTopic(name: document.base.topicName), document.base.routeState?.isBranch != true,
                  document.base.playable == true, document.base.registered != false,
                  let first = document.base.nodes.first else { throw PlayExperienceError.unsupported }
            station = first
            var restored = try store.load(session: session, scope: scope) ?? PlayPrefabRuntimeRecord(owner: PlayPrefabRuntimeStore.owner(session), scopeComponent: PlayPrefabRuntimeStore.scope(scope))
            if restored.hallPhotoURL != nil, first.done == true || document.extras[first.id]?.uploadedImage?.isEmpty == false {
                restored.story.synced = true; restored.pendingPhotoNodeID = nil
            }
            if restored.pendingArrivalNodeID == first.id, first.arrived == true { restored.pendingArrivalNodeID = nil }
            record = restored; try store.save(restored, session: session, scope: scope)
            phase = restored.pendingPhotoNodeID == nil && restored.pendingArrivalNodeID == nil && restored.pendingUploadKey == nil ? "ready" : "unknown"
        } catch { fail(error, session, generation) }
    }
    public func updateStory(_ newValue: PrefabPreviewState) throws {
        guard phase == "ready", let session = owner, session == currentSession(), var record else { throw PlayExperienceError.staleSession }
        var value = newValue
        // UI/narrative edits cannot set remote facts or import preview photographs.
        value.synced = record.story.synced; value.photos = record.story.photos; value.profile.avatar = record.story.profile.avatar
        record.story = value; try store.save(record, session: session, scope: scope); self.record = record
    }
    /// Explicitly initiated two-step chain: verify arrival, then camera/upload. The
    /// ordinary photo upload has no idempotency receipt; unknown upload is never retried.
    public func arriveAndCaptureHallPhoto() async {
        guard phase == "ready", canCapture, let session = owner, session == currentSession(), let station, var record else { return }
        let generation = generation; phase = "submitting"
        do {
            let context = try PlayDeviceContext(session: session, scope: scope, nodeID: station.id)
            let output = try await provider.capture(.location, context: context); try check(session, generation)
            guard case .location(let longitude, let latitude, let coordinateSystem) = output, coordinateSystem == "GCJ02" else { throw PlayExperienceError.unsupported }
            record.pendingArrivalNodeID = station.id; try store.save(record, session: session, scope: scope); self.record = record
            let receipt = try await service.complete(scope: scope, nodeID: station.id, evidence: .location(longitude: longitude, latitude: latitude, coordinateSystem: coordinateSystem), advance: nil, token: session.token)
            try check(session, generation); guard receipt["nodeId"].tolerantInteger == station.id else { throw PlayExperienceError.malformed }
            record.pendingArrivalNodeID = nil; try store.save(record, session: session, scope: scope); self.record = record
            let photo = try await provider.capture(.photo, context: context); try check(session, generation)
            guard case .photo(let bytes, let mime) = photo else { throw PlayExperienceError.unsupported }
            record.pendingUploadKey = "hall"; try store.save(record, session: session, scope: scope); self.record = record
            phase = "uploading"
            let url = try await service.uploadPlayPhoto(bytes: bytes, mimeType: mime, token: session.token); try check(session, generation)
            record.pendingUploadKey = nil; record.hallPhotoURL = url; record.story.photos["hall"] = url
            try store.save(record, session: session, scope: scope); self.record = record; phase = "ready"
        } catch {
            if case PlayExperienceError.rejected = error { record.pendingUploadKey = nil; record.pendingArrivalNodeID = nil; try? store.save(record, session: session, scope: scope); self.record = record }
            fail(error, session, generation)
        }
    }
    public func captureStoryPhoto(key: String) async {
        guard phase == "ready", provider.supported.contains(.photo), let session = owner, session == currentSession(), let station, var record,
              ["sign", "window", "phone", "avatar"].contains(key) else { return }
        let allowed = (key == "avatar" && record.story.scene == .register) ||
            (key == "sign" && record.story.scene == .walk && record.story.walkProgress == 74) ||
            (key == "window" && record.story.scene == .birth && record.story.step == 2) ||
            (key == "phone" && record.story.scene == .work && record.story.step == 1)
        guard allowed else { return }
        let generation = generation; phase = "submitting"
        do {
            let context = try PlayDeviceContext(session: session, scope: scope, nodeID: station.id)
            let output = try await provider.capture(.photo, context: context); try check(session, generation)
            guard case .photo(let bytes, let mime) = output else { throw PlayExperienceError.unsupported }
            record.pendingUploadKey = key; try store.save(record, session: session, scope: scope); self.record = record; phase = "uploading"
            let url = try await service.uploadPlayPhoto(bytes: bytes, mimeType: mime, token: session.token); try check(session, generation)
            record.pendingUploadKey = nil
            if key == "avatar" { record.story.profile.avatar = url } else { record.story.photos[key] = url }
            try store.save(record, session: session, scope: scope); self.record = record; phase = "ready"
        } catch {
            if case PlayExperienceError.rejected = error { record.pendingUploadKey = nil; try? store.save(record, session: session, scope: scope); self.record = record }
            if case PlayExperienceError.disabled = error { record.pendingUploadKey = nil; try? store.save(record, session: session, scope: scope); self.record = record }
            fail(error, session, generation)
        }
    }
    public func syncCompletion() async {
        guard phase == "ready", let session = owner, session == currentSession(), let station, var record,
              let url = record.hallPhotoURL, record.story.scene == .flow, !record.story.synced else { return }
        let generation = generation; phase = "submitting"
        do {
            record.pendingPhotoNodeID = station.id; try store.save(record, session: session, scope: scope); self.record = record
            let receipt = try await service.complete(scope: scope, nodeID: station.id, evidence: .photo(uploadedURL: url), advance: nil, token: session.token)
            try check(session, generation); guard receipt["nodeId"].tolerantInteger == station.id else { throw PlayExperienceError.malformed }
            phase = "unknown"; await load()
        } catch {
            if case PlayExperienceError.rejected = error { record.pendingPhotoNodeID = nil; try? store.save(record, session: session, scope: scope); self.record = record }
            fail(error, session, generation)
        }
    }
    public func cancelDeviceWork() { provider.cancel(); generation &+= 1; if phase == "uploading" || phase == "submitting" { phase = "unknown" } }
    private func check(_ session: PlayExperienceSession, _ generation: UInt64) throws {
        guard self.generation == generation, currentSession() == session, !Task.isCancelled else { throw PlayExperienceError.staleSession }
    }
    private func fail(_ error: Error, _ session: PlayExperienceSession, _ generation: UInt64) {
        guard self.generation == generation else { return }
        guard currentSession() == session else { record = nil; station = nil; phase = "stale"; return }
        issue = error as? PlayExperienceError ?? .unknownResult
        if case PlayExperienceError.disabled = error { phase = "disabled" }
        else { phase = record?.pendingPhotoNodeID != nil || record?.pendingArrivalNodeID != nil || record?.pendingUploadKey != nil || phase == "uploading" ? "unknown" : "failed" }
    }
}
