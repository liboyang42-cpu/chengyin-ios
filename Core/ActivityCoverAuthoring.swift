import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Activity cover uploads have an independent approval; activity publication remains separate.
public struct ActivityCoverApproval: Equatable {
    public let endpoint: OperationEndpointApproval
    public let revision: UUID
    public let approvedOrigins: Set<String>
    public let nativePicker: Bool
    public init(endpoint: OperationEndpointApproval, revision: UUID, approvedOrigins: Set<String>, nativePicker: Bool = false) throws {
        guard endpoint.paths == [ActivityCoverService.path], !approvedOrigins.isEmpty else { throw APIError.invalidConfiguration }
        self.endpoint = endpoint; self.revision = revision; self.approvedOrigins = approvedOrigins; self.nativePicker = nativePicker
    }
}
public enum ActivityCoverTarget: Equatable {
    case newDraft(UUID)
    case existing(Int)
    var replayKey: String {
        // Unsaved draft recreation must not bypass an uncertain new-activity upload.
        switch self { case .newDraft: return "activity.cover:new"; case .existing(let id): return "activity.cover:\(id)" }
    }
}

public enum ActivityCoverFailure: Error, Equatable {
    case notConfigured, stale, invalid, locked, unknown
    case rejected(String)
}
public struct ActivityCoverReview: Equatable, Identifiable {
    public let id: UUID
    public let session: PublishingSession
    public let target: ActivityCoverTarget
    public let image: RetainedSelectedImage
    fileprivate init(session: PublishingSession, target: ActivityCoverTarget, image: RetainedSelectedImage) {
        id = UUID(); self.session = session; self.target = target; self.image = image
    }
}
public struct ActivityCoverReceipt: Equatable {
    public let review: ActivityCoverReview
    public let reference: String
    fileprivate init(review: ActivityCoverReview, reference: String) { self.review = review; self.reference = reference }
}
@MainActor public protocol ActivityCoverHTTPTransport: HTTPTransport {
    func sendActivityCover(_ request: URLRequest, session: PublishingSession, approval: ActivityCoverApproval,
                           current: @escaping () -> Bool) async throws -> (Data, Int)
}
public enum ActivityCoverWire {
    public static func accepts(_ request: URLRequest, configuration: APIConfiguration) -> Bool {
        guard request.url == configuration.baseURL.appendingPathComponent(ActivityCoverService.path),
              request.httpMethod == "POST", !request.httpShouldHandleCookies,
              let type = request.value(forHTTPHeaderField: "Content-Type"),
              type.hasPrefix("multipart/form-data; boundary="), let body = request.httpBody,
              body.count <= RetainedSelectedImage.maximumBytes + 1024 else { return false }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        guard boundary.hasPrefix("ActivityCover-"), boundary.count == "ActivityCover-".count + 36,
              UUID(uuidString: String(boundary.dropFirst("ActivityCover-".count))) != nil else { return false }
        let prefix = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\nimage_16_9\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"activity.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        let suffix = Data("\r\n--\(boundary)--\r\n".utf8)
        guard body.starts(with: prefix), body.suffix(suffix.count) == suffix, body.count > prefix.count + suffix.count else { return false }
        let image = body.subdata(in: prefix.count..<(body.count - suffix.count))
        return image.starts(with: [255, 216, 255]) && image.suffix(2) == Data([255, 217]) &&
            image.range(of: Data(("\r\n--" + boundary).utf8)) == nil
    }
}

/// Reuses the existing upload endpoint, selected-image value and durable local replay lock.
/// The server supplies no reconciliation key, so an ambiguous response remains locked.
@MainActor public final class ActivityCoverService {
    public nonisolated static let path = "api/common/uploadOSS"
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let approval: ActivityCoverApproval?
    private let currentApproval: () -> ActivityCoverApproval?
    private let credentials: () -> PublishingCredentials?
    private let journal: any OperationPendingJournal
    private var reviews: [UUID: ActivityCoverReview] = [:]
    private var receipts: [UUID: ActivityCoverReceipt] = [:]
    public init(configuration: APIConfiguration, transport: any HTTPTransport, approval: ActivityCoverApproval? = nil,
                currentApproval: @escaping () -> ActivityCoverApproval?, credentials: @escaping () -> PublishingCredentials?,
                journal: any OperationPendingJournal) {
        self.configuration = configuration; self.transport = transport; self.approval = approval
        self.currentApproval = currentApproval; self.credentials = credentials; self.journal = journal
    }
    public var session: PublishingSession? { credentials()?.session }
    public func isCurrent(_ session: PublishingSession) -> Bool {
        guard let approval, currentApproval() == approval, self.session == session, session.region == .china,
              ["club", "merchant"].contains(session.role) else { return false }
        return approval.endpoint.allows(configuration: configuration, namespace: session.namespace,
                                        accountID: session.accountID, path: Self.path)
    }
    public func permitsPicker(_ session: PublishingSession) -> Bool { isCurrent(session) && approval?.nativePicker == true }
    public func permitsPreview(_ reference: String, session: PublishingSession) -> Bool {
        guard isCurrent(session), let approval, !reference.isEmpty, reference.utf8.count <= 2048,
              reference.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }), let url = URL(string: reference) else { return false }
        return RetainedImageOrigin.accepts(url, origins: approval.approvedOrigins)
    }

    private func ownerKey(_ session: PublishingSession) -> String { configuration.baseURL.absoluteString + "|" + session.storageKey }
    public func pending(target: ActivityCoverTarget, session: PublishingSession) throws -> OperationPendingRecord? {
        guard self.session == session else { throw ActivityCoverFailure.stale }
        return try journal.pending(ownerKey: ownerKey(session), targetKey: target.replayKey)
    }
    public func prepare(_ image: RetainedSelectedImage, target: ActivityCoverTarget, session: PublishingSession) throws -> ActivityCoverReview {
        guard isCurrent(session) else { throw ActivityCoverFailure.notConfigured }
        if case .existing(let id) = target, id <= 0 { throw ActivityCoverFailure.invalid }
        guard image.width > 0, image.height > 0, image.width <= RetainedSelectedImage.maximumDimension,
              image.height <= RetainedSelectedImage.maximumDimension, image.width * 9 == image.height * 16,
              !image.jpeg.isEmpty, image.jpeg.count <= RetainedSelectedImage.maximumBytes else { throw ActivityCoverFailure.invalid }
        guard try pending(target: target, session: session) == nil else { throw ActivityCoverFailure.locked }
        let review = ActivityCoverReview(session: session, target: target, image: image); reviews[review.id] = review; return review
    }
    public func cancel(_ review: ActivityCoverReview) { reviews.removeValue(forKey: review.id) }
    private func check(_ original: PublishingCredentials, current: () -> Bool) throws {
        try Task.checkCancellation()
        guard current(), credentials() == original, isCurrent(original.session) else { throw ActivityCoverFailure.stale }
    }
    public func upload(_ review: ActivityCoverReview, current: @escaping () -> Bool) async throws -> ActivityCoverReceipt {
        guard reviews[review.id] == review, let original = credentials(), original.session == review.session,
              let approval, isCurrent(review.session) else { throw ActivityCoverFailure.notConfigured }
        try check(original, current: current)
        guard try pending(target: review.target, session: review.session) == nil else { throw ActivityCoverFailure.locked }
        let boundary = "ActivityCover-" + UUID().uuidString
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"bizType\"\r\n\r\nimage_16_9\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"activity.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(review.image.jpeg); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(Self.path))
        request.httpMethod = "POST"; request.httpBody = body; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 30
        request.setValue(original.token, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        guard ActivityCoverWire.accepts(request, configuration: configuration) else { throw ActivityCoverFailure.invalid }
        let record = OperationPendingRecord(operationID: review.id, ownerKey: ownerKey(review.session), targetKey: review.target.replayKey)
        // No suspension separates the authoritative pending check, durable lock and dispatch.
        try journal.write(record)
        guard try pending(target: review.target, session: review.session) == record else { throw ActivityCoverFailure.locked }
        reviews.removeValue(forKey: review.id)
        do {
            let response: (Data, Int)
            if let scoped = transport as? any ActivityCoverHTTPTransport {
                response = try await scoped.sendActivityCover(request, session: review.session, approval: approval, current: current)
            } else { response = try await transport.send(request) }
            try check(original, current: current)
            guard response.0.count <= 64 * 1024,
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: response.0) else { throw ActivityCoverFailure.unknown }
            if [400, 401, 403, 404, 413, 415, 422].contains(envelope.code),
               response.1 == 200 || response.1 == envelope.code {
                try journal.clear(record); throw ActivityCoverFailure.rejected(envelope.msg ?? "")
            }
            guard response.1 == 200, envelope.code == 200, let raw = envelope.url,
                  !raw.isEmpty, raw.utf8.count <= 2048, raw.utf8.allSatisfy({ $0 >= 33 && $0 != 127 }),
                  let url = URL(string: raw), RetainedImageOrigin.accepts(url, origins: approval.approvedOrigins) else { throw ActivityCoverFailure.unknown }
            var acknowledged = record; acknowledged.acknowledgedSteps = 1; try journal.write(acknowledged)
            let receipt = ActivityCoverReceipt(review: review, reference: raw); receipts[review.id] = receipt; return receipt
        } catch let failure as ActivityCoverFailure {
            if case .rejected = failure { throw failure }; throw ActivityCoverFailure.unknown
        } catch { throw ActivityCoverFailure.unknown }
    }
    @discardableResult public func apply(_ receipt: ActivityCoverReceipt, current: () -> Bool, consume: (String) -> Bool) -> Bool {
        guard current(), isCurrent(receipt.review.session), receipts[receipt.review.id] == receipt,
              let record = try? pending(target: receipt.review.target, session: receipt.review.session),
              record.operationID == receipt.review.id, record.acknowledgedSteps == 1,
              consume(receipt.reference) else { return false }
        do { try journal.clear(record); receipts.removeValue(forKey: receipt.review.id); return true }
        catch { return false }
    }
    @discardableResult public func discard(_ receipt: ActivityCoverReceipt, current: () -> Bool) -> Bool {
        // Explicit cancellation of a known ACK only. This never clears an unknown request.
        guard current(), isCurrent(receipt.review.session), receipts[receipt.review.id] == receipt,
              let record = try? pending(target: receipt.review.target, session: receipt.review.session),
              record.operationID == receipt.review.id, record.acknowledgedSteps == 1 else { return false }
        do { try journal.clear(record); receipts.removeValue(forKey: receipt.review.id); return true }
        catch { return false }
    }
    private struct Envelope: Decodable { let code: Int; let msg: String?; let url: String? }
}
