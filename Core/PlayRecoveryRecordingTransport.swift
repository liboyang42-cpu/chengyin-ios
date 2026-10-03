import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Final synthetic byte-script recorder: no callback, delegated transport or network implementation.
@MainActor final class PlayRecoveryRecordingTransport: HTTPTransport {
    enum Response { case reply(Data, Int), failure(PlayExperienceError) }
    private(set) var requests: [URLRequest] = []
    var responses: [String: Response] = [:]
    var queues: [String: [Response]] = [:]
    var afterRequest: [String: [String: Response]] = [:]
    private(set) var observedCancellation = false
    var afterCompletion: [String: Response] = [:]
    var pauseResponse = false
    private var continuation: CheckedContinuation<Void, Never>?
    var isAwaitingResponse: Bool { continuation != nil }
    func resumeResponse() { pauseResponse = false; let old = continuation; continuation = nil; old?.resume() }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if pauseResponse { await withCheckedContinuation { continuation = $0 } }
        if Task.isCancelled { observedCancellation = true; throw CancellationError() }
        let path = request.url?.path ?? ""
        let response: Response?
        if var queue = queues[path], !queue.isEmpty { response = queue.removeFirst(); queues[path] = queue }
        else { response = responses[path] }
        guard let response else { throw PlayExperienceError.unsupported }
        switch response {
        case .failure(let error): throw error
        case .reply(let bytes, let status):
            if let replacements = afterRequest[path] { responses.merge(replacements) { _, new in new } }
            if request.httpMethod == "POST", ["answer", "sensor-result", "checkin", "photo", "arrive"].contains(request.url?.lastPathComponent ?? "") {
                responses.merge(afterCompletion) { _, new in new }
            }
            return (bytes, status)
        }
    }
}
