import SwiftUI

/// A readback ticket grants no write authority and survives only its detail visit.
struct OfficialDetailReturnLease {
    let eventID: Int
    let scope: UUID
    let visit: UUID
    func permits(eventID currentEventID: Int, scope currentScope: UUID, visit currentVisit: UUID,
                 visible: Bool, active: Bool) -> Bool {
        eventID == currentEventID && scope == currentScope && visit == currentVisit && visible && active
    }
}

@MainActor struct OfficialEventDetailView: View {
    let id: Int
    let reader: any OfficialEventReading
    var actions: OfficialActionCoordinator? = nil
    var onLogin: (() -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @State private var visit = UUID()
    @State private var readback = UUID()
    @State private var visible = false
    var body: some View {
        OfficialReadScreen(reader: reader, requestID: "event.\(id).\(readback)", onLogin: onLogin, load: { try await reader.detail(id: id) }) { event in
            List {
                OfficialEventCard(event: event).questifyCardListRow()
                Section("official.facts") {
                    LabeledContent("official.start") { OfficialEventTimeValue(value: event.activityStart) }
                    LabeledContent("official.end") { OfficialEventTimeValue(value: event.activityEnd) }
                    if let participants = event.participants { LabeledContent("official.participants", value: String(participants)) }
                    LabeledContent("official.price") { Text("official.priceNotProvided") }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("official.price"))
                        .accessibilityValue(Text("official.priceNotProvided"))
                        .accessibilityIdentifier("official.price")
                }
                if let story = event.story, !story.isEmpty {
                    Section("official.story") { Text(verbatim: story).textSelection(.enabled) }
                }
                Section("official.participation") {
                    Text(LocalizedStringKey(reader.isAuthenticated ? event.participationKey : event.statusKey)).accessibilityIdentifier("official.participationState")
                    if event.paused, let reason = event.pausedReason, !reason.isEmpty { Text(verbatim: reason) }
                    if reader.isAuthenticated {
                        if event.signed == true {
                            if event.isV2 { LabeledContent("official.completedTasks", value: "\(event.completedMissionCount)/\(event.missions.count)") }
                            else if let progress = event.myProgress { LabeledContent("official.progress", value: String(progress)) }
                        }
                        if let eligible = event.eligible { Text(eligible ? "official.eligible" : "official.notEligible") }
                    } else {
                        Text("official.signInForProgress")
                        if let onLogin { Button("official.signIn", action: onLogin).frame(minHeight: 44) }
                    }
                    Text("official.actionsDeferred").font(.footnote).foregroundStyle(.secondary)
                }
                if reader.isAuthenticated, let actions {
                    let lease = OfficialDetailReturnLease(eventID: id, scope: reader.scope, visit: visit)
                    OfficialParticipationActions(coordinator: actions, event: event, onReturn: {
                        guard lease.permits(eventID: id, scope: reader.scope, visit: visit,
                                            visible: visible, active: scenePhase == .active) else { return }
                        // Reuse the existing detail GET. Never repeat the action or
                        // infer settlement from its acknowledgement/unknown result.
                        readback = UUID()
                    })
                }
                if event.isV2 {
                    Section("official.tasks") {
                        if event.missions.isEmpty { Text("official.noTasks") }
                        ForEach(Array(event.missions.enumerated()), id: \.offset) { index, mission in
                            VStack(alignment: .leading, spacing: 8) {
                                if mission.title.isEmpty { Text("official.untitledTask").font(.headline) }
                                else { Text(verbatim: mission.title).font(.headline) }
                                if let description = mission.description, !description.isEmpty { Text(verbatim: description) }
                                if reader.isAuthenticated {
                                    if mission.complete == true { Label("official.task.verified", systemImage: "checkmark.circle") }
                                    else if mission.canVerifyArrival == true { Label("official.task.arrivalDeferred", systemImage: "location") }
                                    else { Label("official.task.automatic", systemImage: "arrow.triangle.2.circlepath") }
                                }
                            }.accessibilityElement(children: .combine).accessibilityIdentifier("official.mission.\(index)")
                        }
                    }
                }
                if let collective = event.collective, collective.enabled {
                    Section("official.collective") {
                        if let percent = collective.percent {
                            LabeledContent("official.collectivePercent", value: "\(percent)%")
                            ProgressView(value: collective.displayFraction ?? 0).accessibilityHidden(true)
                        }
                        if let count = collective.current { LabeledContent("official.collectiveCurrent", value: String(count)) }
                        if let threshold = collective.threshold { LabeledContent("official.collectiveThreshold", value: String(threshold)) }
                        Text(event.hasCollectiveReward ? "official.collectiveRewardConfigured" : "official.collectiveRewardAbsent")
                    }
                }
                Section("official.rewards") {
                    if event.rewards.isEmpty { Text("official.noRewards") }
                    ForEach(Array(event.rewards.enumerated()), id: \.offset) { _, reward in
                        switch reward {
                        case .badge: Label("official.reward.badge", systemImage: "seal")
                        case .coupon: Label("official.reward.coupon", systemImage: "ticket")
                        case .experience(let amount): LabeledContent("official.reward.experience", value: amount)
                        case .collectiveCoupon: Label("official.reward.collective", systemImage: "person.3")
                        }
                    }
                    if !event.rewards.isEmpty { Text("official.rewardConditions").font(.footnote) }
                }
                Section { OfficialReadOnlyNotice(offline: reader.isOfflineExample) }
            }.accessibilityIdentifier("official.detail.content")
        }
        .appNavigationTitle("official.detail").navigationBarTitleDisplayMode(.inline)
        .onAppear { visible = true }
        .onDisappear { visible = false; visit = UUID() }
        .onChange(of: id) { _, _ in visit = UUID() }
        .onChange(of: reader.scope) { _, _ in visit = UUID() }
        .onChange(of: scenePhase) { _, _ in visit = UUID() }
    }
}
