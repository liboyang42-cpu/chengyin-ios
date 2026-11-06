import Foundation
import XCTest
@testable import Questify
@MainActor private final class ApprovedLinkVault: AppTokenStorage {
    var token: String? = "synthetic-approved-link"
    func read() throws -> String? { token }; func write(_ value: String) throws { token = value }; func clear() throws { token = nil }
}
@MainActor private final class ApprovedLinkLogin: HTTPTransport {
    var requests: [URLRequest] = [], role = "player"
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
    }
}
@MainActor private final class ApprovedLinkListBox { var approval: OwnMediaReadApproval? }
@MainActor private final class ApprovedLinkMetadata: OwnMediaApprovedLinkDispatching {
    var requests: [URLRequest] = [], status = 200, after: (() -> Void)?, wait = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    var value: (Data, Int) { (Data(#"{"code":200,"data":{"assetId":9,"reviewState":"APPROVED","mediaType":"IMAGE","url":"https://approved-host.example.test/a.jpg?Signature=a%2Bb"}}"#.utf8), status) }
    func send(_ request: URLRequest, authorization: OwnMediaApprovedLinkAuthorization) async throws -> (Data, Int) {
        try authorization.forward(request, cancel: {}) { requests.append(request) }; after?()
        if wait { wait = false; return try await withCheckedThrowingContinuation { pending = $0 } }; return value
    }
    func finish(status override: Int? = nil) { let p = pending; pending = nil; let result = value; p?.resume(returning: (result.0, override ?? result.1)) }
}
@MainActor private final class ApprovedLinkHost {
    let root: AppCompositionRoot, defaults: UserDefaults, suite = "approved-link-" + UUID().uuidString
    let vault = ApprovedLinkVault(), login = ApprovedLinkLogin(), listBox = ApprovedLinkListBox(), metadata = ApprovedLinkMetadata()
    let asset = OwnMediaAsset(id: 9, reviewState: .approved, reviewReason: "", mediaType: .image)
    var row: OwnMediaAsset?, made = 0, copies: [String] = [], copyFails = false
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let d = try ReviewedAppDeployment(market: .china, baseURL: "https://approved-api.example.test/native", approvedBaseURLs: [.china: ["https://approved-api.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.approved.link." + UUID().uuidString.lowercased(), realm: "synthetic")
        let login = login, vault = vault, box = listBox
        root = .init(deployment: .reviewed(d), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { login })
        root.ownMediaReadApproval = { context in box.approval.flatMap { $0.matches(context) ? $0 : nil } }; row = asset
    }
    func boot() async -> AppSession { let s = root.makeSession(); await s.bootstrap(); login.requests = []; return s }
    func listGrant(_ s: AppSession, status: Bool = false) throws {
        let context = try XCTUnwrap(s.ownMediaApprovedLinkIdentity(asset).context)
        listBox.approval = try .init(context: context, expiresAt: Date().addingTimeInterval(600), allowsStatus: status)
    }
    func grant(_ s: AppSession, id: Int64 = 9, duration: TimeInterval = 600) throws -> OwnMediaApprovedLinkApproval {
        let identity = s.ownMediaApprovedLinkIdentity(asset)
        let value = try OwnMediaApprovedLinkApproval(context: XCTUnwrap(identity.context), viewerRevision: identity.viewerRevision,
            assetID: id, approvedOrigins: ["https://approved-host.example.test"], expiresAt: Date().addingTimeInterval(duration))
        try root.ownMediaApprovedLinkSelection.replace(assetID: id, with: value); return value
    }
    func model(_ s: AppSession) -> OwnMediaApprovedLinkCopyModel {
        let access = OwnMediaApprovedLinkAccess(sourceRevision: s.ownMediaApprovedLinkAccess.sourceRevision, makeReader: { [unowned self] asset in
            made += 1; return s.makeOwnMediaApprovedLinkReader(asset, transport: metadata)
        })
        return .init(asset: asset, access: access, currentAsset: { [unowned self] in row }, copyText: { [unowned self] value in
            if copyFails { throw OwnMediaApprovedLinkFailure.unavailable }; copies.append(value)
        })
    }
    func cleanup() { listBox.approval?.revoke(); root.ownMediaApprovedLinkSelection.revoke(assetID: 9); root.ownMediaApprovedLinkSelection.revoke(assetID: 10); metadata.finish(); defaults.removePersistentDomain(forName: suite) }
}
@MainActor final class OwnMediaApprovedLinkHostTests: XCTestCase {
    private func host() throws -> ApprovedLinkHost { let f = try ApprovedLinkHost(); addTeardownBlock { @MainActor in f.cleanup() }; return f }
    func testDefaultNoListOrCopyGrantCannotReadOrDeliver() async throws {
        let f = try host(), s = await f.boot(); XCTAssertNil(s.ownMediaApprovedLinkAccess.sourceRevision(f.asset)); XCTAssertNil(s.makeOwnMediaApprovedLinkReader(f.asset, transport: f.metadata))
        let model = f.model(s); model.appear(foreground: true); XCTAssertNil(model.copy()); XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.copies.isEmpty)
    }
    func testListAndStatusPermissionsCannotGrantCopy() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s, status: true)
        XCTAssertTrue(s.ownMediaReader.isAvailable); XCTAssertTrue(s.ownMediaReader.isStatusAvailable); XCTAssertNil(s.ownMediaApprovedLinkAccess.sourceRevision(f.asset))
        _ = try f.grant(s); XCTAssertNotNil(s.ownMediaApprovedLinkAccess.sourceRevision(f.asset)); f.listBox.approval?.revoke(); XCTAssertNil(s.makeOwnMediaApprovedLinkReader(f.asset, transport: f.metadata))
    }
    func testImagePermissionCannotGrantCopyAndCopyRevocationCannotRevokeImage() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s)
        let identity = s.ownMediaImagePreviewIdentity(f.asset)
        let preview = try OwnMediaImagePreviewApproval(context: XCTUnwrap(identity.context), viewerRevision: identity.viewerRevision, assetID: 9,
            approvedOrigins: ["https://approved-host.example.test"], expiresAt: Date().addingTimeInterval(600))
        try f.root.ownMediaImagePreviewSelection.replace(assetID: 9, with: preview)
        XCTAssertNil(s.ownMediaApprovedLinkAccess.sourceRevision(f.asset)); _ = try f.grant(s); f.root.ownMediaApprovedLinkSelection.revoke(assetID: 9)
        XCTAssertFalse(preview.revoked); XCTAssertNotNil(s.ownMediaImagePreviewAccess.sourceRevision(f.asset)); f.root.ownMediaImagePreviewSelection.revoke(assetID: 9)
    }
    func testAppearanceAndForegroundNeverFetchOrCopy() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s)
        let model = f.model(s); model.appear(foreground: true); model.setForeground(false); model.setForeground(true)
        XCTAssertEqual(f.made, 0); XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.copies.isEmpty); model.disappear()
    }
    func testExplicitCopyUsesIndependentTransportAndMemorySinkOnce() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s)
        let model = f.model(s); model.appear(foreground: true); let task = model.copy(); XCTAssertNil(model.copy()); await task?.value
        XCTAssertEqual(f.copies, ["https://approved-host.example.test/a.jpg?Signature=a%2Bb"]); XCTAssertEqual(f.metadata.requests.count, 1)
        XCTAssertTrue(f.login.requests.isEmpty); XCTAssertEqual(model.visiblePhase, .copied); model.disappear()
    }
    func testQueuedActionCancelledBeforeAdmissionMakesNoRequest() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s)
        let model = f.model(s); model.appear(foreground: true); let task = model.copy(); model.disappear(); await task?.value
        XCTAssertTrue(f.metadata.requests.isEmpty); XCTAssertTrue(f.copies.isEmpty)
    }
    func testBackgroundBeforeResponseCannotCopyOrAutoRetry() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s)
        let model = f.model(s); model.appear(foreground: true); f.metadata.after = { model.setForeground(false) }; await model.copy()?.value
        XCTAssertTrue(f.copies.isEmpty); model.setForeground(true); XCTAssertEqual(f.metadata.requests.count, 1); XCTAssertEqual(model.visiblePhase, .idle); model.disappear()
    }
    func testRowReplacementBeforeResponseCannotCopy() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s)
        let model = f.model(s); model.appear(foreground: true); f.metadata.after = { f.row = .init(id: 9, reviewState: .hold, reviewReason: "Changed", mediaType: .image) }; await model.copy()?.value
        XCTAssertFalse(model.available); XCTAssertTrue(f.copies.isEmpty); model.disappear()
    }
    func testListRefreshOrWithdrawalBeforeResponseCannotCopy() async throws {
        for mode in 0..<2 { let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s)
            let model = f.model(s); model.appear(foreground: true); f.metadata.after = { if mode == 0 { f.row = nil } else { f.listBox.approval?.revoke() } }; await model.copy()?.value
            XCTAssertTrue(f.copies.isEmpty); XCTAssertEqual(model.visiblePhase, .idle); model.disappear()
        }
    }
    func testCopiedValueIsNotRecalledOnBackgroundOrSourceRevocation() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s)
        let model = f.model(s); model.appear(foreground: true); await model.copy()?.value; let copied = f.copies
        model.setForeground(false); f.root.ownMediaApprovedLinkSelection.revoke(assetID: 9); model.disappear()
        XCTAssertEqual(f.copies, copied); XCTAssertEqual(copied.count, 1); XCTAssertEqual(model.visiblePhase, .idle)
    }
    func testCopyFailureRequiresNewExplicitActionAndNoAutoRetry() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s); f.copyFails = true
        let model = f.model(s); model.appear(foreground: true); await model.copy()?.value
        XCTAssertEqual(model.visiblePhase, .failed); XCTAssertTrue(f.copies.isEmpty); XCTAssertEqual(f.metadata.requests.count, 1)
        f.copyFails = false; await model.copy()?.value; XCTAssertEqual(model.visiblePhase, .copied); XCTAssertEqual(f.metadata.requests.count, 2); model.disappear()
    }
    func testLateOldReadCannotCopyOrChangeNewActionFeedback() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s)
        let model = f.model(s); model.appear(foreground: true); f.metadata.wait = true; let old = model.copy()
        for _ in 0..<100 { if f.metadata.pending != nil { break }; await Task.yield() }
        guard f.metadata.pending != nil else { model.disappear(); await old?.value; XCTFail("Synthetic admission failed"); return }
        model.cancel(); await model.copy()?.value; f.metadata.finish(status: 403); await old?.value
        XCTAssertEqual(f.copies.count, 1); XCTAssertEqual(model.visiblePhase, .copied); XCTAssertNotNil(s.ownMediaApprovedLinkAccess.sourceRevision(f.asset)); model.disappear()
    }
    func testCurrentUnauthorizedOnlyRevokesSelectedAssetWithoutLoggingOut() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); let own = try f.grant(s), other = try f.grant(s, id: 10); f.metadata.status = 403
        let model = f.model(s); model.appear(foreground: true); await model.copy()?.value
        XCTAssertTrue(own.revoked); XCTAssertFalse(other.revoked); XCTAssertTrue(s.ownMediaReader.isAvailable); XCTAssertEqual(s.account?.id, 7)
        XCTAssertEqual(f.vault.token, "synthetic-approved-link"); XCTAssertTrue(f.copies.isEmpty); model.disappear()
    }
    func testReplacedSourceCannotUseOrRevokeOldIssuance() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); let old = try f.grant(s), model = f.model(s); model.appear(foreground: true)
        let new = try f.grant(s); XCTAssertTrue(old.revoked); XCTAssertFalse(model.available); XCTAssertNil(model.copy())
        XCTAssertThrowsError(try f.root.ownMediaApprovedLinkSelection.replace(assetID: 9, with: old)); XCTAssertFalse(new.revoked); model.disappear()
    }
    func testPerAssetExpiryDoesNotRevokeOtherAssetOrAccount() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); let short = try f.grant(s, duration: 0.5), other = try f.grant(s, id: 10)
        try await Task.sleep(nanoseconds: 600_000_000); XCTAssertTrue(short.revoked); XCTAssertFalse(other.revoked); XCTAssertEqual(f.vault.token, "synthetic-approved-link")
        XCTAssertNil(s.ownMediaApprovedLinkAccess.sourceRevision(f.asset)); XCTAssertTrue(s.ownMediaReader.isAvailable)
    }
    func testAuthoritativeRoleChangeRetiresOldOwner() async throws {
        let f = try host(), s = await f.boot(); try f.listGrant(s); _ = try f.grant(s)
        let reader = try XCTUnwrap(s.makeOwnMediaApprovedLinkReader(f.asset, transport: f.metadata)); f.login.role = "merchant"; await s.refreshOwnAccount()
        XCTAssertFalse(reader.isConfigured); XCTAssertNil(s.ownMediaApprovedLinkAccess.sourceRevision(f.asset)); XCTAssertTrue(f.metadata.requests.isEmpty)
    }
}
