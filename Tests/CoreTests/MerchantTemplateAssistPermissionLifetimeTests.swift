import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class AssistPermissionWire: HTTPTransport {
    var requests: [URLRequest] = []
    var hold = false
    var entered: (() -> Void)?
    var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard request.url?.path.hasSuffix("/api/merchant/access/me") == true else { throw APIError.invalidRequest }
        if hold { return try await withCheckedThrowingContinuation { pending = $0; entered?() } }
        return (Data(#"{"code":200,"data":{"active":true,"merchant":{"id":31,"name":"Synthetic shop"},"roleCode":"MERCHANT_OWNER","permissions":["merchant:basic:read","merchant:profile:write","merchant:coop:manage","merchant:project:manage"]}}"#.utf8), 200)
    }
    func release401() { let value = pending; pending = nil; value?.resume(returning: (Data("{}".utf8), 401)) }
}
@MainActor private final class AssistPermissionCandidate: MerchantTemplateAssistServing {
    let session: PublishingSession? = .init(namespace: "synthetic-permission", accountID: 901, epoch: UUID(), role: "merchant", region: .china)
    let canGenerate = true
    var calls = 0
    func generate(_ input: MerchantTemplateAssistInput) async throws -> MerchantTemplateAssistResult {
        calls += 1
        return try .init(.object(["title": .string("Generated"), "questionName": .string("Synthetic question")]))
    }
    func cancel() {}
}
@MainActor private final class AssistExpirationCounter { var count = 0 }

@MainActor final class MerchantTemplateAssistPermissionLifetimeTests: XCTestCase {
    private func setup() async throws -> (AssistPermissionWire, MerchantOperationsCoordinator, AssistPermissionCandidate, MerchantTemplateAssistFlow, AssistExpirationCounter) {
        let wire = AssistPermissionWire(), expired = AssistExpirationCounter()
        let session = try MerchantOperationsSession(accountID: 901, epoch: 1, token: "synthetic", storageNamespace: "synthetic-permission")
        let service = MerchantOperationsService(configuration: try .init(baseURL: URL(string: "https://example.test/scoped/")!), transport: wire)
        let reader = MerchantOperationsSessionReader(service: service, currentSession: { session }, onUnauthorized: { _ in expired.count += 1 })
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(nil))
        await coordinator.load(); XCTAssertTrue(coordinator.isCurrent)
        let client = AssistPermissionCandidate(), flow = MerchantTemplateAssistFlow(coordinator: coordinator, client: client)
        flow.shopName = "Synthetic shop"; flow.prompt = "Question"
        return (wire, coordinator, client, flow, expired)
    }
    private func titleAction(_ flow: MerchantTemplateAssistFlow) throws -> MerchantTemplateSuggestionReview.Action {
        let review = try XCTUnwrap(flow.visibleReview)
        return review.action(for: try XCTUnwrap(review.suggestions.first { $0.field == .title }))
    }
    func testCloseOrCancelAfterSecondQueuedFieldActionCancelsOriginalPermissionTask() async throws {
        for close in [false, true] {
            let (wire, coordinator, _, flow, expired) = try await setup()
            await flow.generate(); let action = try titleAction(flow), before = coordinator.draft
            let started = expectation(description: "real SessionReader access held")
            wire.hold = true; wire.entered = { started.fulfill() }
            let original = Task { await flow.change(action, .accept) }
            await fulfillment(of: [started], timeout: 2)
            let calls = wire.requests.count
            // Match a sheet replacing its stored Task handle with a second queued button.
            let latestSheetTask = Task { await flow.change(action, .accept) }
            let repeated = await latestSheetTask.value
            XCTAssertFalse(repeated); XCTAssertEqual(wire.requests.count, calls)
            latestSheetTask.cancel()
            if close { flow.close() } else { flow.cancel() }
            XCTAssertFalse(original.isCancelled, "The flow must own cancellation independently of this lost outer handle")
            wire.release401()
            let accepted = await original.value
            XCTAssertFalse(accepted); XCTAssertEqual(expired.count, 0)
            XCTAssertEqual(coordinator.draft, before); XCTAssertNil(flow.visibleReview)
        }
    }
    func testCloseAfterQueuedGenerateSuppressesLate401BeforeCallingAIClient() async throws {
        let (wire, coordinator, client, flow, expired) = try await setup()
        let before = coordinator.draft, started = expectation(description: "real generate access held")
        wire.hold = true; wire.entered = { started.fulfill() }
        let original = Task { await flow.generate() }
        await fulfillment(of: [started], timeout: 2)
        let calls = wire.requests.count, latestSheetTask = Task { await flow.generate() }
        await latestSheetTask.value; latestSheetTask.cancel(); flow.close()
        XCTAssertFalse(original.isCancelled); XCTAssertEqual(wire.requests.count, calls)
        wire.release401(); await original.value
        XCTAssertEqual(expired.count, 0); XCTAssertEqual(client.calls, 0); XCTAssertEqual(coordinator.draft, before)
    }
    func testCurrent401StillExpiresSessionForGenerateAcceptAndUndo() async throws {
        for operation in ["generate", "accept", "undo"] {
            let (wire, coordinator, _, flow, expired) = try await setup()
            if operation != "generate" { await flow.generate() }
            if operation == "undo" {
                let accepted = await flow.change(try titleAction(flow), .accept); XCTAssertTrue(accepted)
            }
            let before = coordinator.draft, started = expectation(description: "current real permission access held")
            wire.hold = true; wire.entered = { started.fulfill() }
            let task: Task<Void, Never>
            if operation == "generate" { task = Task { await flow.generate() } }
            else {
                let action = try titleAction(flow)
                task = Task { _ = await flow.change(action, operation == "undo" ? .undo : .accept) }
            }
            await fulfillment(of: [started], timeout: 2)
            wire.release401(); await task.value
            XCTAssertEqual(expired.count, 1); XCTAssertEqual(flow.failure, .permission)
            XCTAssertEqual(coordinator.draft, before); XCTAssertNil(coordinator.confirmation)
            XCTAssertTrue(wire.requests.allSatisfy { $0.url?.path.hasSuffix("/api/merchant/access/me") == true })
        }
    }
}
