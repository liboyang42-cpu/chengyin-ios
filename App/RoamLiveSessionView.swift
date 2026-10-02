import SwiftUI

@MainActor private final class RoamLiveViewModel: ObservableObject {
    let controller: RoamLiveSessionController
    @Published private var revision = 0
    init(_ controller: RoamLiveSessionController) {
        self.controller = controller
        controller.onChange = { [weak self] in self?.revision &+= 1 }
    }
}
@MainActor struct RoamLiveSessionView: View {
    let offlineExample: Bool
    @StateObject private var model: RoamLiveViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var purposeAccepted = false
    @State private var presenceAccepted = false
    @State private var confirmFinish = false
    @State private var showRules = false
    init(controller: RoamLiveSessionController, offlineExample: Bool = false) { self.offlineExample = offlineExample; _model = StateObject(wrappedValue: RoamLiveViewModel(controller)) }
    private var owner: RoamLiveSessionController { model.controller }
    var body: some View {
        List {
            if offlineExample { RoamExperienceNotice(offline: true) }
            Section {
                Label("roam.live.purposeTitle", systemImage: "figure.walk.circle.fill").font(.title2).bold()
                Text("roam.live.purpose").foregroundStyle(.secondary)
                Button("roam.live.rules") { showRules = true }.accessibilityIdentifier("roam.live.rules")
            }
            if owner.phase == .unavailable {
                Section {
                    Label("roam.live.notApproved", systemImage: "lock.shield")
                    Text("roam.live.notApprovedHint").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                status
                if [.ready, .locationDenied, .paused].contains(owner.phase) {
                    Section {
                        Toggle("roam.live.consent", isOn: $purposeAccepted).accessibilityIdentifier("roam.live.consent")
                        if owner.presenceAvailable {
                            Toggle("roam.live.presenceConsent", isOn: $presenceAccepted)
                            Text("roam.live.presencePrivacy").font(.caption).foregroundStyle(.secondary)
                        }
                        if owner.record == nil {
                            Button("roam.live.start", systemImage: "figure.walk") { Task { await owner.start(purposeAccepted: purposeAccepted, presenceAccepted: presenceAccepted) } }
                                .disabled(!purposeAccepted || owner.busy).accessibilityIdentifier("roam.live.start")
                        } else if owner.record?.finishRequested == false {
                            Button("roam.live.resume", systemImage: "play.fill") { Task { await owner.resume(purposeAccepted: purposeAccepted, presenceAccepted: presenceAccepted) } }
                                .disabled(!purposeAccepted || owner.busy).accessibilityIdentifier("roam.live.resume")
                        }
                    }
                }
                if owner.phase == .active {
                    Section {
                        Button("roam.live.pause", systemImage: "pause.fill") { owner.pause() }.accessibilityIdentifier("roam.live.pause")
                        Label(owner.presenceEnabled ? "roam.live.presenceOn" : "roam.live.presenceOff", systemImage: "person.crop.circle")
                        if owner.presenceError { Text("roam.live.presenceFailed").foregroundStyle(.secondary) }
                    }
                    trace
                    nearby
                }
                if [.active, .paused].contains(owner.phase), owner.record != nil {
                    Section {
                        Button("roam.live.finish", systemImage: "checkmark.circle") { confirmFinish = true }
                            .disabled(owner.busy).accessibilityIdentifier("roam.live.finish")
                    }
                }
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
                    Text(errorText(error)).foregroundStyle(.secondary).accessibilityIdentifier("roam.live.error")
                }
            }
            Section { Text("roam.live.leaveHint").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("roam.experience.live")
        .accessibilityIdentifier("roam.live.session")
        .onAppear { owner.setForeground(scenePhase == .active); owner.prepare() }
        .onDisappear { owner.pause() }
        .onChange(of: scenePhase) { _, value in owner.setForeground(value == .active) }
        .task(id: owner.phase) {
            guard owner.phase == .active else { return }
            while !Task.isCancelled && owner.phase == .active {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard !Task.isCancelled, scenePhase == .active else { return }
                await owner.pulse()
            }
        }
        .confirmationDialog("roam.live.finishConfirm", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("roam.live.finish") { Task { await owner.finish() } }
            Button("action.cancel", role: .cancel) {}
        } message: { Text("roam.live.finishHint") }
        .sheet(isPresented: $showRules) { NavigationStack { RoamLiveRulesView() } }
    }
    @ViewBuilder private var status: some View {
        Section("roam.live.sessionStatus") {
            Text(phaseText).font(.headline)
            if owner.busy { ProgressView("roam.loading") }
            if let record = owner.record {
                LabeledContent("roam.live.measuredDistance", value: Measurement(value: record.distanceMeters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .asProvided)))
                LabeledContent("roam.live.tiles", value: String(record.allTiles.count - record.pendingTiles.count))
                if !record.pendingTiles.isEmpty { LabeledContent("roam.live.pendingTiles", value: String(record.pendingTiles.count)) }
                if owner.pendingActionCount > 0 { Text("roam.live.unknownVisit").foregroundStyle(.secondary) }
            }
            if let fact = owner.settlement, fact.hasCompleteSettlement {
                LabeledContent("roam.live.confirmedXP", value: String(fact.result!.totalXp!))
                LabeledContent("roam.live.confirmedShops", value: String(fact.result!.sessionShops!))
                if owner.phase != .finished { Text("roam.live.archivePending") }
            }
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
        if owner.track.count > 1 {
            Section("roam.experience.routeSketch") {
                let sketch = RoamRouteSketch(track: owner.track, places: [])
                Canvas { context, size in
                    var path = Path()
                    for (index, point) in sketch.track.enumerated() {
                        let value = CGPoint(x: point.x * size.width, y: point.y * size.height)
                        if index == 0 { path.move(to: value) } else { path.addLine(to: value) }
                    }
                    context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }.frame(height: 180).accessibilityHidden(true)
                Text("roam.live.tracePrivacy").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var nearby: some View {
        Section("roam.live.nearby") {
            if owner.places.isEmpty && owner.registeredShops.isEmpty { Text("roam.live.noPlaces").foregroundStyle(.secondary) }
            ForEach(owner.registeredShops) { shop in
                VStack(alignment: .leading, spacing: 8) {
                    Text(shop.addressName.isEmpty ? "#\(shop.id)" : shop.addressName).font(.headline)
                    if owner.registeredShopUnresolved(shop) { Text("roam.live.unknownVisit").font(.caption) }
                    else if owner.registeredShopConfirmed(shop) { Label("roam.live.arrivalConfirmed", systemImage: "checkmark.circle") }
                    else {
                        Button("roam.live.visitShop") { Task { await owner.visitRegisteredShop(shop) } }
                            .disabled(owner.busy || owner.registeredShopGap(shop) != 0)
                        if let gap = owner.registeredShopGap(shop), gap > 0 { Text("roam.live.walkCloser").font(.caption) + Text(" \(gap) m").font(.caption) }
                    }
                }.padding(.vertical, 4)
            }
            ForEach(owner.places) { place in
                VStack(alignment: .leading, spacing: 8) {
                    Text(place.name).font(.headline)
                    arrivalButton(place, shop: false)
                    if place.type == 2 { arrivalButton(place, shop: true) }
                }.padding(.vertical, 4)
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
                    Text("roam.live.walkCloser").font(.caption) + Text(" \(gap) m").font(.caption)
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
        }.navigationTitle("roam.live.rules")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("action.done") { dismiss() } } }
    }
}
