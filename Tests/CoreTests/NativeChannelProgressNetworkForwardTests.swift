import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

private final class ProgressInertNetworkTask: NativeChannelProgressNetworkTask {
    var resumes = 0, cancellations = 0
    let completed: NativeChannelProgressNetworkForward.Completion
    var onResume: (() -> Void)?
    init(_ completed: @escaping NativeChannelProgressNetworkForward.Completion) { self.completed = completed }
    func resume() { resumes += 1; onResume?() }
    func cancel() { cancellations += 1; completed(nil, nil, CancellationError()) }
    func respond(_ data: Data = Data([7]), status: Int = 200) {
        completed(data, HTTPURLResponse(url: URL(string: "https://example.com/api/channel/5/board")!, statusCode: status, httpVersion: nil, headerFields: nil), nil)
    }
}

@MainActor final class NativeChannelProgressNetworkForwardTests: XCTestCase {
    private var request: URLRequest { URLRequest(url: URL(string: "https://example.com/api/channel/5/board")!) }
    func testRetirementAfterInertTaskCreationPreventsActualResume() async {
        var current = true; var task: ProgressInertNetworkTask?
        do {
            _ = try await NativeChannelProgressNetworkForward.send(request, fence: .init { current }, makeTask: { _, completion in
                let made = ProgressInertNetworkTask(completion); task = made; current = false; return made
            })
            XCTFail("An inert task must not resume after retirement")
        } catch { XCTAssertEqual(error as? NativeChannelProgressError, .closed) }
        XCTAssertEqual(task?.resumes, 0); XCTAssertEqual(task?.cancellations, 1)
    }
    func testExactlyOneResumePreservesResultBytes() async throws {
        var task: ProgressInertNetworkTask?
        let result = try await NativeChannelProgressNetworkForward.send(request, fence: .init { true }, makeTask: { _, completion in
            let made = ProgressInertNetworkTask(completion); task = made
            made.onResume = { [weak made] in made?.respond(Data([0, 255, 42]), status: 206) }; return made
        })
        XCTAssertEqual(task?.resumes, 1); XCTAssertEqual(task?.cancellations, 0)
        XCTAssertEqual(result.0, Data([0, 255, 42])); XCTAssertEqual(result.1, 206)
    }
    func testCancelInFlightCancelsNativeTaskAndIgnoresLateCompletion() async {
        let entered = expectation(description: "Native resume reached")
        var task: ProgressInertNetworkTask?
        let work = Task { try await NativeChannelProgressNetworkForward.send(request, fence: .init { true }, makeTask: { _, completion in
            let made = ProgressInertNetworkTask(completion); task = made; made.onResume = { entered.fulfill() }; return made
        }) }
        await fulfillment(of: [entered], timeout: 2); work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled operation published a response") } catch {}
        XCTAssertEqual(task?.resumes, 1); XCTAssertEqual(task?.cancellations, 1)
        task?.respond() // A late native callback must not resume its continuation twice.
    }
    func testCancelledTaskNeverAllocatesOrResumesNetworkTask() async {
        var creates = 0
        let work = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await NativeChannelProgressNetworkForward.send(request, fence: .init { true }, makeTask: { _, completion in
                creates += 1; return ProgressInertNetworkTask(completion)
            })
        }
        do { _ = try await work.value; XCTFail("Cancelled task succeeded") } catch {}
        XCTAssertEqual(creates, 0)
    }
    func testRetirementDuringSynchronousCompletionSuppressesResponse() async {
        var current = true
        do {
            _ = try await NativeChannelProgressNetworkForward.send(request, fence: .init { current }, makeTask: { _, completion in
                let made = ProgressInertNetworkTask(completion)
                made.onResume = { [weak made] in current = false; made?.respond() }; return made
            }); XCTFail("Retired response was published")
        } catch { XCTAssertEqual(error as? NativeChannelProgressError, .closed) }
    }
}
