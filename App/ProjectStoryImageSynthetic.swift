#if DEBUG
import UIKit

/// Generated image and in-memory legacy response through the real client. No Photos or network.
@MainActor final class ProjectStoryImageSynthetic: ProjectStoryImageUploading {
    @MainActor final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var beforeReply: (() -> Void)?
        var reference = "https://example.com/synthetic/story/e%CC%81.jpg?version=1"
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            guard request.url?.path == "/" + ProjectStoryImageUploadClient.path else { throw APIError.invalidRequest }
            reference = "https://example.com/synthetic/story/e%CC%81.jpg?version=\(requests.count)"
            beforeReply?()
            return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "url": .string(reference)]), 200)
        }
    }
    @MainActor final class Picker: OwnedTopicCoverSelecting {
        let image: RetainedSelectedImage
        private(set) var cancelled = false
        init(_ image: RetainedSelectedImage) { self.image = image }
        func select() async throws -> RetainedSelectedImage? { cancelled ? nil : image }
        func cancel() { cancelled = true }
    }
    let picked: RetainedSelectedImage
    let wire: Wire
    private let client: ProjectStoryImageUploadClient
    var uploadCount: Int { wire.requests.count }
    var reference: String { wire.reference }
    init(session: ProjectEditSession, beforeReply: (() -> Void)? = nil, currentSession: @escaping () -> ProjectEditSession?) throws {
        let wire = Wire(); self.wire = wire
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 48))
        let png = renderer.pngData { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 96, height: 48))
            UIColor.white.setFill(); context.fill(CGRect(x: 16, y: 12, width: 28, height: 24))
        }
        picked = try RetainedImageSanitizer.sanitize(png)
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let approval = try ProjectStoryImageUploadApproval(baseURL: configuration.baseURL, namespace: session.storageNamespace, accountID: session.accountID, approvedOrigins: ["https://example.com"], nativePicker: true)
        wire.beforeReply = beforeReply
        client = .init(configuration: configuration, approval: approval, transport: wire, credentials: {
            guard let current = currentSession(), current == session else { return nil }
            return try? .init(session: current, token: "synthetic-story-image")
        }, currentApproval: { currentSession() == session ? approval : nil })
    }
    func isCurrent(session: ProjectEditSession) -> Bool { client.isCurrent(session: session) }
    func permitsPicker(session: ProjectEditSession) -> Bool { client.permitsPicker(session: session) }
    func permitsReference(_ reference: String, session: ProjectEditSession) -> Bool { client.permitsReference(reference, session: session) }
    func upload(_ image: RetainedSelectedImage, attemptID: UUID, session: ProjectEditSession) async throws -> ProjectStoryUploadedImage {
        try await client.upload(image, attemptID: attemptID, session: session)
    }
}
#endif
