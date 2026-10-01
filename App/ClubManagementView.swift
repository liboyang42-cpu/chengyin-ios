import SwiftUI

/// Host injects its retained coordinator and publishes account/epoch changes via identity.
/// No cached ClubRecord or role chooser authorizes a management operation.
struct ClubManagementView: View {
    let clubID: Int
    let identity: ClubReadIdentity?
    let access: any ClubManagementAccess
    let coordinator: ClubManagementCoordinator
    @State private var snapshot: ClubManagementSnapshot?
    @State private var confirmation: ClubManagementConfirmation?
    @State private var state: ClubManagementState = .idle
    @State private var loading = false
    @State private var failed = false
    @State private var serverReadMessage: String?
    @State private var denied = false
    @State private var readbackUnavailable = false
    @State private var generation: UInt64 = 0
    @State private var ownerID = UUID()
    @State private var screenIdentity: ClubReadIdentity?

    var body: some View {
        List {
            if identity == nil {
                Text("club.management.signin")
            } else if !access.isConfigured {
                Text("club.management.unconfigured")
            } else {
                if loading { ProgressView().accessibilityLabel(Text("club.management.loading")) }
                if failed {
                    Text(LocalizedStringKey(denied ? "club.management.denied" : "club.management.unavailable")).foregroundStyle(.secondary)
                    if let serverReadMessage { Text(verbatim: serverReadMessage) }
                }
                status
                if let snapshot {
                    Section { Text(verbatim: snapshot.club.name) }
                    Section("club.management.requests") {
                        if snapshot.requests.isEmpty { Text("club.management.empty") }
                        ForEach(snapshot.requests) { request in
                            NavigationLink {
                                Form {
                                    Text(verbatim: request.nickname ?? "#\(request.id)")
                                    Text(verbatim: "#\(request.id)")
                                    if let time = request.joinTime { Text(verbatim: time) }
                                    if snapshot.allows(.approve, memberID: request.id) {
                                        action(.approve, memberID: request.id)
                                        action(.reject, memberID: request.id)
                                    }
                                }
                                .navigationTitle("club.management.request")
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(verbatim: request.nickname ?? "#\(request.id)")
                                    Text(verbatim: request.joinTime ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("club.management.request.\(request.id)")
                        }
                    }
                    if snapshot.club.isOwner {
                        Section("club.management.members") {
                            if snapshot.members.isEmpty {
                                Text(LocalizedStringKey(snapshot.club.memberCount > 0 ? "club.management.members_unavailable" : "club.management.members_empty"))
                            }
                            ForEach(snapshot.members) { member in
                                NavigationLink {
                                    Form {
                                        Text(verbatim: member.nickname ?? "#\(member.id)")
                                        Text(verbatim: "#\(member.id)")
                                        if snapshot.allows(.remove, memberID: member.id) { action(.remove, memberID: member.id) }
                                    }
                                    .navigationTitle("club.management.member")
                                } label: { Text(verbatim: member.nickname ?? "#\(member.id)") }
                                .accessibilityIdentifier("club.management.member.\(member.id)")
                            }
                        }
                    }
                }
                Button("club.management.refresh") { Task { await refresh() } }
                    .disabled(loading || state == .checking || state == .awaitingConfirmation || state == .submitting)
                    .accessibilityIdentifier("club.management.refresh")
                Text("club.management.deferred").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("club.management.title")
        .sheet(isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { cancel() } })) {
            if let pending = confirmation {
                NavigationStack {
                    Form {
                        Text(LocalizedStringKey("club.management." + String(pending.action.rawValue) + ".body"))
                        LabeledContent("club.management.club") { Text(verbatim: "\(pending.clubName) (#\(pending.clubID))") }
                        LabeledContent("club.management.target") { Text(verbatim: "\(pending.memberName) (#\(pending.memberID))") }
                        Button(role: pending.action == .approve ? nil : .destructive) {
                            confirmation = nil
                            state = .submitting
                            Task { await confirm(pending) }
                        } label: { Text(LocalizedStringKey("club.management." + String(pending.action.rawValue))) }
                        .accessibilityIdentifier("club.management.confirm")
                    }
                    .navigationTitle(LocalizedStringKey("club.management." + String(pending.action.rawValue)))
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("club.management.cancel") { cancel() } } }
                }
                .accessibilityIdentifier("club.management.confirmation")
            }
        }
        .task(id: identity) {
            generation &+= 1
            cancel(); snapshot = nil; state = .idle; loading = false
            screenIdentity = identity
            coordinator.synchronizeSession()
            await refresh()
        }
        .onDisappear {
            generation &+= 1
            if let screenIdentity { coordinator.leaveScreen(clubID: clubID, expectedIdentity: screenIdentity, ownerID: ownerID) }
            cancel()
        }
    }
    @ViewBuilder private var status: some View {
        switch state {
        case .checking, .submitting: ProgressView()
        case .notSent: Text("club.management.not_sent")
        case .acknowledged(let receipt):
            if let message = receipt.message { Text(verbatim: message) } else { Text("club.management.acknowledged") }
        case .rejected(let failure):
            if let message = failure.message { Text(verbatim: message) } else { Text("club.management.rejected") }
        case .outcomeUnknown: Text("club.management.unknown").accessibilityIdentifier("club.management.unknown")
        default: EmptyView()
        }
        if readbackUnavailable { Text("club.management.readback_unavailable") }
    }
    private func action(_ action: ClubManagementAction, memberID: Int) -> some View {
        Button(role: action == .approve ? nil : .destructive) {
            Task { await prepare(action, memberID: memberID) }
        } label: { Text(LocalizedStringKey("club.management." + String(action.rawValue))) }
            .disabled(loading || state.preventsNewAction)
            .accessibilityIdentifier("club.management.\(action.rawValue).\(memberID)")
    }
    private func cancel() {
        if let confirmation { coordinator.cancel(confirmation) }
        confirmation = nil
        state = coordinator.state(clubID: clubID)
    }
    @MainActor private func refresh() async {
        guard identity != nil, access.isConfigured, !loading else { return }
        generation &+= 1; let run = generation; let captured = identity
        loading = true; failed = false; serverReadMessage = nil; denied = false; snapshot = nil; readbackUnavailable = false
        state = coordinator.state(clubID: clubID)
        do {
            let result = try await access.snapshot(clubID: clubID)
            guard run == generation, identity == captured, access.identity == captured, !Task.isCancelled else { return }
            snapshot = result; loading = false
        } catch {
            guard run == generation, identity == captured, access.identity == captured, !Task.isCancelled else { return }
            failed = true; loading = false
            serverReadMessage = (error as? ClubReadFailure)?.message
            denied = (error as? ClubReadFailure)?.isForbidden == true
        }
    }
    @MainActor private func prepare(_ action: ClubManagementAction, memberID: Int) async {
        guard let identity, !state.preventsNewAction, !loading else { return }
        generation &+= 1; let run = generation
        state = .checking
        do {
            let pending = try await coordinator.prepare(clubID: clubID, action: action, memberID: memberID, expectedIdentity: identity, ownerID: ownerID)
            guard run == generation, access.identity == identity, !Task.isCancelled else { coordinator.cancel(pending); return }
            confirmation = pending; state = coordinator.state(clubID: clubID)
        } catch {
            guard run == generation, access.identity == identity else { return }
            snapshot = nil; failed = true; state = coordinator.state(clubID: clubID)
            serverReadMessage = (error as? ClubReadFailure)?.message
            denied = (error as? ClubReadFailure)?.isForbidden == true
        }
    }
    @MainActor private func confirm(_ pending: ClubManagementConfirmation) async {
        generation &+= 1; let run = generation
        snapshot = nil
        _ = await coordinator.confirm(pending)
        guard run == generation, access.identity == pending.identity, !Task.isCancelled else { return }
        state = coordinator.state(clubID: clubID)
        switch coordinator.readback(clubID: clubID) {
        case .received(let result): snapshot = result
        case .unavailable: readbackUnavailable = true
        default: break
        }
    }
}
