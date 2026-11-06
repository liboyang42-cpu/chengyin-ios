import SwiftUI

@MainActor struct NativeChannelRoleEntry: View {
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeChannelRoleFlow?
    @State private var flow: NativeChannelRoleFlow?
    @State private var generation = 0
    @State private var operation: NativeChannelRoleFlow.Operation = .edit
    @State private var selected = ""
    @State private var member = ""
    @State private var name = ""
    @State private var permissions = ""
    @State private var completeIDs = ""
    @State private var reason = ""
    @State private var filterRole = ""
    @State private var options = NativeChannelRoleFlow.Options()
    @State private var color = ""
    @State private var position = ""
    @State private var displayLevel = ""
    @State private var timed = false
    @State private var expiry = Date().addingTimeInterval(86400)
    @State private var localIssue = false
    @State private var retryConfirmation = false
    @Environment(\.scenePhase) private var scenePhase
    private var target: String { operation == .create ? "" : operation == .memberRoles ? member : selected }
    var body: some View {
        Group {
            if let flow,flow.isCurrent {
                Form {
                    if flow.hasPending || flow.state == .unknown || flow.state == .unavailable || flow.state == .loading || flow.state == .submitting || !flow.result.isEmpty {
                        Section {
                            if flow.hasPending {
                                NativeChannelFlowNotice(title:Text("d7.channelRoles.pending"),symbol:"clock.arrow.circlepath")
                                Button("d7.channelRoles.checkStatus") { Task { await flow.refresh() } }.disabled(!flow.canRecover)
                                if flow.canRetry { Button("d7.channelRoles.retry") { retryConfirmation=true } }
                            } else if flow.state == .unknown {
                                NativeChannelFlowNotice(title:Text("d7.channelRoles.unknown"),symbol:"clock.arrow.circlepath")
                            }
                            if flow.state == .unavailable { NativeChannelFlowNotice(title:Text("d7.channelRoles.unavailable"),symbol:"lock.shield") }
                            if flow.state == .loading || flow.state == .submitting { ProgressView().frame(maxWidth:.infinity) }
                            if !flow.result.isEmpty { Text(flow.result).fixedSize(horizontal:false,vertical:true) }
                        }
                    }
                    if !flow.roles.isEmpty {
                        Section("d7.channelRoles.roles") {
                            ForEach(flow.roles) { row in
                                LabeledContent {
                                    if row.status != 1 { Text("d7.channelRoles.disabledRole") }
                                    else if row.system || row.everyone { Text("d7.channelRoles.systemRole") }
                                } label: { Text(verbatim:row.name).fixedSize(horizontal:false,vertical:true) }
                            }
                        }
                    }
                    Section("d7.channelRoles.members") {
                        Picker("d7.channelRoles.filter",selection:$filterRole) {
                            Text("d7.channelRoles.allMembers").tag("")
                            ForEach(flow.roles) { row in Text(verbatim:row.name).tag(row.id) }
                        }
                        if flow.canReadMembers {
                            Button("d7.channelRoles.loadMembers") { Task { await flow.readMembers(roleID:filterRole.isEmpty ? nil : filterRole) } }
                        }
                        if flow.memberReadUnavailable { Text("d7.channelRoles.membersUnavailable").foregroundStyle(.secondary) }
                        ForEach(flow.members) { row in
                            VStack(alignment:.leading,spacing:Theme.Space.s1) {
                                Text(verbatim:row.nickname).font(Theme.Font.sectionTitle).fixedSize(horizontal:false,vertical:true)
                                Text(verbatim:roleNames(row.roleIDs,in:flow)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                                if let joined=row.joinTime { Text(verbatim:joined).font(.footnote).foregroundStyle(.secondary) }
                            }
                            .swipeActions(edge:.trailing) {
                                if !flow.hasPending {
                                    Button("d7.channelRoles.editMemberRoles") { member=row.id;operation = .memberRoles;flow.cancelReview() }.tint(.accentColor)
                                    if operation == .roleMembers {
                                        Button("d7.channelRoles.addToList") {
                                            var ids=completeIDs.split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
                                            if !ids.contains(row.id) { ids.append(row.id) };completeIDs=ids.joined(separator:", ");flow.cancelReview()
                                        }
                                    }
                                }
                            }
                        }
                        if flow.canReadMoreMembers { Button("d7.channelRoles.loadMore") { Task { await flow.readMembers(roleID:filterRole.isEmpty ? nil : filterRole,more:true) } } }
                    }
                    if !flow.hasPending {
                        Section("d7.channelRoles.change") {
                            Picker("d7.channelRoles.action",selection:$operation) {
                                Text("d7.channelRoles.op.edit").tag(NativeChannelRoleFlow.Operation.edit)
                                Text("d7.channelRoles.op.delete").tag(NativeChannelRoleFlow.Operation.delete)
                                Text("d7.channelRoles.op.create").tag(NativeChannelRoleFlow.Operation.create)
                                Text("d7.channelRoles.op.memberRoles").tag(NativeChannelRoleFlow.Operation.memberRoles)
                                Text("d7.channelRoles.op.roleMembers").tag(NativeChannelRoleFlow.Operation.roleMembers)
                            }
                            if operation != .create && operation != .memberRoles {
                                Picker("d7.channelRoles.role",selection:$selected) {
                                    Text("d7.channelRoles.chooseRole").tag("")
                                    ForEach(flow.roles) { row in Text(verbatim:row.name).tag(row.id) }
                                }
                            }
                            if operation == .create || operation == .edit {
                                TextField("d7.channelRoles.name",text:$name)
                                if operation == .create || flow.roles.first(where:{$0.id == selected})?.everyone == false {
                                    LabeledContent("d7.channelRoles.color") {
                                        TextField(text:$color,prompt:Text(verbatim:"FFAA00")) { Text("d7.channelRoles.color") }
                                            .multilineTextAlignment(.trailing).font(.callout.monospaced())
                                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                                    }
                                    Toggle("d7.channelRoles.hoist",isOn:$options.hoist)
                                    Toggle("d7.channelRoles.mentionable",isOn:$options.mentionable)
                                    if operation == .edit {
                                        LabeledContent("d7.channelRoles.position") {
                                            TextField(text:$position,prompt:Text(verbatim:"0")) { Text("d7.channelRoles.position") }
                                                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                        }
                                        Toggle("d7.channelRoles.enabled",isOn:$options.enabled)
                                    } else {
                                        TextField("d7.channelRoles.displayLevel",text:$displayLevel)
                                    }
                                }
                            }
                            if operation == .memberRoles {
                                LabeledContent("d7.channelRoles.memberNumber") {
                                    TextField(text:$member,prompt:Text(verbatim:"0")) { Text("d7.channelRoles.memberNumber") }
                                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                }
                            }
                        }
                        if operation == .create || operation == .edit {
                            Section("d7.channelRoles.permissions") {
                                ForEach(NativeChannelManagementCapability.allCases.filter(\.available)) { capability in
                                    Toggle(isOn:permissionBit(capability)) {
                                        Text(LocalizedStringKey("capability."+capability.rawValue),tableName:"NativeChannelManagement")
                                    }
                                }
                            }
                        }
                        if operation == .memberRoles {
                            Section("d7.channelRoles.memberRolesList") {
                                ForEach(flow.roles.filter { !$0.system && !$0.managed && !$0.everyone }) { row in
                                    Toggle(isOn:listed(row.id)) { Text(verbatim:row.name) }
                                }
                            }
                        }
                        if operation == .roleMembers {
                            Section("d7.channelRoles.roleMembersList") {
                                TextField("d7.channelRoles.memberNumbers",text:$completeIDs,axis:.vertical)
                                    .lineLimit(3...8).font(.callout.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .keyboardType(.numbersAndPunctuation)
                            }
                        }
                        if operation == .memberRoles || operation == .roleMembers {
                            Section {
                                Toggle("d7.channelRoles.wholeSpace",isOn:$options.guildScope)
                                Toggle("d7.channelRoles.setExpiry",isOn:$timed)
                                if timed { DatePicker("d7.channelRoles.expires",selection:$expiry,in:Date()...,displayedComponents:[.date,.hourAndMinute]) }
                                Text("d7.channelRoles.replaceWarning").foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)
                            }
                        }
                        Section {
                            TextField("d7.channelRoles.reason",text:$reason,axis:.vertical).lineLimit(2...6)
                            if localIssue { Text("d7.channelRoles.invalid").foregroundStyle(.red).fixedSize(horizontal:false,vertical:true) }
                        }
                        Section {
                            Button("d7.channelRoles.review") {
                                let ids=completeIDs.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? [] : completeIDs.split(separator:",",omittingEmptySubsequences:false).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
                                let rawColor=color.trimmingCharacters(in:.whitespacesAndNewlines)
                                if !rawColor.isEmpty && Int(rawColor,radix:16) == nil { localIssue=true;return }
                                options.color=rawColor.isEmpty ? nil : Int(rawColor,radix:16)
                                options.position=Int(position);options.displayLevel=displayLevel.isEmpty ? nil : displayLevel
                                options.expiresAt=timed ? expiry : nil
                                localIssue = !flow.prepare(operation,target:target,name:name,permissions:permissions,ids:ids,reason:reason,options:options)
                            }.nativeChannelFlowAction().disabled(!flow.canPrepare(operation,target:target))
                        }
                    }
                    if flow.state == .reviewing {
                        Section("d7.channelRoles.confirmTitle") {
                            Text(flow.reviewedSummary).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                            Button("d7.channelRoles.confirm",role:.destructive) { Task { await flow.confirm() } }.nativeChannelFlowAction()
                        }
                        Section { Button("d7.channelRoles.cancel") { flow.cancelReview() } }
                    }
                }
                .refreshable { await flow.refresh() }
                .confirmationDialog("d7.channelRoles.retryTitle",isPresented:$retryConfirmation,titleVisibility:.visible) {
                    Button("d7.channelRoles.retry",role:.destructive) { Task { await flow.retryOriginal() } }
                    Button("d7.channelRoles.cancel",role:.cancel) {}
                }
            } else {
                ContentUnavailableView {
                    Label("d7.channelRoles.loadFailed",systemImage:"person.badge.key")
                } actions: {
                    Button("d7.channelRoles.tryAgain") { Task { await open() } }
                }
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle("d7.channelRoles.title")
        .task { await open() }
        .task { while !Task.isCancelled { if let flow,!flow.isCurrent { close() };do { try await Task.sleep(nanoseconds:500_000_000) } catch { return } } }
        .onChange(of:selected) { _,value in
            guard let role=flow?.roles.first(where:{$0.id == value}) else { name="";permissions="";return }
            name=role.name;permissions=role.permissions;position=String(role.position)
            color=role.color.map { String($0,radix:16) } ?? "";displayLevel=role.displayLevel ?? ""
            options.hoist=role.hoist;options.mentionable=role.mentionable;options.enabled=role.status == 1
        }
        .onChange(of:filterRole) { _,_ in flow?.clearMemberSelectionSource() }
        .onChange(of:operation) { _,_ in flow?.cancelReview();localIssue=false }
        .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await open() } } else { close() } }
        .onDisappear { close() }.privacySensitive()
    }
    /// Role names for a member row; numbers the role list doesn't know show "—".
    private func roleNames(_ ids: [String], in flow: NativeChannelRoleFlow) -> String {
        let names = ids.map { id in flow.roles.first(where:{ $0.id == id })?.name ?? "—" }
        return names.isEmpty ? "—" : names.joined(separator:", ")
    }
    /// Toggle view of one bit inside the role's hex permission string; other bits are left untouched.
    private func permissionBit(_ capability: NativeChannelManagementCapability) -> Binding<Bool> {
        Binding(get: {
            guard permissions.hasPrefix("0x"), let bits = UInt64(permissions.dropFirst(2), radix: 16) else { return false }
            return bits & capability.bit != 0
        }, set: { on in
            var bits: UInt64 = 0
            if permissions.hasPrefix("0x"), let current = UInt64(permissions.dropFirst(2), radix: 16) { bits = current }
            if on { bits |= capability.bit } else { bits &= ~capability.bit }
            permissions = "0x" + String(bits, radix: 16)
        })
    }
    /// Toggle view of one id inside the complete comma-separated replacement list.
    private func listed(_ id: String) -> Binding<Bool> {
        Binding(get: {
            completeIDs.split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.contains(id)
        }, set: { on in
            var ids = completeIDs.split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if on { if !ids.contains(id) { ids.append(id) } } else { ids.removeAll { $0 == id } }
            completeIDs = ids.joined(separator:", ")
        })
    }
    private func close() { generation += 1;flow?.deactivate();flow=nil;selected="";member="";name="";permissions="";completeIDs="";reason="";retryConfirmation=false;filterRole="";options = .init();color="";position="";displayLevel="";timed=false }
    private func open() async {
        close();let run=generation
        do {
            let captured=try await channels.currentChannelContext(channelID:channelID)
            guard run == generation,scenePhase == .active,!Task.isCancelled,channels.contextIsCurrent(captured),let owner=makeFlow(captured) else { return }
            await owner.activate()
            guard run == generation,scenePhase == .active,!Task.isCancelled else { owner.deactivate();return };flow=owner
        } catch { }
    }
}
