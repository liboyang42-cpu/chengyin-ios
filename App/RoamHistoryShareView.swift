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
    @State private var renderedRecord: RoamHistoryRecord?
    @State private var renderedIncludeRoute = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("roam.share.privacy").foregroundStyle(.secondary)
                if !record.track.isEmpty {
                    Toggle("roam.share.includeRoute", isOn: $includeRoute).onChange(of: includeRoute) { _, _ in invalidateImage() }
                }
                card
                if renderingFailed { Text("roam.share.renderFailed").foregroundStyle(.secondary) }
                if let image, renderedRecord == record, renderedIncludeRoute == includeRoute {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview(Text("roam.share.title"), image: Image(uiImage: image))) {
                        Label("roam.share.system", systemImage: "square.and.arrow.up")
                    }.accessibilityIdentifier("roam.share.system")
                } else {
                    Button("roam.share.prepare", systemImage: "photo") {
                        let renderer = ImageRenderer(content: card.frame(width: 320).padding(24).background(Color(uiColor: .systemBackground)))
                        renderer.scale = min(3, displayScale)
                        image = renderer.uiImage; renderingFailed = image == nil
                        renderedRecord = image == nil ? nil : record
                        renderedIncludeRoute = includeRoute
                    }.accessibilityIdentifier("roam.share.prepare")
                }
                Text("roam.share.saveHint").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("roam.share.title")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("action.done") { dismiss() } } }
            .onChange(of: record) { _, _ in includeRoute = false; invalidateImage() }
            .onDisappear { invalidateImage() }
    }
    private func invalidateImage() {
        image = nil; renderedRecord = nil; renderingFailed = false
    }
    private var privateRoute: some View {
        let sketch = RoamShareRoutePrivacy.sketch(for: record)
        return ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Color.accentColor.opacity(0.09))
            if sketch.track.isEmpty {
                Label("roam.experience.noTrack", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.caption).padding()
            } else {
                Canvas { context, size in
                    var path = Path()
                    for (index, point) in sketch.track.enumerated() {
                        let position = CGPoint(x: point.x * size.width, y: point.y * size.height)
                        if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                    }
                    context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }.padding(8).accessibilityHidden(true)
            }
        }.frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(sketch.track.isEmpty ? "roam.experience.noTrack" : "roam.experience.routeSketch"))
            .accessibilityIdentifier("roam.share.clippedRoute")
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("roam.experience.cityWalk", systemImage: "figure.walk.circle.fill").font(.title).bold()
            if let date = record.recordedAt { Text(date, style: .date).foregroundStyle(.secondary) }
            RoamRecordedStats(record: record)
            if includeRoute { privateRoute }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
