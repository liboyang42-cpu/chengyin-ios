import SwiftUI

/// Supplied concretely by the ordinary session host, using existing readers/factories.
@MainActor struct RoamStampAlbumContinuation {
    let reader: any RoamExperienceReading
    let camera: () -> AnyView
}

@MainActor struct RoamCreatedStampView: View {
    let target: RoamCreatedStampTarget
    let album: RoamStampAlbumContinuation
    @State private var lookup: RoamCreatedStampLookup
    @State private var work: Task<Void, Never>?
    init(target: RoamCreatedStampTarget, album: RoamStampAlbumContinuation) {
        self.target = target; self.album = album
        _lookup = State(initialValue: .init(target: target, reader: album.reader))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !target.isCurrent(reader: album.reader) || lookup.phase == .unavailable {
                    ContentUnavailableView("roam.createdStamp.changed", systemImage: "person.crop.circle.badge.exclamationmark")
                        .accessibilityIdentifier("roam.createdStamp.changed")
                } else {
                    RoamExperienceNotice(offline: album.reader.isOfflineExample)
                    Text("roam.createdStamp.confirmed").font(.headline)
                    LabeledContent("roam.createdStamp.id", value: String(target.stampID))
                    Text("roam.createdStamp.readNotice").font(.footnote).foregroundStyle(.secondary)
                    result
                    NavigationLink {
                        RoamStampAlbumView(reader: album.reader, stampDestination: album.camera)
                    } label: { Label("roam.createdStamp.browse", systemImage: "rectangle.stack") }
                        .disabled(!album.reader.isConfigured)
                        .accessibilityIdentifier("roam.createdStamp.browse")
                }
            }.padding()
        }
        .navigationTitle("roam.createdStamp.title")
        .task { await lookup.refresh() }
        .onDisappear { work?.cancel(); work = nil; lookup.cancel() }
        .accessibilityIdentifier("roam.createdStamp.result")
    }
    @ViewBuilder private var result: some View {
        switch lookup.phase {
        case .idle, .loading:
            ProgressView("roam.loading")
        case .found:
            if let stamp = lookup.stamp, album.reader.isConfigured {
                RoamStampCard(stamp: stamp, offline: album.reader.isOfflineExample)
                    .accessibilityIdentifier("roam.createdStamp.match")
            }
            Button("action.retry", systemImage: "arrow.clockwise") { read(refresh: true) }
        case .more:
            Text("roam.createdStamp.moreHint")
            Button("roam.experience.loadMore") { read() }
                .accessibilityIdentifier("roam.createdStamp.more")
        case .hidden:
            Label("roam.createdStamp.hidden", systemImage: "eye.slash")
            Button("action.retry", systemImage: "arrow.clockwise") { read(refresh: true) }
        case .missing:
            Text("roam.createdStamp.missing")
            Button("action.retry", systemImage: "arrow.clockwise") { read(refresh: true) }
        case .failed:
            if let error = lookup.error { RoamExperienceIssue(error: error) { read() } }
        case .unavailable:
            EmptyView()
        }
    }
    private func read(refresh: Bool = false) {
        work?.cancel()
        work = Task { if refresh { await lookup.refresh() } else { await lookup.loadNext() } }
    }
}
