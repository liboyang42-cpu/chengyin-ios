import SwiftUI
import UIKit

/// Local rendering only. The system sheet lets the user choose Save Image or a recipient;
/// no upload, public-feed post, private URL, tracking token or external message is generated here.
@MainActor struct RoamHistoryShareView: View {
    let record: RoamHistoryRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var includeRoute = false
    @State private var image: UIImage?
    @State private var renderingFailed = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("roam.share.privacy").foregroundStyle(.secondary)
                if !record.track.isEmpty {
                    Toggle("roam.share.includeRoute", isOn: $includeRoute).onChange(of: includeRoute) { _, _ in image = nil }
                }
                card
                if renderingFailed { Text("roam.share.renderFailed").foregroundStyle(.secondary) }
                if let image {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview(Text("roam.share.title"), image: Image(uiImage: image))) {
                        Label("roam.share.system", systemImage: "square.and.arrow.up")
                    }.accessibilityIdentifier("roam.share.system")
                } else {
                    Button("roam.share.prepare", systemImage: "photo") {
                        let renderer = ImageRenderer(content: card.frame(width: 320).padding(24).background(Color(uiColor: .systemBackground)))
                        renderer.scale = min(3, displayScale); image = renderer.uiImage; renderingFailed = image == nil
                    }.accessibilityIdentifier("roam.share.prepare")
                }
                Text("roam.share.saveHint").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("roam.share.title")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("action.done") { dismiss() } } }
            .onDisappear { image = nil }
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("roam.experience.cityWalk", systemImage: "figure.walk.circle.fill").font(.title).bold()
            if let date = record.recordedAt { Text(date, style: .date).foregroundStyle(.secondary) }
            RoamRecordedStats(record: record)
            if includeRoute { RoamRouteSketchView(record: record) }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
