import Foundation
import Observation
import UIKit
import SceneKit
import XCTest
@testable import Questify
private enum ModelPreviewSynthetic {
    static func triangle(changes: [String: Any] = [:]) -> Data {
        var root: [String: Any] = ["asset": ["version": "2.0"], "scene": 0, "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]], "meshes": [["primitives": [["attributes": ["POSITION": 0]]]]],
            "buffers": [["byteLength": 36]], "bufferViews": [["buffer": 0, "byteLength": 36]],
            "accessors": [["bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0,0,0], "max": [1,1,0]]]]
        for (key, value) in changes { root[key] = value }
        var json = try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        while json.count % 4 != 0 { json.append(0x20) }
        var data = Data()
        func append(_ value: UInt32) { for shift in [0,8,16,24] { data.append(UInt8((value >> shift) & 255)) } }
        append(0x46546C67); append(2); append(UInt32(28 + json.count + 36)); append(UInt32(json.count)); append(0x4E4F534A)
        data.append(json); append(36); append(0x004E4942)
        for value: Float in [0,0,0, 1,0,0, 0,1,0] { append(value.bitPattern) }; return data
    }
}

@MainActor private final class ModelPreviewVault: AppTokenStorage {
    var token: String? = "synthetic-model-preview"
    func read() throws -> String? { token }; func write(_ value: String) throws { token = value }; func clear() throws { token = nil }
}
@MainActor private final class ModelPreviewLogin: HTTPTransport {
    var requests: [URLRequest] = [], role = "player"
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
    }
}
@MainActor private final class ModelPreviewListBox { var approval: OwnMediaReadApproval? }
@MainActor @Observable private final class ModelPreviewRowBox { var row: OwnMediaAsset? }
@MainActor private final class ModelPreviewMetadata: OwnMediaModelPreviewMetadataReading {
    var requests: [URLRequest] = [], status = 200, after: (() -> Void)?, wait = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    var value: (Data, Int) { (Data(#"{"code":200,"data":{"authorPreviewUrl":"https://owner-model.example.test/a.glb?Signature=a%2Bb"}}"#.utf8), status) }
    func send(_ request: URLRequest, authorization: OwnMediaModelPreviewAuthorization) async throws -> (Data, Int) {
        try authorization.forward(request, cancel: {}) { requests.append(request) }; after?()
        if wait { wait = false; return try await withCheckedThrowingContinuation { pending = $0 } }; return value
    }
    func finish() { let p = pending; pending = nil; p?.resume(returning: value) }
}
@MainActor private final class ModelPreviewBytes: OwnMediaPrivateModelReading {
    var requests: [URLRequest] = [], after: (() -> Void)?, payload = ModelPreviewSynthetic.triangle()
    func model(_ request: URLRequest, authorization: OwnMediaModelPreviewAuthorization) async throws -> Data {
        try authorization.forward(request, cancel: {}) { requests.append(request) }; after?()
        return payload // Synthetic geometry; injected decoder never calls GLTFKit2.
    }
}
@MainActor private final class ModelPreviewMemoryDevice: OwnMediaModelPreviewRendering {
    var prepares = 0, rotations = 0, stops = 0, fail = false
    var current: (() -> Bool)?
    func prepare(_ scene: SCNScene, current: @escaping () -> Bool) throws { prepares += 1; if fail || !current() { throw OwnMediaModelPreviewFailure.invalidResponse }; self.current = current }
    func rotate() throws { guard current?() == true else { throw OwnMediaModelPreviewFailure.stale }; rotations += 1 }
    func attach(_ surface: any OwnMediaModelPreviewSurface) -> UUID? { nil }
    func detach(_ attachment: UUID) {}
    func stop() { stops += 1; current = nil }
}
@MainActor private final class ModelPreviewHost {
    let root: AppCompositionRoot, defaults: UserDefaults, suite = "owner-model-" + UUID().uuidString, notes = NotificationCenter()
    let vault = ModelPreviewVault(), login = ModelPreviewLogin(), listBox = ModelPreviewListBox(), rowBox = ModelPreviewRowBox()
    let metadata = ModelPreviewMetadata(), bytes = ModelPreviewBytes()
    let asset = OwnMediaAsset(id: 9, reviewState: .hold, reviewReason: "Pending", mediaType: .model3D)
    var devices: [ModelPreviewMemoryDevice] = [], made = 0, decodes = 0
    var decodeWait = false, decodePending: CheckedContinuation<SCNScene, Error>?
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let d = try ReviewedAppDeployment(market: .china, baseURL: "https://model-api.example.test/native", approvedBaseURLs: [.china: ["https://model-api.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.owner.model." + UUID().uuidString.lowercased(), realm: "synthetic")
        let login = login, vault = vault, box = listBox
        root = .init(deployment: .reviewed(d), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { login })
        root.ownMediaReadApproval = { context in box.approval.flatMap { $0.matches(context) ? $0 : nil } }; rowBox.row = asset
    }
    func boot() async -> AppSession { let s = root.makeSession(); await s.bootstrap(); login.requests = []; return s }
    func listGrant(_ s: AppSession) throws {
        let c = try XCTUnwrap(s.ownMediaModelPreviewIdentity(asset).context); listBox.approval = try .init(context: c, expiresAt: Date().addingTimeInterval(600))
    }
    func grant(_ s: AppSession, id: Int64 = 9, duration: TimeInterval = 600) throws -> OwnMediaModelPreviewApproval {
        let identity = s.ownMediaModelPreviewIdentity(asset)
        let value = try OwnMediaModelPreviewApproval(context: XCTUnwrap(identity.context), viewerRevision: identity.viewerRevision,
            assetID: id, approvedOrigins: ["https://owner-model.example.test"], expiresAt: Date().addingTimeInterval(duration))
        try root.ownMediaModelPreviewSelection.replace(assetID: id, with: value); return value
    }
    func model(_ s: AppSession) -> OwnMediaModelPreviewModel {
        let access = OwnMediaModelPreviewAccess(sourceRevision: s.ownMediaModelPreviewAccess.sourceRevision, makeReader: { [unowned self] asset in
            made += 1; return s.makeOwnMediaModelPreviewReader(asset, metadata: metadata, modelReader: bytes)
        })
        return .init(asset: asset, access: access, currentAsset: { [unowned self] in rowBox.row }, notifications: notes, decode: { [unowned self] _ in
            decodes += 1
            if decodeWait { decodeWait = false; return try await withCheckedThrowingContinuation { decodePending = $0 } }
            return SCNScene()
        }, makeDevice: { [unowned self] in let device = ModelPreviewMemoryDevice(); devices.append(device); return device })
    }
    func finishDecode() { let pending = decodePending; decodePending = nil; pending?.resume(returning: SCNScene()) }
    func cleanup() { finishDecode(); root.ownMediaModelPreviewSelection.revoke(assetID: 9); root.ownMediaModelPreviewSelection.revoke(assetID: 10); listBox.approval?.revoke(); devices.forEach { $0.stop() }; metadata.finish(); defaults.removePersistentDomain(forName: suite) }
}
@MainActor final class OwnMediaModelPreviewHostTests: XCTestCase {
    private func host() throws -> ModelPreviewHost { let f = try ModelPreviewHost(); addTeardownBlock { @MainActor in f.cleanup() }; return f }
    func testDefaultHostCannotFetchDecodeOrRender() async throws {
        let f = try host(), s = await f.boot(); let model = f.model(s); model.appear(foreground: true)
        XCTAssertNil(s.ownMediaModelPreviewAccess.sourceRevision(f.asset)); XCTAssertNil(model.open()); XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.devices.isEmpty)
    }
    func testListAuthorityCannotGrantModelAndModelCannotReplaceList() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); XCTAssertNil(s.ownMediaModelPreviewAccess.sourceRevision(f.asset)); _ = try f.grant(s)
        XCTAssertNotNil(s.ownMediaModelPreviewAccess.sourceRevision(f.asset)); f.listBox.approval?.revoke(); XCTAssertNil(s.makeOwnMediaModelPreviewReader(f.asset, metadata: f.metadata, modelReader: f.bytes))
    }
    func testImageAndAudioGrantsCannotAuthorizeModel() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); let identity = s.ownMediaModelPreviewIdentity(f.asset)
        let image = try OwnMediaImagePreviewApproval(context: XCTUnwrap(identity.context), viewerRevision: identity.viewerRevision, assetID: 9, approvedOrigins: ["https://owner-model.example.test"], expiresAt: .distantFuture)
        try f.root.ownMediaImagePreviewSelection.replace(assetID: 9, with: image); XCTAssertNil(s.ownMediaModelPreviewAccess.sourceRevision(f.asset))
        let audio = try OwnMediaAudioPreviewApproval(context: XCTUnwrap(identity.context), viewerRevision: identity.viewerRevision, assetID: 9, approvedOrigins: ["https://owner-model.example.test"], expiresAt: .distantFuture)
        try f.root.ownMediaAudioPreviewSelection.replace(assetID: 9, with: audio); XCTAssertNil(s.ownMediaModelPreviewAccess.sourceRevision(f.asset))
        _ = try f.grant(s); f.root.ownMediaModelPreviewSelection.revoke(assetID: 9); XCTAssertFalse(image.revoked); XCTAssertFalse(audio.revoked)
        f.root.ownMediaImagePreviewSelection.revoke(assetID: 9); f.root.ownMediaAudioPreviewSelection.revoke(assetID: 9)
    }
    func testAppearanceDoesNotRequestAndLoadedPreviewDoesNotRotate() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true)
        XCTAssertTrue(f.devices.isEmpty); XCTAssertTrue(f.metadata.requests.isEmpty); await model.open()?.value
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(f.devices.first?.prepares, 1); XCTAssertEqual(f.devices.first?.rotations, 0); model.disappear()
    }
    func testExplicitRotationIsBoundToCurrentControls() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        let id = try XCTUnwrap(model.presentation); model.rotate(id, operation: model.controlRevision)
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(f.devices[0].rotations, 1); model.disappear()
    }
    func testFirstPartyTokenNeverGoesToModelResourceOrGenericHostTransport() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        XCTAssertEqual(f.metadata.requests.first?.value(forHTTPHeaderField: "Authorization"), "synthetic-model-preview"); XCTAssertNil(f.bytes.requests.first?.value(forHTTPHeaderField: "Authorization")); XCTAssertTrue(f.login.requests.isEmpty); model.disappear()
    }
    func testSystemBackgroundSynchronouslyStopsAndNeverResumes() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        let id = try XCTUnwrap(model.presentation); model.rotate(id, operation: model.controlRevision); f.notes.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices[0].stops, 0); model.setForeground(true); XCTAssertEqual(f.devices[0].rotations, 1); XCTAssertEqual(f.metadata.requests.count, 1)
    }
    func testRowWillChangeStopsSynchronouslyWithoutSwiftUIRendering() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        model.rotate(try XCTUnwrap(model.presentation), operation: model.controlRevision); f.rowBox.row = nil
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices[0].stops, 0)
    }
    func testListWithdrawalStopsSynchronouslyWithoutWaitingForUI() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        model.rotate(try XCTUnwrap(model.presentation), operation: model.controlRevision); f.listBox.approval?.revoke()
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices[0].stops, 0)
    }
    func testSourceWithdrawalStopsOnlyThisAsset() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let other = try f.grant(s, id: 10); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        f.root.ownMediaModelPreviewSelection.revoke(assetID: 9); XCTAssertNil(model.presentation); XCTAssertFalse(other.revoked); XCTAssertTrue(s.ownMediaReader.isAvailable)
    }
    func testSessionLifetimeStopsReadersAndViewportSynchronously() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        model.rotate(try XCTUnwrap(model.presentation), operation: model.controlRevision); s.ownMediaModelPreviewLifetime.retireAll()
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices.first?.stops ?? 0, 0); XCTAssertEqual(f.vault.token, "synthetic-model-preview")
    }
    func testAuthoritativeRoleRefreshStopsOldModel() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        f.login.role = "merchant"; await s.refreshOwnAccount(); XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices[0].stops, 0)
    }
    func testOriginalLoginGateTransitionStopsOldModelEvenWhenLoginFails() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        await s.login(username: "synthetic", password: "synthetic") // Stub returns no login token; no real HTTP.
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices[0].stops, 0)
    }
    func testQueuedOpenCancelledBeforeAdmissionDoesNotRead() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true)
        let work = model.open(); model.disappear(); await work?.value; XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.devices.isEmpty)
    }
    func testOldCloseAndControlsCannotStopNewPresentation() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        let old = try XCTUnwrap(model.presentation), run = model.controlRevision, binding = model.binding(old); model.close(old); await model.open()?.value
        let current = try XCTUnwrap(model.presentation); model.close(old); binding.wrappedValue = nil; model.rotate(old, operation: run)
        XCTAssertEqual(model.presentation, current); XCTAssertEqual(f.devices.last?.rotations, 0); model.close(current)
    }
    func testLateOldMetadataCannotDecodeOrRenderNewPresentation() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); f.metadata.wait = true
        let oldTask = model.open(); for _ in 0..<100 { if f.metadata.pending != nil { break }; await Task.yield() }
        guard f.metadata.pending != nil else { model.disappear(); await oldTask?.value; XCTFail("Synthetic admission failed"); return }
        model.close(try XCTUnwrap(model.presentation)); await model.open()?.value; f.metadata.finish(); await oldTask?.value
        XCTAssertEqual(f.devices.count, 1); XCTAssertEqual(f.devices[0].rotations, 0); model.disappear()
    }
    func testLoadingTimeoutRequiresExplicitRetryAndOldTimeoutCannotClearNewRender() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); f.metadata.wait = true
        let oldTask = model.open(); for _ in 0..<100 { if f.metadata.pending != nil { break }; await Task.yield() }
        guard f.metadata.pending != nil else { model.disappear(); await oldTask?.value; XCTFail("Synthetic admission failed"); return }
        let id = try XCTUnwrap(model.presentation), old = model.controlRevision
        model.loadingTimedOut(id, old); XCTAssertEqual(model.phase, .failed)
        await model.retry(id, operation: model.controlRevision)?.value
        model.loadingTimedOut(id, old); f.metadata.finish(); await oldTask?.value
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(f.devices.count, 1); model.disappear()
    }
    func testLateDecoderAfterWithdrawalCannotCreateViewport() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); f.decodeWait = true
        let work = model.open(); for _ in 0..<100 { if f.decodePending != nil { break }; await Task.yield() }
        guard f.decodePending != nil else { model.disappear(); await work?.value; XCTFail("Synthetic decode admission failed"); return }
        f.root.ownMediaModelPreviewSelection.revoke(assetID: 9); f.finishDecode(); await work?.value
        XCTAssertNil(model.presentation); XCTAssertTrue(f.devices.isEmpty)
    }
    func testOldDecoderCannotReplaceNewPresentation() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); f.decodeWait = true
        let oldTask = model.open(); for _ in 0..<100 { if f.decodePending != nil { break }; await Task.yield() }
        guard f.decodePending != nil else { model.disappear(); await oldTask?.value; XCTFail("Synthetic decode admission failed"); return }
        model.close(try XCTUnwrap(model.presentation)); await model.open()?.value
        let current = model.presentation; f.finishDecode(); await oldTask?.value
        XCTAssertEqual(model.presentation, current); XCTAssertEqual(f.devices.count, 1); model.disappear()
    }
    func testPerAssetExpiryClearsViewportAndDoesNotLogOut() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); let grant = try f.grant(s, duration: 0.5), other = try f.grant(s, id: 10)
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value; if let id = model.presentation { model.rotate(id, operation: model.controlRevision) }
        try await Task.sleep(nanoseconds: 600_000_000); XCTAssertTrue(grant.revoked); XCTAssertFalse(other.revoked); XCTAssertNil(model.presentation)
        XCTAssertGreaterThan(f.devices.first?.stops ?? 0, 0); XCTAssertEqual(f.vault.token, "synthetic-model-preview")
    }
    func testMetadataDenialDoesNotRevokeListOrAccount() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); let grant = try f.grant(s); f.metadata.status = 403
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        XCTAssertTrue(grant.revoked); XCTAssertTrue(s.ownMediaReader.isAvailable); XCTAssertEqual(s.account?.id, 7); XCTAssertTrue(f.devices.isEmpty)
    }
    func testSignificantTimeChangeSynchronouslyDropsPrivateModel() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        model.rotate(try XCTUnwrap(model.presentation), operation: model.controlRevision); f.notes.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        XCTAssertNil(model.presentation); XCTAssertGreaterThan(f.devices.first?.stops ?? 0, 0); XCTAssertEqual(f.metadata.requests.count, 1)
    }
    func testUnsupportedAnimationNeverReachesDecoderOrViewport() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s)
        f.bytes.payload = ModelPreviewSynthetic.triangle(changes: ["animations": [[:]]])
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        XCTAssertEqual(model.phase, .failed); XCTAssertEqual(f.decodes, 0); XCTAssertTrue(f.devices.isEmpty); model.disappear()
    }
    func testLosingActiveStateDuringDecodeCancelsPresentationSynchronously() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s)
        let model = f.model(s); model.appear(foreground: true); f.decodeWait = true
        let work = model.open(); for _ in 0..<100 { if f.decodePending != nil { break }; await Task.yield() }
        guard f.decodePending != nil else { model.disappear(); await work?.value; XCTFail("Synthetic decode admission failed"); return }
        f.notes.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertNil(model.presentation); f.finishDecode(); await work?.value; XCTAssertTrue(f.devices.isEmpty)
    }

}
