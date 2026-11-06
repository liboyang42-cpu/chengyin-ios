import Foundation
import XCTest
import UIKit
@testable import Questify
@MainActor private final class OwnerPreviewVault: AppTokenStorage {
    var token: String? = "synthetic-private-preview"
    func read() throws -> String? { token }; func write(_ value: String) throws { token = value }; func clear() throws { token = nil }
}
@MainActor private final class OwnerPreviewLogin: HTTPTransport {
    var requests: [URLRequest] = [], role = "player"
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
    }
}
@MainActor private final class OwnerPreviewListBox { var approval: OwnMediaReadApproval? }
@MainActor private final class OwnerPreviewMetadata: OwnMediaImagePreviewMetadataReading {
    var requests: [URLRequest] = [], status = 200, after: (() -> Void)?, wait = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    var value: (Data, Int) { (Data(#"{"code":200,"data":{"authorPreviewUrl":"https://owner-images.example.test/a.jpg?Signature=a%2Bb"}}"#.utf8), status) }
    func send(_ request: URLRequest, authorization: OwnMediaImagePreviewAuthorization) async throws -> (Data, Int) {
        try authorization.forward(request, cancel: {}) { requests.append(request) }; after?()
        if wait { wait = false; return try await withCheckedThrowingContinuation { pending = $0 } }
        return value
    }
    func finish() { let p = pending; pending = nil; p?.resume(returning: value) }
}
@MainActor private final class OwnerPreviewBytes: OwnMediaPrivateImageReading {
    var requests: [URLRequest] = [], after: (() -> Void)?, invalid = false
    func image(_ request: URLRequest, authorization: OwnMediaImagePreviewAuthorization) async throws -> Data {
        try authorization.forward(request, cancel: {}) { requests.append(request) }; after?()
        if invalid { return Data([0]) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).pngData { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
@MainActor private final class OwnerPreviewHost {
    let root: AppCompositionRoot, defaults: UserDefaults, suite = "owner-preview-" + UUID().uuidString
    let vault = OwnerPreviewVault(), login = OwnerPreviewLogin(), listBox = OwnerPreviewListBox()
    let metadata = OwnerPreviewMetadata(), bytes = OwnerPreviewBytes()
    let asset = OwnMediaAsset(id: 9, reviewState: .hold, reviewReason: "Pending", mediaType: .image)
    var row: OwnMediaAsset?, made = 0
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let d = try ReviewedAppDeployment(market: .china, baseURL: "https://owner-host.example.test/native", approvedBaseURLs: [.china: ["https://owner-host.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.owner.preview." + UUID().uuidString.lowercased(), realm: "synthetic")
        let login = login, vault = vault, box = listBox
        root = .init(deployment: .reviewed(d), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { login })
        root.ownMediaReadApproval = { context in box.approval.flatMap { $0.matches(context) ? $0 : nil } }
        row = asset
    }
    func boot() async -> AppSession { let session = root.makeSession(); await session.bootstrap(); login.requests = []; return session }
    func listGrant(_ session: AppSession) throws {
        let context = try XCTUnwrap(session.ownMediaImagePreviewIdentity(asset).context)
        listBox.approval = try .init(context: context, expiresAt: Date().addingTimeInterval(600))
    }
    func previewGrant(_ session: AppSession, id: Int64 = 9, duration: TimeInterval = 600) throws -> OwnMediaImagePreviewApproval {
        let identity = session.ownMediaImagePreviewIdentity(asset)
        let value = try OwnMediaImagePreviewApproval(context: XCTUnwrap(identity.context), viewerRevision: identity.viewerRevision,
            assetID: id, approvedOrigins: ["https://owner-images.example.test"], expiresAt: Date().addingTimeInterval(duration))
        try root.ownMediaImagePreviewSelection.replace(assetID: id, with: value); return value
    }
    func access(_ session: AppSession) -> OwnMediaImagePreviewAccess {
        .init(sourceRevision: session.ownMediaImagePreviewAccess.sourceRevision, makeReader: { [unowned self] asset in
            made += 1; return session.makeOwnMediaImagePreviewReader(asset, metadata: metadata, imageReader: bytes)
        })
    }
    func model(_ session: AppSession) -> OwnMediaImagePreviewModel { .init(asset: asset, access: access(session), currentAsset: { [unowned self] in row }) }
    func cleanup() { listBox.approval?.revoke(); root.ownMediaImagePreviewSelection.revoke(assetID: 9); root.ownMediaImagePreviewSelection.revoke(assetID: 10); metadata.finish(); defaults.removePersistentDomain(forName: suite) }
}
@MainActor final class OwnMediaImagePreviewHostTests: XCTestCase {
    private func host() throws -> OwnerPreviewHost { let f = try OwnerPreviewHost(); addTeardownBlock { @MainActor in f.cleanup() }; return f }
    func testDefaultHostCannotReadOrProduceImageAccess() async throws {
        let f = try host(), s = await f.boot()
        XCTAssertNil(s.ownMediaImagePreviewAccess.sourceRevision(f.asset)); XCTAssertNil(s.makeOwnMediaImagePreviewReader(f.asset, metadata: f.metadata, imageReader: f.bytes))
        XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.bytes.requests.isEmpty); XCTAssertTrue(f.login.requests.isEmpty)
    }
    func testListGrantCannotAuthorizePreviewAndPreviewGrantCannotReplaceListGrant() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s)
        XCTAssertNil(s.ownMediaImagePreviewAccess.sourceRevision(f.asset)); _ = try f.previewGrant(s)
        XCTAssertNotNil(s.ownMediaImagePreviewAccess.sourceRevision(f.asset)); f.listBox.approval?.revoke()
        XCTAssertNil(s.makeOwnMediaImagePreviewReader(f.asset, metadata: f.metadata, imageReader: f.bytes))
    }
    func testAppearanceDoesNotSignOrDownloadUntilExplicitOpen() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s)
        let model = f.model(s); model.appear(foreground: true)
        XCTAssertEqual(f.made, 0); XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.bytes.requests.isEmpty)
        await model.open()?.value
        XCTAssertEqual(f.made, 1); XCTAssertEqual(f.metadata.requests.count, 1); XCTAssertEqual(f.bytes.requests.count, 1); XCTAssertNotNil(model.image)
        if let id = model.presentation { model.close(id) }
    }
    func testAnonymousImageAndFirstPartyMetadataNeverUseGenericHostTransport() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s)
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        XCTAssertTrue(f.login.requests.isEmpty); XCTAssertEqual(f.metadata.requests.first?.value(forHTTPHeaderField: "Authorization"), "synthetic-private-preview")
        XCTAssertNil(f.bytes.requests.first?.value(forHTTPHeaderField: "Authorization")); XCTAssertEqual(s.account?.id, 7)
        model.disappear()
    }
    func testBackgroundClearsPixelsAndForegroundDoesNotReopenOrFetch() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s)
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value; XCTAssertNotNil(model.image)
        model.setForeground(false); XCTAssertNil(model.image); XCTAssertNil(model.presentation)
        model.setForeground(true); XCTAssertNil(model.presentation); XCTAssertEqual(f.metadata.requests.count, 1)
    }
    func testDismissedOwnerCannotBeRevivedByForeground() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s)
        let model = f.model(s); model.appear(foreground: true); model.disappear(); model.setForeground(true)
        XCTAssertFalse(model.available); XCTAssertNil(model.open()); XCTAssertTrue(f.metadata.requests.isEmpty)
    }
    func testOldCloseAndSheetBindingCannotDismissNewPresentation() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s)
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        let old = try XCTUnwrap(model.presentation), binding = model.binding(old); model.close(old); await model.open()?.value
        let current = try XCTUnwrap(model.presentation); binding.wrappedValue = nil; model.close(old)
        XCTAssertEqual(model.presentation, current); XCTAssertNotNil(model.image); model.close(current)
    }
    func testListRefreshOrCurrentRowChangeHidesPrivatePixelsImmediately() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s)
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value; f.row = nil
        XCTAssertFalse(model.available); XCTAssertNil(model.image); XCTAssertNil(model.binding(try XCTUnwrap(model.presentation)).wrappedValue)
        model.disappear()
    }
    func testPreviewRevocationDoesNotRevokeListOrAnotherAsset() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s); let other = try f.previewGrant(s, id: 10)
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        f.root.ownMediaImagePreviewSelection.revoke(assetID: 9)
        XCTAssertNil(model.image); XCTAssertTrue(s.ownMediaReader.isAvailable); XCTAssertFalse(other.revoked); XCTAssertEqual(f.vault.token, "synthetic-private-preview"); model.disappear()
    }
    func testReplacementLeaseCannotBeRevokedByOldLateFailure() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s)
        let model = f.model(s); model.appear(foreground: true); var replacement: OwnMediaImagePreviewApproval?
        f.metadata.status = 401; f.metadata.after = { replacement = try? f.previewGrant(s) }
        await model.open()?.value; XCTAssertFalse(replacement?.revoked ?? true); XCTAssertEqual(s.account?.id, 7); XCTAssertNil(model.image); model.disappear()
    }
    func testCurrentMetadataDenialDoesNotLogOutOrWithdrawListPermission() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s); f.metadata.status = 403
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        XCTAssertNil(model.image); XCTAssertNil(s.ownMediaImagePreviewAccess.sourceRevision(f.asset))
        XCTAssertTrue(s.ownMediaReader.isAvailable); XCTAssertEqual(s.account?.id, 7); XCTAssertEqual(f.vault.token, "synthetic-private-preview")
        model.disappear()
    }
    func testOriginalGrantCannotBeReusedOrAssignedToAnotherAsset() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); let old = try f.previewGrant(s)
        XCTAssertThrowsError(try f.root.ownMediaImagePreviewSelection.replace(assetID: 10, with: old))
        f.root.ownMediaImagePreviewSelection.revoke(assetID: 9)
        XCTAssertThrowsError(try f.root.ownMediaImagePreviewSelection.replace(assetID: 9, with: old))
    }
    func testLateOldReadCannotPaintNewPresentation() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s)
        let model = f.model(s); model.appear(foreground: true); f.metadata.wait = true
        let oldTask = model.open(); for _ in 0..<100 { if f.metadata.pending != nil { break }; await Task.yield() }
        guard f.metadata.pending != nil else { model.disappear(); await oldTask?.value; XCTFail("Synthetic read was not admitted"); return }
        let old = try XCTUnwrap(model.presentation); model.close(old); await model.open()?.value
        let current = try XCTUnwrap(model.presentation); f.metadata.finish(); await oldTask?.value
        XCTAssertEqual(model.presentation, current); XCTAssertNotNil(model.image); XCTAssertEqual(f.bytes.requests.count, 1); model.close(current)
    }
    func testInvalidImageHasFailureAndOnlyExplicitRetryStartsAnotherRequest() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s); f.bytes.invalid = true
        let model = f.model(s); model.appear(foreground: true); await model.open()?.value
        XCTAssertEqual(model.phase, .failed); XCTAssertNil(model.image); XCTAssertEqual(f.metadata.requests.count, 1)
        f.bytes.invalid = false; await model.retry(try XCTUnwrap(model.presentation))?.value
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(f.metadata.requests.count, 2); model.disappear()
    }
    func testPerAssetExpiryClearsOnlyThatLeaseAndNeverClearsToken() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); let short = try f.previewGrant(s, duration: 0.5), other = try f.previewGrant(s, id: 10)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(short.revoked); XCTAssertFalse(other.revoked); XCTAssertTrue(s.ownMediaReader.isAvailable)
        XCTAssertNil(s.ownMediaImagePreviewAccess.sourceRevision(f.asset)); XCTAssertEqual(f.vault.token, "synthetic-private-preview")
    }
    func testAuthoritativeRoleChangeInvalidatesExistingOwnerPreview() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.previewGrant(s)
        let reader = try XCTUnwrap(s.makeOwnMediaImagePreviewReader(f.asset, metadata: f.metadata, imageReader: f.bytes))
        f.login.role = "merchant"; await s.refreshOwnAccount()
        XCTAssertFalse(reader.isConfigured); XCTAssertNil(s.ownMediaImagePreviewAccess.sourceRevision(f.asset)); XCTAssertTrue(f.metadata.requests.isEmpty)
    }
}
