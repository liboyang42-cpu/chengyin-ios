import SwiftUI

@MainActor struct RoamHistoryView: View {
    let reader: any RoamExperienceReading
    var liveDestination: (() -> AnyView)? = nil
    @State private var records: [RoamHistoryRecord] = []
    @State private var error: Error?
    @State private var loaded = false
    @State private var liveEntry = RoamHistoryLiveEntry()
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                if let error { RoamExperienceIssue(error: error, retry: load) }
                else if !loaded { ProgressView("roam.loading") }
                else if records.isEmpty {
                    ContentUnavailableView("roam.experience.historyEmpty", systemImage: "figure.walk", description: Text("roam.experience.historyEmptyHint"))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("roam.experience.history.empty")
                    if liveEntry.canOpen(reader: reader, hasDestination: liveDestination != nil) {
                        let presentationID = liveEntry.presentationID
                        Button("roam.experience.live", systemImage: "figure.walk") {
                            liveEntry.activate(reader: reader, hasDestination: liveDestination != nil, presentationID: presentationID)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("roam.experience.history.live.open")
                    }
                } else {
                    let summary = RoamHistorySummary(records)
                    RoamExperienceCard {
                        LabeledContent("roam.experience.trips", value: String(summary.trips)).font(.headline)
                        if let distance = summary.knownKilometers, summary.tripsWithDistance > 0 {
                            LabeledContent("roam.experience.knownDistance") { Text(distance, format: .number.precision(.fractionLength(1))) + Text(verbatim: " km") }
                        }
                        Text("roam.experience.partialStats").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(records) { record in
                        NavigationLink { RoamHistoryDetailView(reader: reader, timestamp: record.ts) } label: {
                            RoamExperienceCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    if let zone = record.meaningfulZone { Text(verbatim: zone).font(.title3).bold() }
                                    else { Text("roam.experience.cityWalk").font(.title3).bold() }
                                    if let date = record.recordedAt { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
                                    RoamRouteSketchView(record: record)
                                    RoamRecordedStats(record: record)
                                }
                            }
                        }.buttonStyle(QuestifyCardButtonStyle())
                            .accessibilityIdentifier("roam.experience.history.record")
                    }
                }
            }.padding()
        }.navigationTitle("roam.experience.history")
            .task(id: RoamHistoryLiveOwner(reader: reader)) { load() }
            .onAppear { liveEntry.appear() }
            .onDisappear { liveEntry.disappear() }
            .onChange(of: RoamHistoryLiveOwner(reader: reader)) { _, _ in
                liveEntry.retireIfOwnerChanged(reader: reader, hasDestination: liveDestination != nil)
            }
            .onChange(of: liveDestination != nil) { _, _ in
                liveEntry.retireIfOwnerChanged(reader: reader, hasDestination: liveDestination != nil)
            }
            .navigationDestination(item: $liveEntry.target) { target in
                if liveEntry.matches(target, reader: reader, hasDestination: liveDestination != nil), let liveDestination {
                    liveDestination()
                }
            }
            .accessibilityIdentifier("roam.experience.history")
    }
    private func load() {
        records = []; error = nil; loaded = false
        let snapshot = liveEntry.beginRead(reader: reader)
        do {
            records = try reader.history(); loaded = true
            liveEntry.acceptRead(isEmpty: records.isEmpty, snapshot: snapshot, reader: reader)
        } catch { self.error = error }
    }
}

/// This only selects the already supplied live screen. It never creates or starts a roam session.
struct RoamHistoryLiveOwner: Equatable, Hashable {
    let readerID: ObjectIdentifier
    let scopeKey: String?
    let epoch: UInt64?
    let isConfigured: Bool
    @MainActor init(reader: any RoamExperienceReading) {
        let identity = reader.identity
        readerID = ObjectIdentifier(reader)
        // storageKey preserves the exact UTF-8 namespace, market, deployment and account bytes.
        scopeKey = identity?.scope.storageKey
        epoch = identity?.epoch
        isConfigured = reader.isConfigured
    }
    var isAuthorized: Bool { scopeKey != nil && isConfigured }
}
@MainActor struct RoamHistoryLiveEntry {
    struct Target: Hashable {
        let id = UUID()
        let owner: RoamHistoryLiveOwner
    }
    private var owner: RoamHistoryLiveOwner?
    private var successfulEmptyRead = false
    private var visible = false
    private(set) var presentationID = UUID()
    var target: Target?

    mutating func beginRead(reader: any RoamExperienceReading) -> RoamHistoryLiveOwner {
        invalidate()
        let snapshot = RoamHistoryLiveOwner(reader: reader)
        owner = snapshot
        return snapshot
    }
    mutating func acceptRead(isEmpty: Bool, snapshot: RoamHistoryLiveOwner, reader: any RoamExperienceReading) {
        successfulEmptyRead = isEmpty && owner == snapshot && snapshot == RoamHistoryLiveOwner(reader: reader)
    }
    mutating func appear() { visible = true; presentationID = UUID() }
    mutating func disappear() {
        // Pushing the live screen hides this view; retain its active destination until native Back.
        visible = false; presentationID = UUID()
    }
    func canOpen(reader: any RoamExperienceReading, hasDestination: Bool) -> Bool {
        visible && target == nil && hasDestination && successfulEmptyRead && owner?.isAuthorized == true
            && owner == RoamHistoryLiveOwner(reader: reader)
    }
    mutating func activate(reader: any RoamExperienceReading, hasDestination: Bool, presentationID: UUID) {
        guard self.presentationID == presentationID, canOpen(reader: reader, hasDestination: hasDestination), let owner else { return }
        target = Target(owner: owner)
    }
    func matches(_ target: Target, reader: any RoamExperienceReading, hasDestination: Bool) -> Bool {
        self.target == target && hasDestination && target.owner.isAuthorized
            && target.owner == RoamHistoryLiveOwner(reader: reader)
    }
    mutating func retireIfOwnerChanged(reader: any RoamExperienceReading, hasDestination: Bool) {
        if owner != RoamHistoryLiveOwner(reader: reader) || !hasDestination { invalidate() }
    }
    private mutating func invalidate() {
        target = nil; owner = nil; successfulEmptyRead = false; presentationID = UUID()
    }
}
@MainActor struct RoamHistoryDetailView: View {
    let reader: any RoamExperienceReading
    let timestamp: Int64
    @State private var record: RoamHistoryRecord?
    @State private var showShare = false
    @State private var loaded = false
    @State private var error: Error?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                if let error { RoamExperienceIssue(error: error, retry: load) }
                else if let record {
                    RoamExperienceCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Label("roam.experience.savedRecord", systemImage: "book.closed").font(.caption).foregroundStyle(.secondary)
                            if let zone = record.meaningfulZone { Text(verbatim: zone).font(.title2).bold() }
                            else { Text("roam.experience.cityWalk").font(.title2).bold() }
                            if let date = record.recordedAt { Text(date, style: .date) }
                            RoamRouteSketchView(record: record)
                            RoamRecordedStats(record: record)
                        }
                    }
                    if !record.pois.isEmpty {
                        Text("roam.experience.recordedPlaces").font(.headline)
                        ForEach(Array(record.pois.enumerated()), id: \.offset) { _, place in
                            Label { RoamTitle(place.name) } icon: { Image(systemName: place.cat == "merchant" ? "storefront" : "mappin") }
                        }
                    }
                    if let medal = record.medal { Label { Text(verbatim: medal) } icon: { Image(systemName: "medal") } }
                    if let medal = record.shopMedalName { Label { Text(verbatim: medal) } icon: { Image(systemName: "medal") } }
                    if !record.photos.isEmpty { LabeledContent("roam.experience.savedPhotoReferences", value: String(record.photos.count)) }
                    Button("roam.share.title", systemImage: "square.and.arrow.up") { showShare = true }
                        .accessibilityIdentifier("roam.share.open")
                    Text("roam.experience.historyPrivacy").font(.caption).foregroundStyle(.secondary)
                } else if loaded {
                    ContentUnavailableView("roam.experience.recordMissing", systemImage: "questionmark.folder", description: Text("roam.experience.recordMissingHint"))
                        .accessibilityIdentifier("roam.experience.history.missing")
                } else { ProgressView("roam.loading") }
            }.padding()
        }.navigationTitle("roam.experience.session")
            .task(id: reader.identity) { showShare = false; load() }
            .sheet(isPresented: $showShare) { if let record { NavigationStack { RoamHistoryShareView(record: record) } } }
            .accessibilityIdentifier("roam.experience.session")
    }
    private func load() {
        record = nil; error = nil; loaded = false
        do { record = try reader.history().first { $0.ts == timestamp }; loaded = true } catch { self.error = error }
    }
}
