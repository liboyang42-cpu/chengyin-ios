import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol NativeChannelProgressNetworkTask: AnyObject {
    func resume()
    func cancel()
}
extension URLSessionDataTask: NativeChannelProgressNetworkTask {}

/// Cancellation, task installation and terminal completion share one lock. Recursive
/// locking also permits an injected inert test task to complete synchronously in resume.
private final class NativeChannelProgressNetworkExchange: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var terminal: Result<(Data, Int), Error>?
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    private var task: (any NativeChannelProgressNetworkTask)?
    func install(_ continuation: CheckedContinuation<(Data, Int), Error>) -> Bool {
        lock.lock()
        if let terminal { lock.unlock(); continuation.resume(with: terminal); return false }
        self.continuation = continuation; lock.unlock(); return true
    }
    func finish(_ result: Result<(Data, Int), Error>) {
        lock.lock()
        guard terminal == nil else { lock.unlock(); return }
        terminal = result; let waiting = continuation; continuation = nil; task = nil
        lock.unlock(); waiting?.resume(with: result)
    }
    func cancel() {
        lock.lock()
        guard terminal == nil else { lock.unlock(); return }
        let result: Result<(Data, Int), Error> = .failure(CancellationError())
        terminal = result; let waiting = continuation; continuation = nil
        let active = task; task = nil; lock.unlock()
        active?.cancel()
        waiting?.resume(with: result)
    }
    @MainActor func resume(_ task: any NativeChannelProgressNetworkTask,
                           fence: NativeChannelProgressDispatchFence) {
        lock.lock()
        guard terminal == nil, fence.isCurrent else {
            finish(.failure(NativeChannelProgressError.closed)); lock.unlock(); task.cancel(); return
        }
        self.task = task
        // No actor hop, queue or suspension between the fence and actual resume.
        task.resume()
        lock.unlock()
    }
}

@MainActor enum NativeChannelProgressNetworkForward {
    typealias Completion = @Sendable (Data?, URLResponse?, Error?) -> Void
    typealias TaskFactory = (URLRequest, @escaping Completion) -> any NativeChannelProgressNetworkTask
    static func send(_ request: URLRequest, fence: NativeChannelProgressDispatchFence,
                     makeTask: TaskFactory) async throws -> (Data, Int) {
        let exchange = NativeChannelProgressNetworkExchange()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            guard fence.isCurrent else { throw NativeChannelProgressError.closed }
            let result: (Data, Int) = try await withCheckedThrowingContinuation { continuation in
                guard exchange.install(continuation) else { return }
                let task = makeTask(request) { data, response, error in
                    if let error { exchange.finish(.failure(error)); return }
                    guard let data, let response = response as? HTTPURLResponse else {
                        exchange.finish(.failure(NativeChannelProgressError.malformed)); return
                    }
                    exchange.finish(.success((data, response.statusCode)))
                }
                exchange.resume(task, fence: fence)
            }
            try Task.checkCancellation()
            guard fence.isCurrent else { throw NativeChannelProgressError.closed }
            return result
        }, onCancel: { exchange.cancel() })
    }
}

// Kept outside AuthService.swift so conformance cannot infer MainActor isolation
// for the existing URLSessionTransport initializer or its ordinary send method.
extension URLSessionTransport: NativeChannelProgressDispatching {
    @MainActor public func send(_ request: URLRequest, fence: NativeChannelProgressDispatchFence) async throws -> (Data, Int) {
        try await NativeChannelProgressNetworkForward.send(request, fence: fence, makeTask: { request, completion in
            makeNativeChannelProgressTask(request: request, completion: completion)
        })
    }
}
