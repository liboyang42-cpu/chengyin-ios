import SwiftUI

/// The session owner supplies one retained coordinator. No coordinator or writer is
/// constructed by a view, and the read-only detail remains the default without one.
@MainActor
struct ClubActionPanel: View {
    let club: ClubRecord
    let identity: ClubReadIdentity
    let coordinator: ClubActionCoordinator
    let onReadbackStarted: () -> UInt64
    let onReadback: (ClubRecord, ClubReadIdentity, UInt64) -> Void
    @State private var ownerID = UUID()
    @State private var revision: UInt64 = 0
    @State private var generation: UInt64 = 0
    @State private var confirmation: ClubActionConfirmation? = nil
    @State private var issueKey: String? = nil
    @State private var task: Task<Void, Never>? = nil
    @State private var isWorking = false
    @State private var joinMessage = ""

    private var availability: ClubActionAvailability {
        ClubActionAvailability.resolve(club, viewerIsMerchant: coordinator.viewerIsMerchant)
    }
    var body: some View {
        let _ = revision
        let state = coordinator.state(clubID: club.id)
        Section {
            if coordinator.identity != identity || !identity.isSignedIn {
                Text("club.signInRequired").foregroundStyle(.secondary)
            } else if !coordinator.isConfigured {
                Text("club.action.unavailable").foregroundStyle(.secondary)
            } else {
                stateContent(state)
                if case .available(let action) = availability {
                    if action == .apply {
                        TextField("club.application.message", text: $joinMessage, axis: .vertical)
                            .disabled(isWorking || state.preventsNewAction)
                            .accessibilityIdentifier("club.application.message")
                        Text("club.application.messageHelp").font(.caption).foregroundStyle(.secondary)
                        if !ClubApplicationMessage.isValid(joinMessage, for: .apply) {
                            Text("club.application.messageTooLong").foregroundStyle(.secondary)
                                .accessibilityIdentifier("club.application.messageTooLong")
                        }
                    }
                    Button(role: action == .leave ? .destructive : nil) { prepare(action) } label: {
                        Label(LocalizedStringKey(actionKey(action)), systemImage: action == .leave ? "rectangle.portrait.and.arrow.right" : "person.badge.plus")
                    }
                    .disabled(isWorking || state.preventsNewAction || !ClubApplicationMessage.isValid(action == .apply ? joinMessage : "", for: action))
                    .accessibilityIdentifier("club.action.\(action.rawValue)")
                } else {
                    Text(LocalizedStringKey(availabilityKey)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("club.action.gated")
                }
                if isWorking { ProgressView("club.action.working").accessibilityIdentifier("club.action.loading") }
                if let issueKey { Text(LocalizedStringKey(issueKey)).foregroundStyle(.secondary).accessibilityIdentifier("club.action.error") }
            }
        } header: { Text("club.action.membership") }
        .confirmationDialog(LocalizedStringKey(confirmation.map { actionKey($0.action) } ?? "club.action.membership"),
                            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { cancelConfirmation() } }),
                            titleVisibility: .visible, presenting: confirmation) { value in
            Button(LocalizedStringKey(actionKey(value.action)), role: value.action == .leave ? .destructive : nil) { submit(value) }
                .accessibilityIdentifier("club.action.confirm")
            Button("action.cancel", role: .cancel) { cancelConfirmation() }
        } message: { value in
            Text(verbatim: value.clubName) + Text("\n") + Text(LocalizedStringKey(confirmationKey(value.action)))
                + Text(verbatim: value.action == .apply ? "\n" + value.joinMessage : "")
        }
        .onChange(of: identity) { _, _ in reset() }
        .onChange(of: club.id) { old, _ in reset(clubID: old) }
        .onDisappear { reset() }
    }
    @ViewBuilder private func stateContent(_ state: ClubActionState) -> some View {
        switch state {
        case .outcomeUnknown:
            Text("club.action.unknown").accessibilityIdentifier("club.action.unknown")
            Button("club.action.readback") { readBack() }
                .disabled(isWorking).accessibilityIdentifier("club.action.readback")
            readbackContent
        case .acknowledged(let receipt):
            if let message = receipt.message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: message).accessibilityIdentifier("club.action.serverMessage")
            } else { Text("club.action.acknowledged").accessibilityIdentifier("club.action.acknowledged") }
            readbackContent
            if coordinator.readback(clubID: club.id) == .unavailable {
                Button("club.action.readback") { readBack() }.disabled(isWorking).accessibilityIdentifier("club.action.readback")
            }
        case .notSent: Text("club.action.notSent").accessibilityIdentifier("club.action.notSent")
        case .rejected(let failure):
            Text("club.action.rejected")
            if let message = failure.message { Text(verbatim: message).accessibilityIdentifier("club.action.serverMessage") }
        default: EmptyView()
        }
    }
    @ViewBuilder private var readbackContent: some View {
        switch coordinator.readback(clubID: club.id) {
        case .received:
            // The displayed club may come from a newer ordinary refresh. Never show
            // an older coordinator snapshot as current membership beside it.
            Label {
                Text(LocalizedStringKey(club.isOwner ? "club.role.creator" : club.isJoined ? "club.membership.joined" : club.joinPending ? "club.membership.pending" : "club.action.notJoined"))
                    .accessibilityIdentifier("club.action.serverMembership")
            } icon: {
                // This is a status, not a Refresh action. Keep the decorative symbol
                // out of VoiceOver and attach the status identifier only to its text.
                Image(systemName: "arrow.clockwise").accessibilityHidden(true)
            }
        case .unavailable: Text("club.action.readbackUnavailable").foregroundStyle(.secondary)
        default: EmptyView()
        }
    }
    private var availabilityKey: String {
        switch availability {
        case .owner: return "club.action.owner"
        case .pending: return "club.membership.pending"
        case .merchant: return "club.action.merchant"
        case .unsupportedStatus: return "club.action.unsupported"
        case .available: return "club.action.membership"
        }
    }
    private func actionKey(_ action: ClubAction) -> String {
        if action == .apply && club.myJoinStatus == 2 { return "club.action.reapply" }
        switch action {
        case .join: return "club.action.join"
        case .apply: return "club.action.apply"
        case .leave: return "club.action.leave"
        }
    }
    private func confirmationKey(_ action: ClubAction) -> String {
        switch action {
        case .join: return "club.action.confirm.join"
        case .apply: return "club.action.confirm.apply"
        case .leave: return "club.action.confirm.leave"
        }
    }
    private func prepare(_ action: ClubAction) {
        guard !isWorking, coordinator.identity == identity else { return }
        generation &+= 1
        let operation = generation, snapshot = identity, clubID = club.id
        let reviewedMessage = action == .apply ? joinMessage : ""
        isWorking = true; issueKey = nil
        task = Task {
            defer { if operation == generation { isWorking = false; revision &+= 1 } }
            do {
                let value = try await coordinator.prepare(clubID: clubID, action: action, expectedIdentity: snapshot, ownerID: ownerID, joinMessage: reviewedMessage)
                guard !Task.isCancelled, operation == generation, coordinator.identity == snapshot else { coordinator.cancel(value); return }
                confirmation = value
            } catch {
                guard operation == generation, coordinator.identity == snapshot, !Task.isCancelled else { return }
                issueKey = (error as? ClubActionBlock) == .eligibilityChanged ? "club.action.changed" : "club.action.prepareFailed"
            }
        }
    }
    private func submit(_ value: ClubActionConfirmation) {
        guard !isWorking, coordinator.identity == value.identity else { cancelConfirmation(); return }
        // Clear local presentation without cancelling the coordinator's frozen intent.
        confirmation = nil; isWorking = true; issueKey = nil
        generation &+= 1
        let operation = generation
        task = Task {
            var readbackGeneration: UInt64?
            _ = await coordinator.confirm(value, onReadbackStarted: { readbackGeneration = onReadbackStarted() })
            guard operation == generation, !Task.isCancelled, coordinator.identity == value.identity else { return }
            isWorking = false; revision &+= 1
            if let readbackGeneration { deliverReadback(identity: value.identity, readbackGeneration: readbackGeneration) }
        }
    }
    private func readBack() {
        guard !isWorking, coordinator.identity == identity else { return }
        generation &+= 1
        let operation = generation, snapshot = identity
        isWorking = true; issueKey = nil
        task = Task {
            var readbackGeneration: UInt64?
            _ = await coordinator.readBack(clubID: club.id, ownerID: ownerID, onStarted: { readbackGeneration = onReadbackStarted() })
            guard operation == generation, !Task.isCancelled, coordinator.identity == snapshot else { return }
            isWorking = false; revision &+= 1
            if let readbackGeneration { deliverReadback(identity: snapshot, readbackGeneration: readbackGeneration) }
        }
    }
    private func deliverReadback(identity: ClubReadIdentity, readbackGeneration: UInt64) {
        if case .received(let detail) = coordinator.readback(clubID: club.id), detail.id == club.id { onReadback(detail, identity, readbackGeneration) }
    }
    private func cancelConfirmation() { if let confirmation { coordinator.cancel(confirmation) }; confirmation = nil; revision &+= 1 }
    private func reset(clubID: Int? = nil) {
        generation &+= 1; task?.cancel(); task = nil
        if let confirmation { coordinator.cancel(confirmation) }
        // Synchronization handles old-session writes even when the view now has a new identity.
        coordinator.synchronizeSession()
        coordinator.leaveScreen(clubID: clubID ?? club.id, expectedIdentity: identity, ownerID: ownerID)
        confirmation = nil; isWorking = false; issueKey = nil; joinMessage = ""; revision &+= 1
    }
}
