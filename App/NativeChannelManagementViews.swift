import SwiftUI

private func ncmText(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "NativeChannelManagement") }

/// Optional destinations reuse the host's existing message consumer and original 8's Webhook UI.
/// No conversation is synthesized from a channel id here. The host must provide a real mapping.
@MainActor struct NativeChannelManagementDestinations {
    var conversation: ((NativeChannelManagementChannel) -> AnyView)? = nil
    var contextConversation: ((any NativeChannelManagementIntegrationContextProviding, NativeChannelManagementID, Binding<Bool>) -> AnyView)? = nil
    var notifications: ((any NativeChannelManagementIntegrationContextProviding, NativeChannelManagementID) -> AnyView)? = nil
    var webhook: (@MainActor (NativeWebhookScope) throws -> NativeWebhookCoordinator)? = nil
    var progress: ((NativeChannelManagementID, any NativeChannelManagementIntegrationContextProviding) -> AnyView)? = nil
    var contextProgress: ((NativeChannelManagementID, any NativeChannelManagementIntegrationContextProviding, Binding<Bool>) -> AnyView)? = nil
    var progressPrivacy: ((any NativeChannelManagementIntegrationContextProviding, NativeChannelManagementID) -> AnyView)? = nil
    var audit: ((any NativeChannelManagementIntegrationContextProviding, NativeChannelManagementID) -> AnyView)? = nil
    var lifecycleAudit: ((any NativeChannelManagementIntegrationContextProviding, NativeChannelManagementID) -> AnyView)? = nil
    var personalState: ((any NativeChannelManagementIntegrationContextProviding, NativeChannelManagementID) -> AnyView)? = nil
    var roles: ((any NativeChannelManagementIntegrationContextProviding, NativeChannelManagementID) -> AnyView)? = nil
    var moderation: ((any NativeChannelManagementIntegrationContextProviding, NativeChannelManagementID) -> AnyView)? = nil
    var friendInvites: ((any NativeChannelManagementIntegrationContextProviding, NativeChannelManagementID) -> AnyView)? = nil
    var onboarding: ((NativeChannelManagementCoordinator, Binding<Bool>) -> AnyView)? = nil
    var welcome: ((NativeChannelManagementCoordinator, Binding<Bool>) -> AnyView)? = nil
    var friendMembers: ((any NativeChannelManagementIntegrationContextProviding, NativeChannelManagementID) -> AnyView)? = nil
}

@MainActor struct NativeChannelManagementDirectoryView: View {
    let model: NativeChannelManagementCoordinator
    var destinations = NativeChannelManagementDestinations()
    var parentRouteIsActive: () -> Bool = { false }
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var selection = NativeChannelManagementSelectionState<NativeChannelManagementID>()
    @StateObject private var onboardingRoute = NativeChannelManagementRouteState()
    @StateObject private var welcomeRoute = NativeChannelManagementRouteState()
    @State private var creates = false
    var body: some View {
        let onboardingVisit = childRoute(onboardingRoute)
        let welcomeVisit = childRoute(welcomeRoute)
        Group {
            if model.isCurrent {
                List {
                    if model.busy { Section { ProgressView() } }
                    if let onboarding=destinations.onboarding { NavigationLink(isActive: onboardingVisit) { onboarding(model, onboardingVisit).id(onboardingRoute.visitID) } label: { Label("入群引导（可跳过）",systemImage:"list.bullet.clipboard") } }
                    if let welcome=destinations.welcome { NavigationLink(isActive: welcomeVisit) { welcome(model, welcomeVisit).id(welcomeRoute.visitID) } label: { Label("欢迎屏与路标",systemImage:"signpost.right") } }
                    NativeChannelManagementIssueView(issue: model.issue)
                    NativeChannelManagementRecoveryView(model: model)
                    NativeChannelManagementOutcomeView(outcome: model.outcome)
                    Section {
                        Toggle("显示我隐藏的频道",isOn:Binding(get:{ model.showingOwnHidden },set:{ value in Task { await model.loadDirectory(showOwnHidden:value) } }))
                            .disabled(model.busy)
                        Text("仅包含当前原权限仍可见的本人隐藏项，不读取他人偏好或恢复频道访问权。").font(Theme.Font.label)
                    }
                    if let directory = model.directory {
                        ForEach(directory.groups) { group in
                            Section(group.category.name) { ForEach(group.channels) { row in channelRow(row) } }
                        }
                        Section { ForEach(directory.ungrouped) { row in channelRow(row) } }
                        if directory.channels.isEmpty { NativeChannelFlowNotice(title:ncmText("empty"),symbol:"number.square") }
                    } else if !model.busy {
                        Button { Task { await model.loadDirectory() } } label: { ncmText("refresh") }
                    }
                    if model.managerInventoryConfirmed && model.managementInventory.contains(where: { $0.kind == 0 && $0.status < 2 }) {
                        Section { ForEach(model.managementInventory.filter { $0.kind == 0 && $0.status < 2 }) { row in
                            Button { selection.selected = row.id } label: { Text(row.name).fixedSize(horizontal: false, vertical: true) }
                        } } header: { ncmText("manageCategories") }
                    }
                    if !model.managementInventory.filter({ $0.status == 3 }).isEmpty {
                        Section { ForEach(model.managementInventory.filter { $0.status == 3 }) { row in
                            NavigationLink { NativeChannelManagementEditorView(model: model, channel: row) } label: {
                                VStack(alignment: .leading, spacing: Theme.Space.s2) { Text(row.name).fixedSize(horizontal: false, vertical: true); ncmText("pendingDeletion").font(Theme.Font.label).foregroundStyle(.secondary) }
                            }
                        } } header: { ncmText("recoveryChannels") }
                    }
                }
                .listStyle(.insetGrouped)
                .font(Theme.Font.body)
                .refreshable { await model.loadDirectory() }

                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button { creates = true } label: { Label { ncmText("create") } icon: { Image(systemName: "plus") } }
                        .disabled(!model.canCreate || model.busy).accessibilityIdentifier("ncm.create")
                } }
            } else { NativeChannelManagementUnavailableView() }
        }
        .nativeChannelFlowPage()
        .navigationTitle(ncmTitle("directory"))
        .navigationDestination(item: selection.binding) { id in
            let visit = selection.route(for: id, parentCurrent: parentRouteIsActive)
            let owner = model
            NativeChannelManagementDetailView(model: owner, channelID: id, destinations: destinations,
                parentRouteIsActive: { [weak owner] in visit.wrappedValue && owner?.isCurrent == true })
                .id(selection.visitID)
        }
        .sheet(isPresented: $creates) { NavigationStack { NativeChannelManagementEditorView(model: model, channel: nil) } }
        .task {
            // Receipt recovery does not depend on a successful current directory read.
            model.restoreOriginal()
            await model.loadDirectory()
        }
        .task {
            // Also retires a retained off-screen view after expiry, logout or configuration replacement.
            while !Task.isCancelled && !model.retired {
                model.synchronizeIdentity()
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, value in if value != .active { model.retire() } }
    }
    private func childRoute(_ state: NativeChannelManagementRouteState) -> Binding<Bool> {
        let parent = parentRouteIsActive, owner = model
        return NativeChannelManagementRouteState.child(state.binding, parentCurrent: { [weak owner] in
            parent() && owner?.isCurrent == true
        })
    }
    private func channelRow(_ row: NativeChannelManagementChannel) -> some View {
        Button { selection.selected = row.id } label: {
            HStack {
                Image(systemName: row.kind == 2 ? "megaphone" : "number").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Text(row.name).font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true).foregroundStyle(.primary)
                    if let topic = row.topic, !topic.isEmpty { Text(topic).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer()
                if row.status == 1 { Image(systemName: "archivebox").accessibilityLabel(ncmText("archived")) }
                if row.visibility == 2 { Image(systemName: "lock").accessibilityLabel(ncmText("private")) }
                Image(systemName: "chevron.right").font(Theme.Font.label).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }.accessibilityIdentifier("ncm.channel.\(row.id)")
    }
}

private func ncmTitle(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), table: "NativeChannelManagement")
}

@MainActor struct NativeChannelManagementDetailView: View {
    let model: NativeChannelManagementCoordinator
    let channelID: NativeChannelManagementID
    let destinations: NativeChannelManagementDestinations
    let parentRouteIsActive: () -> Bool
    @StateObject private var messagesRoute = NativeChannelManagementRouteState()
    @StateObject private var webhookRoute = NativeChannelManagementRouteState()
    private var messageRouteBinding: Binding<Bool> {
        NativeChannelManagementRouteState.child(messagesRoute.binding, parentCurrent: parentRouteIsActive)
    }
    private var webhookRouteBinding: Binding<Bool> {
        NativeChannelManagementRouteState.child(webhookRoute.binding, parentCurrent: parentRouteIsActive)
    }
    @StateObject private var progressRoute = NativeChannelManagementRouteState()
    private var progressRouteBinding: Binding<Bool> {
        let owner = model, parent = parentRouteIsActive
        return NativeChannelManagementRouteState.child(progressRoute.binding, parentCurrent: { [weak owner] in
            parent() && owner?.isCurrent == true
        })
    }
    var body: some View {
        let messageVisit = messageRouteBinding
        let webhookVisit = webhookRouteBinding
        let progressVisit = progressRouteBinding
        Group {
            if model.isCurrent {
                Form {
                    if model.busy { Section { ProgressView() } }
                    NativeChannelManagementIssueView(issue: model.issue)
                    NativeChannelManagementRecoveryView(model: model)
                    NativeChannelManagementOutcomeView(outcome: model.outcome)
                    if let row = model.detail, row.id == channelID {
                        Section {
                            Text(row.name).font(Theme.Font.sheetTitle).fixedSize(horizontal: false, vertical: true)
                            if let topic = row.topic, !topic.isEmpty { Text(topic).textSelection(.enabled) }
                            LabeledContent { ncmText(row.status == 1 ? "archived" : "active") } label: { ncmText("status") }
                            LabeledContent { ncmText(row.visibility == 2 ? "private" : "public") } label: { ncmText("visibility") }
                            LabeledContent { Text(row.slowmodeSeconds, format: .number) } label: { ncmText("slowmode") }
                            if let count = row.memberCount {
                                LabeledContent { Text(row.memberCountCapped ? "\(count)+" : "\(count)") } label: { ncmText("members") }
                            }
                        }
                        if row.kind != 0, let conversation = destinations.contextConversation {
                            Section { NavigationLink(isActive: messageVisit) { conversation(model.service, row.id, messageVisit).id(messagesRoute.visitID) } label: { ncmText("messages") } }
                        } else if let conversation = destinations.conversation, row.kind != 0 {
                            Section { NavigationLink { conversation(row) } label: { ncmText("messages") } }
                        }
                        if let notifications = destinations.notifications {
                            Section {
                                NavigationLink { notifications(model.service, row.id) } label: {
                                    Label { Text("notification.channel.title", tableName: "NativeChannelNotification") } icon: { Image(systemName: "bell.badge") }
                                }.accessibilityIdentifier("notification.channel.entry")
                            }
                        }
                        if row.kind != 0, row.scope.guildKind == 1, (destinations.contextProgress != nil || destinations.progress != nil) {
                            Section { Button { progressVisit.wrappedValue = true } label: { Text("title", tableName: "NativeChannelProgress") } }
                                .accessibilityIdentifier("ncm.progressEntry")
                        }
                        if row.kind != 0, row.status == 0, row.scope.guildKind == 1,
                           row.permissionNames.isSuperset(of: ["VIEW_CHANNEL", "MANAGE_PROGRESS"]), let privacy = destinations.progressPrivacy {
                            Section { NavigationLink("频道总览隐私") { privacy(model.service, row.id) } }
                                .accessibilityIdentifier("ncm.aggregatePrivacyEntry")
                        }
                        if row.scope.guildKind == 1, row.permissionNames.contains("VIEW_AUDIT"), let lifecycle = destinations.lifecycleAudit {
                            Section { NavigationLink("频道管理变更记录") { lifecycle(model.service, row.id) } }
                        }
                        if row.scope.guildKind == 1, row.permissionNames.contains("VIEW_AUDIT"), let audit = destinations.audit {
                            Section { NavigationLink("原频道审计记录") { audit(model.service, row.id) } }
                                .accessibilityIdentifier("ncm.originalAuditEntry")
                        }
                        if row.scope.guildKind == 1, !row.permissionNames.isDisjoint(with: ["VIEW_AUDIT", "TIMEOUT_MEMBER", "KICK_MEMBER", "BAN_MEMBER"]),
                           let moderation = destinations.moderation {
                            Section { NavigationLink("原频道处置管理") { moderation(model.service, row.id) } }
                                .accessibilityIdentifier("ncm.originalModerationEntry")
                        }
                        if row.scope.guildKind == 1, row.permissionNames.contains("MANAGE_ROLE"), let roles = destinations.roles {
                            Section { NavigationLink("原频道角色管理") { roles(model.service, row.id) } }
                                .accessibilityIdentifier("ncm.originalRoleEntry")
                        }
                        if row.kind != 0, row.status == 0, [1, 3].contains(row.scope.guildKind),
                           row.permissionNames.isSuperset(of: ["VIEW_CHANNEL", "MANAGE_CHANNEL"]), let invites = destinations.friendInvites {
                            Section { NavigationLink("邀请原好友") { invites(model.service, row.id) } }
                        }
                        if row.kind != 0, row.status == 0, row.permissionNames.contains("VIEW_CHANNEL"), let friends = destinations.friendMembers {
                            Section { NavigationLink("频道成员与好友申请") { friends(model.service, row.id) } }
                        }
                        if let personalState = destinations.personalState {
                            Section { NavigationLink("本人目录与静音") { personalState(model.service,row.id) } }
                        }
                        if row.canManage || row.canManagePermissions {
                            Section {
                                if row.canManage {
                                    NavigationLink { NativeChannelManagementEditorView(model: model, channel: row) } label: { ncmText("settings") }
                                }
                                if row.canManagePermissions {
                                    NavigationLink { NativeChannelManagementPermissionsView(model: model, channelID: row.id) } label: { ncmText("permissions") }
                                }
                            }
                        }
                        if row.scope.guildKind == 1, row.permissionNames.isSuperset(of: ["VIEW_CHANNEL", "READ_HISTORY", "MANAGE_WEBHOOKS"]),
                           destinations.webhook != nil {
                            Section {
                                Button { webhookVisit.wrappedValue = true } label: { Label("Webhook", systemImage: "point.3.connected.trianglepath.dotted") }
                                .accessibilityIdentifier("ncm.webhookEntry")
                            }
                        }
                    } else {
                        Button { Task { await model.loadDetail(channelID) } } label: { ncmText("refresh") }
                    }
                }
                .formStyle(.grouped)
                .font(Theme.Font.body)

            } else { NativeChannelManagementUnavailableView() }
        }
        .nativeChannelFlowPage()
        .navigationTitle(ncmTitle("detail"))
        .task(id: channelID) { await model.loadDetail(channelID) }
        .sheet(isPresented: progressVisit) {
            if let progress = destinations.contextProgress {
                progress(channelID, model.service, progressVisit).id(progressRoute.visitID)
            } else if let progress = destinations.progress { progress(channelID, model.service) }
        }
        .sheet(isPresented: webhookVisit) {
            NativeChannelManagementWebhookEntry(channels: model.service, channelID: channelID, makeCoordinator: destinations.webhook,
                parentRouteIsActive: { webhookVisit.wrappedValue })
                .id(webhookRoute.visitID)
        }
    }
}

@MainActor struct NativeChannelManagementEditorView: View {
    let model: NativeChannelManagementCoordinator
    let channel: NativeChannelManagementChannel?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NativeChannelManagementDraft
    @State private var reason = ""
    @State private var localIssue: NativeChannelManagementError?
    @State private var reviews = false
    init(model: NativeChannelManagementCoordinator, channel: NativeChannelManagementChannel?) {
        self.model = model; self.channel = channel
        _draft = State(initialValue: channel.map(NativeChannelManagementDraft.init(channel:)) ?? .init())
    }
    var body: some View {
        Group {
            if model.isCurrent {
                Form {
                    if model.busy { Section { ProgressView() } }
                    NativeChannelManagementIssueView(issue: localIssue ?? model.issue)
                    Section {
                        TextField(ncmTitle("name"), text: $draft.name)
                        TextField(ncmTitle("topic"), text: $draft.topic, axis: .vertical).lineLimit(3...6)
                        LabeledContent {
                            TextField("0", value: $draft.slowmodeSeconds, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        } label: { ncmText("slowmode") }
                        Picker(selection: $draft.visibility) { ncmText("public").tag(1); ncmText("private").tag(2) } label: { ncmText("visibility") }
                        if channel == nil {
                            Picker(selection: $draft.kind) { ncmText("textChannel").tag(1); ncmText("announcement").tag(2); ncmText("category").tag(0) } label: { ncmText("kind") }
                            Picker(selection: $draft.parentID) {
                                ncmText("ungrouped").tag("0")
                                ForEach(model.managementInventory.filter { $0.kind == 0 && $0.status == 0 }) { Text($0.name).tag($0.id.rawValue) }
                            } label: { ncmText("category") }
                            .disabled(draft.kind == 0)
                        }
                    }.disabled(channel.map({ $0.status != 0 }) ?? false)
                    Section { TextField(ncmTitle("reason"), text: $reason, axis: .vertical).lineLimit(2...4) }
                    Section {
                        if channel == nil || channel?.status == 0 {
                            Button { prepareEdit() } label: { ncmText("review") }
                                .disabled(model.busy || model.pending != nil).accessibilityIdentifier("ncm.reviewEdit")
                        }
                        if let channel {
                            if channel.status == 0 { action("archive", operation: .archive, channel: channel) }
                            if channel.status == 1 && channel.archiveReason == "manual" { action("unarchive", operation: .unarchive, channel: channel) }
                            if channel.canDelete { action("delete", operation: .delete, channel: channel, destructive: true) }
                            if channel.status == 3 && channel.recoverable { action("restore", operation: .restore, channel: channel) }
                            if let purge = channel.purgeAt { LabeledContent { Text(purge) } label: { ncmText("purgeAt") } }
                        }
                    }
                }
                .formStyle(.grouped)
                .font(Theme.Font.body)
                .disabled(model.busy)
            } else { NativeChannelManagementUnavailableView() }
        }
        .nativeChannelFlowPage()
        .navigationTitle(ncmTitle(channel == nil ? "create" : "settings"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { ncmText("close") } } }
        .sheet(isPresented: $reviews) { NavigationStack { NativeChannelManagementReviewView(model: model) } }
        .onChange(of: draft.kind) { _, kind in if kind == 0 { draft.parentID = "0" } }
    }
    private func prepareEdit() {
        do {
            let intent: NativeChannelManagementIntent
            if let channel { intent = try .edit(channel: channel, draft: draft, reason: reason) }
            else { intent = try .create(scope: model.scope, draft: draft, reason: reason) }
            try model.prepare(intent); localIssue = nil; reviews = true
        } catch { localIssue = (error as? NativeChannelManagementError) ?? .invalidDraft }
    }
    private func action(_ key: String, operation: NativeChannelManagementIntent.Operation,
                        channel: NativeChannelManagementChannel, destructive: Bool = false) -> some View {
        Button(role: destructive ? .destructive : nil) {
            do {
                let intent: NativeChannelManagementIntent
                if operation == .restore {
                    guard let inventory = model.managementInventoryEvidence else { throw NativeChannelManagementError.forbidden }
                    let current = try inventory.restorableChannel(channel.id)
                    guard current.scope == channel.scope, current.version == channel.version else { throw NativeChannelManagementError.versionConflict }
                    intent = try .restore(channelID: channel.id, inventory: inventory, reason: reason)
                } else { intent = try .lifecycle(operation, channel: channel, reason: reason) }
                try model.prepare(intent); localIssue = nil; reviews = true
            }
            catch { localIssue = (error as? NativeChannelManagementError) ?? .invalidDraft }
        } label: { ncmText(key) }.disabled(model.busy || model.pending != nil)
    }
}

@MainActor struct NativeChannelManagementReviewView: View {
    let model: NativeChannelManagementCoordinator
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            NativeChannelManagementIssueView(issue: model.issue)
            if model.isCurrent, let intent = model.prepared {
                Section {
                    ncmText("operation.\(intent.operation.rawValue)").font(Theme.Font.sectionTitle)
                    if let id = intent.channelID { NativeChannelFlowFact(label:ncmText("channelID"),value:id.rawValue) }
                    NativeChannelFlowReference(label:ncmText("requestID"),value:intent.requestID)
                    if let version = intent.expectedVersion { LabeledContent(ncmTitle("version"), value: String(version.value)) }
                    if let permission = intent.permissionVersion { LabeledContent(ncmTitle("permissionVersion"), value: String(permission.value)) }
                    if let type = intent.targetType, let target = intent.targetID {
                        NativeChannelFlowFact(label:ncmText("permissionTarget"),value:type == 1 ? ncmTitle("everyone") : target)
                    }
                    Text(intent.reason).fixedSize(horizontal: false, vertical: true)
                    ForEach(intent.fields.keys.sorted(), id: \.self) { key in
                        NativeChannelFlowFact(label:ncmText("field.\(key)"),value:display(intent.fields[key], key: key))
                    }
                }
                if intent.isPermissionChange && !model.permissionWritesAvailable { ncmText("permissionSubmissionUnavailable").foregroundStyle(.secondary) }
                Section {
                    Button(role: intent.operation == .delete ? .destructive : nil) {
                        Task { await model.submitPrepared(); if model.prepared == nil { dismiss() } }
                    } label: { ncmText("confirm") }
                    .nativeChannelFlowAction()
                    .disabled(!model.canSubmitPrepared).accessibilityIdentifier("ncm.confirmOriginal")
                }
            } else { ncmText("refreshRequired") }
        }
        .formStyle(.grouped)
        .font(Theme.Font.body)
        .nativeChannelFlowPage()
        .navigationTitle(ncmTitle("review"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button { model.cancelPreparation(); dismiss() } label: { ncmText("cancel") } } }
        .interactiveDismissDisabled(model.busy)
        .onDisappear { if !model.busy { model.cancelPreparation() } }
    }
    private func display(_ value: NativeChannelManagementJSON?, key: String) -> String {
        if case .some(.integer(let number)) = value {
            if key == "visibility" { return ncmTitle(number == 2 ? "private" : "public") }
            if key == "kind" { return ncmTitle(number == 0 ? "category" : (number == 2 ? "announcement" : "textChannel")) }
            if key == "archived" { return ncmTitle(number == 1 ? "archive" : "unarchive") }
        }
        if case .some(.string(let text)) = value {
            if key == "parent_id" { return text == "0" ? ncmTitle("ungrouped") : (model.managementInventory.first { $0.id.rawValue == text }?.name ?? text) }
            if (key == "allow_bits" || key == "deny_bits"), let bits = UInt64(text.dropFirst(2), radix: 16) {
                let names = NativeChannelManagementCapability.allCases.filter { bits & $0.bit != 0 }.map { ncmTitle("capability.\($0.rawValue)") }
                return names.isEmpty ? ncmTitle("none") : names.joined(separator: ", ")
            }
        }
        switch value { case .some(.string(let text)): return text; case .some(.integer(let n)): return String(n); case .some(.null): return ncmTitle("clearValue"); case nil: return "" }
    }
}

@MainActor struct NativeChannelManagementRecoveryView: View {
    let model: NativeChannelManagementCoordinator
    var body: some View {
        if model.isCurrent, let pending = model.pending {
            Section {
                NativeChannelFlowNotice(title:ncmText("originalPending"),symbol:"clock.arrow.circlepath")
                NativeChannelFlowReference(label:ncmText("requestID"),value:pending.requestID)
                Button { Task { await model.recoverOriginal() } } label: { ncmText("queryOriginal") }.disabled(model.busy)
                if model.canResendOriginal {
                    ncmText("notFoundUnknown").font(Theme.Font.label).foregroundStyle(.secondary)
                    Button { Task { await model.resendOriginal() } } label: { ncmText("retryOriginal") }.disabled(model.busy)
                }
            }
            .font(Theme.Font.body)
        }
    }
}

@MainActor struct NativeChannelManagementOutcomeView: View {
    let outcome: NativeChannelManagementOriginalOutcome?
    var body: some View {
        if let outcome {
            Section {
                switch outcome {
                case .applied(let result):
                    NativeChannelFlowNotice(title:ncmText("applied"),symbol:"checkmark.circle")
                    if let name = result.name { Text(name).font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true) }
                    NativeChannelFlowReference(label:ncmText("requestID"),value:result.requestID)
                case .appliedRedacted: ncmText("appliedRedacted")
                case .pending: ncmText("originalPending")
                case .notFound: ncmText("notFoundUnknown")
                }
            }
            .font(Theme.Font.body)
        }
    }
}

@MainActor struct NativeChannelManagementUnavailableView: View {
    var body: some View { ContentUnavailableView { Label { ncmText("unavailable") } icon: { Image(systemName: "lock.shield") } } description: { ncmText("entryUnavailable") } }
}

@MainActor struct NativeChannelManagementIssueView: View {
    let issue: NativeChannelManagementError?
    var body: some View {
        if let issue { NativeChannelFlowNotice(title:ncmText(key(issue)),symbol:"exclamationmark.circle").accessibilityIdentifier("ncm.issue") }
    }
    private func key(_ issue: NativeChannelManagementError) -> String {
        switch issue {
        case .unavailable, .forbidden: return "unavailable"
        case .changedIdentity: return "refreshRequired"
        case .invalidDraft: return "invalidDraft"
        case .versionConflict: return "versionConflict"
        case .pendingOriginal: return "originalPending"
        case .storageUnavailable: return "storageUnavailable"
        case .permissionCASUnavailable: return "permissionSubmissionUnavailable"
        case .invalidSource, .outcomeUnknown: return "outcomeUnknown"
        case .rejected(let code):
            switch code {
            case "CHANNEL_NAME_DUPLICATE", "CHANNEL_NAME_TAKEN_BY_RESTORE": return "duplicateName"
            case "CHANNEL_VERSION_CONFLICT": return "versionConflict"
            case "CHANNEL_UNDELETABLE", "CHANNEL_ARCHIVE_IMMUTABLE": return "protectedChannel"
            case "PERMISSION_DENIED", "CHANNEL_NOT_VISIBLE", "CHANNEL_ACCESS_DENIED", "GUILD_MEMBER_REQUIRED": return "unavailable"
            default: return "rejected"
            }
        }
    }
}
