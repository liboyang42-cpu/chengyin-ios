import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// These tests feed the real delegate state machine through suspended fake tasks.
/// No task used in this suite opens a connection or makes a live request.
final class ResponseLimitedHTTPTransportTests: XCTestCase {
    private func request(_ value: String = "https://api.example.com/api/common/uploadOSS") throws -> URLRequest {
        var request = URLRequest(url: try XCTUnwrap(URL(string: value)))
        request.httpMethod = "POST"
        request.httpBody = Data("fixture multipart bytes".utf8)
        request.setValue("fixture-token", forHTTPHeaderField: "Authorization")
        return request
    }

    private func response(status: Int = 200, length: Int? = nil) throws -> HTTPURLResponse {
        let url = try XCTUnwrap(request().url)
        return try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                            headerFields: length.map { ["Content-Length": String($0)] }))
    }

    private func assertFailure(_ expected: ResponseLimitedHTTPTransportFailure,
                               transport: ResponseLimitedHTTPTransport, request: URLRequest? = nil,
                               file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await transport.send(try request ?? self.request())
            XCTFail("Expected a transport failure", file: file, line: line)
        } catch { XCTAssertEqual(error as? ResponseLimitedHTTPTransportFailure, expected, file: file, line: line) }
    }

    func testDefaultDisabledNeverCreatesOrResumesTask() async throws {
        let fixture = ResponseLimitedFakeFactory { _ in XCTFail("Disabled transport dispatched") }
        let transport = ResponseLimitedHTTPTransport(makeTask: fixture.makeTask)
        XCTAssertFalse(transport.enabled)
        XCTAssertEqual(transport.maximumResponseBytes, 1_048_576)
        await assertFailure(.disabled, transport: transport)
        XCTAssertEqual(fixture.creationCount, 0)
    }

    func testSessionConfigurationDoesNotPersistCredentialsCookiesOrCache() {
        let configuration = ResponseLimitedHTTPTransport.makeSessionConfiguration()
        XCTAssertNil(configuration.identifier)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 30)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 30)
    }

    func testInvalidLimitsAndUnsafeURLsFailBeforeDispatch() async throws {
        let fixture = ResponseLimitedFakeFactory { _ in XCTFail("Invalid request dispatched") }
        for limit in [0, -1] {
            await assertFailure(.invalidConfiguration, transport: .init(enabled: true, maximumResponseBytes: limit,
                                                                        makeTask: fixture.makeTask))
        }
        let transport = ResponseLimitedHTTPTransport(enabled: true, makeTask: fixture.makeTask)
        for url in ["http://api.example.com/upload", "https://user:password@api.example.com/upload",
                    "https://api.example.com/upload#fragment"] {
            await assertFailure(.invalidRequest, transport: transport, request: try request(url))
        }
        var streamed = try request()
        streamed.httpBodyStream = InputStream(data: Data([1]))
        await assertFailure(.invalidRequest, transport: transport, request: streamed)
        XCTAssertEqual(fixture.creationCount, 0)
    }

    func testExactLimitStreamsSuccessfullyAndKeepsRequestScope() async throws {
        let response = try response(status: 201, length: 4)
        let fixture = ResponseLimitedFakeFactory { delegate in
            XCTAssertTrue(delegate.receive(response))
            delegate.receive(Data([1, 2]))
            delegate.receive(Data([3, 4]))
            XCTAssertEqual(delegate.bufferedByteCount, 4)
            delegate.complete(error: nil)
        }
        var original = try request()
        original.setValue("session=must-not-send", forHTTPHeaderField: "Cookie")
        original.setValue("legacy=must-not-send", forHTTPHeaderField: "Cookie2")
        let transport = ResponseLimitedHTTPTransport(enabled: true, maximumResponseBytes: 4, makeTask: fixture.makeTask)
        let (data, status) = try await transport.send(original)
        XCTAssertEqual(data, Data([1, 2, 3, 4]))
        XCTAssertEqual(status, 201)
        let sent = try XCTUnwrap(fixture.request)
        XCTAssertEqual(sent.url, original.url)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.httpBody, original.httpBody)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        XCTAssertNil(sent.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(sent.value(forHTTPHeaderField: "Cookie2"))
        XCTAssertFalse(sent.httpShouldHandleCookies)
        XCTAssertEqual(sent.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNotNil(original.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(fixture.task?.resumeCount, 1)
        XCTAssertEqual(fixture.task?.cancellationCount, 1)
        XCTAssertEqual(fixture.delegate?.peakBufferedByteCount, 4)
        XCTAssertEqual(fixture.delegate?.bufferedByteCount, 0)
    }

    func testAdvertisedOversizeCancelsBeforeFirstChunk() async throws {
        let response = try response(length: 5)
        let fixture = ResponseLimitedFakeFactory { delegate in
            XCTAssertFalse(delegate.receive(response))
            delegate.receive(Data(repeating: 1, count: 16))
            delegate.complete(error: nil)
        }
        await assertFailure(.outcomeUnknown(.responseTooLarge),
                            transport: .init(enabled: true, maximumResponseBytes: 4, makeTask: fixture.makeTask))
        XCTAssertEqual(fixture.delegate?.peakBufferedByteCount, 0)
        XCTAssertEqual(fixture.task?.cancellationCount, 1)
    }

    func testMissingAndFalseContentLengthCannotBypassChunkLimit() async throws {
        for length: Int? in [nil, 1] {
            let response = try response(length: length)
            let fixture = ResponseLimitedFakeFactory { delegate in
                XCTAssertTrue(delegate.receive(response))
                delegate.receive(Data([1, 2]))
                delegate.receive(Data([3, 4, 5]))
                // The rejected chunk was never appended; late callbacks stay inert.
                delegate.receive(Data(repeating: 7, count: 50))
                delegate.complete(error: nil)
                delegate.complete(error: URLError(.cancelled))
            }
            await assertFailure(.outcomeUnknown(.responseTooLarge),
                                transport: .init(enabled: true, maximumResponseBytes: 4, makeTask: fixture.makeTask))
            XCTAssertEqual(fixture.delegate?.peakBufferedByteCount, 2)
            XCTAssertEqual(fixture.delegate?.bufferedByteCount, 0)
            XCTAssertEqual(fixture.task?.cancellationCount, 1)
        }
    }

    func testSingleOversizedChunkNeverEntersAccumulator() async throws {
        let response = try response()
        let fixture = ResponseLimitedFakeFactory { delegate in
            XCTAssertTrue(delegate.receive(response))
            delegate.receive(Data(repeating: 1, count: 5))
        }
        await assertFailure(.outcomeUnknown(.responseTooLarge),
                            transport: .init(enabled: true, maximumResponseBytes: 4, makeTask: fixture.makeTask))
        XCTAssertEqual(fixture.delegate?.peakBufferedByteCount, 0)
    }

    func testAllRedirectResponseStatusesFailWithoutReplay() async throws {
        for status in [300, 301, 302, 303, 304, 307, 308] {
            let response = try response(status: status)
            let fixture = ResponseLimitedFakeFactory { delegate in
                XCTAssertFalse(delegate.receive(response))
                delegate.complete(error: nil)
            }
            await assertFailure(.outcomeUnknown(.redirectDenied),
                                transport: .init(enabled: true, makeTask: fixture.makeTask))
            XCTAssertEqual(fixture.creationCount, 1)
            XCTAssertEqual(fixture.task?.resumeCount, 1)
        }
    }

    func testRedirectDelegateRejectsSameAndCrossOriginReplacementRequests() async throws {
        let response = try response(status: 307)
        // The URLSession objects below only satisfy delegate signatures and remain
        // suspended for their entire lifetime. Fake task callbacks drive the test.
        let session = URLSession(configuration: .ephemeral)
        let suspendedTask = session.dataTask(with: try request())
        defer { suspendedTask.cancel(); session.invalidateAndCancel() }
        for destination in ["https://api.example.com/another-path", "https://other.example.com/upload"] {
            let replacement = try request(destination)
            let fixture = ResponseLimitedFakeFactory { delegate in
                var callbackCount = 0
                delegate.urlSession(session, task: suspendedTask, willPerformHTTPRedirection: response,
                                    newRequest: replacement) { request in
                    callbackCount += 1
                    XCTAssertNil(request)
                }
                XCTAssertEqual(callbackCount, 1)
                delegate.complete(error: nil)
            }
            await assertFailure(.outcomeUnknown(.redirectDenied),
                                transport: .init(enabled: true, makeTask: fixture.makeTask))
            XCTAssertEqual(fixture.creationCount, 1)
        }
    }

    func testDataDelegateAppliesLimitAndDeclinesResponseCaching() async throws {
        let response = try response(length: 5)
        let session = URLSession(configuration: .ephemeral)
        let suspendedTask = session.dataTask(with: try request())
        defer { suspendedTask.cancel(); session.invalidateAndCancel() }
        let fixture = ResponseLimitedFakeFactory { delegate in
            delegate.urlSession(session, dataTask: suspendedTask, willCacheResponse:
                                    CachedURLResponse(response: response, data: Data([1]))) { XCTAssertNil($0) }
            delegate.urlSession(session, dataTask: suspendedTask, didReceive: response) {
                XCTAssertEqual($0, .cancel)
            }
            delegate.urlSession(session, dataTask: suspendedTask, didReceive: Data([1, 2]))
            delegate.urlSession(session, task: suspendedTask, didCompleteWithError: URLError(.cancelled))
        }
        await assertFailure(.outcomeUnknown(.responseTooLarge),
                            transport: .init(enabled: true, maximumResponseBytes: 4, makeTask: fixture.makeTask))
        XCTAssertEqual(fixture.delegate?.peakBufferedByteCount, 0)
    }

    func testPreCancelledCallerDoesNotCreateTask() async throws {
        let fixture = ResponseLimitedFakeFactory { _ in XCTFail("Cancelled caller dispatched") }
        let transport = ResponseLimitedHTTPTransport(enabled: true, makeTask: fixture.makeTask)
        let request = try request()
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.send(request)
        }
        do { _ = try await caller.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fixture.creationCount, 0)
    }

    func testCancellationBeforeContinuationInstallationRemainsUnsent() async throws {
        let fixture = ResponseLimitedFakeFactory { _ in XCTFail("Cancelled exchange dispatched") }
        let delegate = ResponseLimitedHTTPExchange(maximumResponseBytes: 4)
        delegate.cancel()
        do { _ = try await delegate.send(try request(), makeTask: fixture.makeTask); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fixture.creationCount, 0)
    }

    func testCancellationDuringTaskCreationInvalidatesWithoutResuming() async throws {
        let fixture = ResponseLimitedFakeFactory { _ in XCTFail("Cancelled exchange resumed") }
        let transport = ResponseLimitedHTTPTransport(enabled: true, makeTask: { request, delegate in
            let task = fixture.makeTask(request, delegate)
            // Simulates caller cancellation racing suspended-task construction.
            delegate.cancel()
            return task
        })
        do { _ = try await transport.send(try request()); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fixture.task?.resumeCount, 0)
        XCTAssertEqual(fixture.task?.cancellationCount, 1)
    }

    func testCallerCancellationAfterDispatchIsUnknownAndLateCallbacksStayInert() async throws {
        let started = expectation(description: "Suspended fake task resumed")
        let response = try response()
        let fixture = ResponseLimitedFakeFactory { delegate in
            XCTAssertTrue(delegate.receive(response))
            delegate.receive(Data([1, 2]))
            started.fulfill()
        }
        let transport = ResponseLimitedHTTPTransport(enabled: true, maximumResponseBytes: 4, makeTask: fixture.makeTask)
        let request = try request()
        let caller = Task { try await transport.send(request) }
        await fulfillment(of: [started], timeout: 2)
        caller.cancel()
        do { _ = try await caller.value; XCTFail("Expected unknown outcome") }
        catch { XCTAssertEqual(error as? ResponseLimitedHTTPTransportFailure, .outcomeUnknown(.cancelled)) }
        let delegate = try XCTUnwrap(fixture.delegate)
        delegate.receive(Data([3, 4]))
        delegate.complete(error: nil)
        delegate.complete(error: URLError(.cancelled))
        delegate.cancel()
        XCTAssertEqual(fixture.task?.cancellationCount, 1)
        XCTAssertEqual(delegate.peakBufferedByteCount, 2)
        XCTAssertEqual(delegate.bufferedByteCount, 0)
    }

    func testPostDispatchFailuresCannotClaimUploadWasNotSent() async throws {
        for (error, reason) in [(URLError(.networkConnectionLost), ResponseLimitedHTTPTransportFailure.Reason.network),
                                (URLError(.cancelled), .cancelled)] {
            let fixture = ResponseLimitedFakeFactory { delegate in delegate.complete(error: error) }
            await assertFailure(.outcomeUnknown(reason), transport: .init(enabled: true, makeTask: fixture.makeTask))
            // No upload-progress callback is needed to classify a dispatched write as unknown.
            XCTAssertEqual(fixture.task?.resumeCount, 1)
            XCTAssertEqual(fixture.task?.cancellationCount, 1)
        }
    }

    func testMissingOrNonHTTPResponseAndChunksBeforeHeadersAreUnknown() async throws {
        let nonHTTP = URLResponse(url: try XCTUnwrap(request().url), mimeType: nil,
                                  expectedContentLength: 1, textEncodingName: nil)
        let scripts: [(ResponseLimitedHTTPExchange) -> Void] = [
            { $0.complete(error: nil) },
            { XCTAssertFalse($0.receive(nonHTTP)) },
            { $0.receive(Data([1])) }
        ]
        for script in scripts {
            let fixture = ResponseLimitedFakeFactory(script: script)
            await assertFailure(.outcomeUnknown(.invalidResponse),
                                transport: .init(enabled: true, makeTask: fixture.makeTask))
            XCTAssertEqual(fixture.delegate?.peakBufferedByteCount, 0)
        }
    }
}

private final class ResponseLimitedFakeFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let script: (ResponseLimitedHTTPExchange) -> Void
    private var creations = 0
    private var storedTask: ResponseLimitedFakeTask?
    private var storedDelegate: ResponseLimitedHTTPExchange?
    private var storedRequest: URLRequest?

    init(script: @escaping (ResponseLimitedHTTPExchange) -> Void) { self.script = script }
    var creationCount: Int { lock.lock(); defer { lock.unlock() }; return creations }
    var task: ResponseLimitedFakeTask? { lock.lock(); defer { lock.unlock() }; return storedTask }
    var delegate: ResponseLimitedHTTPExchange? { lock.lock(); defer { lock.unlock() }; return storedDelegate }
    var request: URLRequest? { lock.lock(); defer { lock.unlock() }; return storedRequest }

    func makeTask(_ request: URLRequest, _ delegate: ResponseLimitedHTTPExchange) -> any ResponseLimitedHTTPTask {
        let task = ResponseLimitedFakeTask(delegate: delegate, script: script)
        lock.lock()
        creations += 1
        storedTask = task
        storedDelegate = delegate
        storedRequest = request
        lock.unlock()
        return task
    }
}

private final class ResponseLimitedFakeTask: ResponseLimitedHTTPTask, @unchecked Sendable {
    private let lock = NSLock()
    private let delegate: ResponseLimitedHTTPExchange
    private let script: (ResponseLimitedHTTPExchange) -> Void
    private var resumes = 0
    private var cancellations = 0

    init(delegate: ResponseLimitedHTTPExchange, script: @escaping (ResponseLimitedHTTPExchange) -> Void) {
        self.delegate = delegate
        self.script = script
    }
    var resumeCount: Int { lock.lock(); defer { lock.unlock() }; return resumes }
    var cancellationCount: Int { lock.lock(); defer { lock.unlock() }; return cancellations }
    func resume() {
        lock.lock()
        guard cancellations == 0 else { lock.unlock(); return }
        resumes += 1
        lock.unlock()
        script(delegate)
    }
    func invalidateAndCancel() { lock.lock(); cancellations += 1; lock.unlock() }
}
