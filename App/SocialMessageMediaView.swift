import SwiftUI
import ImageIO

@MainActor struct SocialMessageMediaView: View {
    let message: MessagingMessage
    let reader: any SocialMessageMediaReading
    let expectedIdentity: MessagingReadIdentity
    var isMessageCurrent: () -> Bool = { true }
    @State private var image: UIImage?
    @State private var error: Error?
    @State private var loading = false
    @State private var generation = 0
    @State private var requested = false
    private var media: SocialMessageMedia? { try? .init(message: message) }
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 16) {
                if !isMessageCurrent() || reader.identity != expectedIdentity { SocialIssueView(error: APIError.unauthorized) }
                else if let media {
                    if reader.isOfflineExample { Text("social.offline").font(.caption) }
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 1200, maxHeight: 1200)
                            .accessibilityLabel("social.media.image").accessibilityIdentifier("social.media.loaded")
                    } else {
                        Label("social.media.image", systemImage: "photo").font(.title)
                        if !reader.isConfigured { Text("social.media.disabled") }
                        else {
                            Text("social.media.purpose").font(.footnote)
                            // Display only origin, never leak signed query parameters.
                            Text(verbatim: SocialMessageMediaService.origin(media.url) ?? "").font(.caption)
                            Button(LocalizedStringKey(requested ? "action.retry" : "social.media.load")) { Task { await load(media) } }
                                .disabled(loading).accessibilityIdentifier("social.media.load")
                        }
                        if loading { ProgressView("social.loading") }
                        if error != nil { Text("social.media.failed").accessibilityIdentifier("social.media.failed") }
                    }
                } else { Text("social.media.invalid") }
            }.padding()
        }
        .appNavigationTitle("social.media.title").privacySensitive()
        .onChange(of: isMessageCurrent()) { _, _ in clear() }
        .onChange(of: reader.identity) { _, _ in clear() }
        .onDisappear { clear() }
        .accessibilityIdentifier("social.media")
    }
    private func load(_ media: SocialMessageMedia) async {
        guard !loading, isMessageCurrent(), reader.identity == expectedIdentity else { return }
        generation += 1; let run = generation; loading = true; requested = true; error = nil
        defer { if run == generation { loading = false } }
        do {
            let data = try await reader.image(media, expectedIdentity: expectedIdentity)
            try Task.checkCancellation()
            // Inspect dimensions before creating the decoded bitmap. Avoid huge/decompression-bomb images.
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0,
                  width.doubleValue * height.doubleValue <= 32_000_000,
                  let decoded = UIImage(data: data) else { throw SocialMediaFailure.notImage }
            guard run == generation, isMessageCurrent(), reader.identity == expectedIdentity else { return }; image = decoded
        } catch is CancellationError { }
        catch { if run == generation, isMessageCurrent(), reader.identity == expectedIdentity { self.error = error } }
    }
    private func clear() { generation += 1; image = nil; error = nil; loading = false; requested = false }
}
