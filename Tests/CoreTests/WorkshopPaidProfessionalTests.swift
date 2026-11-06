import XCTest
@testable import QuestifyCore

@MainActor enum WorkshopProfessionalFixture {
    static let instant = "2026-10-06T00:00:00Z"
    static func data(_ value: [String: Any]) throws -> Data { try WorkshopPaidTextFixture.data(value) }
    static func decode<T: Decodable>(_ type: T.Type, _ value: [String: Any]) throws -> T { try WorkshopPaidTextFixture.decode(type, value) }
    static var target: [String: Any] { ["topicId":501,"name":"Synthetic city target","productType":1,"mode":"CITY_ORIENTATION","routeConfigVersion":4,"ownerModeFingerprint":String(repeating:"d",count:64),"fingerprintProfile":"W18_CONTENT_OWNER_MODE_V1","materializationStatus":"PROTECTED_TEMPLATE_ADAPTER_REQUIRED"] }
    static var draft: [String: Any] { ["targetDraftId":91,"targetRevision":2,"businessType":"TOPIC","targetPayloadHash":String(repeating:"e",count:64),"mode":"UNRESOLVED","destinationKind":"W18_PRIVATE_COMPONENT_ONLY"] }
    static func command() throws -> WorkshopPaidProfessionalCommand {
        try .init(reference: WorkshopPaidTextFixture.reference(), body: decode(WorkshopPaidInstalledText.self, WorkshopPaidTextFixture.body()),
                  currentDraft: decode(WorkshopPaidInstallTarget.self, draft), target: decode(WorkshopPaidProfessionalTarget.self, target), confirmedMode: .city,
                  requestID: UUID(uuidString:"00000000-0000-4000-8000-000000000002")!)
    }
    static func operation(_ command: WorkshopPaidProfessionalCommand, state: String) -> [String: Any] {
        var v: [String: Any] = ["schema":"w18-paid-professional-operation-v1","scope":"OWNER_OPERATION_METADATA_ONLY","requestId":command.requestId,"state":state,"safeToReplace":["REJECTED","CANCELLED"].contains(state)]
        if state == "NOT_FOUND" { return v }
        v["commandHash"] = command.commandHash; v["createdAt"] = instant; v["updatedAt"] = instant
        v["rejectionCode"] = state == "REJECTED" ? "CURRENT_SOURCE_OR_TARGET_UNAVAILABLE" as Any : NSNull(); v["creation"] = NSNull()
        if state == "CREATED" {
            v["creation"] = ["schema":"w18-paid-professional-materialization-status-v1","scope":"OWNER_HISTORICAL_CREATION_REFERENCE_ONLY","requestId":command.requestId,"state":"CREATION_COMMITTED","templateId":700,"targetTopicId":command.targetTopicId,"ownedDraftId":command.ownedDraftId,"confirmedMode":command.confirmedMode.rawValue,"licenseId":command.licenseId,"purchasedVersionId":command.purchasedVersionId,"templateContentHash":String(repeating:"f",count:64),"createdAt":instant,"currentTemplateState":"NOT_CHECKED","currentUseAuthority":"NOT_GRANTED_BY_HISTORY"] as [String: Any]
        }
        return v
    }
    static func record(_ c: WorkshopPaidProfessionalCommand) throws -> [String: Any] { ["operationKey":String(repeating:"a",count:64),"commandHash":c.commandHash,"createdAt":instant,"command":try JSONSerialization.jsonObject(with:c.wireData())] }
}
@MainActor final class WorkshopPaidProfessionalTests: XCTestCase {
    typealias F = WorkshopProfessionalFixture
    @MainActor private final class Memory: TemplateAuthoringStorage {
        var values: [String: Data] = [:], failWrite = false
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { if failWrite { throw WorkshopPaidProfessionalIssue.storageUnavailable }; values[key] = data }
        func remove(_ key: String) throws { values.removeValue(forKey:key) }
    }
    @MainActor private final class Wire: HTTPTransport, WorkshopPaidProfessionalMutationTransport {
        let context: RuntimeDependencyContext
        var requests: [URLRequest] = [], writes = 0, delay = false, commitThenThrow = false
        var target = F.target, detailTarget: [String: Any]?, status = "NOT_FOUND", writeState = "CREATED"
        var recorded: WorkshopPaidProfessionalCommand?, emptyNextPage = false, nextPages = 0
        var continuationFailure: WorkshopPaidProfessionalIssue?
        var targetPages: [[String: Any]] = [], historyPages: [[String: Any]] = []
        var suspended: CheckedContinuation<(Data, Int), Never>?
        init(_ context: RuntimeDependencyContext) { self.context = context }
        func wait() async { for _ in 0..<1000 { if suspended != nil { return }; await Task.yield() }; XCTFail("Expected suspended real service transport") }
        func resume401() { let old = suspended; suspended = nil; old?.resume(returning:(Data(),401)) }
        private func envelope(_ value: [String: Any]) throws -> (Data, Int) { (try F.data(["code":200,"data":value]),200) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if delay { delay = false; return await withCheckedContinuation { suspended = $0 } }
            let path = request.url!.path
            let fields = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
            if fields?["beforeTopicId"] != nil || fields?["beforeOperationKey"] != nil {
                if let failure = continuationFailure { continuationFailure = nil; throw failure }
            }
            if path.hasSuffix("/professional-targets/list"), !targetPages.isEmpty { return try envelope(targetPages.removeFirst()) }
            if path.hasSuffix("/professional-operations/history"), !historyPages.isEmpty { return try envelope(historyPages.removeFirst()) }
            if path.hasSuffix("/installed-text/detail") { return (try WorkshopPaidTextFixture.envelope(),200) }
            if path.hasSuffix("/install/targets") { return try envelope(["schema":"w18-paid-install-targets-v1","scope":"OWNER_DRAFT_METADATA_ONLY","licenseId":"w18-paid-11","checkedAt":F.instant,"items":[F.draft],"hasMore":false,"nextBeforeDraftId":NSNull()]) }
            if path.hasSuffix("/professional-targets/list") { return try envelope(["schema":"w18-owned-professional-topic-targets-v1","scope":"INDIVIDUAL_CONTENT_OWNER_AND_PUBLISHER_METADATA_ONLY","licenseId":"w18-paid-11","checkedAt":F.instant,"items":[target],"hasMore":false,"nextBeforeTopicId":NSNull()]) }
            if path.hasSuffix("/professional-targets/detail") { return try envelope(detailTarget ?? target) }
            if path.hasSuffix("/professional-operations/history") {
                let next = emptyNextPage && nextPages == 0; nextPages += 1
                return try envelope(["schema":"w18-paid-professional-operation-history-v1","scope":"OWNER_OPERATION_INTENT_REFERENCES_ONLY","licenseId":"w18-paid-11","items":recorded.map { [try! F.record($0)] } ?? [],"scannedCount":next ? 50 : recorded == nil ? 0 : 1,"hasMore":next,"nextBeforeOperationKey":next ? String(repeating:"b",count:64) as Any : NSNull()])
            }
            if path.hasSuffix("/professional-operations/status") {
                let value = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                if let recorded { return try envelope(F.operation(recorded,state:status)) }
                var c = try JSONSerialization.jsonObject(with:F.command().wireData()) as! [String: Any]; c["requestId"] = value["requestId"]
                return try envelope(F.operation(try F.decode(WorkshopPaidProfessionalCommand.self,c),state:"NOT_FOUND"))
            }
            throw WorkshopPaidProfessionalIssue.disabled
        }
        func sendWorkshopPaidProfessional(_ request: URLRequest, authorization: WorkshopPaidProfessionalDispatchAuthorization) async throws -> (Data, Int) {
            try authorization.consume(request,context:context,revision:authorization.approvalRevision)
            let command = try WorkshopPaidInstallWire.decode(WorkshopPaidProfessionalCommand.self,data:request.httpBody!)
            requests.append(request); writes += 1; recorded = command
            if request.url?.lastPathComponent == "cancel" { if status != "CREATED" { status = "CANCELLED" } } else { status = writeState }
            if delay { delay = false; return await withCheckedContinuation { suspended = $0 } }
            if commitThenThrow { throw WorkshopPaidProfessionalIssue.unavailable }
            return try envelope(F.operation(command,state:status))
        }
    }
    @MainActor private final class Harness {
        let context: RuntimeDependencyContext, wire: Wire, memory = Memory(), reference: WorkshopPaidInstalledTextReference
        var current: RuntimeDependencyContext?, read: WorkshopPaidProfessionalReadApproval?, write: WorkshopPaidProfessionalWriteApproval?, unauthorized = 0
        let bodyApproval: WorkshopPaidInstalledTextApproval, installApproval: WorkshopPaidInstallApproval
        lazy var lease = ContentDraftSessionLease(context:context,current:{[weak self] in self?.current})
        lazy var store = try! WorkshopPaidProfessionalPendingStore(storage:memory,context:context,reference:reference)
        lazy var service = WorkshopPaidProfessionalService(api:try! APIConfiguration(baseURL:context.baseURL),transport:wire,lease:lease,readApproval:read,currentReadApproval:{[weak self] in self?.read},writeApproval:write,currentWriteApproval:{[weak self] in self?.write},onUnauthorized:{[weak self] _ in self?.unauthorized += 1})
        lazy var preparation = WorkshopPaidProfessionalPreparation(bodyReader:WorkshopPaidInstalledTextService(api:try! APIConfiguration(baseURL:context.baseURL),transport:wire,lease:lease,approval:bodyApproval,currentApproval:{[weak self] in self?.bodyApproval},onUnauthorized:{[weak self] _ in self?.unauthorized += 1}), installReader:WorkshopPaidInstallService(api:try! APIConfiguration(baseURL:context.baseURL),transport:wire,lease:lease,approval:installApproval,currentApproval:{[weak self] in self?.installApproval}))
        lazy var controller = WorkshopPaidProfessionalController(reference:reference,service:service,preparation:preparation,store:store,lease:lease)
        init(read: Bool = true, write: Bool = true) throws {
            context = .init(market:.china,baseURL:URL(string:"https://example.com/native")!,role:"player",session:try .init(accountID:7,epoch:1,namespace:"synthetic",token:"synthetic-test-7",role:"player"))
            current = context; wire = Wire(context); reference = try WorkshopPaidTextFixture.reference()
            self.read = read ? try .init(context:context,expiresAt:.distantFuture) : nil; self.write = write ? try .init(context:context,expiresAt:.distantFuture) : nil
            bodyApproval = try .init(context:context,expiresAt:.distantFuture); installApproval = try .init(context:context,expiresAt:.distantFuture)
        }
        func appear(_ a: WorkshopPaidProfessionalAppearance) async throws { await (try XCTUnwrap(controller.appear(a)))() }
        func review(_ a: WorkshopPaidProfessionalAppearance) async throws {
            try await appear(a); await (try XCTUnwrap(controller.offerNewReview(a)))()
            await (try XCTUnwrap(controller.offerSelect(XCTUnwrap(controller.targets.first),displayed:a)))()
            XCTAssertEqual(controller.phase,.review)
        }
    }
    func testActualServiceReviewSubmitCreatesDistinctTemplateAndRetainsIntentUntilAcknowledged() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a)
        XCTAssertEqual(h.controller.body?.sourceFields["merchantGuide"]," 保密说明 ")
        await (try XCTUnwrap(h.controller.offerSubmit(a,confirmedMode:.city)))()
        XCTAssertEqual(h.wire.writes,1); XCTAssertEqual(h.controller.operation?.creation?.templateId,700); XCTAssertEqual(h.controller.operation?.state,.created)
        XCTAssertNotNil(try h.store.load()); XCTAssertNil(h.controller.body)
        await (try XCTUnwrap(h.controller.offerAcknowledge(a)))(); XCTAssertNil(try h.store.load()); XCTAssertEqual(h.controller.phase,.history)
    }
    func testDefaultApprovalCausesZeroRequests() async throws {
        let h = try Harness(read:false,write:false); try await h.appear(.init()); XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertEqual(h.controller.issue,.disabled)
    }
    func testQueuedAppearAfterBackDoesNotResurrectAndFreshReopenWorks() async throws {
        let h = try Harness(), old = WorkshopPaidProfessionalAppearance(); let queued = try XCTUnwrap(h.controller.appear(old))
        h.controller.close(old); await queued(); XCTAssertTrue(h.wire.requests.isEmpty)
        let fresh = WorkshopPaidProfessionalAppearance(); try await h.appear(fresh); h.controller.close(old)
        XCTAssertEqual(h.controller.phase,.history); XCTAssertNil(h.controller.appear(old))
    }
    func testQueuedConfirmAfterBackPersistsIntentWithoutSendingAndCanCloseUnknownOnServer() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a)
        let queued = try XCTUnwrap(h.controller.offerSubmit(a,confirmedMode:.city)); let id = try XCTUnwrap(h.store.load()).requestId
        h.controller.close(a); await queued(); XCTAssertEqual(h.wire.writes,0)
        let b = WorkshopPaidProfessionalAppearance(); try await h.appear(b); XCTAssertEqual(h.controller.operation?.state,.notFound)
        XCTAssertNil(h.controller.offerAcknowledge(b)); XCTAssertEqual(try h.store.load()?.requestId,id)
        await (try XCTUnwrap(h.controller.offerCancelPending(b)))(); XCTAssertEqual(h.controller.operation?.state,.cancelled)
        await (try XCTUnwrap(h.controller.offerAcknowledge(b)))(); XCTAssertNil(try h.store.load())
    }
    func testCommittedLostResponseRecoversSameUUIDWithoutDuplicateCreate() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a); h.wire.commitThenThrow = true
        await (try XCTUnwrap(h.controller.offerSubmit(a,confirmedMode:.city)))(); XCTAssertEqual(h.controller.issue,.outcomeUnknown)
        let id = try XCTUnwrap(h.store.load()).requestId; h.wire.commitThenThrow = false
        await (try XCTUnwrap(h.controller.offerRefreshStatus(a)))(); XCTAssertEqual(h.controller.operation?.state,.created)
        XCTAssertEqual(h.controller.command?.requestId,id); XCTAssertEqual(h.wire.writes,1)
    }
    func testReadGrantDoesNotAuthorizeMutation() async throws {
        let h = try Harness(write:false), a = WorkshopPaidProfessionalAppearance(); try await h.review(a)
        XCTAssertNil(h.controller.offerSubmit(a,confirmedMode:.city)); XCTAssertEqual(h.controller.issue,.disabled); XCTAssertEqual(h.wire.writes,0); XCTAssertNil(try h.store.load())
    }
    func testFailedStorageStopsDispatchAndPreservesExistingBytes() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a); h.memory.failWrite = true
        let old = h.memory.values; XCTAssertNil(h.controller.offerSubmit(a,confirmedMode:.city)); XCTAssertEqual(h.memory.values,old); XCTAssertEqual(h.wire.writes,0)
    }
    func testChangedTargetFingerprintRejectsBeforeConfirmation() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.appear(a); await (try XCTUnwrap(h.controller.offerNewReview(a)))()
        h.wire.detailTarget = F.target; h.wire.detailTarget?["ownerModeFingerprint"] = String(repeating:"e",count:64)
        await (try XCTUnwrap(h.controller.offerSelect(XCTUnwrap(h.controller.targets.first),displayed:a)))()
        XCTAssertNil(h.controller.body); XCTAssertNil(h.controller.offerSubmit(a,confirmedMode:.city)); XCTAssertEqual(h.wire.writes,0)
    }
    func testUnresolvedModeRemainsReadOnly() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); h.wire.target["mode"] = "UNRESOLVED"; h.wire.target["productType"] = NSNull()
        try await h.appear(a); await (try XCTUnwrap(h.controller.offerNewReview(a)))()
        XCTAssertNil(h.controller.offerSelect(try XCTUnwrap(h.controller.targets.first),displayed:a)); XCTAssertEqual(h.wire.writes,0)
    }
    func testColdHistoryDiscoveryNeedsNoBodyAndReadsTerminalStatus() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); h.wire.recorded = try F.command(); h.wire.status = "CREATED"
        try await h.appear(a); await (try XCTUnwrap(h.controller.offerInspect(XCTUnwrap(h.controller.operations.first),displayed:a)))()
        XCTAssertEqual(h.controller.operation?.state,.created); XCTAssertTrue(h.wire.requests.allSatisfy { $0.url!.path.contains("professional-operations") })
    }
    func testEmptyFilteredPageWithCursorStillContinues() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); h.wire.emptyNextPage = true; try await h.appear(a)
        XCTAssertTrue(h.controller.operations.isEmpty); XCTAssertNotNil(h.controller.nextOperationCursor)
        await (try XCTUnwrap(h.controller.offerMoreOperations(a)))(); XCTAssertNil(h.controller.nextOperationCursor); XCTAssertEqual(h.wire.nextPages,2)
    }
    func testClosedSuspendedRead401HasNoLogoutSideEffect() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); h.wire.delay = true
        let action = try XCTUnwrap(h.controller.appear(a)); let task = Task { await action() }; await h.wire.wait()
        h.controller.close(a); try await h.appear(.init()); h.wire.resume401(); await task.value
        XCTAssertEqual(h.unauthorized,0); XCTAssertEqual(h.controller.phase,.history)
    }
    func testCurrent401DoesExpireSessionOnce() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); h.wire.delay = true
        let action = try XCTUnwrap(h.controller.appear(a)); let task = Task { await action() }; await h.wire.wait(); h.wire.resume401(); await task.value
        XCTAssertEqual(h.unauthorized,1)
    }
    func testApprovalReplacementAndTaskCancellationFenceOld401() async throws {
        for cancel in [false,true] {
            let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); h.wire.delay = true
            let action = try XCTUnwrap(h.controller.appear(a)); let task = Task { await action() }; await h.wire.wait()
            if cancel { task.cancel() } else { h.read = try .init(context:h.context,expiresAt:.distantFuture) }
            h.wire.resume401(); await task.value; XCTAssertEqual(h.unauthorized,0)
        }
    }
    func testRejectedTerminalCannotUseOldConfirmationAgain() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a); h.wire.writeState = "REJECTED"
        let offer = try XCTUnwrap(h.controller.offerSubmit(a,confirmedMode:.city)); await offer(); await offer()
        XCTAssertEqual(h.wire.writes,1); XCTAssertEqual(h.controller.operation?.state,.rejected); XCTAssertNil(h.controller.offerSubmit(a,confirmedMode:.city))
    }
    func testOperationHashMismatchAndUnsafeAbsenceCannotClearPending() throws {
        let h = try Harness(); let c = try F.command(); try h.store.save(c); let old = h.memory.values
        XCTAssertThrowsError(try h.store.acknowledge(F.decode(WorkshopPaidProfessionalOperation.self,F.operation(c,state:"NOT_FOUND"))))
        var value = F.operation(c,state:"CANCELLED"); value["commandHash"] = String(repeating:"0",count:64)
        XCTAssertThrowsError(try h.store.acknowledge(F.decode(WorkshopPaidProfessionalOperation.self,value))); XCTAssertEqual(h.memory.values,old)
    }
    func testMalformedOperationAndUnknownCommandFieldsAreRejected() throws {
        let c = try F.command(); var op = F.operation(c,state:"NOT_FOUND"); op["safeToReplace"] = true
        XCTAssertThrowsError(try F.decode(WorkshopPaidProfessionalOperation.self,op))
        var command = try JSONSerialization.jsonObject(with:c.wireData()) as! [String: Any]; command["paid"] = true
        XCTAssertThrowsError(try F.decode(WorkshopPaidProfessionalCommand.self,command))
        command.removeValue(forKey:"paid"); command["confirmedMode"] = "UNRESOLVED"; XCTAssertThrowsError(try F.decode(WorkshopPaidProfessionalCommand.self,command))
    }
    func testExplicitModeMismatchCannotPersistOrDispatch() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a)
        XCTAssertNil(h.controller.offerSubmit(a,confirmedMode:.free)); XCTAssertEqual(h.controller.issue,.invalid)
        XCTAssertNil(try h.store.load()); XCTAssertEqual(h.wire.writes,0)
    }
    func testCancelAfterUnknownCommittedCreateReturnsSameCreationWithoutReplacingIntent() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a); h.wire.commitThenThrow = true
        await (try XCTUnwrap(h.controller.offerSubmit(a,confirmedMode:.city)))()
        let old = try XCTUnwrap(h.store.load()); h.wire.commitThenThrow = false
        await (try XCTUnwrap(h.controller.offerCancelPending(a)))()
        XCTAssertEqual(h.controller.operation?.state,.created); XCTAssertEqual(h.controller.command?.requestId,old.requestId)
        XCTAssertEqual(h.wire.requests.filter { $0.url?.lastPathComponent == "submit" }.count,1)
        XCTAssertEqual(h.wire.requests.filter { $0.url?.lastPathComponent == "cancel" }.count,1)
    }
    func testCorruptPendingRecordBlocksNewReviewWithoutRemovingBytes() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try h.store.save(F.command())
        let key = try XCTUnwrap(h.memory.values.keys.first); h.memory.values[key] = Data("corrupt".utf8)
        let before = h.memory.values; try await h.appear(a)
        XCTAssertEqual(h.controller.issue,.storageUnavailable); XCTAssertEqual(h.memory.values,before)
        XCTAssertNil(h.controller.offerNewReview(a)); XCTAssertEqual(h.wire.requests.count,0)
    }
    func testCancellationTicketCannotBeSubmittedAsCreate() async throws {
        let h = try Harness(); let confirmation = WorkshopPaidProfessionalConfirmation(command:try F.command(),lifetime:.init(current:{true}),purpose:.cancel)
        do { _ = try await h.service.submit(confirmation); XCTFail("Wrong purpose must fail") } catch { }
        XCTAssertEqual(h.wire.writes,0)
    }
    func testBackgroundClearsReviewAndRequiresFreshExplicitPreparation() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a)
        let count = h.wire.requests.count
        h.controller.suspend(a)
        XCTAssertNil(h.controller.body); XCTAssertNil(h.controller.currentDraft); XCTAssertNil(h.controller.selectedTarget)
        XCTAssertNil(h.controller.offerSubmit(a, confirmedMode: .city))
        XCTAssertNil(h.controller.offerRecovery(a)); XCTAssertEqual(h.wire.requests.count, count)
        await (try XCTUnwrap(h.controller.resume(a)))()
        XCTAssertEqual(h.controller.phase, .history); XCTAssertNil(h.controller.body)
        XCTAssertTrue(h.wire.requests.dropFirst(count).allSatisfy { $0.url!.path.hasSuffix("/professional-operations/history") })
        XCTAssertNil(h.controller.offerSubmit(a, confirmedMode: .city)); XCTAssertNil(h.controller.resume(a))
        await (try XCTUnwrap(h.controller.offerNewReview(a)))()
        XCTAssertNotNil(h.controller.body); XCTAssertEqual(h.controller.phase, .targets)
        XCTAssertEqual(h.wire.writes, 0)
    }
    func testBackgroundQueuedSubmitKeepsOriginalUnknownAndResumeNeverWrites() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a)
        let queued = try XCTUnwrap(h.controller.offerSubmit(a, confirmedMode: .city))
        let bytes = h.memory.values, original = try XCTUnwrap(h.store.load())
        h.controller.suspend(a); await queued()
        XCTAssertEqual(h.wire.writes, 0); XCTAssertEqual(h.memory.values, bytes)
        await (try XCTUnwrap(h.controller.resume(a)))()
        XCTAssertEqual(h.controller.operation?.state, .notFound)
        XCTAssertEqual(h.controller.command?.requestId, original.requestId)
        XCTAssertNil(h.controller.offerAcknowledge(a)); XCTAssertEqual(h.memory.values, bytes)
        XCTAssertEqual(h.wire.writes, 0)
    }
    func testBackgroundAfterLostCommittedResponseReadsOriginalStatusOnly() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a)
        h.wire.commitThenThrow = true
        await (try XCTUnwrap(h.controller.offerSubmit(a, confirmedMode: .city)))()
        let original = try XCTUnwrap(h.store.load()), bytes = h.memory.values
        h.controller.suspend(a); h.wire.commitThenThrow = false
        await (try XCTUnwrap(h.controller.resume(a)))()
        XCTAssertEqual(h.controller.operation?.state, .created)
        XCTAssertEqual(h.controller.command?.requestId, original.requestId)
        XCTAssertEqual(h.memory.values, bytes); XCTAssertEqual(h.wire.writes, 1)
    }
    func testBackgroundLateBodyCannotRepopulateOrExpireSessionAfterResume() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.appear(a)
        h.wire.delay = true
        let old = try XCTUnwrap(h.controller.offerNewReview(a)), task = Task { await old() }
        await h.wire.wait(); h.controller.suspend(a)
        await (try XCTUnwrap(h.controller.resume(a)))()
        h.wire.resume401(); await task.value
        XCTAssertEqual(h.controller.phase, .history); XCTAssertNil(h.controller.body)
        XCTAssertNil(h.controller.currentDraft); XCTAssertEqual(h.unauthorized, 0); XCTAssertEqual(h.wire.writes, 0)
    }
    func testBackgroundQueuedAppearAndClosedResumeCannotReadOrResurrect() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance()
        let queued = try XCTUnwrap(h.controller.appear(a))
        h.controller.suspend(a); await queued(); XCTAssertTrue(h.wire.requests.isEmpty)
        h.controller.close(a); XCTAssertNil(h.controller.resume(a)); XCTAssertNil(h.controller.appear(a))
        let fresh = WorkshopPaidProfessionalAppearance(); try await h.appear(fresh)
        h.controller.suspend(a); XCTAssertEqual(h.controller.phase, .history)
        XCTAssertNil(h.controller.resume(a)); XCTAssertNotNil(h.controller.offerRecovery(fresh))
    }
    func testBackgroundScopeLossPreservesPendingForOriginalOwnerReconstruction() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a)
        let queued = try XCTUnwrap(h.controller.offerSubmit(a, confirmedMode: .city))
        let bytes = h.memory.values, original = try XCTUnwrap(h.store.load())
        h.controller.suspend(a); h.current = nil
        XCTAssertNil(h.controller.resume(a)); await queued()
        XCTAssertEqual(h.controller.phase, .invalidated); XCTAssertEqual(h.memory.values, bytes)
        h.current = h.context
        let lease = ContentDraftSessionLease(context: h.context, current: { h.current })
        // Recreate the original service as well: invalidation revokes its old lease.
        let service = WorkshopPaidProfessionalService(api: try APIConfiguration(baseURL: h.context.baseURL), transport: h.wire,
            lease: lease, readApproval: h.read, currentReadApproval: { h.read })
        let restarted = WorkshopPaidProfessionalController(reference: h.reference, service: service, store: h.store, lease: lease)
        await (try XCTUnwrap(restarted.appear(.init())))()
        XCTAssertEqual(restarted.command?.requestId, original.requestId)
        XCTAssertEqual(restarted.operation?.state, .notFound); XCTAssertEqual(h.memory.values, bytes)
        XCTAssertEqual(h.wire.writes, 0)
    }
    func testBackgroundRetiresGeneratedCurrentDetailReference() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a)
        await (try XCTUnwrap(h.controller.offerSubmit(a, confirmedMode: .city)))()
        let result = try XCTUnwrap(h.controller.operation), revision = h.controller.generatedDetailRevision
        XCTAssertNotNil(h.controller.generatedTemplateID(a, expected: result))
        h.controller.suspend(a)
        XCTAssertNotEqual(h.controller.generatedDetailRevision, revision)
        XCTAssertNil(h.controller.generatedTemplateID(a, expected: result)); XCTAssertNil(h.controller.operation)
        await (try XCTUnwrap(h.controller.resume(a)))()
        XCTAssertNotNil(h.controller.generatedTemplateID(a, expected: result))
        XCTAssertEqual(h.wire.writes, 1)
    }

    func testBackgroundLateSuccessfulBodyCannotRefillFreshHistory() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.appear(a)
        h.wire.delay = true
        let old = try XCTUnwrap(h.controller.offerNewReview(a)), task = Task { await old() }
        await h.wire.wait(); h.controller.suspend(a)
        await (try XCTUnwrap(h.controller.resume(a)))()
        let suspended = h.wire.suspended; h.wire.suspended = nil
        suspended?.resume(returning: (try WorkshopPaidTextFixture.envelope(), 200)); await task.value
        XCTAssertEqual(h.controller.phase, .history); XCTAssertNil(h.controller.body)
        XCTAssertNil(h.controller.currentDraft); XCTAssertTrue(h.controller.targets.isEmpty)
        XCTAssertEqual(h.wire.writes, 0)
    }
    func testBackgroundInflightCreateCannotOverwriteIndependentStatusRead() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance(); try await h.review(a)
        h.wire.delay = true
        let old = try XCTUnwrap(h.controller.offerSubmit(a, confirmedMode: .city)), task = Task { await old() }
        await h.wire.wait(); let original = try XCTUnwrap(h.store.load()), bytes = h.memory.values
        h.controller.suspend(a); await (try XCTUnwrap(h.controller.resume(a)))()
        XCTAssertEqual(h.controller.operation?.state, .created)
        let suspended = h.wire.suspended; h.wire.suspended = nil
        suspended?.resume(returning: (try F.data(["code":200,"data":F.operation(original,state:"PREPARED")]), 200))
        await task.value
        XCTAssertEqual(h.controller.operation?.state, .created)
        XCTAssertEqual(h.controller.command?.requestId, original.requestId)
        XCTAssertEqual(h.memory.values, bytes); XCTAssertEqual(h.wire.writes, 1)
    }

    private func targetPage(_ ids: [Int], more: Bool = false) -> [String: Any] {
        let items = ids.map { id -> [String: Any] in var value = F.target; value["topicId"] = id; return value }
        return ["schema":"w18-owned-professional-topic-targets-v1", "scope":"INDIVIDUAL_CONTENT_OWNER_AND_PUBLISHER_METADATA_ONLY",
                "licenseId":"w18-paid-11", "checkedAt":F.instant, "items":items, "hasMore":more,
                "nextBeforeTopicId":more ? ids.last! as Any : NSNull()]
    }
    private func historyPage(key: String, next: String? = nil) throws -> [String: Any] {
        var record = try F.record(F.command()); record["operationKey"] = key
        return ["schema":"w18-paid-professional-operation-history-v1", "scope":"OWNER_OPERATION_INTENT_REFERENCES_ONLY",
                "licenseId":"w18-paid-11", "items":[record], "scannedCount":next == nil ? 1 : 50,
                "hasMore":next != nil, "nextBeforeOperationKey":next.map { $0 as Any } ?? NSNull()]
    }
    private func cursors(_ h: Harness, field: String) throws -> [String] {
        try h.wire.requests.compactMap { request in
            guard let data = request.httpBody, let values = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cursor = values[field] else { return nil }
            return String(describing: cursor)
        }
    }
    func testHistoryContinuationFailureKeepsRowsAndRetriesExactCursor() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance()
        let high = String(repeating:"f",count:64), cursor = String(repeating:"e",count:64), low = String(repeating:"d",count:64)
        h.wire.historyPages = [try historyPage(key:high,next:cursor), try historyPage(key:low)]
        try await h.appear(a); h.wire.continuationFailure = .unavailable
        await (try XCTUnwrap(h.controller.offerMoreOperations(a)))()
        XCTAssertEqual(h.controller.phase,.history); XCTAssertEqual(h.controller.operations.map(\.id),[high])
        XCTAssertEqual(h.controller.nextOperationCursor,cursor); XCTAssertEqual(h.controller.issue,.unavailable)
        await (try XCTUnwrap(h.controller.offerMoreOperations(a)))()
        XCTAssertEqual(h.controller.operations.map(\.id),[high,low]); XCTAssertNil(h.controller.nextOperationCursor)
        XCTAssertNil(h.controller.issue); XCTAssertEqual(try cursors(h,field:"beforeOperationKey"),[cursor,cursor])
        XCTAssertEqual(h.wire.writes,0); XCTAssertNil(try h.store.load())
    }
    func testTargetsContinuationFailureKeepsPreparationAndExactCursor() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance()
        h.wire.targetPages = [targetPage(Array((452...501).reversed()),more:true),targetPage([451])]
        try await h.appear(a); await (try XCTUnwrap(h.controller.offerNewReview(a)))()
        let body = try XCTUnwrap(h.controller.body); h.wire.continuationFailure = .unavailable
        await (try XCTUnwrap(h.controller.offerMoreTargets(a)))()
        XCTAssertEqual(h.controller.phase,.targets); XCTAssertEqual(h.controller.targets.count,50)
        XCTAssertEqual(h.controller.nextTargetCursor,452); XCTAssertEqual(h.controller.body?.contentHash,body.contentHash)
        await (try XCTUnwrap(h.controller.offerMoreTargets(a)))()
        XCTAssertEqual(h.controller.targets.count,51); XCTAssertEqual(h.controller.targets.last?.topicId,451)
        XCTAssertNil(h.controller.nextTargetCursor); XCTAssertNil(h.controller.issue)
        XCTAssertEqual(try cursors(h,field:"beforeTopicId"),["452","452"])
        XCTAssertEqual(h.wire.writes,0); XCTAssertNil(try h.store.load())
    }
    func testMalformedContinuationNeverPartiallyAppendsAndCanRetryOriginalCursor() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance()
        let high = String(repeating:"f",count:64), cursor = String(repeating:"e",count:64), low = String(repeating:"d",count:64)
        // The real service rejects a row above the requested cursor before controller append.
        h.wire.historyPages = [try historyPage(key:high,next:cursor),try historyPage(key:high),try historyPage(key:low)]
        try await h.appear(a); await (try XCTUnwrap(h.controller.offerMoreOperations(a)))()
        XCTAssertEqual(h.controller.issue,.malformed); XCTAssertEqual(h.controller.phase,.history)
        XCTAssertEqual(h.controller.operations.map(\.id),[high]); XCTAssertEqual(h.controller.nextOperationCursor,cursor)
        await (try XCTUnwrap(h.controller.offerMoreOperations(a)))()
        XCTAssertEqual(h.controller.operations.map(\.id),[high,low]); XCTAssertEqual(try cursors(h,field:"beforeOperationKey"),[cursor,cursor])
    }
    func testContinuationReadGrantRevocationDoesNotPreserveProtectedPreparation() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance()
        h.wire.targetPages = [targetPage(Array((452...501).reversed()),more:true)]
        try await h.appear(a); await (try XCTUnwrap(h.controller.offerNewReview(a)))()
        let count = h.wire.requests.count; h.read = nil
        await (try XCTUnwrap(h.controller.offerMoreTargets(a)))()
        XCTAssertEqual(h.controller.phase,.unavailable); XCTAssertEqual(h.controller.issue,.disabled)
        XCTAssertNil(h.controller.body); XCTAssertNil(h.controller.offerMoreTargets(a))
        XCTAssertEqual(h.wire.requests.count,count); XCTAssertEqual(h.wire.writes,0)
    }
    func testBackgroundLateContinuationFailureCannotRestoreOldTargets() async throws {
        let h = try Harness(), a = WorkshopPaidProfessionalAppearance()
        h.wire.targetPages = [targetPage(Array((452...501).reversed()),more:true)]
        try await h.appear(a); await (try XCTUnwrap(h.controller.offerNewReview(a)))()
        h.wire.delay = true
        let old = try XCTUnwrap(h.controller.offerMoreTargets(a)), task = Task { await old() }
        await h.wire.wait(); h.controller.suspend(a); await (try XCTUnwrap(h.controller.resume(a)))()
        let suspended = h.wire.suspended; h.wire.suspended = nil
        suspended?.resume(returning:(Data(),503)); await task.value
        XCTAssertEqual(h.controller.phase,.history); XCTAssertNil(h.controller.body)
        XCTAssertTrue(h.controller.targets.isEmpty); XCTAssertNil(h.controller.nextTargetCursor)
        XCTAssertNil(h.controller.issue); XCTAssertEqual(h.wire.writes,0)
    }

}
