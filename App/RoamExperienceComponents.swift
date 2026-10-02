import SwiftUI

struct RoamExperienceNotice: View {
    let offline: Bool
    var body: some View {
        Label(offline ? "roam.experience.offline" : "roam.experience.readOnly", systemImage: offline ? "testtube.2" : "lock.shield")
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("roam.experience.notice")
    }
}
struct RoamExperienceIssue: View {
    let error: Error
    var retry: (() -> Void)? = nil
    private var key: LocalizedStringKey {
        if error as? APIError == .unauthorized { return "roam.signInRequired" }
        if error as? APIError == .notConfigured { return "roam.notConfigured" }
        if error as? RoamExperienceFailure == .historyUnreadable { return "roam.experience.historyUnreadable" }
        return "roam.experience.readFailed"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(key, systemImage: "exclamationmark.circle")
            if let retry, error as? APIError != .unauthorized, error as? APIError != .notConfigured {
                Button("action.retry", action: retry).accessibilityIdentifier("roam.experience.retry")
            }
        }.accessibilityIdentifier("roam.experience.error")
    }
}
struct RoamExperienceCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(.primary.opacity(0.1), lineWidth: 1) }
    }
}
struct RoamRouteSketchView: View {
    let record: RoamHistoryRecord
    var body: some View {
        let sketch = RoamRouteSketch(track: record.track, places: record.pois.map(\.point))
        ZStack {
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
                    for point in sketch.places {
                        let rect = CGRect(x: point.x * size.width - 5, y: point.y * size.height - 5, width: 10, height: 10)
                        context.fill(Path(ellipseIn: rect), with: .color(.primary))
                    }
                }.padding(8).accessibilityHidden(true)
            }
        }.frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(sketch.track.isEmpty ? "roam.experience.noTrack" : "roam.experience.routeSketch"))
    }
}
struct RoamRecordedStats: View {
    let record: RoamHistoryRecord
    var body: some View {
        VStack(spacing: 8) {
            if let distance = record.distance {
                LabeledContent("roam.experience.distance") { Text(distance, format: .number.precision(.fractionLength(1))) + Text(verbatim: " km") }
            }
            if let duration = record.durationText { LabeledContent("roam.experience.duration", value: duration) }
            if let shops = record.shops { LabeledContent("roam.experience.shops", value: String(shops)) }
            if record.distance == nil && record.durationText == nil && record.shops == nil { Text("roam.experience.statsUnknown").foregroundStyle(.secondary) }
        }.font(.subheadline).monospacedDigit()
    }
}
