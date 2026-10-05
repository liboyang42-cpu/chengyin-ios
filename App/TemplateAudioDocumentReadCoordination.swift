import Foundation

typealias TemplateAudioDocumentReadAccessor = @Sendable (URL, @Sendable () throws -> Void) throws -> TemplateAudioDocumentMetadata

protocol TemplateAudioDocumentReadCoordinating: Sendable {
    func coordinateRead(selectedURL: URL, accessor: @escaping TemplateAudioDocumentReadAccessor) async throws -> TemplateAudioDocumentMetadata
}

/// One request per driver. Registration must return without waiting for access and callbacks
/// must be enqueued on the supplied queue, never invoked inline. Only cancel is cross-thread.
protocol TemplateAudioDocumentCoordinationDriving: AnyObject, Sendable {
    func coordinateRead(at url: URL, queue: OperationQueue, accessor: @escaping @Sendable (URL, Error?) -> Void)
    func cancel()
}

/// Each instance is used for one coordination registration on one background thread. Apple's
/// documented cross-thread exception is cancel(); no other concurrent coordinator calls occur.
final class AppleTemplateAudioDocumentCoordinationDriver: TemplateAudioDocumentCoordinationDriving, @unchecked Sendable {
    private let coordinator = NSFileCoordinator(filePresenter: nil)
    func coordinateRead(at url: URL, queue: OperationQueue, accessor: @escaping @Sendable (URL, Error?) -> Void) {
        let intent = NSFileAccessIntent.readingIntent(with: url, options: [])
        coordinator.coordinate(with: [intent], queue: queue) { error in
            // NSFileCoordinator updates this URL if a provider moves or renames the item.
            accessor(intent.url, error)
        }
    }
    func cancel() { coordinator.cancel() }
}

protocol TemplateAudioDocumentSecurityScoping: Sendable {
    func start(_ url: URL) -> Bool
    func stop(_ url: URL)
}
struct AppleTemplateAudioDocumentSecurityScope: TemplateAudioDocumentSecurityScoping {
    func start(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    func stop(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

struct AppleTemplateAudioDocumentReadCoordinator: TemplateAudioDocumentReadCoordinating {
    private let makeDriver: @Sendable () -> any TemplateAudioDocumentCoordinationDriving
    private let scoping: any TemplateAudioDocumentSecurityScoping
    init(makeDriver: @escaping @Sendable () -> any TemplateAudioDocumentCoordinationDriving = { AppleTemplateAudioDocumentCoordinationDriver() },
         scoping: any TemplateAudioDocumentSecurityScoping = AppleTemplateAudioDocumentSecurityScope()) {
        self.makeDriver = makeDriver; self.scoping = scoping
    }
    func coordinateRead(selectedURL: URL, accessor: @escaping TemplateAudioDocumentReadAccessor) async throws -> TemplateAudioDocumentMetadata {
        try Task.checkCancellation()
        guard selectedURL.isFileURL else { throw TemplateAudioDocumentFailure.unreadable }
        _ = try TemplateAudioDocumentInspection.format(fileExtension: selectedURL.pathExtension)
        let operation = TemplateAudioCoordinatedReadOperation(makeDriver: makeDriver, scoping: scoping)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                operation.start(selectedURL: selectedURL, accessor: accessor, continuation: continuation)
            }
        }, onCancel: { operation.cancel() })
    }
}

/// The lock protects registration/delivery/cancellation and resource ownership. It is never
/// held during a file read, provider wait, scope stop or continuation resumption.
private final class TemplateAudioCoordinatedReadOperation: @unchecked Sendable {
    private let lock = NSLock()
    private let queue: OperationQueue
    private let makeDriver: @Sendable () -> any TemplateAudioDocumentCoordinationDriving
    private let scoping: any TemplateAudioDocumentSecurityScoping
    private var driver: (any TemplateAudioDocumentCoordinationDriving)?
    private var scope: TemplateAudioScopeLifetime?
    private var continuation: CheckedContinuation<TemplateAudioDocumentMetadata, Error>?
    private var cancelled = false
    private var settled = false
    private var reading = false

    init(makeDriver: @escaping @Sendable () -> any TemplateAudioDocumentCoordinationDriving,
         scoping: any TemplateAudioDocumentSecurityScoping) {
        self.makeDriver = makeDriver; self.scoping = scoping
        queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .userInitiated
    }

    func start(selectedURL: URL, accessor: @escaping TemplateAudioDocumentReadAccessor,
               continuation: CheckedContinuation<TemplateAudioDocumentMetadata, Error>) {
        lock.lock()
        if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        lock.unlock()
        queue.addOperation { [weak self] in self?.register(selectedURL: selectedURL, accessor: accessor) }
    }

    private func register(selectedURL: URL, accessor: @escaping TemplateAudioDocumentReadAccessor) {
        do { try checkCancellation() } catch { return }
        let scope = TemplateAudioScopeLifetime(url: selectedURL, scoping: scoping)
        let driver = makeDriver()
        lock.lock()
        guard !settled else { lock.unlock(); scope.close(); return }
        self.scope = scope; self.driver = driver
        // Registration is asynchronous and protected by the lock. Cancellation therefore cannot
        // miss a not-yet-registered request between the last check and NSFileCoordinator setup.
        driver.coordinateRead(at: selectedURL, queue: queue) { [weak self] coordinatedURL, error in
            self?.access(coordinatedURL: coordinatedURL, error: error, accessor: accessor)
        }
        lock.unlock()
    }

    private func access(coordinatedURL: URL, error: Error?, accessor: TemplateAudioDocumentReadAccessor) {
        lock.lock()
        guard !settled, !reading else { lock.unlock(); return }
        reading = true
        lock.unlock()
        let result: Result<TemplateAudioDocumentMetadata, Error>
        do {
            try checkCancellation()
            if let error {
                let cocoa = error as NSError
                if cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSUserCancelledError { throw CancellationError() }
                throw TemplateAudioDocumentFailure.coordinationFailed
            }
            // All open/fstat/read/close operations occur inside this coordinated accessor.
            let metadata = try accessor(coordinatedURL, { try self.checkCancellation() })
            try checkCancellation()
            result = .success(metadata)
        } catch { result = .failure(error) }
        finish(result)
    }

    private func checkCancellation() throws {
        lock.lock(); let cancelled = cancelled; lock.unlock()
        if cancelled { throw CancellationError() }
    }

    private func finish(_ result: Result<TemplateAudioDocumentMetadata, Error>) {
        lock.lock()
        reading = false
        let scope = scope; self.scope = nil; driver = nil
        let continuation = continuation; self.continuation = nil
        settled = true
        lock.unlock()
        scope?.close()
        continuation?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        cancelled = true; settled = true
        let continuation = continuation; self.continuation = nil
        let driver = driver; self.driver = nil
        // A running accessor owns its scope until its descriptor closes. A pending/late
        // callback cannot open anything after cancellation and needs no remaining access.
        let scope = reading ? nil : scope
        if !reading { self.scope = nil }
        lock.unlock()
        driver?.cancel()
        scope?.close()
        continuation?.resume(throwing: CancellationError())
    }

    deinit { cancel() }
}

/// Scope lifetime is idempotent across pending cancellation, accessor completion and teardown.
/// start=false is permitted for sandbox URLs; the coordinated descriptor open still must work.
private final class TemplateAudioScopeLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let scoping: any TemplateAudioDocumentSecurityScoping
    private var active: Bool
    init(url: URL, scoping: any TemplateAudioDocumentSecurityScoping) {
        self.url = url; self.scoping = scoping; active = scoping.start(url)
    }
    func close() {
        lock.lock(); let shouldStop = active; active = false; lock.unlock()
        if shouldStop { scoping.stop(url) }
    }
    deinit { close() }
}
