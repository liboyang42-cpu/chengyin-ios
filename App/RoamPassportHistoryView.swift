import SwiftUI

private struct RoamPassportHistoryReaderKey: EnvironmentKey {
    static let defaultValue: (any RoamPassportHistoryReading)? = nil
}
extension EnvironmentValues {
    var roamPassportHistoryReader: (any RoamPassportHistoryReading)? {
        get { self[RoamPassportHistoryReaderKey.self] }
        set { self[RoamPassportHistoryReaderKey.self] = newValue }
    }
}
private func passportText(_ key: String) -> Text { Text(LocalizedStringKey("roam.serverHistory." + key), tableName: "RoamPassportHistory") }

/// Additive entry from the original local-history page. Nil hosts keep their existing page unchanged.
@MainActor struct RoamPassportHistoryNavigation: ViewModifier {
    @Environment(\.roamPassportHistoryReader) private var reader
    let localReader: any RoamExperienceReading
    @State private var target: Target?
    private struct Target: Hashable { let id = UUID(); let owner: RoamPassportHistoryOwner }
    func body(content: Content) -> some View {
        if let reader {
            let offered = RoamPassportHistoryOwner(reader)
            content.safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        guard offered == RoamPassportHistoryOwner(reader), offered.configured, offered.storageKey != nil, target == nil else { return }
                        target = Target(owner: offered)
                    } label: { Label { passportText("open") } icon: { Image(systemName: "icloud") } }
                        .disabled(!offered.configured || offered.storageKey == nil)
                        .accessibilityIdentifier("roam.serverHistory.open")
                    if !offered.configured { Text(LocalizedStringKey(reader.identity == nil ? "roam.signInRequired" : "roam.notConfigured")).font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.regularMaterial)
            }
            .onChange(of: offered) { _, _ in target = nil }
            // The destination belongs to the outer page, never a lazy list row.
            .navigationDestination(item: $target) { target in
                if target.owner == RoamPassportHistoryOwner(reader) {
                    RoamPassportHistoryView(reader: reader, localReader: localReader, owner: target.owner)
                } else { passportText("changed") }
            }
        } else { content }
    }
}

@MainActor struct RoamPassportHistoryView: View {
    let reader: any RoamPassportHistoryReading
    let localReader: (any RoamExperienceReading)?
    let owner: RoamPassportHistoryOwner
    @State private var model: RoamPassportHistoryCoordinator
    @State private var selected: Selection?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    private struct Selection: Identifiable { let id: String; let owner: RoamPassportHistoryOwner }
    init(reader: any RoamPassportHistoryReading, localReader: (any RoamExperienceReading)? = nil, owner: RoamPassportHistoryOwner? = nil) {
        self.reader = reader; self.localReader = localReader; self.owner = owner ?? .init(reader)
        _model = State(initialValue: .init(reader: reader))
    }
    var body: some View {
        let refresh = model.intent(.refresh), more = model.intent(.more), retry = model.intent(model.retryOperation), summary = model.intent(.summary)
        List {
            if owner != RoamPassportHistoryOwner(reader) { passportText("changed") }
            else if !reader.isConfigured || reader.identity == nil { Text(LocalizedStringKey(reader.identity == nil ? "roam.signInRequired" : "roam.notConfigured")) }
            else if scenePhase == .active {
                Section { passportText("boundary").font(.footnote).foregroundStyle(.secondary) }
                if model.isVisible {
                    Section {
                        if let value = model.summary {
                            metric("trips", String(value.trips)); metric("distance", value.distanceM.map { String(format: "%.1f km", locale: locale, Double($0) / 1000) } ?? "—")
                            metric("days", value.days.map(String.init) ?? "—"); metric("shops", value.shops.map(String.init) ?? "—")
                        }
                        if let error = model.summaryError {
                            RoamExperienceIssue(error: error) { Task { await model.read(summary) } }
                        }
                        if model.summary == nil && model.summaryError == nil { passportText("summaryPending") }
                    } header: { passportText("summary") }
                    Section {
                        if let error = model.pageError { RoamExperienceIssue(error: error) { Task { await model.read(retry) } } }
                        if model.loaded && model.items.isEmpty { passportText("empty").accessibilityIdentifier("roam.serverHistory.empty") }
                        ForEach(model.items) { item in
                            Button {
                                guard model.isVisible, owner == RoamPassportHistoryOwner(reader), model.items.contains(item), selected == nil else { return }
                                selected = .init(id: item.sessionID, owner: owner)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(verbatim: "#" + item.sessionID).font(.headline)
                                    if let date = passportDate(item.timestamp) { Text(date, format: .dateTime.year().month().day().hour().minute()) }
                                    else { passportText("dateUnknown") }
                                    HStack { Text(verbatim: item.distanceKM.map { String(format: "%.1f km", locale: locale, $0) } ?? "—"); Spacer(); Image(systemName: "chevron.right") }
                                }
                            }.accessibilityIdentifier("roam.serverHistory.record")
                        }
                        if model.busy { ProgressView("roam.loading") }
                        else if model.hasMore {
                            Button("roam.experience.loadMore") { Task { await model.read(more) } }.accessibilityIdentifier("roam.serverHistory.more")
                        }
                        if !model.busy {
                            Button("action.retry") { Task { await model.read(refresh) } }.accessibilityIdentifier("roam.serverHistory.refresh")
                        }
                    } header: { passportText("records") }
                }
            }
        }
        .navigationTitle(passportText("title"))
        .task {
            guard scenePhase == .active, owner == RoamPassportHistoryOwner(reader), !Task.isCancelled else { return }
            model.activate(); await model.read(model.intent(.refresh))
        }
        .onChange(of: scenePhase) { _, phase in
            selected = nil
            if phase == .active { model.activate() } else { model.suspend() }
        }
        .onChange(of: RoamPassportHistoryOwner(reader)) { _, _ in selected = nil; model.suspend() }
        .onDisappear { model.suspend() }
        .refreshable { await model.read(refresh) }
        .sheet(item: $selected) { selected in
            if selected.owner == RoamPassportHistoryOwner(reader) {
                NavigationStack { RoamPassportRecordView(reader: reader, sessionID: selected.id, localReader: localReader, owner: selected.owner) }
            } else { passportText("changed") }
        }
        .privacySensitive().accessibilityIdentifier("roam.serverHistory.page")
    }
    private func metric(_ key: String, _ value: String) -> some View { LabeledContent { Text(verbatim: value) } label: { passportText(key) } }
}

@MainActor struct RoamPassportRecordView: View {
    let reader: any RoamPassportHistoryReading
    let owner: RoamPassportHistoryOwner
    @State private var model: RoamPassportRecordCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    init(reader: any RoamPassportHistoryReading, sessionID: String, localReader: (any RoamExperienceReading)? = nil, owner: RoamPassportHistoryOwner? = nil) {
        self.reader = reader; self.owner = owner ?? .init(reader)
        _model = State(initialValue: .init(reader: reader, sessionID: sessionID, localReader: localReader))
    }
    var body: some View {
        let retry = model.intent()
        List {
            if owner != RoamPassportHistoryOwner(reader) { passportText("changed") }
            else if !reader.isConfigured || reader.identity == nil { Text(LocalizedStringKey(reader.identity == nil ? "roam.signInRequired" : "roam.notConfigured")) }
            else if scenePhase == .active && model.isVisible {
                if model.isMissing {
                    ContentUnavailableView("roam.experience.recordMissing", systemImage: "questionmark.folder")
                        .accessibilityIdentifier("roam.serverHistory.detail.missing")
                } else if let error = model.error { RoamExperienceIssue(error: error) { Task { await model.read(retry) } } }
                if let fact = model.fact {
                    Section {
                        Text(verbatim: "#" + fact.sessionID).font(.headline)
                        if let date = passportDate(fact.timestamp) { Text(date, format: .dateTime.year().month().day().hour().minute()) }
                        else { passportText("dateUnknown") }
                        LabeledContent { Text(verbatim: fact.distanceKM.map { String(format: "%.1f km", locale: locale, $0) } ?? "—") } label: { passportText("distance") }
                        LabeledContent { Text(verbatim: fact.shops.map(String.init) ?? "—") } label: { passportText("shops") }
                        LabeledContent { Text(verbatim: fact.durationSeconds.map { "\($0 / 3600):" + String(format: "%02lld", $0 % 3600 / 60) } ?? "—") } label: { passportText("duration") }
                        RoamPassportTrackView(track: model.track, places: model.supplement?.pois.map(\.point) ?? [])
                        passportText("trackBoundary").font(.caption).foregroundStyle(.secondary)
                    }
                    if let local = model.supplement {
                        Section {
                            if let zone = local.meaningfulZone { Text(verbatim: zone) }
                            LabeledContent { Text(verbatim: String(local.photos.count)) } label: { passportText("photos") }
                            passportText("localBoundary").font(.caption).foregroundStyle(.secondary)
                        } header: { passportText("localSupplement") }
                    }
                }
                if model.busy { ProgressView("roam.loading") }
                else { Button("action.retry") { Task { await model.read(retry) } }.accessibilityIdentifier("roam.serverHistory.detail.retry") }
            }
        }
        .navigationTitle(passportText("recordTitle"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("action.close") { dismiss() } } }
        .task {
            guard scenePhase == .active, owner == RoamPassportHistoryOwner(reader), !Task.isCancelled else { return }
            model.activate(); await model.read(model.intent())
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.activate() } else { model.suspend() } }
        .onChange(of: RoamPassportHistoryOwner(reader)) { _, _ in model.suspend() }
        .onDisappear { model.suspend() }
        .privacySensitive().accessibilityIdentifier("roam.serverHistory.detail")
    }
}
private func passportDate(_ timestamp: Int64) -> Date? {
    guard timestamp > 0 && timestamp <= 253_402_300_799_999 else { return nil }
    return Date(timeIntervalSince1970: Double(timestamp) / 1000)
}
private struct RoamPassportTrackView: View {
    let track: [RoamHistoryPoint]
    let places: [RoamHistoryPoint]
    var body: some View {
        let sketch = RoamRouteSketch(track: track, places: places)
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.08))
            if sketch.track.isEmpty { Text("roam.experience.noTrack").font(.caption) }
            else {
                Canvas { context, size in
                    var path = Path()
                    for (index, point) in sketch.track.enumerated() {
                        let p = CGPoint(x: point.x * size.width, y: point.y * size.height)
                        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(.accentColor), lineWidth: 3)
                    for point in sketch.places {
                        context.fill(Path(ellipseIn: CGRect(x: point.x * size.width - 3, y: point.y * size.height - 3, width: 6, height: 6)), with: .color(.primary))
                    }
                }.padding(8).accessibilityHidden(true)
            }
        }.frame(height: 180).accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(sketch.track.isEmpty ? "roam.experience.noTrack" : "roam.experience.routeSketch"))
    }
}
