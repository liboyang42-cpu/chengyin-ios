import SwiftUI

/// Host injects its retained coordinator and publishes account/epoch changes via identity.
/// No cached ClubRecord or role chooser authorizes a management operation.
struct ClubManagementView: View {
    let clubID: Int
    let identity: ClubReadIdentity?
    let access: any ClubManagementAccess
    let coordinator: ClubManagementCoordinator
    var viewerRevision: UInt64 = 0
    var onMembershipChanged: (() -> Void)? = nil
    @State private var selection: DetailSelection?
    private enum DetailSelection: Hashable, Identifiable {
        case request(Int), member(Int)
        var id: Self { self }
    }
    @State private var snapshot: ClubManagementSnapshot?
    @State private var confirmation: ClubManagementConfirmation?
    @State private var state: ClubManagementState = .idle
    @State private var loading = false
    @State private var stale = false
    @State private var screenRevision: UInt64?
    private struct ReadContext: Hashable { let identity: ClubReadIdentity?; let revision: UInt64 }
    private var readContext: ReadContext { .init(identity: identity, revision: viewerRevision) }
    private var contextMatches: Bool { screenIdentity == identity && access.identity == identity && screenRevision == viewerRevision }
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
                if contextMatches, let snapshot {
                    Section { Text(verbatim: snapshot.club.name) }
                    Section("club.management.requests") {
                        if snapshot.requests.isEmpty { Text("club.management.empty") }
                        ForEach(snapshot.requests) { request in
                            Button { selection = .request(request.id) } label: {
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
                                Button { selection = .member(member.id) } label: { Text(verbatim: member.nickname ?? "#\(member.id)") }
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
        .appNavigationTitle("club.management.title")
        .navigationDestination(item: $selection) { selected in detail(selected) }
        .sheet(isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { cancel() } })) {
            if contextMatches, let pending = confirmation {
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
                    .appNavigationTitle(key: "club.management." + pending.action.rawValue)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("club.management.cancel") { cancel() } } }
                }
                .accessibilityIdentifier("club.management.confirmation")
            }
        }
        .task(id: readContext) {
            guard screenIdentity != identity || screenRevision != viewerRevision || snapshot == nil && state == .idle else { return }
            leaveScreen()
            generation &+= 1
            cancel(); selection = nil; snapshot = nil; stale = false; state = .idle; loading = false
            screenIdentity = identity; screenRevision = viewerRevision
            coordinator.synchronizeSession()
            await refresh()
        }
        .onDisappear { leaveScreen() }
    }
    @ViewBuilder private func detail(_ selected: DetailSelection) -> some View {
        Form {
            if loading { ProgressView().accessibilityIdentifier("club.management.detail.loading") }
            status
            if contextMatches, access.identity == identity, let snapshot {
                switch selected {
                case .request(let id):
                    if let request = snapshot.requests.first(where: { $0.id == id }) {
                        Text(verbatim: request.nickname ?? "#\(id)")
                        Text(verbatim: "#\(id)")
                        if let time = request.joinTime { Text(verbatim: time) }
                        if let message = request.joinMessage, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("club.application.messageReceived").font(.caption).foregroundStyle(.secondary)
                                Text(verbatim: message).accessibilityIdentifier("club.management.joinMessage")
                            }
                        }
                        if snapshot.allows(.approve, memberID: id) {
                            action(.approve, memberID: id)
                            action(.reject, memberID: id)
                        }
                    }
                case .member(let id):
                    if let member = snapshot.members.first(where: { $0.id == id }) {
                        Text(verbatim: member.nickname ?? "#\(id)")
                        Text(verbatim: "#\(id)")
                        if snapshot.allows(.remove, memberID: id) { action(.remove, memberID: id) }
                    }
                }
            }
            if failed {
                Text(LocalizedStringKey(denied ? "club.management.denied" : "club.management.unavailable"))
                if let serverReadMessage { Text(verbatim: serverReadMessage) }
            }
            Button("club.management.refresh") { Task { await refresh() } }
                .disabled(loading || state == .checking || state == .awaitingConfirmation || state == .submitting)
                .accessibilityIdentifier("club.management.detail.refresh")
        }
        .appNavigationTitle(key: {
            switch selected { case .request: return "club.management.request"; case .member: return "club.management.member" }
        }())
        // The root List's task is suspended while this destination is pushed.
        // Invalidate its selection here, where viewer changes are still observed.
        .onChange(of: readContext) { _, _ in invalidateDetailContext() }
        .onDisappear { leaveScreen() }
    }
    private func invalidateDetailContext() {
        guard screenIdentity != identity || screenRevision != viewerRevision else { return }
        // Fence cancellation-ignoring completions and cancel only undispatched review.
        // leaveScreen preserves dispatched/unknown coordinator journal entries.
        leaveScreen()
        selection = nil; snapshot = nil; stale = false
        failed = false; denied = false; serverReadMessage = nil; readbackUnavailable = false
        // Do not mark the new context as read. The returning root must fetch it.
        screenRevision = nil
    }
    private func leaveScreen() {
        generation &+= 1
        loading = false
        if let screenIdentity { coordinator.leaveScreen(clubID: clubID, expectedIdentity: screenIdentity, ownerID: ownerID) }
        cancel()
    }
    @ViewBuilder private var status: some View {
        if stale { Text("club.management.stale").accessibilityIdentifier("club.management.stale") }
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
        if readbackUnavailable { Text("club.management.readback_unavailable").accessibilityIdentifier("club.management.readbackUnavailable") }
    }
    private func action(_ action: ClubManagementAction, memberID: Int) -> some View {
        Button(role: action == .approve ? nil : .destructive) {
            Task { await prepare(action, memberID: memberID) }
        } label: { Text(LocalizedStringKey("club.management." + String(action.rawValue))) }
            .disabled(loading || stale || !contextMatches || state.preventsNewAction)
            .accessibilityIdentifier("club.management.\(action.rawValue).\(memberID)")
    }
    private func cancel() {
        if let confirmation { coordinator.cancel(confirmation) }
        confirmation = nil
        state = coordinator.state(clubID: clubID)
    }
    @MainActor private func refresh() async {
        guard identity != nil, access.isConfigured, contextMatches, !loading,
              state != .checking, state != .awaitingConfirmation, state != .submitting else { return }
        generation &+= 1; let run = generation; let captured = identity; let revision = viewerRevision
        loading = true; failed = false; serverReadMessage = nil; denied = false
        stale = snapshot != nil
        state = coordinator.state(clubID: clubID)
        do {
            let result = try await access.snapshot(clubID: clubID)
            guard run == generation, identity == captured, access.identity == captured, viewerRevision == revision, screenRevision == revision, !Task.isCancelled else { return }
            guard result.club.id == clubID, result.club.canGovern else { throw ClubReadFailure.forbidden(message: nil) }
            snapshot = result; stale = false; loading = false; readbackUnavailable = false
        } catch {
            guard run == generation, identity == captured, access.identity == captured, viewerRevision == revision, screenRevision == revision, !Task.isCancelled else { return }
            if let snapshot, let failure = error as? ClubManagementListConnectionFailure, failure.canRetain(snapshot) {
                stale = true
            } else { snapshot = nil; stale = false }
            failed = true; loading = false
            serverReadMessage = (error as? ClubReadFailure)?.message
            denied = (error as? ClubReadFailure)?.isForbidden == true
        }
    }
    @MainActor private func prepare(_ action: ClubManagementAction, memberID: Int) async {
        guard let identity, contextMatches, !stale, !state.preventsNewAction, !loading else { return }
        generation &+= 1; let run = generation; let revision = viewerRevision
        state = .checking
        do {
            let pending = try await coordinator.prepare(clubID: clubID, action: action, memberID: memberID, expectedIdentity: identity, ownerID: ownerID)
            guard run == generation, access.identity == identity, viewerRevision == revision, screenRevision == revision, !Task.isCancelled else { coordinator.cancel(pending); return }
            confirmation = pending; state = coordinator.state(clubID: clubID)
        } catch {
            guard run == generation, access.identity == identity, viewerRevision == revision, screenRevision == revision else { return }
            snapshot = nil; stale = false; failed = true; state = coordinator.state(clubID: clubID)
            serverReadMessage = (error as? ClubReadFailure)?.message
            denied = (error as? ClubReadFailure)?.isForbidden == true
        }
    }
    @MainActor private func confirm(_ pending: ClubManagementConfirmation) async {
        guard contextMatches, !stale, pending.identity == identity else { coordinator.cancel(pending); return }
        generation &+= 1; let run = generation; let revision = viewerRevision
        snapshot = nil; stale = false
        _ = await coordinator.confirm(pending)
        guard run == generation, access.identity == pending.identity, !Task.isCancelled, viewerRevision == revision, screenRevision == revision else { return }
        state = coordinator.state(clubID: clubID)
        switch coordinator.readback(clubID: clubID) {
        case .received(let result): snapshot = result
        case .unavailable: readbackUnavailable = true
        default: break
        }
        if case .acknowledged = state {
            // Navigate back only after a definite server acknowledgement. A failed
            // readback remains visible on the list; it never fabricates new rows.
            selection = nil
            onMembershipChanged?()
        }
    }
}
