import SwiftUI

/// Session host owns access/coordinator and passes a published identity. This additive
/// entry can be mounted on ClubHome (.create) and ClubDetail (.club(id)).
struct ClubOperationsEntryButton: View {
    let target: ClubOperationsTarget
    let identity: ClubReadIdentity?
    let access: any ClubOperationsAccess
    let coordinator: ClubOperationsCoordinator
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: { Label(target == .create ? "club.ops.create" : "club.ops.manage", systemImage: target == .create ? "plus.circle" : "slider.horizontal.3") }
            .accessibilityIdentifier("club.ops." + (target == .create ? "openCreate" : "openManage"))
            .sheet(isPresented: $presented) {
                NavigationStack { ClubOperationsWorkspaceView(target: target, identity: identity, access: access, coordinator: coordinator) }
            }
    }
}

struct ClubOperationsWorkspaceView: View {
    let target: ClubOperationsTarget
    let identity: ClubReadIdentity?
    let access: any ClubOperationsAccess
    let coordinator: ClubOperationsCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: ClubOperationsSnapshot?
    @State private var draft = ClubOperationsDraft()
    @State private var baseline = ClubOperationsDraft()
    @State private var state: ClubOperationsState = .idle
    @State private var review: ClubOperationsReview?
    @State private var loading = false
    @State private var errorKey: String?
    @State private var serverMessage: String?
    @State private var generation: UInt64 = 0
    @State private var screenIdentity: ClubReadIdentity?
    @State private var showDiscard = false
    @State private var readbackUnavailable = false
    @State private var ownerID = UUID()
    private var dirty: Bool { draft != baseline }
    private var title: LocalizedStringKey { target == .create ? "club.ops.create" : "club.ops.manage" }
    var body: some View {
        Form {
            if loading { ProgressView().accessibilityIdentifier("club.ops.loading") }
            if identity == nil { Text("club.ops.signedOut") }
            else if !access.isConfigured { Text("club.ops.unavailable") }
            if let errorKey { Text(LocalizedStringKey(errorKey)).accessibilityIdentifier("club.ops.error") }
            if let serverMessage { Text(verbatim: serverMessage).textSelection(.enabled) }
            if let snapshot { content(snapshot) }
            status
        }
        .navigationTitle(title)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: loading)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("club.ops.close") {
                    if dirty || state.locksForm { showDiscard = true } else { dismiss() }
                }.accessibilityIdentifier("club.ops.close")
            }
        }
        .interactiveDismissDisabled(dirty || state.locksForm)
        .confirmationDialog("club.ops.discardTitle", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("club.ops.discard", role: .destructive) { dismiss() }
            Button("club.ops.keepEditing", role: .cancel) {}
        } message: { Text("club.ops.discardMessage") }
        .sheet(item: $review, onDismiss: cancelReview) { pending in
            NavigationStack {
                ClubOperationsReviewView(review: pending, canSubmit: coordinator.writeAvailability != .unverified, isExample: coordinator.writeAvailability == .syntheticOnly, onCancel: cancelReview) {
                    review = nil; state = .preflighting
                    Task { await confirm(pending) }
                }
            }.interactiveDismissDisabled(state == .preflighting || state == .submitting)
        }
        .task(id: identity) {
            generation &+= 1; cancelReview(); snapshot = nil; draft = .init(); baseline = .init()
            screenIdentity = identity; errorKey = nil; serverMessage = nil; readbackUnavailable = false
            coordinator.synchronizeSession()
            state = coordinator.state(target: target); loading = false
            await load()
        }
        .onDisappear {
            generation &+= 1
            if let screenIdentity { coordinator.leaveScreen(target: target, expectedIdentity: screenIdentity, ownerID: ownerID) }
        }
    }
    @ViewBuilder private func content(_ value: ClubOperationsSnapshot) -> some View {
        if let profile = value.profile {
            Section {
                QuestifyImageEntityCard(imageSource: profile.club.cover, title: profile.club.name, subtitle: profile.club.city, fallbackSymbol: "person.3.fill", minimumHeight: 230) {
                    Text(profile.club.isOwner ? "club.ops.owner" : "club.ops.administrator")
                }.questifyCardListRow()
            }
        }
        if target == .create && !value.canCreate {
            Section {
                Text(value.accountRole != "club" ? "club.ops.leaderRequired" : "club.ops.clubLimit")
            }
        } else {
            ClubOperationsProfileForm(draft: $draft, isCreate: target == .create, joinPolicySupported: value.profile?.club.joinPolicySupported == true)
                .disabled(loading || state.locksForm)
            Section {
                Button("club.ops.reviewProfile") {
                    let command: ClubOperationsCommand
                    if let original = value.profile { command = .update(draft, original: original) }
                    else { command = .create(draft) }
                    Task { await prepare(command) }
                }
                .disabled(loading || state.locksForm || (target != .create && !dirty))
                .accessibilityIdentifier("club.ops.reviewProfile")
                Text("club.ops.mediaUnavailable").font(.footnote).foregroundStyle(.secondary)
            }
        }
        if let profile = value.profile, profile.club.isOwner {
            Section("club.ops.openSettings") {
                ForEach(ClubOpenSetting.allCases, id: \.rawValue) { setting in
                    if let enabled = profile.value(setting) {
                        Button {
                            Task { await prepare(.openSetting(setting, enabled: !enabled, previous: enabled)) }
                        } label: {
                            LabeledContent(LocalizedStringKey("club.ops." + setting.rawValue)) { Text(enabled ? "club.ops.enabled" : "club.ops.disabled") }
                        }
                        .disabled(loading || state.locksForm)
                        .accessibilityIdentifier("club.ops.setting." + setting.rawValue)
                    } else { LabeledContent(LocalizedStringKey("club.ops." + setting.rawValue)) { Text("club.ops.unknownValue") } }
                }
                Text("club.ops.settingsHint").font(.footnote).foregroundStyle(.secondary)
            }
            Section("club.ops.memberRoles") {
                if value.members.isEmpty { Text("club.ops.membersUnavailable") }
                ForEach(value.members) { member in
                    if !member.isOwner, member.memberId != identity?.accountID, [0, 1].contains(member.role) {
                        Button {
                            Task { await prepare(.memberRole(memberID: member.id, admin: !member.isAdmin, previousRole: member.role)) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: member.trimmedNickname ?? "#\(member.id)")
                                Text(member.isAdmin ? "club.ops.removeAdmin" : "club.ops.makeAdmin").font(.caption)
                            }
                        }
                        .disabled(loading || state.locksForm)
                        .accessibilityIdentifier("club.ops.member.\(member.id)")
                    } else {
                        LabeledContent { Text(member.isOwner ? "club.ops.owner" : "club.ops.unknownRole") } label: { Text(verbatim: member.trimmedNickname ?? "#\(member.id)") }
                    }
                }
                Text("club.ops.adminHint").font(.footnote).foregroundStyle(.secondary)
            }
        }
        if access.writeAvailability == .unverified { Section { Text("club.ops.writeGated").accessibilityIdentifier("club.ops.writeGated") } }
    }
    @ViewBuilder private var status: some View {
        Section {
            switch state {
            case .preparing, .preflighting, .submitting: ProgressView("club.ops.checking")
            case .notSent: Text("club.ops.notSent").accessibilityIdentifier("club.ops.notSent")
            case .acknowledged(let receipt):
                Text("club.ops.acknowledged").accessibilityIdentifier("club.ops.acknowledged")
                if let message = receipt.message { Text(verbatim: message) }
                if let id = receipt.clubID { LabeledContent("club.ops.clubID") { Text(id, format: .number) } }
            case .rejected(let failure):
                Text("club.ops.rejected")
                if let message = failure.message { Text(verbatim: message) }
            case .outcomeUnknown: Text("club.ops.outcomeUnknown").accessibilityIdentifier("club.ops.outcomeUnknown")
            default: EmptyView()
            }
            if readbackUnavailable { Text("club.ops.readbackUnavailable") }
            if case .outcomeUnknown = state {
                Button("club.ops.readBack") { Task { await readBack() } }
                    .disabled(loading).accessibilityIdentifier("club.ops.readBack")
            }
            if snapshot == nil, identity != nil, access.isConfigured, !loading {
                Button("club.ops.retryRead") { Task { await load() } }.accessibilityIdentifier("club.ops.retryRead")
            }
        }
    }
    @MainActor private func load() async {
        guard let identity, access.isConfigured, !loading else { return }
        generation &+= 1; let run = generation
        loading = true; errorKey = nil; serverMessage = nil
        do {
            let result = try await access.snapshot(target: target)
            guard generation == run, access.identity == identity, !Task.isCancelled else { return }
            guard result.target == target else { throw ClubOperationsBlock.changed }
            snapshot = result; draft = result.profile.map(ClubOperationsDraft.init(profile:)) ?? .init(); baseline = draft
            loading = false; state = coordinator.state(target: target)
        } catch {
            guard generation == run, access.identity == identity, !Task.isCancelled else { return }
            loading = false; show(error)
        }
    }
    @MainActor private func prepare(_ command: ClubOperationsCommand) async {
        guard let identity, !state.locksForm, !loading else { return }
        generation &+= 1; let run = generation
        state = .preparing; errorKey = nil; serverMessage = nil
        do {
            let pending = try await coordinator.prepare(command, target: target, expectedIdentity: identity, ownerID: ownerID)
            guard run == generation, access.identity == identity, !Task.isCancelled else { coordinator.cancel(pending); return }
            review = pending; state = coordinator.state(target: target)
        } catch {
            guard run == generation, access.identity == identity else { return }
            state = coordinator.state(target: target); show(error)
        }
    }
    private func cancelReview() {
        if let review { coordinator.cancel(review) }; review = nil
        state = coordinator.state(target: target)
    }
    @MainActor private func confirm(_ pending: ClubOperationsReview) async {
        generation &+= 1; let run = generation
        snapshot = nil; readbackUnavailable = false
        await coordinator.confirm(pending)
        guard run == generation, access.identity == pending.identity, !Task.isCancelled else { return }
        state = coordinator.state(target: target); acceptReadback()
    }
    @MainActor private func readBack() async {
        guard let identity, !loading else { return }
        generation &+= 1; let run = generation; loading = true
        await coordinator.readBack(target: target, ownerID: ownerID)
        guard run == generation, access.identity == identity, !Task.isCancelled else { return }
        loading = false; acceptReadback(); state = coordinator.state(target: target)
    }
    private func acceptReadback() {
        switch coordinator.readback(target: target) {
        case .received(let value):
            snapshot = value; readbackUnavailable = false
            if case .acknowledged = coordinator.state(target: target) {
                draft = value.profile.map(ClubOperationsDraft.init(profile:)) ?? .init(); baseline = draft
            }
        case .unavailable: readbackUnavailable = true
        default: break
        }
    }
    private func show(_ error: Error) {
        serverMessage = (error as? ClubReadFailure)?.message
        if let block = error as? ClubOperationsBlock { errorKey = "club.ops.error." + String(describing: block) }
        else if (error as? ClubReadFailure)?.isForbidden == true { errorKey = "club.ops.error.forbidden" }
        else { errorKey = "club.ops.readFailed" }
    }
}

private struct ClubOperationsProfileForm: View {
    @Binding var draft: ClubOperationsDraft
    let isCreate: Bool
    let joinPolicySupported: Bool
    var body: some View {
        Section("club.ops.profile") {
            field("name", text: $draft.name)
            field("city", text: $draft.city)
            Picker("club.ops.clubType", selection: $draft.clubType) {
                Text("club.ops.chooseType").tag("")
                ForEach(ClubOperationsCatalog.types, id: \.self) { Text(LocalizedStringKey("club.ops.value." + $0)).tag($0) }
                if !draft.clubType.isEmpty, !ClubOperationsCatalog.types.contains(draft.clubType) { Text(verbatim: draft.clubType).tag(draft.clubType) }
            }.accessibilityIdentifier("club.ops.clubType")
            field("description", text: $draft.description, axis: .vertical)
            field("keywords", text: $draft.keywords)
            field("style", text: $draft.style)
        }
        Section("club.ops.directions") {
            ForEach(ClubOperationsCatalog.directions, id: \.self) { value in
                Toggle(isOn: Binding(get: { draft.activityPrefs.contains(value) }, set: { enabled in
                    if enabled { if draft.activityPrefs.count < 3 { draft.activityPrefs.append(value) } }
                    else { draft.activityPrefs.removeAll { $0 == value } }
                })) { Text(LocalizedStringKey("club.ops.value." + value)) }
                .disabled(!draft.activityPrefs.contains(value) && draft.activityPrefs.count >= 3)
            }
            if draft.activityPrefs.contains(where: { !ClubOperationsCatalog.directions.contains($0) }) {
                Text(verbatim: draft.activityPrefs.filter { !ClubOperationsCatalog.directions.contains($0) }.joined(separator: ", "))
            }
            Text("club.ops.directionsHint").font(.footnote).foregroundStyle(.secondary)
        }
        if !isCreate {
            Section("club.ops.signupSettings") {
                Toggle("club.ops.prioritySignup", isOn: $draft.prioritySignupEnabled).accessibilityIdentifier("club.ops.prioritySignup")
                field("quota", text: $draft.memberReservedQuota).keyboardType(.numberPad)
                if joinPolicySupported {
                    Picker("club.ops.joinPolicy", selection: $draft.joinPolicy) {
                        Text("club.ops.joinDirect").tag(0); Text("club.ops.joinReview").tag(1)
                    }.accessibilityIdentifier("club.ops.joinPolicy")
                } else { Text("club.ops.joinPolicyUnavailable").font(.footnote) }
            }
        }
    }
    private func field(_ key: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        TextField(LocalizedStringKey("club.ops." + key), text: text, axis: axis)
            .accessibilityLabel(Text(LocalizedStringKey("club.ops." + key)))
            .accessibilityIdentifier("club.ops.field." + key)
    }
}
