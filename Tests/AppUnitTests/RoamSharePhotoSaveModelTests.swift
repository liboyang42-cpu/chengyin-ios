import XCTest
import UIKit
import Combine
@testable import Questify

@MainActor private final class RoamPhotoWriterFixture: RoamSharePhotoWriting {
    var status: RoamSharePhotoSaveState.Authorization = .notDetermined
    var permissionCalls = 0
    var writeCalls = 0
    var image: UIImage?
    var permission: CheckedContinuation<RoamSharePhotoSaveState.Authorization, Never>?
    var write: CheckedContinuation<Void, Error>?
    var requested: (() -> Void)?
    var submitted: (() -> Void)?
    func authorizationStatus() -> RoamSharePhotoSaveState.Authorization { status }
    func requestAuthorization() async -> RoamSharePhotoSaveState.Authorization {
        permissionCalls += 1
        return await withCheckedContinuation { permission = $0; requested?() }
    }
    func add(_ image: UIImage) async throws {
        writeCalls += 1; self.image = image
        try await withCheckedThrowingContinuation { write = $0; submitted?() }
    }
}

@MainActor final class RoamSharePhotoSaveModelTests: XCTestCase {
    private var subscriptions: Set<AnyCancellable> = []
    private func card(route: Bool = false) throws -> RoamSharePhotoSaveState.Selection {
        let record = try JSONDecoder().decode(RoamHistoryRecord.self, from: Data(#"{"ts":1}"#.utf8))
        return .init(record: record, includeRoute: route)
    }
    private func completion(_ model: RoamSharePhotoSaveModel) -> XCTestExpectation {
        let done = expectation(description: "Save flight completed")
        model.$inFlight.dropFirst().filter { !$0 }.first().sink { _ in done.fulfill() }.store(in: &subscriptions)
        return done
    }
    func testDeniedPermissionNeverWritesAndCanRetryWithoutRerendering() async throws {
        let writer = RoamPhotoWriterFixture(), image = UIImage(), card = try card()
        let model = RoamSharePhotoSaveModel(writer: writer), request = expectation(description: "Permission requested")
        writer.requested = { request.fulfill() }; let denied = completion(model)
        model.save(image, selection: card, isCurrent: { true })
        await fulfillment(of: [request], timeout: 1)
        writer.permission?.resume(returning: .denied)
        await fulfillment(of: [denied], timeout: 1)
        XCTAssertEqual(model.state.phase, .permissionDenied); XCTAssertEqual(writer.writeCalls, 0)
        writer.status = .authorized
        let submitted = expectation(description: "Write submitted"), saved = completion(model)
        writer.submitted = { submitted.fulfill() }
        model.save(image, selection: card, isCurrent: { true })
        await fulfillment(of: [submitted], timeout: 1)
        XCTAssertTrue(writer.image === image); writer.write?.resume()
        await fulfillment(of: [saved], timeout: 1)
        XCTAssertEqual(model.state.phase, .saved); XCTAssertEqual(writer.permissionCalls, 1)
    }
    func testRepeatedTapsUseOnePermissionRequestAndOneWrite() async throws {
        let writer = RoamPhotoWriterFixture()
        let subject = RoamSharePhotoSaveModel(writer: writer), card = try card(), image = UIImage()
        let requested = expectation(description: "Permission requested"), submitted = expectation(description: "Write submitted")
        writer.requested = { requested.fulfill() }; writer.submitted = { submitted.fulfill() }; let done = completion(subject)
        subject.save(image, selection: card, isCurrent: { true }); subject.save(image, selection: card, isCurrent: { true })
        await fulfillment(of: [requested], timeout: 1)
        XCTAssertEqual(writer.permissionCalls, 1); writer.permission?.resume(returning: .authorized)
        await fulfillment(of: [submitted], timeout: 1)
        subject.save(image, selection: card, isCurrent: { true }); XCTAssertEqual(writer.writeCalls, 1)
        writer.write?.resume(); await fulfillment(of: [done], timeout: 1)
        subject.save(image, selection: card, isCurrent: { true }); XCTAssertEqual(writer.writeCalls, 1)
    }
    func testDismissBeforeTaskStartsNeverRequestsPermission() async throws {
        let writer = RoamPhotoWriterFixture()
        let subject = RoamSharePhotoSaveModel(writer: writer), done = completion(subject)
        subject.save(UIImage(), selection: try card(), isCurrent: { true }); subject.invalidate()
        await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(writer.permissionCalls, 0); XCTAssertEqual(writer.writeCalls, 0)
    }
    func testDismissDuringPermissionPreventsLaterPhotoWrite() async throws {
        let writer = RoamPhotoWriterFixture()
        let model = RoamSharePhotoSaveModel(writer: writer), request = expectation(description: "Permission requested")
        writer.requested = { request.fulfill() }; let done = completion(model)
        model.save(UIImage(), selection: try card(), isCurrent: { true })
        await fulfillment(of: [request], timeout: 1); model.invalidate()
        writer.permission?.resume(returning: .authorized); await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(writer.writeCalls, 0); XCTAssertNil(model.state.selection)
    }
    func testAccountOrRecordChangeDuringPermissionPreventsWriteWithoutViewCallback() async throws {
        let writer = RoamPhotoWriterFixture()
        let subject = RoamSharePhotoSaveModel(writer: writer), request = expectation(description: "Permission requested")
        var isCurrent = true
        writer.requested = { request.fulfill() }; let done = completion(subject)
        subject.save(UIImage(), selection: try card(), isCurrent: { isCurrent })
        await fulfillment(of: [request], timeout: 1); isCurrent = false
        writer.permission?.resume(returning: .authorized); await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(writer.writeCalls, 0); XCTAssertEqual(subject.state.phase, .sourceChanged)
    }
    func testInvalidateDuringSubmittedWriteDropsCompletionAndKeepsFlightLock() async throws {
        let writer = RoamPhotoWriterFixture(); writer.status = .authorized
        let model = RoamSharePhotoSaveModel(writer: writer), submitted = expectation(description: "Write submitted")
        writer.submitted = { submitted.fulfill() }; let done = completion(model)
        model.save(UIImage(), selection: try card(), isCurrent: { true })
        await fulfillment(of: [submitted], timeout: 1); model.invalidate()
        model.save(UIImage(), selection: try card(route: true), isCurrent: { true })
        XCTAssertEqual(writer.writeCalls, 1); XCTAssertTrue(model.inFlight)
        writer.write?.resume(); await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(model.state.phase, .ready); XCTAssertNil(model.state.selection)
    }
    func testWriteFailureCanRetryPreparedImage() async throws {
        enum Failure: Error { case synthetic }
        let writer = RoamPhotoWriterFixture(); writer.status = .authorized
        let model = RoamSharePhotoSaveModel(writer: writer), image = UIImage(), card = try card()
        let submitted = expectation(description: "Write submitted"), failed = completion(model)
        writer.submitted = { submitted.fulfill() }; model.save(image, selection: card, isCurrent: { true })
        await fulfillment(of: [submitted], timeout: 1); writer.write?.resume(throwing: Failure.synthetic)
        await fulfillment(of: [failed], timeout: 1); XCTAssertEqual(model.state.phase, .failed)
        let retried = expectation(description: "Retry submitted"), done = completion(model)
        writer.submitted = { retried.fulfill() }; model.save(image, selection: card, isCurrent: { true })
        await fulfillment(of: [retried], timeout: 1); XCTAssertTrue(writer.image === image)
        writer.write?.resume(); await fulfillment(of: [done], timeout: 1)
        XCTAssertEqual(model.state.phase, .saved); XCTAssertEqual(writer.writeCalls, 2)
    }
    func testRestrictedAndMissingConfigurationNeverRequestOrWrite() async throws {
        let statuses: [RoamSharePhotoSaveState.Authorization] = [.restricted, .unavailable]
        for status in statuses {
            let writer = RoamPhotoWriterFixture(); writer.status = status
            let model = RoamSharePhotoSaveModel(writer: writer), done = completion(model)
            model.save(UIImage(), selection: try card(), isCurrent: { true })
            await fulfillment(of: [done], timeout: 1)
            XCTAssertEqual(writer.permissionCalls, 0); XCTAssertEqual(writer.writeCalls, 0)
        }
    }
    func testStaleSourceAtTapDoesNothing() throws {
        let writer = RoamPhotoWriterFixture()
        let subject = RoamSharePhotoSaveModel(writer: writer)
        subject.save(UIImage(), selection: try card(), isCurrent: { false })
        XCTAssertFalse(subject.inFlight); XCTAssertNil(subject.state.selection)
        XCTAssertEqual(subject.state.phase, .sourceChanged)
        XCTAssertEqual(writer.permissionCalls, 0); XCTAssertEqual(writer.writeCalls, 0)
    }
}
