import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class AvatarCheckedTransport: ProfileAvatarDispatching {
    var isConfigured = true
    var hold = false
    var skipForward = false
    var mutateRequest = false
    var failAfterForward = false
    var beforeForward: (() -> Void)?
    var afterForward: (() -> Void)?
    var onStart: ((URLRequest) -> Void)?
    var data = Data(#"{"code":200,"url":"https://avatar.invalid/square.jpg?sig=exact%2Bbytes"}"#.utf8)
    var status = 200
    private(set) var calls = 0
    private(set) var forwarded: [URLRequest] = []
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    func send(_ request: URLRequest, authorization: ProfileAvatarDispatchAuthorization) async throws -> (Data, Int) {
        calls += 1; let index = calls
        if hold { await withCheckedContinuation { waiting[index] = $0 } }
        beforeForward?()
        if !skipForward {
            var forwardingRequest = request
            if mutateRequest { forwardingRequest.setValue("wrong", forHTTPHeaderField: "Authorization") }
            try authorization.forward(forwardingRequest) { forwarded.append(forwardingRequest); onStart?(forwardingRequest) }
        }
        afterForward?()
        if failAfterForward { throw URLError(.networkConnectionLost) }
        return (data, status)
    }
    func waitForCall(_ index: Int = 1) async {
        for _ in 0..<200 where waiting[index] == nil { await Task.yield() }
        XCTAssertNotNil(waiting[index])
    }
    func resume(_ index: Int = 1) { waiting.removeValue(forKey: index)?.resume() }
}
@MainActor private final class AvatarPlainHTTP: HTTPTransport {
    var row: [String: Any] = ["id": 41, "nickname": "Name", "introduction": "intro", "avatar": " old avatar ", "wechat": " wechat \n", "casePics": "a;;b;", "tagIds": "9,2,9"]
    var onRead: (() -> Void)?
    var holdRead = false
    private var readContinuation: CheckedContinuation<Void, Never>?
    private(set) var reads = 0
    private(set) var plainSaves = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        if request.url?.path.hasSuffix("/info") == true {
            reads += 1
            if holdRead { await withCheckedContinuation { readContinuation = $0 } }
            onRead?(); return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": row]), 200)
        }
        plainSaves += 1; try apply(request)
        return (Data(#"{"code":200}"#.utf8), 200)
    }
    func waitForRead() async {
        for _ in 0..<200 where readContinuation == nil { await Task.yield() }
        XCTAssertNotNil(readContinuation)
    }
    func resumeRead() { holdRead = false; let continuation = readContinuation; readContinuation = nil; continuation?.resume() }
    func apply(_ request: URLRequest) throws {
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        for (key, item) in value { row[key == "name" ? "nickname" : key] = item }
    }
    func snapshot() throws -> ProfileEditSnapshot { try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: row)) }
}
@MainActor private final class AvatarHarness {
    let configuration = try! APIConfiguration(baseURL: URL(string: "https://profile.invalid/")!)
    var session = try! ProfileEditSession(accountID: 41, epoch: 1, token: "fixture-token", viewerRevision: 3)
    let approved: ProfileAvatarApproval
    var currentApproval: ProfileAvatarApproval?
    let upload = AvatarCheckedTransport(), save = AvatarCheckedTransport(), plain = AvatarPlainHTTP()
    var owner = true
    var revision: UInt64 = 1
    var draft = ProfileEditDraft(name: "Name", introduction: "intro")
    var storage: [String: Data] = [:]
    var failWrite = false
    var rejectPhase: ProfileAvatarJournalEntry.Phase?
    lazy var source = ProfileAvatarUploadClient(configuration: configuration, approval: approved, transport: upload,
        credentials: { [unowned self] in try? .init(session: session, namespace: "fixture-namespace", token: "fixture-token") },
        currentApproval: { [unowned self] in currentApproval })
    lazy var journal = StoredProfileAvatarJournal(read: { [unowned self] in storage[$0] }, write: { [unowned self] bytes, key in
        if failWrite { throw ProfileAvatarFailure.storage }
        if let rejectPhase, let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
           let entry = object["entry"] as? [String: Any], entry["phase"] as? String == rejectPhase.rawValue { throw ProfileAvatarFailure.storage }
        storage[key] = bytes
    })
    lazy var service = ProfileEditService(configuration: configuration, transport: plain, avatarTransport: save)
    lazy var coordinator = ProfileEditCoordinator(service: service, currentSession: { [unowned self] in session })
    init(picker: Bool = true) throws {
        approved = try .init(baseURL: configuration.baseURL, namespace: "fixture-namespace", accountID: 41, approvedOrigins: ["https://avatar.invalid"], nativePicker: picker)
        currentApproval = approved
        save.data = Data(#"{"code":200}"#.utf8)
        save.onStart = { [weak plain] request in try? plain?.apply(request) }
    }
    func target() throws -> ProfileAvatarTarget {
        let scope = try XCTUnwrap(source.scope(session: session, editorID: UUID(), lifetimeID: UUID()))
        return try .init(scope: scope, snapshot: plain.snapshot(), draft: draft, draftRevision: revision)
    }
    func image(width: Int = 2, height: Int = 2) throws -> RetainedSelectedImage { try .init(jpeg: Data([255, 216, 255, 1, 2, 3]), width: width, height: height) }
    func flow(target: ProfileAvatarTarget? = nil, withJournal: Bool = true) throws -> ProfileAvatarFlow {
        try .init(target: target ?? self.target(), source: source, journal: withJournal ? journal : nil,
            currentSnapshot: { [unowned self] in try? plain.snapshot() }, currentDraft: { [unowned self] in draft },
            currentRevision: { [unowned self] in revision }, ownerCurrent: { [unowned self] in owner },
            apply: { [unowned self] in draft = draft.stagingAvatar($0); revision += 1 })
    }
    func uploaded() async throws -> ProfileAvatarFlow {
        let flow = try flow(); flow.prepare(try image()); let review = try XCTUnwrap(flow.review)
        await flow.confirm(review); XCTAssertEqual(flow.state, .uploaded); return flow
    }
    func staged() async throws -> ProfileAvatarReplacement {
        let flow = try await uploaded(); flow.stage(); XCTAssertEqual(flow.state, .staged)
        return try XCTUnwrap(draft.avatarReplacement)
    }
}

@MainActor final class ProfileAvatarTests: XCTestCase {
    func testMissingApprovalOrTransportCannotFormScope() throws {
        let h = try AvatarHarness()
        let source = ProfileAvatarUploadClient(configuration: h.configuration)
        XCTAssertNil(source.scope(session: h.session, editorID: UUID(), lifetimeID: UUID()))
        XCTAssertEqual(h.upload.calls, 0)
    }
    func testNativePickerApprovalDefaultsOff() throws {
        let h = try AvatarHarness(picker: false); let target = try h.target()
        XCTAssertFalse(h.source.permitsPicker(target.scope)); XCTAssertFalse(try h.flow(target: target).canSelect)
    }
    func testChangedApprovalIdentityRevokesScopeEvenWithSameFields() throws {
        let h = try AvatarHarness(); let target = try h.target()
        h.currentApproval = try .init(baseURL: h.approved.baseURL, namespace: h.approved.namespace, accountID: 41, approvedOrigins: h.approved.approvedOrigins, nativePicker: true)
        XCTAssertFalse(h.source.isCurrent(target.scope))
    }
    func testCredentialTokenMustMatchExistingProfileSession() throws {
        let h = try AvatarHarness()
        XCTAssertThrowsError(try ProfileAvatarCredentials(session: h.session, namespace: "fixture", token: "different"))
    }
    func testMissingJournalDisablesSelectionAndUpload() throws {
        let h = try AvatarHarness(); let flow = try h.flow(withJournal: false)
        flow.prepare(try h.image()); XCTAssertNil(flow.review); XCTAssertFalse(flow.canSelect); XCTAssertEqual(flow.state, .unknown)
    }
    func testImageNeedsSquareCropAndExplicitUploadReview() async throws {
        let h = try AvatarHarness(); let flow = try h.flow()
        flow.prepare(try h.image(width: 4, height: 2)); XCTAssertNil(flow.review)
        flow.prepare(try h.image()); XCTAssertNotNil(flow.review)
        XCTAssertEqual(h.upload.calls, 0); XCTAssertNil(h.draft.avatarReplacement)
    }
    func testExactAvatarMultipartAndUnchangedSignedReference() async throws {
        let h = try AvatarHarness(); let flow = try await h.uploaded(); let request = try XCTUnwrap(h.upload.forwarded.first)
        XCTAssertEqual(request.url, h.configuration.baseURL.appendingPathComponent("api/common/uploadOSS"))
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"bizType\"\r\n\r\nimage_1_1")); XCTAssertTrue(body.contains("name=\"file\"; filename=\"avatar.jpg\""))
        XCTAssertFalse(body.contains("refundId")); XCTAssertFalse(body.contains("wechat"))
        XCTAssertEqual(flow.receipt?.reference, "https://avatar.invalid/square.jpg?sig=exact%2Bbytes")
        XCTAssertNil(h.draft.avatarReplacement); XCTAssertEqual(h.plain.plainSaves, 0)
    }
    func testForeignInsecureCredentialFragmentAndEmptyPathURLsRemainUnknown() async throws {
        for url in ["https://foreign.invalid/a.jpg", "http://avatar.invalid/a.jpg", "https://user@avatar.invalid/a.jpg", "https://avatar.invalid/a.jpg#fragment", "https://avatar.invalid/", " https://avatar.invalid/a.jpg"] {
            let h = try AvatarHarness(); h.upload.data = try JSONSerialization.data(withJSONObject: ["code": 200, "url": url])
            let flow = try h.flow(); flow.prepare(try h.image()); await flow.confirm(try XCTUnwrap(flow.review))
            XCTAssertEqual(flow.state, .unknown, url); XCTAssertNil(flow.receipt); XCTAssertNil(h.draft.avatarReplacement)
        }
    }
    func testOversizedResponseCannotMintReceipt() async throws {
        let h = try AvatarHarness(); h.upload.data = Data(repeating: 32, count: 65537)
        let flow = try h.flow(); flow.prepare(try h.image()); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertEqual(flow.state, .unknown); XCTAssertNil(flow.receipt)
    }
    func testTransportWithoutFinalForwardCannotMintReceipt() async throws {
        let h = try AvatarHarness(); h.upload.skipForward = true
        let flow = try h.flow(); flow.prepare(try h.image()); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertNil(flow.receipt); XCTAssertEqual(h.upload.forwarded.count, 0); XCTAssertEqual(flow.state, .failed)
    }
    func testTransportCannotMutateTheBoundRequestAtFinalForward() async throws {
        let h = try AvatarHarness(); h.upload.mutateRequest = true
        let flow = try h.flow(); flow.prepare(try h.image()); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertEqual(h.upload.forwarded.count, 0); XCTAssertNil(flow.receipt)
    }
    func testOwnerRetirementDuringTransportSuspensionPreventsUploadForward() async throws {
        let h = try AvatarHarness(); h.upload.hold = true; let flow = try h.flow(); flow.prepare(try h.image())
        let review = try XCTUnwrap(flow.review); let task = Task { await flow.confirm(review) }; await h.upload.waitForCall()
        h.owner = false; h.upload.resume(); await task.value
        XCTAssertEqual(h.upload.forwarded.count, 0); XCTAssertNil(flow.receipt); XCTAssertNil(h.draft.avatarReplacement)
    }
    func testRawDraftRevisionChangeDuringTransportSuspensionPreventsUploadForward() async throws {
        let h = try AvatarHarness(); h.upload.hold = true; let flow = try h.flow(); flow.prepare(try h.image())
        let review = try XCTUnwrap(flow.review); let task = Task { await flow.confirm(review) }; await h.upload.waitForCall()
        h.draft.name += " "; h.revision += 1; h.upload.resume(); await task.value
        XCTAssertEqual(h.upload.forwarded.count, 0); XCTAssertNil(h.draft.avatarReplacement)
    }
    func testScopeRevocationAtFinalForwardPreventsUpload() async throws {
        let h = try AvatarHarness(); h.upload.beforeForward = { h.currentApproval = nil }
        let flow = try h.flow(); flow.prepare(try h.image()); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertEqual(h.upload.forwarded.count, 0); XCTAssertNil(flow.receipt)
    }
    func testPostForwardOwnerRetirementPreservesPendingUnknown() async throws {
        let h = try AvatarHarness(); h.upload.afterForward = { h.owner = false }
        let flow = try h.flow(); flow.prepare(try h.image()); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertEqual(h.upload.forwarded.count, 1); XCTAssertEqual(flow.state, .unknown)
        XCTAssertEqual(try h.journal.entry(for: .init(scope: flow.target.scope))?.phase, .pending)
    }
    func testUnknownUploadStaysLockedAcrossNavigationAndSameAccountReauthentication() async throws {
        let h = try AvatarHarness(); h.upload.failAfterForward = true
        let flow = try h.flow(); flow.prepare(try h.image()); await flow.confirm(try XCTUnwrap(flow.review)); flow.close()
        h.session = try .init(accountID: 41, epoch: 2, token: "fixture-token", viewerRevision: 4)
        let replacement = try h.flow(); XCTAssertEqual(replacement.state, .unknown); XCTAssertFalse(replacement.canSelect)
        XCTAssertEqual(h.upload.forwarded.count, 1)
    }
    func testJournalReservationFailureNeverDispatches() async throws {
        let h = try AvatarHarness(); let flow = try h.flow(); flow.prepare(try h.image()); h.failWrite = true
        await flow.confirm(try XCTUnwrap(flow.review)); XCTAssertEqual(h.upload.calls, 0); XCTAssertEqual(flow.state, .unknown)
    }
    func testAcknowledgmentPersistenceFailureRetainsReceiptButCannotStage() async throws {
        let h = try AvatarHarness(); h.rejectPhase = .acknowledged
        let flow = try h.flow(); flow.prepare(try h.image()); await flow.confirm(try XCTUnwrap(flow.review))
        XCTAssertNotNil(flow.receipt); XCTAssertFalse(flow.canStage); XCTAssertEqual(flow.state, .unknown)
        XCTAssertNil(h.draft.avatarReplacement)
    }
    func testOnlyExplicitStageChangesDraftAndItDoesNotSaveProfile() async throws {
        let h = try AvatarHarness(); let flow = try await h.uploaded(); XCTAssertNil(h.draft.avatarReplacement)
        flow.stage(); let first = try XCTUnwrap(h.draft.avatarReplacement); flow.stage()
        XCTAssertEqual(h.draft.avatarReplacement, first); XCTAssertEqual(h.plain.plainSaves, 0); XCTAssertEqual(h.save.calls, 0)
    }
    func testChangedBaselineOrDraftCannotConsumeAcceptedReceipt() async throws {
        let h = try AvatarHarness(); let flow = try await h.uploaded(); let receipt = flow.receipt
        h.plain.row["wechat"] = "new raw value"; flow.stage()
        XCTAssertNil(h.draft.avatarReplacement); XCTAssertEqual(flow.receipt, receipt)
        XCTAssertEqual(try h.journal.entry(for: .init(scope: flow.target.scope))?.phase, .acknowledged)
    }
    func testFailedStageReservationLeavesOriginalDraftAndReceiptUntouched() async throws {
        let h = try AvatarHarness(); let flow = try await h.uploaded(); let before = h.draft, receipt = flow.receipt
        h.rejectPhase = .stageReserved; flow.stage()
        XCTAssertEqual(h.draft, before); XCTAssertEqual(flow.receipt, receipt); XCTAssertEqual(flow.state, .unknown)
    }
    func testJournalMetadataContainsNoReferenceCredentialOrSelectedBytes() async throws {
        let h = try AvatarHarness(); _ = try await h.staged()
        let text = String(decoding: try XCTUnwrap(h.storage.values.first), as: UTF8.self)
        for secret in ["fixture-token", "avatar.invalid", "old avatar", "wechat", "square.jpg"] { XCTAssertFalse(text.contains(secret)) }
        XCTAssertTrue(text.contains("locallyStaged"))
    }
    func testStagedPayloadChangesOnlyAvatarAndRetainsExactOtherRawFields() async throws {
        let h = try AvatarHarness(); _ = try await h.staged(); let snapshot = try h.plain.snapshot()
        let payload = try ProfileEditPayload(draft: h.draft, preserving: snapshot)
        XCTAssertEqual(payload.avatar, "https://avatar.invalid/square.jpg?sig=exact%2Bbytes")
        XCTAssertEqual(Data(payload.wechat.utf8), Data(snapshot.wechat.utf8)); XCTAssertEqual(Data(payload.casePics.utf8), Data(snapshot.casePics.utf8))
        XCTAssertEqual(Data(payload.tagIds.utf8), Data(snapshot.tagIds.utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: String])
        XCTAssertEqual(Set(object.keys), ["name", "introduction", "avatar", "wechat", "casePics", "tagIds"])
    }
    func testOrdinaryPayloadStillPreservesRawAvatarWithoutProof() throws {
        let h = try AvatarHarness(); let payload = try ProfileEditPayload(draft: .init(name: " Changed "), preserving: h.plain.snapshot())
        XCTAssertEqual(payload.name, "Changed"); XCTAssertEqual(payload.avatar, " old avatar "); XCTAssertNil(payload.avatarReplacement)
    }
    func testOrdinarySaveRejectsImagePayloadInsteadOfUsingPlainTransport() async throws {
        let h = try AvatarHarness(); _ = try await h.staged(); let payload = try ProfileEditPayload(draft: h.draft, preserving: h.plain.snapshot())
        do { try await h.service.save(payload, token: "fixture-token"); XCTFail() } catch ProfileEditWriteError.notSent {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(h.plain.plainSaves, 0); XCTAssertEqual(h.save.calls, 0)
    }
    func testImageSaveWithoutCheckedTransportIsDisabled() async throws {
        let h = try AvatarHarness(); _ = try await h.staged(); let service = ProfileEditService(configuration: h.configuration, transport: h.plain)
        let payload = try ProfileEditPayload(draft: h.draft, preserving: h.plain.snapshot())
        do { try await service.saveAvatar(payload, token: "fixture-token", isCurrent: { true }); XCTFail() } catch ProfileEditWriteError.notSent {} catch { XCTFail("Unexpected error") }
        XCTAssertFalse(service.avatarSavingAvailable); XCTAssertEqual(h.plain.plainSaves, 0)
    }
    func testImageSaveOwnerChangeDuringFinalTransportSuspensionPreventsForward() async throws {
        let h = try AvatarHarness(); _ = try await h.staged(); h.save.hold = true
        let payload = try ProfileEditPayload(draft: h.draft, preserving: h.plain.snapshot())
        let task = Task { try await h.service.saveAvatar(payload, token: "fixture-token", isCurrent: { h.owner }) }
        await h.save.waitForCall(); h.owner = false; h.save.resume()
        do { try await task.value; XCTFail() } catch ProfileEditWriteError.notSent {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(h.save.forwarded.count, 0)
    }
    func testImageSaveRetiredAfterForwardIsUnknown() async throws {
        let h = try AvatarHarness(); _ = try await h.staged(); h.save.afterForward = { h.owner = false }
        let payload = try ProfileEditPayload(draft: h.draft, preserving: h.plain.snapshot())
        do { try await h.service.saveAvatar(payload, token: "fixture-token", isCurrent: { h.owner }); XCTFail() } catch ProfileEditWriteError.outcomeUnknown {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(h.save.forwarded.count, 1)
    }
    func testImageSaveCapabilityRevokedDuringSuspendedTransportCannotForward() async throws {
        let h = try AvatarHarness(); _ = try await h.staged(); h.save.hold = true
        let payload = try ProfileEditPayload(draft: h.draft, preserving: h.plain.snapshot())
        let task = Task { try await h.service.saveAvatar(payload, token: "fixture-token", isCurrent: { h.owner }) }
        await h.save.waitForCall(); h.save.isConfigured = false; h.save.resume()
        do { try await task.value; XCTFail() } catch ProfileEditWriteError.notSent {} catch { XCTFail("Unexpected error") }
        XCTAssertTrue(h.owner); XCTAssertEqual(h.save.forwarded.count, 0); XCTAssertEqual(h.plain.plainSaves, 0)
    }
    func testCoordinatorRejectsAvatarWithoutOwnerValidity() async throws {
        let h = try AvatarHarness(); _ = try await h.staged(); await h.coordinator.load(); await h.coordinator.prepare(h.draft)
        XCTAssertNil(h.coordinator.confirmation); XCTAssertEqual(h.coordinator.messageKey, "profile.avatar.changed")
    }
    func testCoordinatorOwnerRevocationDuringFreshReadCannotProduceReview() async throws {
        let h = try AvatarHarness(); _ = try await h.staged(); await h.coordinator.load()
        h.plain.onRead = { h.owner = false }
        await h.coordinator.prepare(h.draft, avatarValidity: .init(current: { h.owner }))
        XCTAssertNil(h.coordinator.confirmation); XCTAssertEqual(h.save.calls, 0)
    }
    func testCoordinatorPassesDynamicOwnerValidityToFinalSaveBoundary() async throws {
        let h = try AvatarHarness(); _ = try await h.staged(); await h.coordinator.load()
        await h.coordinator.prepare(h.draft, avatarValidity: .init(current: { h.owner }))
        let review = try XCTUnwrap(h.coordinator.confirmation); h.save.hold = true
        let task = Task { await h.coordinator.save(review) }; await h.save.waitForCall()
        h.owner = false; h.save.resume(); await task.value
        XCTAssertEqual(h.save.forwarded.count, 0); XCTAssertFalse(h.coordinator.isLocked)
    }
    func testPostConfirmationReadRejectsCanonicallyEquivalentByteChangeForEveryPreservedField() async throws {
        for field in ["nickname", "introduction", "avatar", "wechat", "casePics", "tagIds"] {
            let h = try AvatarHarness()
            h.plain.row[field] = "\u{00E9}"
            _ = try await h.staged(); await h.coordinator.load()
            await h.coordinator.prepare(h.draft, avatarValidity: .init(current: { h.owner }))
            let review = try XCTUnwrap(h.coordinator.confirmation)
            let original = try h.plain.snapshot()
            h.plain.holdRead = true
            let task = Task { await h.coordinator.save(review) }
            await h.plain.waitForRead()
            h.plain.row[field] = "e\u{0301}"
            let latest = try h.plain.snapshot()
            XCTAssertEqual(latest, original, field)
            XCTAssertNotEqual(ProfileAvatarExact.snapshot(latest), ProfileAvatarExact.snapshot(original), field)
            h.plain.resumeRead(); await task.value
            XCTAssertEqual(h.save.calls, 0, field); XCTAssertEqual(h.save.forwarded.count, 0, field)
            XCTAssertEqual(h.plain.plainSaves, 0, field); XCTAssertFalse(h.coordinator.isLocked, field)
            XCTAssertEqual(h.coordinator.messageKey, "profile.edit.changed", field)
            XCTAssertEqual(ProfileAvatarExact.snapshot(try XCTUnwrap(h.coordinator.snapshot)), ProfileAvatarExact.snapshot(latest), field)
            XCTAssertEqual(h.draft.avatarReplacement, review.payload.avatarReplacement, field)
        }
    }
    func testAcknowledgedImageSaveUsesExistingMatchingReadbackToUnlock() async throws {
        let h = try AvatarHarness(); _ = try await h.staged(); await h.coordinator.load()
        await h.coordinator.prepare(h.draft, avatarValidity: .init(current: { h.owner }))
        await h.coordinator.save(try XCTUnwrap(h.coordinator.confirmation))
        XCTAssertEqual(h.save.forwarded.count, 1); XCTAssertEqual(h.plain.plainSaves, 0)
        XCTAssertFalse(h.coordinator.isLocked); XCTAssertEqual(h.coordinator.messageKey, "profile.edit.saved")
    }
    func testUnacknowledgedMatchingImageReadbackStaysLockedAcrossEpoch() async throws {
        let h = try AvatarHarness(); _ = try await h.staged(); await h.coordinator.load(); h.save.failAfterForward = true
        await h.coordinator.prepare(h.draft, avatarValidity: .init(current: { h.owner }))
        await h.coordinator.save(try XCTUnwrap(h.coordinator.confirmation))
        XCTAssertTrue(h.coordinator.isLocked); XCTAssertEqual(h.coordinator.messageKey, "profile.edit.readbackUnconfirmed")
        h.session = try .init(accountID: 41, epoch: 2, token: "fixture-token", viewerRevision: 4)
        h.coordinator.synchronizeSession(); await h.coordinator.load()
        XCTAssertTrue(h.coordinator.isLocked); XCTAssertEqual(h.save.forwarded.count, 1)
    }
    func testOrdinaryTextSaveStillUsesOnlyOriginalTransportAndReconciliation() async throws {
        let h = try AvatarHarness(); await h.coordinator.load(); await h.coordinator.prepare(.init(name: "Other", introduction: "body"))
        await h.coordinator.save(try XCTUnwrap(h.coordinator.confirmation))
        XCTAssertEqual(h.plain.plainSaves, 1); XCTAssertEqual(h.save.calls, 0); XCTAssertFalse(h.coordinator.isLocked)
        XCTAssertEqual(h.coordinator.snapshot?.avatar, " old avatar "); XCTAssertEqual(h.coordinator.messageKey, "profile.edit.saved")
    }
    func testDispatchAuthorizationIsExactAndSingleUse() throws {
        var request = URLRequest(url: URL(string: "https://profile.invalid/api/user/update")!); request.httpMethod = "POST"
        let authorization = ProfileAvatarDispatchAuthorization(request: request, validity: { true }); var starts = 0
        try authorization.forward(request) { starts += 1 }
        XCTAssertThrowsError(try authorization.forward(request) { starts += 1 }); XCTAssertEqual(starts, 1)
    }
}
