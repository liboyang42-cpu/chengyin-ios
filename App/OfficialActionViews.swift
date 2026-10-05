import SwiftUI

/// Additive sheet; host constructs one coordinator per identity and destroys the sheet on epoch changes.
/// Existing official read views remain unchanged.
@MainActor struct OfficialActionSheet: View {
    let coordinator: OfficialActionCoordinator
    let command: OfficialActionCommand
    @Environment(\.dismiss) private var dismiss
    @State private var review: OfficialActionReview?
    @State private var busy = false
    @State private var message: String?
    @State private var receipt: OfficialActionReceipt?
    @State private var rejectionReason: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("officialAction.reviewNotice", systemImage: "lock.shield")
                    Text(LocalizedStringKey(command.titleKey)).font(.headline)
                    Text("officialAction.noOutcomePromise").foregroundStyle(.secondary)
                }
                if let review {
                    Section("officialAction.target") {
                        Text(review.command.scope).textSelection(.enabled)
                        if let event = review.snapshot.event { Text(event.title) }
                        if let invite = review.snapshot.invite { Text(invite.title) }
                        // Exact immutable payload, including explicit audience/channel and location details.
                        if let body = review.body, let object = try? JSONSerialization.jsonObject(with: body),
                           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
                            Text(String(decoding: pretty, as: UTF8.self)).font(.body.monospaced())
                                .textSelection(.enabled).accessibilityIdentifier("officialAction.reviewPayload")
                        }
                    }
                    Section {
                        Button("officialAction.confirm") { submit(review) }
                            .disabled(busy || !coordinator.enabled || receipt != nil)
                            .frame(minHeight: 44).accessibilityIdentifier("officialAction.confirm")
                        if !coordinator.enabled { Text("officialAction.disabled").foregroundStyle(.secondary) }
                    }
                }
                if busy { ProgressView().accessibilityLabel(Text("officialAction.working")) }
                if let message { Text(LocalizedStringKey(message)).accessibilityIdentifier("officialAction.message") }
                if let rejectionReason { Text(rejectionReason).accessibilityIdentifier("officialAction.rejectionReason") }
                if let receipt { receiptView(receipt) }
            }
            .navigationTitle("officialAction.review")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("officialAction.close") { coordinator.cancelReview(); dismiss() }.disabled(busy)
            } }
            .interactiveDismissDisabled(busy)
            .task { await prepare() }
            .onDisappear { coordinator.cancelReview() }
        }
    }
    @ViewBuilder private func receiptView(_ receipt: OfficialActionReceipt) -> some View {
        Section("officialAction.result") {
            switch receipt {
            case .published(let id): Text("officialAction.published"); Text(String(id))
            case .broadcastSubmitted(let id): Text("officialAction.broadcastSubmitted"); Text(String(id))
            case .invitesIssued(let ids): Text("officialAction.invitesIssued"); Text(ids.map(String.init).joined(separator: ", "))
            case .arrival(let accepted, let completed, _):
                Text(accepted ? "officialAction.arrivalAccepted" : "officialAction.arrivalRejected")
                Text(completed ? "officialAction.serverCompleted" : "officialAction.serverNotCompleted")
            case .acknowledged: Text("officialAction.acknowledged")
            }
            Text("officialAction.refreshFacts").foregroundStyle(.secondary)
        }
    }
    private func prepare() async {
        busy = true; defer { busy = false }
        do { review = try await coordinator.prepare(command) }
        catch { message = issue(error) }
    }
    private func submit(_ review: OfficialActionReview) {
        busy = true; message = nil
        Task { defer { busy = false }
            do { receipt = try await coordinator.confirm(review) }
            catch {
                if case let OfficialActionFailure.rejected(_, reason) = error { rejectionReason = reason }
                message = issue(error); self.review = nil
            }
        }
    }
    private func issue(_ error: Error) -> String {
        switch error {
        case OfficialActionFailure.disabled: return "officialAction.disabled"
        case OfficialActionFailure.locked: return "officialAction.locked"
        case OfficialActionFailure.unknown: return "officialAction.unknown"
        case OfficialActionFailure.storage: return "officialAction.storage"
        case OfficialActionFailure.stale: return "officialAction.stale"
        case OfficialActionFailure.forbidden: return "officialAction.forbidden"
        default: return coordinator.state == .unknown ? "officialAction.unknown" : "officialAction.rejected"
        }
    }
}

@MainActor struct OfficialPublishEditor: View {
    let coordinator: OfficialActionCoordinator
    @State private var draft = OfficialEventDraft()
    @State private var includeDates = false
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(86400)
    @State private var reviewed: OfficialActionCommand?
    var body: some View {
        Form {
            Section("officialAction.draft") {
                TextField("officialAction.title", text: $draft.title).accessibilityIdentifier("officialAction.title")
                TextField("officialAction.subtitle", text: $draft.subtitle, axis: .vertical)
                TextField("officialAction.city", text: $draft.city)
                Picker("officialAction.category", selection: $draft.category) {
                    ForEach(["city_light", "custom", "festival", "brand", "challenge"], id: \.self) { Text(LocalizedStringKey("officialAction.category." + $0)).tag($0) }
                }
                Toggle("officialAction.dates", isOn: $includeDates)
                if includeDates {
                    DatePicker("officialAction.start", selection: $start)
                    DatePicker("officialAction.end", selection: $end)
                }
            }
            Section("officialAction.rewards") {
                Toggle("officialAction.collective", isOn: $draft.collective)
                if draft.collective {
                    Picker("officialAction.metric", selection: $draft.metric) {
                        ForEach(["light_count", "complete_count", "signup_count"], id: \.self) { Text(LocalizedStringKey("officialAction.metric." + $0)).tag($0) }
                    }
                    TextField("officialAction.threshold", value: $draft.threshold, format: .number).keyboardType(.decimalPad)
                }
                TextField("officialAction.xp", value: $draft.experience, format: .number).keyboardType(.decimalPad)
                Toggle("officialAction.badge", isOn: $draft.badge)
                Text("officialAction.rewardWarning").foregroundStyle(.secondary)
            }
            Section {
                Button("officialAction.review") {
                    var copy = draft; copy.start = includeDates ? start : nil; copy.end = includeDates ? end : nil
                    reviewed = .publish(copy)
                }.disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(minHeight: 44).accessibilityIdentifier("officialAction.reviewPublish")
                Text("officialAction.editGap").foregroundStyle(.secondary)
            }
        }.navigationTitle("officialAction.publish")
            .sheet(isPresented: Binding(get: { reviewed != nil }, set: { if !$0 { reviewed = nil } })) {
                if let reviewed { OfficialActionSheet(coordinator: coordinator, command: reviewed) }
            }
    }
}

@MainActor struct OfficialBroadcastEditor: View {
    let coordinator: OfficialActionCoordinator
    @State private var draft = OfficialBroadcastDraft()
    @State private var reviewed: OfficialActionCommand?
    var body: some View {
        Form {
            Section("officialAction.audience") {
                ForEach(OfficialAudience.allCases, id: \.self) { role in
                    Toggle(LocalizedStringKey("officialAction.role." + role.rawValue), isOn: Binding(
                        get: { draft.audience.contains(role) }, set: { if $0 { draft.audience.insert(role) } else { draft.audience.remove(role) } }))
                }
                TextField("officialAction.city", text: $draft.city)
                Text("officialAction.cityWarning").foregroundStyle(.secondary)
            }
            Section("officialAction.channels") {
                ForEach(OfficialChannel.allCases, id: \.self) { channel in
                    Toggle(LocalizedStringKey("officialAction.channel." + channel.rawValue), isOn: Binding(
                        get: { draft.channels.contains(channel) }, set: { if $0 { draft.channels.insert(channel) } else { draft.channels.remove(channel) } }))
                }
            }
            Section("officialAction.copy") {
                Toggle("officialAction.split", isOn: $draft.split)
                if draft.split {
                    ForEach(OfficialAudience.allCases.filter { draft.audience.contains($0) }, id: \.self) { role in
                        Text(LocalizedStringKey("officialAction.role." + role.rawValue)).font(.headline)
                        TextField("officialAction.title", text: roleBinding(role, title: true))
                        TextField("officialAction.subtitle", text: roleBinding(role, title: false), axis: .vertical)
                    }
                } else {
                    TextField("officialAction.title", text: $draft.unified.title)
                    TextField("officialAction.subtitle", text: $draft.unified.sub, axis: .vertical)
                }
            }
            Button("officialAction.review") { reviewed = .broadcast(draft) }
                .disabled((try? draft.payload()) == nil).frame(minHeight: 44)
                .accessibilityIdentifier("officialAction.reviewBroadcast")
        }.navigationTitle("officialAction.broadcast")
            .sheet(isPresented: Binding(get: { reviewed != nil }, set: { if !$0 { reviewed = nil } })) {
                if let reviewed { OfficialActionSheet(coordinator: coordinator, command: reviewed) }
            }
    }
    private func roleBinding(_ role: OfficialAudience, title: Bool) -> Binding<String> {
        Binding(get: { let copy = draft.copies[role] ?? OfficialCopy(); return title ? copy.title : copy.sub },
                set: { var copy = draft.copies[role] ?? OfficialCopy(); if title { copy.title = $0 } else { copy.sub = $0 }; draft.copies[role] = copy })
    }
}

/// A caller must fetch the current account's inbox and permission before exposing controls.
@MainActor struct OfficialInviteResponseActions: View {
    let coordinator: OfficialActionCoordinator
    let invite: OfficialPartyInvite
    let publisher: Bool
    @State private var reason = ""
    @State private var reviewed: OfficialActionCommand?
    private var actions: [OfficialResponseAction] {
        if invite.partyType == "OFFICIAL" { return publisher && invite.status == "INVITED" ? [.accept, .decline] : [] }
        guard ["MERCHANT", "CLUB"].contains(invite.partyType ?? "") else { return [] }
        return invite.status == "INVITED" ? [.accept, .decline] : (["ACCEPTED", "ACTIVE"].contains(invite.status ?? "") ? [.withdraw] : [])
    }
    var body: some View {
        Section("officialAction.respond") {
            if !actions.isEmpty, invite.partyType != "OFFICIAL" { TextField("officialAction.reason", text: $reason, axis: .vertical) }
            ForEach(actions, id: \.self) { action in
                Button(LocalizedStringKey("officialAction." + action.rawValue.lowercased())) {
                    reviewed = .respond(partyID: invite.id, type: invite.partyType ?? "", action: action, reason: reason.isEmpty ? nil : reason)
                }.frame(minHeight: 44)
            }
        }.sheet(isPresented: Binding(get: { reviewed != nil }, set: { if !$0 { reviewed = nil } })) {
            if let reviewed { OfficialActionSheet(coordinator: coordinator, command: reviewed) }
        }
    }
}

@MainActor struct OfficialParticipationActions: View {
    let coordinator: OfficialActionCoordinator
    let event: OfficialEvent
    var arrival: OfficialArrivalEvidence? = nil
    @State private var reviewed: OfficialActionCommand?
    private var command: OfficialActionCommand? {
        guard !event.paused else { return nil }
        if event.signed == false && [2, 3].contains(event.status ?? -1) { return .signup(event.id) }
        if event.signed == true && event.status == 3 {
            if !event.isV2 && !event.roamEnabled { return .complete(event.id) }
            if event.isV2, let arrival, arrival.eventID == event.id,
               event.missions.contains(where: { $0.code == arrival.missionCode && $0.complete == false && $0.canVerifyArrival == true }) { return .arrival(arrival) }
        }
        return nil
    }
    var body: some View {
        Section("officialAction.participation") {
            if let command {
                Button(LocalizedStringKey(command.titleKey)) { reviewed = command }.frame(minHeight: 44)
                    .accessibilityIdentifier("officialAction.participationReview")
            } else { Text("officialAction.noAction").foregroundStyle(.secondary) }
        }.sheet(isPresented: Binding(get: { reviewed != nil }, set: { if !$0 { reviewed = nil } })) {
            if let reviewed { OfficialActionSheet(coordinator: coordinator, command: reviewed) }
        }
    }
}
@MainActor struct OfficialMerchantInviteEditor: View {
    struct Merchant: Identifiable { let id: Int; let name: String }
    let coordinator: OfficialActionCoordinator
    /// Host supplies verified candidates. This screen never searches contacts or sends suggestions.
    let candidates: [Merchant]
    @State private var selected: Set<Int> = []
    @State private var reviewed: OfficialActionCommand?
    var body: some View {
        Form {
            Section("officialAction.merchants") {
                ForEach(candidates) { merchant in
                    Toggle(merchant.name, isOn: Binding(get: { selected.contains(merchant.id) }, set: {
                        if $0 { selected.insert(merchant.id) } else { selected.remove(merchant.id) }
                    }))
                }
            }
            Text("officialAction.inviteWarning")
            Button("officialAction.review") { reviewed = .inviteMerchants(selected.sorted()) }
                .disabled(selected.isEmpty).frame(minHeight: 44)
        }.navigationTitle("officialAction.invite")
            .sheet(isPresented: Binding(get: { reviewed != nil }, set: { if !$0 { reviewed = nil } })) {
                if let reviewed { OfficialActionSheet(coordinator: coordinator, command: reviewed) }
            }
    }
}
