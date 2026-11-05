import SwiftUI
import UIKit
import Combine

@MainActor private final class RoamLiveViewModel: ObservableObject {
    let controller: RoamLiveSessionController
    let finishedHistory: RoamFinishedHistoryReader
    @Published private var revision = 0
    init(_ controller: RoamLiveSessionController, offlineExample: Bool) {
        self.controller = controller
        finishedHistory = controller.makeFinishedHistoryReader(offlineExample: offlineExample)
        controller.onChange = { [weak self] in self?.revision &+= 1 }
    }
}
@MainActor struct RoamLiveSessionView: View {
    let offlineExample: Bool
    let localHistoryReader: (any RoamExperienceReading)?
    let albumMetadataReader: RoamAlbumMetadataReader?
    @StateObject private var browse: RoamPausedBrowsePresentation
    @StateObject private var model: RoamLiveViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var purposeAccepted = false
    @State private var presenceAccepted = false
    @State private var confirmFinish = false
    @State private var showRules = false
    @State private var nearbyExpanded = true
    init(controller: RoamLiveSessionController, offlineExample: Bool = false, localHistoryReader: (any RoamExperienceReading)? = nil, albumMetadataReader: RoamAlbumMetadataReader? = nil, browsePresentation: RoamPausedBrowsePresentation? = nil) {
        self.offlineExample = offlineExample; self.localHistoryReader = localHistoryReader; self.albumMetadataReader = albumMetadataReader
        _browse = StateObject(wrappedValue: browsePresentation ?? RoamPausedBrowsePresentation())
        _model = StateObject(wrappedValue: RoamLiveViewModel(controller, offlineExample: offlineExample))
    }
    private var owner: RoamLiveSessionController { model.controller }
    private func browseReader(for kind: RoamPausedBrowseKind) -> (any RoamExperienceReading)? {
        if kind == .album, let albumMetadataReader { return albumMetadataReader }
        return localHistoryReader
    }
    private var currentBrowseReader: (any RoamExperienceReading)? {
        browseReader(for: browse.target?.context.kind ?? .history)
    }
    var body: some View {
        List {
            if offlineExample { RoamExperienceNotice(offline: true) }
            // Mini-program pcard: goal line, then 用时 / 地盘 / 距离 (公里).
            Section { hud }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            if owner.phase == .unavailable {
                Section {
                    Label("roam.live.notApproved", systemImage: "lock.shield")
                    Text("roam.live.notApprovedHint").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                status
                if let medals = RoamFinishedMedalsPresentation(controller: owner) {
                    RoamFinishedMedalsSection(presentation: medals)
                }
                if let story = RoamFinishedStoryPresentation(controller: owner) {
                    RoamFinishedStorySection(presentation: story)
                }
                if let track = owner.finishedRouteTrack {
                    RoamLiveRouteOverviewSection(track: track, paused: false, finished: true)
                }
                if owner.canContinueUnstartedRoam {
                    Section {
                        Button("roam.unstarted.continue", systemImage: "arrow.uturn.backward") { owner.continueUnstartedRoam() }
                            .accessibilityIdentifier("roam.unstarted.continue")
                    }
                }
                if owner.phase == .finished, let saved = owner.completedHistory, model.finishedHistory.identity != nil {
                    Section("roam.finishedHistory.title") {
                        NavigationLink {
                            RoamHistoryDetailView(reader: model.finishedHistory, timestamp: saved.timestamp)
                        } label: {
                            Label("roam.finishedHistory.thisWalk", systemImage: "book.closed")
                        }.accessibilityIdentifier("roam.finishedHistory.record.open")
                        NavigationLink {
                            RoamHistoryView(reader: model.finishedHistory)
                        } label: {
                            Label("roam.experience.history", systemImage: "clock.arrow.circlepath")
                        }.accessibilityIdentifier("roam.finishedHistory.history.open")
                    }
                }
                if [.ready, .locationDenied, .paused].contains(owner.phase) {
                    Section {
                        Toggle("roam.live.consent", isOn: $purposeAccepted).accessibilityIdentifier("roam.live.consent")
                        if owner.presenceAvailable {
                            Toggle("roam.live.presenceConsent", isOn: $presenceAccepted)
                        }
                    } footer: {
                        // Disclosure of what nearby players see; kept because it is a consent.
                        if owner.presenceAvailable { Text("roam.live.presencePrivacy") }
                    }
                }
                if owner.phase == .active {
                    Section {
                        Label(owner.presenceEnabled ? "roam.live.presenceOn" : "roam.live.presenceOff",
                              systemImage: owner.presenceEnabled ? "person.wave.2" : "person.crop.circle")
                        if owner.presenceError { Text("roam.live.presenceFailed").foregroundStyle(.secondary) }
                    }
                    if let memory = owner.placeMemory {
                        RoamPlaceMemorySection(placeName: memory.placeName, text: memory.text) {
                            owner.dismissPlaceMemory(id: memory.id)
                        }
                    }
                    nearby
                    trace
                }
                if owner.phase == .paused { trace }
                pauseAndBrowse
                if owner.phase == .recoveryRequired {
                    Section {
                        Text("roam.live.recoveryHint")
                        Button("roam.live.recover", systemImage: "arrow.clockwise") { Task { if owner.record == nil { owner.prepare() }; await owner.recover() } }
                            .disabled(owner.busy).accessibilityIdentifier("roam.live.recover")
                    }
                }
            }
            if let error = owner.error {
                Section {
                    Label { Text(errorText(error)) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        .accessibilityIdentifier("roam.live.error")
                }
            }
        }
        // Mini-program pbar: one main round control (start / pause / continue) with 结束 beside it.
        .safeAreaInset(edge: .bottom) { actionBar }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showRules = true } label: { Label("roam.live.rules", systemImage: "info.circle") }
                    .accessibilityIdentifier("roam.live.rules")
            }
        }
        .navigationTitle("roam.experience.live")
        .accessibilityIdentifier("roam.live.session")
        .onAppear { owner.setForeground(scenePhase == .active); owner.prepare(); browse.appear() }
        .onDisappear { nearbyExpanded = true; browse.parentHidden(); owner.pause() }
        .onChange(of: owner.phase) { _, phase in
            if phase != .active { nearbyExpanded = true }
            browse.retireIfStale(owner: owner, reader: currentBrowseReader)
        }
        .onChange(of: scenePhase) { _, value in
            if value != .active { browse.retire() }
            owner.setForeground(value == .active)
        }
        .onChange(of: owner.localBrowseIdentity) { _, _ in browse.retireIfStale(owner: owner, reader: currentBrowseReader) }
        .onChange(of: owner.record?.clientSessionKey) { _, _ in browse.retireIfStale(owner: owner, reader: currentBrowseReader) }
        .onChange(of: localHistoryReader?.identity) { _, _ in browse.retireIfStale(owner: owner, reader: currentBrowseReader) }
        .onChange(of: localHistoryReader.map { ObjectIdentifier($0) }) { _, _ in browse.retireIfStale(owner: owner, reader: currentBrowseReader) }
        .onChange(of: albumMetadataReader?.scope) { _, _ in browse.retireIfStale(owner: owner, reader: currentBrowseReader) }
        .onChange(of: albumMetadataReader.map { ObjectIdentifier($0) }) { _, _ in browse.retireIfStale(owner: owner, reader: currentBrowseReader) }
        .task(id: owner.phase) {
            guard owner.phase == .active else { return }
            while !Task.isCancelled && owner.phase == .active {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard !Task.isCancelled, scenePhase == .active else { return }
                await owner.pulse()
            }
        }
        .confirmationDialog("roam.live.finishConfirm", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("roam.live.finish") { Task { await owner.finish() } }.accessibilityIdentifier("roam.live.finish.confirm")
            Button("action.cancel", role: .cancel) {}
        } message: { Text("roam.live.finishHint") }
        .sheet(isPresented: $showRules) {
            NavigationStack { RoamLiveRulesView() }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .background {
            RoamPausedBrowseLifetimeAnchor(presentation: browse).frame(width: 0, height: 0)
        }
        .background {
            if let target = browse.target {
                RoamPausedBrowseSheetOwner(presentation: browse, target: target,
                    owner: owner, reader: browseReader(for: target.context.kind)).id(target.id)
            }
        }
    }
    /// Mini-program pcard: the goal line with the phase, then 用时 / 地盘 / 距离 (公里).
    /// Built inline so every controller change redraws it.
    private var hud: some View {
        let active = owner.phase == .active
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(active ? "roam.live.goal" : phaseText)
                    .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Circle().fill(active ? Color.green : Color.secondary).frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("roam.live.phase")
            HStack(alignment: .top, spacing: 8) {
                TimelineView(.animation(minimumInterval: 1, paused: owner.phase != .active || !owner.foreground)) { _ in
                    RoamLiveElapsedRow(seconds: owner.record == nil ? nil : owner.localForegroundElapsedSeconds)
                }
                RoamLiveCoverageRow(presentation: .init(controller: owner))
                RoamLiveStatTile(value: hudDistance, label: "roam.live.stat.distance")
                    .accessibilityIdentifier("roam.live.distance")
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(active ? 0.6 : 0.2), lineWidth: 1.5))
        .padding(.horizontal)
    }
    private var hudDistance: String {
        guard let meters = owner.record?.distanceMeters, meters.isFinite, meters >= 0 else { return "—" }
        return (meters / 1000).formatted(.number.precision(.fractionLength(1)))
    }
    /// Bottom game bar. Every button keeps its identifier and controller call.
    @ViewBuilder private var actionBar: some View {
        let canStart = [.ready, .locationDenied, .paused].contains(owner.phase)
        let canFinish = [.active, .paused].contains(owner.phase) && owner.record != nil
        if owner.phase != .unavailable && (canStart || owner.phase == .active || canFinish) {
            HStack(spacing: 12) {
                if owner.phase == .active {
                    Button { owner.pause() } label: {
                        Label("roam.live.pause", systemImage: "pause.fill").frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("roam.live.pause")
                } else if canStart, owner.record == nil {
                    Button { Task { await owner.start(purposeAccepted: purposeAccepted, presenceAccepted: presenceAccepted) } } label: {
                        Label("roam.live.start", systemImage: "figure.walk").frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!purposeAccepted || owner.busy).accessibilityIdentifier("roam.live.start")
                } else if canStart, owner.record?.finishRequested == false {
                    Button { Task { await owner.resume(purposeAccepted: purposeAccepted, presenceAccepted: presenceAccepted) } } label: {
                        Label("roam.live.resume", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!purposeAccepted || owner.busy).accessibilityIdentifier("roam.live.resume")
                }
                if canFinish {
                    Button(role: .destructive) { confirmFinish = true } label: {
                        Label("roam.live.finish", systemImage: "flag.checkered").frame(minHeight: 30)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                    .disabled(owner.busy).accessibilityIdentifier("roam.live.finish")
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
    }
    @ViewBuilder private var pauseAndBrowse: some View {
        if owner.localBrowseIdentity != nil {
            Section {
                ForEach(RoamPausedBrowseKind.allCases, id: \.self) { kind in
                    let entryID = browse.entryID
                    let reader = browseReader(for: kind)
                    let context = RoamPausedBrowseContext.capture(kind: kind, owner: owner, reader: reader)
                    if let context {
                        Button {
                            browse.open(context, entryID: entryID, owner: owner, reader: reader)
                        } label: {
                            Label(LocalizedStringKey(kind.titleKey), systemImage: kind.symbol)
                        }
                        .accessibilityIdentifier(kind.accessibilityID)
                    }
                }
            } header: { Text("roam.live.more") }
        }
    }
    @ViewBuilder private var status: some View {
        let settled = owner.settlement.map { $0.hasCompleteSettlement } ?? false
        if owner.busy || owner.record != nil || settled {
            Section {
                if owner.busy { ProgressView("roam.loading") }
                if let record = owner.record {
                    LabeledContent("roam.live.tiles", value: String(record.allTiles.count - record.pendingTiles.count))
                    if !record.pendingTiles.isEmpty { LabeledContent("roam.live.pendingTiles", value: String(record.pendingTiles.count)) }
                    if owner.pendingActionCount > 0 { Text("roam.live.unknownVisit").foregroundStyle(.secondary) }
                }
                if let fact = owner.settlement, fact.hasCompleteSettlement {
                    LabeledContent("roam.live.confirmedXP", value: String(fact.result!.totalXp!))
                    LabeledContent("roam.live.confirmedShops", value: String(fact.result!.sessionShops!))
                    if owner.phase != .finished { Text("roam.live.archivePending").foregroundStyle(.secondary) }
                }
            } header: { Text("roam.live.sessionStatus") }
        }
    }
    private var phaseText: LocalizedStringKey {
        switch owner.phase {
        case .ready: return "roam.live.ready"
        case .acquiring: return "roam.live.acquiring"
        case .active: return "roam.live.active"
        case .paused: return "roam.live.paused"
        case .recovering, .recoveryRequired: return "roam.live.needsRecovery"
        case .finishing: return "roam.live.finishing"
        case .finished: return "roam.live.finished"
        case .locationDenied: return "roam.live.locationProblem"
        case .unavailable: return "roam.live.notApproved"
        }
    }
    @ViewBuilder private var trace: some View {
        if let track = owner.currentRouteTrack, owner.phase == .paused || track.count > 1 {
            RoamLiveRouteOverviewSection(track: track, paused: owner.phase == .paused)
        }
    }
    @ViewBuilder private var nearby: some View {
        Section("roam.live.nearby") {
            if owner.nearbyReadFailed {
                if owner.placesReadError != nil {
                    Label("roam.liveRead.placesFailed", systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("roam.liveRead.placesFailed")
                }
                if owner.registeredShopsReadError != nil {
                    Label("roam.liveRead.shopsFailed", systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("roam.liveRead.shopsFailed")
                }
                Text("roam.liveRead.failed").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("roam.liveRead.failed")
                if owner.canRetryNearbyRead {
                    Button("action.retry") { Task { await owner.retryNearbyRead() } }
                        .accessibilityIdentifier("roam.liveRead.retry")
                }
            } else if owner.places.isEmpty && owner.registeredShops.isEmpty {
                Text("roam.live.noPlaces").foregroundStyle(.secondary)
            }
            if !owner.places.isEmpty || !owner.registeredShops.isEmpty {
                RoamNearbyVisibilityButton(expanded: $nearbyExpanded)
            }
            ForEach(owner.registeredShops) { shop in
                if nearbyExpanded || owner.busy || owner.error != nil || owner.registeredShopUnresolved(shop) || owner.registeredShopConfirmed(shop) {
                    VStack(alignment: .leading, spacing: 8) {
                        if shop.addressName.isEmpty { Text("roam.unnamed").font(.headline) } else { Text(verbatim: shop.addressName).font(.headline) }
                        if owner.registeredShopUnresolved(shop) { Text("roam.live.unknownVisit").font(.caption) }
                        else if owner.registeredShopConfirmed(shop) { Label("roam.live.arrivalConfirmed", systemImage: "checkmark.circle") }
                        else {
                            Button("roam.live.visitShop") { Task { await owner.visitRegisteredShop(shop) } }
                                .disabled(owner.busy || owner.registeredShopGap(shop) != 0)
                            if let gap = owner.registeredShopGap(shop), gap > 0 { Text("roam.live.walkCloser \(gap)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.padding(.vertical, 4)
                }
            }
            ForEach(owner.places) { place in
                if nearbyExpanded || owner.busy || owner.error != nil || owner.actionUnresolved(place, shop: false) || owner.actionUnresolved(place, shop: true)
                    || owner.actionConfirmed(place, shop: false) || owner.actionConfirmed(place, shop: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        RoamTitle(place.name).font(.headline)
                        if let text = owner.merchantDescription(for: place) {
                            RoamLiveMerchantDescriptionRow(text: text)
                        }
                        arrivalButton(place, shop: false)
                        if place.type == 2 { arrivalButton(place, shop: true) }
                    }.padding(.vertical, 4)
                }
            }
        }
    }
    private func arrivalButton(_ place: RoamPlace, shop: Bool) -> some View {
        VStack(alignment: .leading) {
            if owner.actionUnresolved(place, shop: shop) { Text("roam.live.unknownVisit").font(.caption) }
            else if owner.actionConfirmed(place, shop: shop) { Label("roam.live.arrivalConfirmed", systemImage: "checkmark.circle") }
            else {
                Button(shop ? "roam.live.visitShop" : "roam.live.discover") { Task { if shop { await owner.visitShop(place) } else { await owner.discover(place) } } }
                    .disabled(owner.busy || owner.gapMeters(place, shop: shop) != 0)
                if let gap = owner.gapMeters(place, shop: shop), gap > 0 {
                    Text("roam.live.walkCloser \(gap)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func errorText(_ error: Error) -> LocalizedStringKey {
        if error as? RoamLiveFailure == .locationQuality { return "roam.live.locationQuality" }
        if error as? RoamLiveFailure == .outOfRange { return "roam.live.outOfRange" }
        if error as? RoamLiveFailure == .journalUnavailable { return "roam.live.storageError" }
        if error as? RoamLiveFailure == .unresolvedVisit { return "roam.live.unknownVisit" }
        if error as? RoamExperienceFailure == .incompleteSettlement { return "roam.live.incomplete" }
        return "roam.live.operationError"
    }
}
@MainActor private struct RoamLiveRulesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section("roam.live.ruleExploreTitle") { Text("roam.live.ruleExplore") }
            Section("roam.live.ruleArrivalTitle") { Text("roam.live.ruleArrival") }
            Section("roam.live.ruleFinishTitle") { Text("roam.live.ruleFinish") }
            Section("roam.live.rulePrivacyTitle") { Text("roam.live.presencePrivacy"); Text("roam.live.leaveHint") }
        }.navigationTitle("roam.live.rules").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("action.done") { dismiss() } } }
    }
}

/// A display-only projection of the current controller's accepted in-memory samples.
/// Saved tile totals and timestamps do not establish this local-area estimate.
struct RoamLiveCoveragePresentation: Equatable {
    let percentage: Int?
    @MainActor init(controller: RoamLiveSessionController) {
        guard controller.isAvailable, controller.foreground,
              [.active, .paused].contains(controller.phase),
              let record = controller.record, !record.finishRequested, record.pendingWrite == nil,
              !controller.track.isEmpty else { percentage = nil; return }
        percentage = controller.explorationPercent
    }
    func value(locale: Locale) -> String {
        percentage.map { "\($0)%" } ?? RoamLiveCoverageCopy(locale: locale).unknown
    }
}

struct RoamLiveCoverageCopy {
    let title: String
    let unknown: String
    let hint: String
    init(locale: Locale) {
        if locale.language.languageCode?.identifier == "zh" {
            title = "本地片区探索度"
            unknown = "暂无可靠数据"
            hint = "仅反映当前内存保留的局部片区，不代表全城覆盖或服务器确认结果。恢复记录不能还原这一比例。"
        } else {
            title = "Local area explored"
            unknown = "Unavailable"
            hint = "Based on the local area retained in memory, not citywide coverage or a server-confirmed result. Recovery records cannot reconstruct this percentage."
        }
    }
}

/// HUD tile 地盘: the explored percentage, or — when it isn't known.
@MainActor struct RoamLiveCoverageRow: View {
    let presentation: RoamLiveCoveragePresentation
    var body: some View {
        RoamLiveStatTile(value: presentation.percentage.map { "\($0)%" } ?? "—", label: "roam.live.stat.turf")
            .accessibilityIdentifier("roam.live.localCoverage")
    }
}

/// One HUD reading: a large number over a short label, as in the mini-program pstat.
struct RoamLiveStatTile: View {
    let value: String
    let label: LocalizedStringKey
    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: value).font(.title2.weight(.bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct RoamLiveElapsedCopy {
    let locale: Locale
    private var chinese: Bool { locale.languageCode == "zh" }
    var title: String { chinese ? "本次前台用时" : "Foreground time" }
    var unknown: String { chinese ? "暂无可靠数据" : "Unavailable" }
    var hint: String {
        chinese ? "仅累计本次打开期间的前台漫游时间，暂停或进入后台即停止。恢复记录无法还原用时，也不代表服务器确认的成绩。"
            : "Counts this walk's foreground time while open. Pausing or backgrounding stops the clock. Recovery cannot restore this value; it is not a server-confirmed result."
    }
    func value(seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else { return unknown }
        let minutes = seconds / 60, remainder = seconds % 60
        return "\(minutes < 10 ? "0" : "")\(minutes):\(remainder < 10 ? "0" : "")\(remainder)"
    }
}
/// HUD tile 用时: mm:ss of this walk's foreground time, or — when it isn't known.
struct RoamLiveElapsedRow: View {
    let seconds: Int?
    var body: some View {
        let known = seconds.map { $0 >= 0 } ?? false
        RoamLiveStatTile(value: known ? RoamLiveElapsedCopy(locale: Locale(identifier: "en")).value(seconds: seconds) : "—",
                         label: "roam.live.stat.time")
            .accessibilityIdentifier("roam.live.foregroundElapsed")
    }
}

/// Only displays fields of the complete, current settlement after the existing archive succeeds.
/// A missing field is not evidence that no medal was awarded.
struct RoamFinishedMedalsPresentation: Equatable {
    let journey: String?
    let shop: String?
    @MainActor init?(controller: RoamLiveSessionController) {
        guard controller.phase == .finished, controller.isAvailable, controller.foreground,
              !controller.busy, controller.record == nil,
              controller.makeFinishedHistoryReader().identity != nil,
              let reference = controller.completedHistory,
              let fact = controller.settlement, fact.hasCompleteSettlement,
              fact.sessionID == reference.serverSessionID, let result = fact.result else { return nil }
        journey = Self.provided(result.medal)
        shop = Self.provided(result.shopMedal?.name)
    }
    private static func provided(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

struct RoamFinishedMedalsCopy {
    let title: String
    let journey: String
    let shop: String
    let unavailable: String
    let hint: String
    init(locale: Locale) {
        if locale.language.languageCode?.identifier == "zh" {
            title = "本次结算的勋章信息"
            journey = "漫游勋章"
            shop = "探店勋章"
            unavailable = "本次结算未提供"
            hint = "仅显示本次已保存结算返回的信息。缺失字段不代表没有获得勋章。"
        } else {
            title = "Medal details from this settlement"
            journey = "Journey medal"
            shop = "Shop medal"
            unavailable = "Not provided in this settlement"
            hint = "Only information returned with this saved settlement is shown. A missing field does not mean no medal was awarded."
        }
    }
}

struct RoamFinishedMedalsSection: View {
    let presentation: RoamFinishedMedalsPresentation
    @Environment(\.locale) private var locale
    var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: presentation.journey ?? "—")
            } label: { Label("roam.live.medal.journey", systemImage: "medal") }
                .accessibilityIdentifier("roam.live.finishedMedals.journey")
            LabeledContent {
                Text(verbatim: presentation.shop ?? "—")
            } label: { Label("roam.live.medal.shop", systemImage: "storefront") }
                .accessibilityIdentifier("roam.live.finishedMedals.shop")
        } header: { Text("roam.live.medal.title") }
    }
}

struct RoamPlaceMemoryCopy {
    let title: String
    let close: String
    init(locale: Locale) {
        if locale.language.languageCode?.identifier == "zh" {
            title = "地点记忆"; close = "关闭地点提示"
        } else {
            title = "Place memory"; close = "Close place note"
        }
    }
}
struct RoamPlaceMemorySection: View {
    let placeName: String
    let text: String
    let close: () -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        Section {
            if !placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: placeName).font(.headline)
            }
            Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("roam.live.placeMemory.text")
            Button(action: close) { Text("roam.live.placeMemory.close") }
                .accessibilityIdentifier("roam.live.placeMemory.close")
        } header: { Text("roam.live.placeMemory.title") }
    }
}

/// Only the currently owned, fully archived settlement may provide this display text.
struct RoamFinishedStoryPresentation: Equatable {
    let text: String
    @MainActor init?(controller: RoamLiveSessionController) {
        guard controller.phase == .finished, controller.isAvailable, controller.foreground,
              !controller.busy, controller.record == nil,
              controller.makeFinishedHistoryReader().identity != nil,
              let reference = controller.completedHistory,
              let fact = controller.settlement, fact.hasCompleteSettlement,
              fact.sessionID == reference.serverSessionID,
              let text = fact.result?.routeStory else { return nil }
        self.text = text
    }
}
struct RoamFinishedStoryCopy {
    let title: String
    let hint: String
    init(locale: Locale) {
        if locale.language.languageCode?.identifier == "zh" {
            title = "这段足迹"
            hint = "来自本次已保存的结算回顾。"
        } else {
            title = "This walk"
            hint = "A reflection returned with this saved settlement."
        }
    }
}
struct RoamFinishedStorySection: View {
    let presentation: RoamFinishedStoryPresentation
    @Environment(\.locale) private var locale
    var body: some View {
        Section {
            Text(verbatim: presentation.text).font(.body.italic())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("roam.live.finishedStory.text")
        } header: { Text("roam.live.story.title") }
    }
}

struct RoamLiveMerchantDescriptionCopy {
    let title: String
    init(locale: Locale) {
        title = locale.language.languageCode?.identifier == "zh" ? "商家介绍" : "About this merchant"
    }
}
struct RoamLiveMerchantDescriptionRow: View {
    let text: String
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("roam.live.merchant.about")
                .font(.caption).foregroundStyle(.secondary)
            Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
        }.accessibilityIdentifier("roam.live.merchantDescription")
    }
}

struct RoamNearbyVisibilityCopy {
    let hide, show, expanded, collapsed, hint: String
    init(locale: Locale) {
        if locale.language.languageCode?.identifier == "zh" {
            hide = "收起附近卡片"; show = "展开附近卡片"
            expanded = "已展开"; collapsed = "已收起"
            hint = "只收起普通卡片。到场状态、待确认结果和重试仍会显示。"
        } else {
            hide = "Hide nearby cards"; show = "Show nearby cards"
            expanded = "Expanded"; collapsed = "Collapsed"
            hint = "Only ordinary cards are hidden. Arrival status, pending results and retries stay visible."
        }
    }
}
struct RoamNearbyVisibilityButton: View {
    @Binding var expanded: Bool
    @Environment(\.locale) private var locale
    func toggle() { expanded = !expanded }
    var body: some View {
        Button(action: toggle) {
            Label(expanded ? "roam.live.nearby.hide" : "roam.live.nearby.show", systemImage: expanded ? "chevron.up" : "chevron.down")
        }
        .accessibilityIdentifier("roam.live.nearby.visibility")
    }
}

struct RoamLiveRouteOverviewCopy {
    let pausedHint, finishedHint, missing, onePoint, recordedPoints: String
    init(locale: Locale) {
        if locale.language.languageCode?.identifier == "zh" {
            pausedHint = "暂停时可查看本次内存中已有的路线。继续仍需点击原来的继续按钮。"
            finishedHint = "本次结算已保存。这里只展示本次内存中保留的路线点，可能不完整；离开或切到后台后不再保留。"
            missing = "本次内存中没有路线点。恢复记录不能还原之前的路线。"
            onePoint = "目前只有一个路线点，尚不足以画出路线。"
            recordedPoints = "本机路线点"
        } else {
            pausedHint = "While paused, review the route already held for this walk. Use the existing Resume button to continue."
            finishedHint = "This settlement is saved. Only route points held for this walk are shown and they may be incomplete. They are discarded when you leave or enter the background."
            missing = "No route points are held for this walk. A recovery record cannot restore the earlier route."
            onePoint = "Only one route point is available, so no route line can be drawn yet."
            recordedPoints = "Local route points"
        }
    }
}
struct RoamLiveRouteOverviewSection: View {
    let track: [RoamHistoryPoint]
    let paused: Bool
    var finished = false
    @Environment(\.locale) private var locale
    var hasDrawableRoute: Bool { track.count > 1 }
    var body: some View {
        Section("roam.live.route.title") {
            if hasDrawableRoute {
                let sketch = RoamRouteSketch(track: track, places: [])
                Canvas { context, size in
                    var path = Path()
                    for (index, point) in sketch.track.enumerated() {
                        let value = CGPoint(x: point.x * size.width, y: point.y * size.height)
                        if index == 0 { path.move(to: value) } else { path.addLine(to: value) }
                    }
                    context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }.frame(height: 180).accessibilityHidden(true)
                    .accessibilityIdentifier("roam.live.routeOverview.points")
            } else {
                Text("roam.live.route.empty")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("roam.live.routeOverview.unavailable")
            }
        }.accessibilityIdentifier("roam.live.routeOverview")
    }
}


enum RoamPausedBrowseKind: CaseIterable, Hashable {
    case history, settings, album
    var symbol: String { switch self { case .history: return "clock.arrow.circlepath"; case .settings: return "location.slash"; case .album: return "rectangle.stack" } }
    var titleKey: String { switch self { case .history: return "roam.live.more.history"; case .settings: return "roam.live.more.settings"; case .album: return "roam.live.more.album" } }
    var accessibilityID: String { switch self { case .history: return "roam.live.pausedHistory.open"; case .settings: return "roam.live.pausedSettings.open"; case .album: return "roam.live.pausedAlbum.open" } }
}
struct RoamPausedBrowseContext: Equatable {
    let kind: RoamPausedBrowseKind
    let controllerID: ObjectIdentifier
    let identity: RoamExperienceIdentity
    let clientSessionKey: String
    let readerID: ObjectIdentifier?
    var albumReadScope: UUID? = nil
    @MainActor static func capture(kind: RoamPausedBrowseKind, owner: RoamLiveSessionController,
                                  reader: (any RoamExperienceReading)?) -> Self? {
        guard let identity = owner.localBrowseIdentity, let key = owner.record?.clientSessionKey else { return nil }
        if kind != .settings {
            guard let reader, reader.identity == identity else { return nil }
            return .init(kind: kind, controllerID: ObjectIdentifier(owner), identity: identity, clientSessionKey: key, readerID: ObjectIdentifier(reader), albumReadScope: (reader as? RoamAlbumMetadataReader)?.scope)
        }
        return .init(kind: kind, controllerID: ObjectIdentifier(owner), identity: identity, clientSessionKey: key, readerID: nil)
    }
}
@MainActor struct RoamPausedBrowseTarget: Identifiable {
    let id: UUID
    let context: RoamPausedBrowseContext
    let historyReader: RoamPausedLocalHistoryReader?
    let albumScope: RoamStampAlbumReadOnlyScope?
}
@MainActor final class RoamPausedBrowsePresentation: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var dismantling = false
    private(set) var target: RoamPausedBrowseTarget? { willSet { publishChange() } }
    private(set) var entryID = UUID() { willSet { publishChange() } }
    private func publishChange() { if !dismantling { objectWillChange.send() } }
    private var visible = false
    private var attached = false
    func appear() { if !visible { entryID = UUID() }; visible = true; attached = true }
    func parentHidden() { visible = false; if target == nil { retire() } }
    func parentDisappeared(departing: Bool, coveredByPresentation: Bool) {
        if !departing && coveredByPresentation && target != nil { parentHidden() }
        else { disappear() }
    }
    func disappear() { visible = false; attached = false; retire() }
    func dismantle() {
        dismantling = true; disappear(); dismantling = false
        Task { @MainActor [weak self] in self?.objectWillChange.send() }
    }
    func retire() { target?.albumScope?.retire(); target = nil; entryID = UUID() }
    func open(_ rendered: RoamPausedBrowseContext, entryID: UUID, owner: RoamLiveSessionController,
              reader: (any RoamExperienceReading)?) {
        guard attached, visible, self.entryID == entryID, target == nil,
              rendered == RoamPausedBrowseContext.capture(kind: rendered.kind, owner: owner, reader: reader) else { return }
        owner.pause()
        guard owner.phase == .paused,
              rendered == RoamPausedBrowseContext.capture(kind: rendered.kind, owner: owner, reader: reader) else { return }
        let id = UUID()
        let history: RoamPausedLocalHistoryReader?
        if rendered.kind == .history, let reader {
            history = .init(base: reader, expected: rendered.identity, isCurrent: { [weak self, weak owner] in
                guard let self, let owner, let current = self.target, current.id == id else { return false }
                return self.matches(current, owner: owner, reader: reader)
            })
        } else { history = nil }
        let album: RoamStampAlbumReadOnlyScope?
        if rendered.kind == .album, let reader {
            album = .init(reader: reader, identity: rendered.identity, isCurrent: { [weak self, weak owner] in
                guard let self, let owner, let current = self.target, current.id == id else { return false }
                return self.matches(current, owner: owner, reader: reader)
            })
        } else { album = nil }
        target = .init(id: id, context: rendered, historyReader: history, albumScope: album)
    }
    func matches(_ offered: RoamPausedBrowseTarget, owner: RoamLiveSessionController,
                 reader: (any RoamExperienceReading)?) -> Bool {
        attached && target?.id == offered.id && owner.phase == .paused &&
        offered.context == RoamPausedBrowseContext.capture(kind: offered.context.kind, owner: owner, reader: reader)
    }
    func retireIfStale(owner: RoamLiveSessionController, reader: (any RoamExperienceReading)?) {
        if let target, !matches(target, owner: owner, reader: reader) { retire() }
    }
    func close(id: UUID) { if target?.id == id { retire() } }
    func binding(for offered: RoamPausedBrowseTarget?, owner: RoamLiveSessionController, reader: (any RoamExperienceReading)?) -> Binding<RoamPausedBrowseTarget?> {
        return Binding(get: {
            guard let offered, self.matches(offered, owner: owner, reader: reader) else { return nil }
            return offered
        }, set: { value in
            if value == nil, let offered { self.close(id: offered.id) }
        })
    }
}
/// Only the two existing local reads are delegated. This presentation grants no remote capability.
@MainActor final class RoamPausedLocalHistoryReader: RoamExperienceReading {
    private let base: any RoamExperienceReading
    private let expected: RoamExperienceIdentity
    private let isCurrent: () -> Bool
    init(base: any RoamExperienceReading, expected: RoamExperienceIdentity, isCurrent: @escaping () -> Bool) {
        self.base = base; self.expected = expected; self.isCurrent = isCurrent
    }
    var identity: RoamExperienceIdentity? { isCurrent() && base.identity == expected ? expected : nil }
    var isConfigured: Bool { false }
    var isOfflineExample: Bool { base.isOfflineExample }
    func history() throws -> [RoamHistoryRecord] {
        guard identity != nil else { throw CancellationError() }
        let result = try base.history()
        guard identity != nil else { throw CancellationError() }
        return result
    }
    func localWalkStatus() throws -> RoamLocalWalkStatus {
        guard identity != nil else { throw CancellationError() }
        let result = try base.localWalkStatus()
        guard identity != nil else { throw CancellationError() }
        return result
    }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
    func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
}
struct RoamPausedBrowseCopy {
    let title, hint, history, settings, album: String
    init(locale: Locale) {
        if locale.language.languageCode?.identifier == "zh" {
            title = "暂停后查看"
            hint = "打开前会先暂停本次漫游。返回后不会自动继续，仍需使用原来的继续按钮。"
            history = "查看本机漫游历史"; settings = "查看定位设置"; album = "只读查看集邮册"
        } else {
            title = "Pause and review"
            hint = "This walk pauses before opening. Returning does not resume it; use the existing Resume button when ready."
            history = "View local walk history"; settings = "View location settings"; album = "View stamp album (read-only)"
        }
    }
    func label(_ kind: RoamPausedBrowseKind) -> String {
        switch kind { case .history: return history; case .settings: return settings; case .album: return album }
    }
}


@MainActor private struct RoamPausedBrowseSheetOwner: View {
    let presentation: RoamPausedBrowsePresentation
    let target: RoamPausedBrowseTarget
    let owner: RoamLiveSessionController
    let reader: (any RoamExperienceReading)?
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(item: presentation.binding(for: target, owner: owner, reader: reader),
                   onDismiss: { presentation.close(id: target.id) }) { offered in
                NavigationStack {
                    if presentation.matches(offered, owner: owner, reader: reader) {
                        Group {
                            switch offered.context.kind {
                            case .history:
                                if let local = offered.historyReader { RoamHistoryView(reader: local) }
                            case .settings: RoamLocationSettingsDestination()
                            case .album:
                                if let reader, let scope = offered.albumScope, scope.matches(reader) {
                                    RoamStampAlbumView(reader: reader, readOnlyScope: scope)
                                }
                            }
                        }
                        .toolbar { ToolbarItem(placement: .confirmationAction) {
                            Button("action.done") { presentation.close(id: offered.id) }
                        } }
                    }
                }
            }
    }
}
/// Native attachment distinguishes a covering sheet from the source leaving its hierarchy.
@MainActor struct RoamPausedBrowseLifetimeAnchor: UIViewControllerRepresentable {
    let presentation: RoamPausedBrowsePresentation
    func makeUIViewController(context: Context) -> RoamPausedBrowseLifetimeController {
        RoamPausedBrowseLifetimeController(presentation: presentation)
    }
    func updateUIViewController(_ controller: RoamPausedBrowseLifetimeController, context: Context) {}
    static func dismantleUIViewController(_ controller: RoamPausedBrowseLifetimeController, coordinator: ()) {
        controller.presentation?.dismantle()
    }
}
@MainActor final class RoamPausedBrowseLifetimeController: UIViewController {
    weak var presentation: RoamPausedBrowsePresentation?
    private var departing = false
    init(presentation: RoamPausedBrowsePresentation) {
        self.presentation = presentation; super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { return nil }
    private var ancestry: [UIViewController] {
        var result: [UIViewController] = [], next: UIViewController? = self
        while let value = next { result.append(value); next = value.parent }
        return result
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); departing = false; presentation?.appear()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        departing = ancestry.contains { $0.isMovingFromParent || $0.isBeingDismissed }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let source = ancestry
        presentation?.parentDisappeared(
            departing: departing || source.contains { $0.isMovingFromParent || $0.isBeingDismissed },
            coveredByPresentation: source.contains { $0.presentedViewController != nil })
    }
}
