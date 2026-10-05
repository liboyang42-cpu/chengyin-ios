import SwiftUI
import UIKit

@MainActor struct RetainedPublicReviewImages: View {
    let urls: [String]
    let reader: any RetainedPublicImageReading
    @State private var selected: String?
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))]) {
            ForEach(Array(urls.prefix(9).enumerated()), id: \.offset) { index, raw in
                Button { selected = raw } label: { RetainedPublicImageTile(raw: raw, reader: reader) }
                    .accessibilityLabel(Text("image.retained.preview"))
                    .accessibilityValue(Text("\(index + 1) / \(min(urls.count, 9))"))
                    .accessibilityIdentifier("image.retained.reviewPhoto.\(index)")
            }
        }.sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            NavigationStack {
                if let selected { RetainedPublicImageTile(raw: selected, reader: reader).padding() }
                Button("image.retained.close") { selected = nil }
            }
        }.onDisappear { selected = nil }
    }
}
@MainActor private struct RetainedPublicImageTile: View {
    let raw: String
    let reader: any RetainedPublicImageReading
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Label(failed ? "image.retained.failed" : "image.retained.photos", systemImage: "photo") }
        }.frame(minWidth: 44, minHeight: 88)
        .task(id: raw) {
            image = nil; failed = false
            guard reader.enabled, let url = URL(string: raw) else { return }
            do {
                let bytes = try await reader.image(url: url)
                try Task.checkCancellation()
                let sanitized = try RetainedImageSanitizer.sanitize(bytes)
                try Task.checkCancellation(); image = UIImage(data: sanitized.jpeg)
            } catch { if !Task.isCancelled { failed = true } }
        }.onDisappear { image = nil }
    }
}
