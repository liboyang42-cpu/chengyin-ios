#if DEBUG
import SwiftUI
import UIKit

private final class RetainedImageFixtureTransport: HTTPTransport {
    let unknown: Bool
    init(unknown: Bool) { self.unknown = unknown }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        // No URLSession/socket. This only returns authored bytes.
        (Data((unknown ? "not-json" : #"{"code":200,"url":"https://media.example.com/synthetic.jpg"}"#).utf8), 200)
    }
}
@MainActor private final class RetainedFixtureJournalStorage {
    private var values: [String: Data] = [:]
    func journal() -> StoredImageUploadJournal {
        StoredImageUploadJournal(read: { self.values[$0] }, write: { self.values[$1] = $0 })
    }
}
@MainActor struct RetainedImageFixtureView: View {
    private let context: RetainedImageSelectionContext
    @State private var applied = false
    init(mode: String = "success") {
        let scope = try! RetainedImageScope(accountID: 8, epoch: UUID(), realm: "https://api.example.com",
            destination: .publicReview(merchantRowID: 73, registrationID: 19), namespace: "fixture")
        let upload = try! RetainedImageHTTPUploader(configuration: .init(baseURL: URL(string: scope.realm)!),
            transport: RetainedImageFixtureTransport(unknown: mode == "unknown"), enabled: true,
            approvedOrigins: ["https://media.example.com"], currentScope: { scope }, token: { "fixture-token" })
        context = .init(scope: scope, currentScope: { scope }, picker: .init(present: { _ in false }, dismiss: {}),
                        uploads: .init(uploader: upload, journal: RetainedFixtureJournalStorage().journal()))
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("image.retained.synthetic")
                Button("image.retained.syntheticSelect") {
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                    let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
                        UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
                    }
                    if let bytes = image.jpegData(compressionQuality: 0.9), let sanitized = try? RetainedImageSanitizer.sanitize(bytes) {
                        context.uploads.prepare(sanitized, scope: context.scope)
                    }
                }.accessibilityIdentifier("image.retained.fixtureSelect")
                RetainedImageSelectionView(context: context) { _ in applied = true; return true }
                if applied { Text("image.retained.uploaded").accessibilityIdentifier("image.retained.fixtureApplied") }
            }
        }
    }
}
#endif
