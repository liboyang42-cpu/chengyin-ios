import XCTest
@testable import Questify

/// Authored, NOT_RUN. Controlled in-memory reads, no campaign dispatch or device action.
@MainActor final class MerchantEngagementDetailOwnerTests: XCTestCase {
    private final class Reader: MerchantEngagementReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic://detail-owner", accountID: 7, epoch: 1)
        let isConfigured = true
        let isSyntheticEnabled = false
        var authorizationGeneration: UUID? = UUID()
        var started: ((Int) -> Void)?
        var pending: [Int: CheckedContinuation<MerchantEngagementPayload, Error>] = [:]
        func access() async throws -> MerchantEngagementAccess { throw MerchantBusinessFailure.disabled }
        func read(_ query: MerchantEngagementQuery) async throws -> MerchantEngagementPayload {
            guard case .campaign(let id) = query else { throw MerchantBusinessFailure.disabled }
            return try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation; started?(id)
            }
        }
        func finish(_ id: Int, failure: Bool = false) throws {
            let continuation = try XCTUnwrap(pending.removeValue(forKey: id))
            if failure { continuation.resume(throwing: MerchantBusinessFailure.denied) }
            else { continuation.resume(returning: .campaign(try .init(["id": .int(id), "title": .string("Synthetic")], expectedID: id))) }
        }
        func proof(_ command: MerchantEngagementCommand) async throws -> MerchantEngagementProof { throw MerchantBusinessFailure.disabled }
        func execute(_ command: MerchantEngagementCommand, requestID: String, proof: MerchantEngagementProof, scope: MerchantBusinessScope) async throws -> MerchantEngagementReceipt {
            XCTFail("No campaign writes allowed"); throw MerchantBusinessFailure.disabled
        }
    }
    private func makeModel(_ reader: Reader) -> MerchantEngagementViewModel {
        .init(reader: reader, journal: MerchantBusinessMemoryIntentStore(), exports: MerchantExportMemoryRecoveryStore())
    }
    func testLateFirstSelectionCannotReplaceSecondSelection() async throws {
        let reader = Reader(), model = makeModel(reader)
        let first = expectation(description: "first read"), second = expectation(description: "second read")
        reader.started = { id in if id == 1 { first.fulfill() } else { second.fulfill() } }
        let a = Task { await model.loadTask(1) }
        await fulfillment(of: [first], timeout: 1)
        let b = Task { await model.loadTask(2) }
        await fulfillment(of: [second], timeout: 1)
        try reader.finish(2); await b.value
        XCTAssertEqual(model.detail?.id, 2)
        try reader.finish(1); await a.value
        XCTAssertEqual(model.detail?.id, 2)
    }
    func testLateFailureCannotContaminateNewSelection() async throws {
        let reader = Reader(), model = makeModel(reader)
        let first = expectation(description: "first read"), second = expectation(description: "second read")
        reader.started = { id in if id == 1 { first.fulfill() } else { second.fulfill() } }
        let a = Task { await model.loadTask(1) }; await fulfillment(of: [first], timeout: 1)
        let b = Task { await model.loadTask(2) }; await fulfillment(of: [second], timeout: 1)
        try reader.finish(2); await b.value
        try reader.finish(1, failure: true); await a.value
        XCTAssertEqual(model.detail?.id, 2)
        XCTAssertNil(model.issue)
    }
    func testInvalidateAndDisappearCancelRetirePendingRead() async throws {
        for invalidate in [true, false] {
            let reader = Reader(), model = makeModel(reader)
            let started = expectation(description: "read started")
            reader.started = { _ in started.fulfill() }
            let task = Task { await model.loadTask(1) }
            await fulfillment(of: [started], timeout: 1)
            if invalidate { model.invalidate() } else { model.cancel() }
            try reader.finish(1); await task.value
            XCTAssertNil(model.detail)
            XCTAssertNil(model.issue)
        }
    }
    func testChangedAuthorizationDropsSameAccountCompletion() async throws {
        let reader = Reader(), model = makeModel(reader)
        let started = expectation(description: "read started")
        reader.started = { _ in started.fulfill() }
        let task = Task { await model.loadTask(1) }
        await fulfillment(of: [started], timeout: 1)
        reader.authorizationGeneration = UUID()
        try reader.finish(1); await task.value
        XCTAssertNil(model.detail)
    }
}
