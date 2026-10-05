import XCTest
@testable import Questify

@MainActor final class TemplateAudioDocumentReadCoordinationTests: XCTestCase {
    private let originalURL = URL(fileURLWithPath: "/synthetic-only/original.mp3")
    private func fixture() -> (AppleTemplateAudioDocumentReadCoordinator, ControlledAudioCoordinationDriver, AudioScopeProbe, XCTestExpectation) {
        let registered = expectation(description: "Coordination registered")
        let driver = ControlledAudioCoordinationDriver(registered: registered)
        let scope = AudioScopeProbe()
        return (.init(makeDriver: { driver }, scoping: scope), driver, scope, registered)
    }

    func testProviderSuppliedURLIsUsedInsteadOfOriginalSelection() async throws {
        let (coordinator, driver, scope, registered) = fixture()
        let moved = URL(fileURLWithPath: "/synthetic-only/moved.m4a")
        let probe = AudioReadProbe()
        let task = Task {
            try await coordinator.coordinateRead(selectedURL: originalURL) { url, checkCancellation in
                try checkCancellation(); probe.record(url.absoluteString)
                return try audioMetadata(extension: url.pathExtension)
            }
        }
        await fulfillment(of: [registered], timeout: 1)
        driver.deliver(url: moved)
        let value = try await task.value
        XCTAssertEqual(value.format, .m4a)
        XCTAssertEqual(probe.events, [moved.absoluteString])
        XCTAssertEqual(scope.events, ["start", "stop"])
        XCTAssertEqual(driver.selectedURL, originalURL)
    }

    func testCoordinationFailureDoesNotInvokeAccessorAndBalancesScope() async {
        let (coordinator, driver, scope, registered) = fixture()
        let probe = AudioReadProbe()
        let task = Task {
            try await coordinator.coordinateRead(selectedURL: originalURL) { _, _ in
                probe.record("read"); return try audioMetadata()
            }
        }
        await fulfillment(of: [registered], timeout: 1)
        driver.deliver(url: originalURL, error: NSError(domain: "SyntheticProvider", code: 1, userInfo: [NSFilePathErrorKey: "/must-not-escape"]))
        do { _ = try await task.value; XCTFail("Expected coordination failure") }
        catch { XCTAssertEqual(error as? TemplateAudioDocumentFailure, .coordinationFailed) }
        XCTAssertTrue(probe.events.isEmpty)
        XCTAssertEqual(scope.events, ["start", "stop"])
    }

    func testProviderCancellationDoesNotInvokeAccessor() async {
        let (coordinator, driver, scope, registered) = fixture()
        let probe = AudioReadProbe()
        let task = Task {
            try await coordinator.coordinateRead(selectedURL: originalURL) { _, _ in
                probe.record("read"); return try audioMetadata()
            }
        }
        await fulfillment(of: [registered], timeout: 1)
        driver.deliver(url: originalURL, error: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(probe.events.isEmpty)
        XCTAssertEqual(scope.events, ["start", "stop"])
    }

    func testCancellationWhileProviderIsPendingReturnsWithoutAccessorCallback() async {
        let (coordinator, driver, scope, registered) = fixture()
        let probe = AudioReadProbe()
        let task = Task {
            try await coordinator.coordinateRead(selectedURL: originalURL) { _, _ in
                probe.record("read"); return try audioMetadata()
            }
        }
        await fulfillment(of: [registered], timeout: 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(driver.cancelCount, 1)
        XCTAssertTrue(probe.events.isEmpty)
        XCTAssertEqual(scope.events, ["start", "stop"])
    }

    func testLateSuccessAndFailureAfterPendingCancelNeverOpenStream() async {
        for error in [nil, NSError(domain: "SyntheticProvider", code: 9)] as [Error?] {
            let (coordinator, driver, scope, registered) = fixture()
            let probe = AudioReadProbe()
            let task = Task {
                try await coordinator.coordinateRead(selectedURL: originalURL) { _, _ in
                    probe.record("read"); return try audioMetadata()
                }
            }
            await fulfillment(of: [registered], timeout: 1)
            task.cancel()
            do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
            let delivered = expectation(description: "Late provider callback delivered")
            driver.deliver(url: originalURL, error: error, delivered: delivered)
            await fulfillment(of: [delivered], timeout: 1)
            XCTAssertTrue(probe.events.isEmpty)
            XCTAssertEqual(scope.events, ["start", "stop"])
        }
    }

    func testCancelDuringAccessorKeepsScopeUntilReadCleanupThenDropsResult() async {
        let (coordinator, driver, scope, registered) = fixture()
        let opened = expectation(description: "Synthetic read opened")
        let release = DispatchSemaphore(value: 0)
        let probe = AudioReadProbe()
        let task = Task {
            try await coordinator.coordinateRead(selectedURL: originalURL) { _, checkCancellation in
                defer { probe.record("closed") }
                probe.record("open"); opened.fulfill()
                guard release.wait(timeout: .now() + 2) == .success else { throw TemplateAudioDocumentFailure.unreadable }
                try checkCancellation()
                return try audioMetadata()
            }
        }
        await fulfillment(of: [registered], timeout: 1)
        let delivered = expectation(description: "Accessor exited")
        driver.deliver(url: originalURL, delivered: delivered)
        await fulfillment(of: [opened], timeout: 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(scope.events, ["start"])
        XCTAssertEqual(probe.events, ["open"])
        release.signal()
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(probe.events, ["open", "closed"])
        XCTAssertEqual(scope.events, ["start", "stop"])
        XCTAssertEqual(driver.cancelCount, 1)
    }

    func testAccessorFailureBalancesScopeAndPropagatesSafeFailure() async {
        let (coordinator, driver, scope, registered) = fixture()
        let task = Task {
            try await coordinator.coordinateRead(selectedURL: originalURL) { _, _ in
                throw TemplateAudioDocumentFailure.tooLarge
            }
        }
        await fulfillment(of: [registered], timeout: 1)
        driver.deliver(url: originalURL)
        do { _ = try await task.value; XCTFail("Expected read failure") }
        catch { XCTAssertEqual(error as? TemplateAudioDocumentFailure, .tooLarge) }
        XCTAssertEqual(scope.events, ["start", "stop"])
    }

    func testDuplicateProviderCallbackDoesNotReadTwiceOrResumeTwice() async throws {
        let (coordinator, driver, scope, registered) = fixture()
        let probe = AudioReadProbe()
        let task = Task {
            try await coordinator.coordinateRead(selectedURL: originalURL) { _, _ in
                probe.record("read"); return try audioMetadata()
            }
        }
        await fulfillment(of: [registered], timeout: 1)
        driver.deliver(url: originalURL)
        _ = try await task.value
        let duplicate = expectation(description: "Duplicate callback delivered")
        driver.deliver(url: originalURL, delivered: duplicate)
        await fulfillment(of: [duplicate], timeout: 1)
        XCTAssertEqual(probe.events, ["read"])
        XCTAssertEqual(scope.events, ["start", "stop"])
    }

    func testAlreadyCancelledTaskNeverRegistersOrStartsScope() async {
        let driver = ControlledAudioCoordinationDriver()
        let scope = AudioScopeProbe()
        let coordinator = AppleTemplateAudioDocumentReadCoordinator(makeDriver: { driver }, scoping: scope)
        let task = Task {
            try await coordinator.coordinateRead(selectedURL: originalURL) { _, _ in
                XCTFail("Unexpected read"); return try audioMetadata()
            }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(driver.selectedURL)
        XCTAssertTrue(scope.events.isEmpty)
    }

    func testUnsupportedExtensionAndRemoteURLNeverStartScope() async {
        for url in [URL(string: "https://example.invalid/audio.mp3")!, URL(fileURLWithPath: "/synthetic-only/audio.wav")] {
            let driver = ControlledAudioCoordinationDriver()
            let scope = AudioScopeProbe()
            let coordinator = AppleTemplateAudioDocumentReadCoordinator(makeDriver: { driver }, scoping: scope)
            do {
                _ = try await coordinator.coordinateRead(selectedURL: url) { _, _ in
                    XCTFail("Unexpected read"); return try audioMetadata()
                }
                XCTFail("Expected invalid input")
            } catch { XCTAssertNotNil(error as? TemplateAudioDocumentFailure) }
            XCTAssertNil(driver.selectedURL)
            XCTAssertTrue(scope.events.isEmpty)
        }
    }

    func testSandboxScopeFalseDoesNotStopUnacquiredScope() async throws {
        let registered = expectation(description: "Coordination registered")
        let driver = ControlledAudioCoordinationDriver(registered: registered)
        let scope = AudioScopeProbe(acquires: false)
        let coordinator = AppleTemplateAudioDocumentReadCoordinator(makeDriver: { driver }, scoping: scope)
        let task = Task { try await coordinator.coordinateRead(selectedURL: originalURL) { _, _ in try audioMetadata() } }
        await fulfillment(of: [registered], timeout: 1)
        driver.deliver(url: originalURL)
        _ = try await task.value
        XCTAssertEqual(scope.events, ["start"])
    }
}

private func audioMetadata(extension fileExtension: String = "mp3") throws -> TemplateAudioDocumentMetadata {
    var read = false
    return try TemplateAudioDocumentInspection.inspect(fileExtension: fileExtension, reportedByteCount: 1) { _ in
        defer { read = true }
        return read ? Data() : Data([0])
    }
}

private final class ControlledAudioCoordinationDriver: TemplateAudioDocumentCoordinationDriving, @unchecked Sendable {
    private let lock = NSLock()
    private let registered: XCTestExpectation?
    private var callback: (@Sendable (URL, Error?) -> Void)?
    private var queue: OperationQueue?
    private var url: URL?
    private var cancellations = 0
    init(registered: XCTestExpectation? = nil) { self.registered = registered }
    var selectedURL: URL? { lock.lock(); defer { lock.unlock() }; return url }
    var cancelCount: Int { lock.lock(); defer { lock.unlock() }; return cancellations }
    func coordinateRead(at url: URL, queue: OperationQueue, accessor: @escaping @Sendable (URL, Error?) -> Void) {
        lock.lock(); self.url = url; self.queue = queue; callback = accessor; lock.unlock()
        registered?.fulfill()
    }
    func cancel() { lock.lock(); cancellations += 1; lock.unlock() }
    func deliver(url: URL, error: Error? = nil, delivered: XCTestExpectation? = nil) {
        lock.lock(); let queue = queue; let callback = callback; lock.unlock()
        queue?.addOperation { callback?(url, error); delivered?.fulfill() }
    }
}

private final class AudioScopeProbe: TemplateAudioDocumentSecurityScoping, @unchecked Sendable {
    private let lock = NSLock()
    private let acquires: Bool
    private var values: [String] = []
    init(acquires: Bool = true) { self.acquires = acquires }
    var events: [String] { lock.lock(); defer { lock.unlock() }; return values }
    func start(_ url: URL) -> Bool { lock.lock(); values.append("start"); lock.unlock(); return acquires }
    func stop(_ url: URL) { lock.lock(); values.append("stop"); lock.unlock() }
}

private final class AudioReadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var events: [String] { lock.lock(); defer { lock.unlock() }; return values }
    func record(_ event: String) { lock.lock(); values.append(event); lock.unlock() }
}
