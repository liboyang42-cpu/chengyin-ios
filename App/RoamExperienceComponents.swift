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
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("roam.experience.error")
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
    var visibleSegments: Int? = nil
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
                    let segmentCount = max(0, sketch.track.count - 1)
                    let pointCount = visibleSegments.map { min(segmentCount, max(0, $0)) + 1 } ?? sketch.track.count
                    for (index, point) in sketch.track.prefix(pointCount).enumerated() {
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

/// Replays only the stored sketch. This view has no location, network or write capability.
@MainActor struct RoamSavedRouteReplayView: View {
    let reader: any RoamExperienceReading
    let record: RoamHistoryRecord
    @Environment(\.scenePhase) private var scenePhase
    @QuestifyReduceMotion private var reduceMotion
    @State private var replay = RoamRouteReplayState()
    @State private var visible = false
    @State private var request: Request?
    private struct Request {
        let id = UUID()
        let context: RoamRouteReplayState.Context
        let counts: [Int]
    }
    private var owner: RoamRouteReplayState.Owner { .init(reader: reader, record: record) }
    var body: some View {
        let current = owner
        let context = replay.context(for: current)
        VStack(alignment: .leading, spacing: 12) {
            // Always normalize the complete record; revealing a prefix never rescales it.
            RoamRouteSketchView(record: record, visibleSegments: context == nil ? nil : replay.visibleSegments)
            if let context {
                if replay.phase == .playing {
                    Button("roamRouteReplay.skip", systemImage: "forward.end") {
                        synchronize()
                        guard replay.accepts(context, current: owner) else { return }
                        replay.skip(in: context, current: owner); request = nil
                    }.frame(minHeight: 44).accessibilityIdentifier("roamRouteReplay.skip")
                } else {
                    Button(LocalizedStringKey(replay.phase == .completed ? "roamRouteReplay.again" : "roamRouteReplay.start"), systemImage: "play") {
                        synchronize()
                        guard replay.accepts(context, current: owner) else { return }
                        if let ticket = replay.start(in: context, current: owner) {
                            request = Request(context: ticket, counts: replay.plan.counts)
                        }
                    }.frame(minHeight: 44).accessibilityIdentifier("roamRouteReplay.start")
                }
                ProgressView(value: replay.progress, total: 1)
                    .accessibilityLabel(Text("roamRouteReplay.progress"))
                    .accessibilityValue(Text(replay.progress, format: .percent.precision(.fractionLength(0))))
                    .accessibilityIdentifier("roamRouteReplay.progress")
                Text(LocalizedStringKey(replay.phase == .playing ? "roamRouteReplay.playing" : (replay.phase == .completed ? "roamRouteReplay.completed" : "roamRouteReplay.ready")))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { visible = true; synchronize() }
        .onDisappear { visible = false; synchronize() }
        .onChange(of: owner) { _, _ in synchronize() }
        .onChange(of: scenePhase) { _, _ in synchronize() }
        .onChange(of: reduceMotion) { _, _ in synchronize() }
        .task(id: request?.id) {
            guard let captured = request else { return }
            for (index, count) in captured.counts.enumerated() {
                if index > 0 {
                    do { try await Task.sleep(nanoseconds: RoamRouteReplayPlan.intervalNanoseconds) }
                    catch { return }
                }
                if reduceMotion { synchronize(); return }
                guard !Task.isCancelled, visible, scenePhase == .active,
                      replay.accepts(captured.context, current: owner) else { return }
                replay.advance(to: count, in: captured.context, current: owner)
            }
            // No old-task cleanup can clear a later request.
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roamRouteReplay.saved")
    }
    private func synchronize() {
        replay.update(owner: owner, active: visible && scenePhase == .active, reduceMotion: reduceMotion)
        if let captured = request, !replay.accepts(captured.context, current: owner) { request = nil }
    }
}
