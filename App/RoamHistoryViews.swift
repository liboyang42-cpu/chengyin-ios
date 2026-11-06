import SwiftUI

@MainActor struct RoamHistoryView: View {
    let reader: any RoamExperienceReading
    var liveDestination: (() -> AnyView)? = nil
    /// 那年今日 / 月度回顾 reader; nil shows each tool's own "not configured" state.
    var toolsReader: (any RoamPassportToolsReading)? = nil
    /// Owner-only export; nil hides the 导出 tool.
    var privateToolsReader: (any RoamPrivateToolsServing)? = nil
    var anniversaryRouteDestination: ((String) -> AnyView)? = nil
    @State private var historyRead = RoamHistoryListRead()
    @State private var liveEntry = RoamHistoryLiveEntry()
    @State private var localWalk = RoamHistoryLocalWalkState()
    var body: some View {
        let records = historyRead.records(for: reader)
        let error = historyRead.error(for: reader)
        let loaded = historyRead.loaded(for: reader)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                if let error { RoamExperienceIssue(error: error, retry: load) }
                else if !loaded { ProgressView("roamSub.w208.history.loading") }
                else if records.isEmpty {
                    if toolsReader != nil { RoamHistoryToolsRow(reader: toolsReader, privateTools: privateToolsReader, anniversaryRouteDestination: anniversaryRouteDestination) }
                    if let keys = localWalk.noticeKeys(reader: reader) {
                        ContentUnavailableView(LocalizedStringKey(keys.title), systemImage: "pause.circle",
                            description: Text(LocalizedStringKey(keys.hint)))
                            .accessibilityIdentifier("roam.experience.history.unfinished")
                    } else {
                        ContentUnavailableView("roam.experience.historyEmpty", systemImage: "figure.walk", description: Text("roam.experience.historyEmptyHint"))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("roam.experience.history.empty")
                    }
                    if localWalk.failed(reader: reader) {
                        Label("roam.historyLocal.unreadable", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("action.retry", action: load).accessibilityIdentifier("roam.historyLocal.retry")
                    }
                    if liveEntry.canOpen(reader: reader, hasDestination: liveDestination != nil) {
                        let presentationID = liveEntry.presentationID
                        Button("roam.experience.live", systemImage: "figure.walk") {
                            liveEntry.activate(reader: reader, hasDestination: liveDestination != nil, presentationID: presentationID)
                        }
                        .buttonStyle(.questifyPrimary)
                        .accessibilityIdentifier("roam.experience.history.live.open")
                    }
                } else {
                    let summary = RoamHistorySummary(records)
                    // Mini-program order: total (big km, then trips and shops), tools, then run cards.
                    RoamExperienceCard { VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Group {
                                if let distance = summary.knownKilometers, summary.tripsWithDistance > 0 {
                                    Text(distance, format: .number.precision(.fractionLength(1)))
                                } else { Text(verbatim: "—") }
                            }
                            .font(.system(size: 52, weight: .heavy).italic()).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.5)
                            Text("roam.history.km").font(.headline).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        // 次漫游 · 公里 · 家店 on one line under the total, as in the mini-program.
                        RoamHistoryParityStrip(records: records)
                    } }
                    if toolsReader != nil { RoamHistoryToolsRow(reader: toolsReader, privateTools: privateToolsReader, anniversaryRouteDestination: anniversaryRouteDestination) }
                    ForEach(records) { record in
                        NavigationLink { RoamHistoryDetailView(reader: reader, timestamp: record.ts) } label: {
                            RoamExperienceCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    RoamRunCardTitle(record: record)
                                    RoamRouteSketchView(record: record)
                                    RoamRunCardParityMeta(record: record)
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
            .modifier(RoamPassportHistoryNavigation(localReader: reader))
            .accessibilityIdentifier("roam.experience.history")
    }
    private func load() {
        localWalk.invalidate()
        let snapshot = liveEntry.beginRead(reader: reader)
        guard historyRead.load(reader: reader, expected: snapshot) else { return }
        let records = historyRead.records(for: reader)
        if records.isEmpty { localWalk.load(reader: reader) }
        liveEntry.acceptRead(isEmpty: records.isEmpty, snapshot: snapshot, reader: reader)
    }
}

/// Fence the list's summary, rows and errors immediately, before a replacement
/// SwiftUI task reloads. Like detail/local-walk state, a read belongs to one owner.
@MainActor struct RoamHistoryListRead {
    private var owner: RoamHistoryLiveOwner?
    private var values: [RoamHistoryRecord] = []
    private var failure: Error?
    private var didLoad = false

    @discardableResult mutating func load(reader: any RoamExperienceReading,
                                         expected: RoamHistoryLiveOwner) -> Bool {
        owner = nil; values = []; failure = nil; didLoad = false
        guard expected == RoamHistoryLiveOwner(reader: reader) else { return false }
        do {
            let result = try reader.history()
            guard expected == RoamHistoryLiveOwner(reader: reader) else { return false }
            owner = expected; values = result; didLoad = true
            return true
        } catch {
            guard expected == RoamHistoryLiveOwner(reader: reader) else { return false }
            owner = expected; failure = error
            return false
        }
    }
    func records(for reader: any RoamExperienceReading) -> [RoamHistoryRecord] {
        owner == RoamHistoryLiveOwner(reader: reader) ? values : []
    }
    func error(for reader: any RoamExperienceReading) -> Error? {
        owner == RoamHistoryLiveOwner(reader: reader) ? failure : nil
    }
    func loaded(for reader: any RoamExperienceReading) -> Bool {
        owner == RoamHistoryLiveOwner(reader: reader) && didLoad
    }
}

/// A local read result is visible only to the exact reader/account/epoch that produced it.
@MainActor struct RoamHistoryLocalWalkState {
    private var owner: RoamHistoryLiveOwner?
    private var status: RoamLocalWalkStatus = .unavailable
    private var readFailed = false
    mutating func invalidate() { owner = nil; status = .unavailable; readFailed = false }
    mutating func load(reader: any RoamExperienceReading) {
        invalidate()
        let captured = RoamHistoryLiveOwner(reader: reader)
        guard captured.scopeKey != nil else { return }
        do {
            let value = try reader.localWalkStatus()
            guard captured == RoamHistoryLiveOwner(reader: reader) else { return }
            owner = captured; status = value
        } catch {
            guard captured == RoamHistoryLiveOwner(reader: reader) else { return }
            owner = captured; readFailed = true
        }
    }
    func failed(reader: any RoamExperienceReading) -> Bool {
        owner == RoamHistoryLiveOwner(reader: reader) && readFailed
    }
    func noticeKeys(reader: any RoamExperienceReading) -> (title: String, hint: String)? {
        guard owner == RoamHistoryLiveOwner(reader: reader), !readFailed else { return nil }
        switch status {
        case .unfinished: return ("roam.historyLocal.unfinished", "roam.historyLocal.unfinishedHint")
        case .finishPending: return ("roam.historyLocal.finishPending", "roam.historyLocal.finishPendingHint")
        case .unavailable, .none: return nil
        }
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
    @State private var selectedMedal: RoamMedalShareSelection?
    @State private var loaded = false
    @State private var error: Error?
    @State private var loadedOwner: ReadKey?
    private struct ReadKey: Hashable {
        let owner: RoamHistoryLiveOwner
        let timestamp: Int64
    }
    private var readKey: ReadKey { .init(owner: .init(reader: reader), timestamp: timestamp) }
    private var currentRecord: RoamHistoryRecord? { loadedOwner == readKey ? record : nil }
    private var currentError: Error? { loadedOwner == readKey ? error : nil }
    private var currentLoaded: Bool { loadedOwner == readKey && loaded }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                if let error = currentError { RoamExperienceIssue(error: error, retry: load) }
                else if let record = currentRecord {
                    RoamExperienceCard {
                        VStack(alignment: .leading, spacing: 18) {
                            RoamSessionParityHeader(record: record)
                            RoamSessionRouteNameText(name: RoamSessionRouteName(record)).font(.title3).bold()
                                .accessibilityIdentifier("roamSub.w208.session.routeName")
                            Text("roamSub.w208.session.completeFact").font(.subheadline).foregroundStyle(.secondary)
                            RoamSavedRouteReplayView(reader: reader, record: record)
                            RoamRecordedStats(record: record)
                        }
                    }
                    // 解锁奖励, then 点亮地点, each with its own empty line, as in the mini-program.
                    let medals = RoamMedalShareSelection.selections(for: record)
                    Text("roam.experience.rewards").font(.headline).accessibilityAddTraits(.isHeader)
                    if medals.isEmpty {
                        Text("roam.experience.rewardsEmpty").foregroundStyle(.secondary)
                    }
                    ForEach(medals) { medal in
                        Button { showShare = false; selectedMedal = medal } label: {
                            HStack {
                                Label { Text(verbatim: medal.card.name) } icon: { Image(systemName: "medal.fill").foregroundStyle(.yellow) }
                                Spacer(minLength: 0)
                                Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityLabel(Text("roam.medalShare.open") + Text(verbatim: ": " + medal.card.name))
                        .accessibilityIdentifier("roam.medalShare.open." + medal.card.kind.rawValue)
                    }
                    Text("roam.experience.recordedPlaces").font(.headline).accessibilityAddTraits(.isHeader)
                    if record.pois.isEmpty {
                        Text("roam.experience.recordedPlacesEmpty").foregroundStyle(.secondary)
                    }
                    ForEach(Array(record.pois.enumerated()), id: \.offset) { _, place in
                        Label { RoamTitle(place.name) } icon: { Image(systemName: place.cat == "merchant" ? "storefront" : "mappin") }
                    }
                    Button { showShare = true } label: {
                        Label("roam.share.title", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.questifyPrimary)
                    .accessibilityIdentifier("roam.share.open")
                } else if currentLoaded {
                    ContentUnavailableView("roam.experience.recordMissing", systemImage: "questionmark.folder", description: Text("roam.experience.recordMissingHint"))
                        .accessibilityIdentifier("roam.experience.history.missing")
                } else { ProgressView("roam.loading") }
            }.padding()
        }.navigationTitle("roam.experience.session")
            .task(id: readKey) { showShare = false; selectedMedal = nil; load() }
            .onChange(of: readKey) { _, _ in showShare = false; selectedMedal = nil }
            .sheet(isPresented: $showShare) { if let record = currentRecord { NavigationStack { RoamHistoryShareView(record: record, reader: reader) } } }
            .sheet(item: $selectedMedal) { medal in
                if currentRecord == medal.record {
                    NavigationStack { RoamMedalShareView(selection: medal, reader: reader) }
                }
            }
            .accessibilityIdentifier("roam.experience.session")
    }
    private func load() {
        record = nil; error = nil; loaded = false; loadedOwner = nil
        let captured = readKey
        do {
            let value = try reader.history().first { $0.ts == timestamp }
            guard captured == readKey else { return }
            record = value; loaded = true; loadedOwner = captured
        } catch {
            guard captured == readKey else { return }
            self.error = error; loadedOwner = captured
        }
    }
}
