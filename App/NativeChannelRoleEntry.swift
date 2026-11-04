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
                    Section("角色与处理进度") {
                        Text("系统角色由原成员业务派生，不可在此改造。只有当前 MANAGE_ROLE 及独立请求授权才可提交；自定义创建仍需服务端平台开关。")
                        Button("刷新原角色与回执") { Task { await flow.refresh() } }
                        if let id=flow.originalRequestID { NativeChannelFlowReference(label:Text("请求编号"),value:id) }
                        if flow.hasPending {
                            Text("保留原请求，不会自动发送。重新进入只回读同一回执。")
                            Button("回读原请求") { Task { await flow.refresh() } }.disabled(!flow.canRecover)
                            Button("核对后重试同一原请求") { retryConfirmation=true }.disabled(!flow.canRetry)
                        }
                        if flow.state == .unknown { NativeChannelFlowNotice(title:Text("结果未知，不将错误或权限消失当成未执行。"),symbol:"clock.arrow.circlepath") }
                        if flow.state == .unavailable { NativeChannelFlowNotice(title:Text("原来源或当前权限不可用。"),symbol:"lock.shield") }
                        if flow.state == .loading || flow.state == .submitting { ProgressView() }
                        if !flow.result.isEmpty { Text(flow.result) }
                    }
                    Section("成员列表") {
                        Picker("按原角色筛选",selection:$filterRole) {
                            Text("当前可见成员").tag("")
                            ForEach(flow.roles) { row in Text(row.name).tag(row.id) }
                        }
                        Button("读取当前原名单") { Task { await flow.readMembers(roleID:filterRole.isEmpty ? nil : filterRole) } }.disabled(!flow.canReadMembers)
                        Text("列表仅当前频道可见成员，受原 MEMBER_LIST_READ 限制。角色编号包含系统派生项，不会自动填为增量替换集合；分页或筛选结果也不会自动当成全部组织成员。")
                        if flow.memberReadUnavailable { Text("原名单不可用，未使用其他权限或缓存名单代替。") }
                        ForEach(flow.members) { row in
                            VStack(alignment:.leading,spacing:Theme.Space.s2) {
                                Text(verbatim:row.nickname).font(Theme.Font.sectionTitle)
                                NativeChannelFlowReference(label:Text("成员编号"),value:row.id)
                                Text("原有效角色：\(row.roleIDs.joined(separator:", "))").font(.caption)
                                if let joined=row.joinTime { Text("原加入时间：\(joined)").font(.caption) }
                                if !flow.hasPending {
                                    Button("选为成员角色请求的目标") { member=row.id;operation = .memberRoles;flow.cancelReview() }
                                    if operation == .roleMembers {
                                        Button("仅将此成员加入待确认的完整集合") {
                                            var ids=completeIDs.split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
                                            if !ids.contains(row.id) { ids.append(row.id) };completeIDs=ids.joined(separator:", ");flow.cancelReview()
                                        }
                                    }
                                }
                            }
                        }
                        if flow.canReadMoreMembers { Button("读取下一页原游标") { Task { await flow.readMembers(roleID:filterRole.isEmpty ? nil : filterRole,more:true) } } }
                    }
                    if !flow.hasPending {
                        Section("角色操作") {
                            Picker("操作",selection:$operation) {
                                Text("编辑角色名称与权限").tag(NativeChannelRoleFlow.Operation.edit)
                                Text("删除自定义角色").tag(NativeChannelRoleFlow.Operation.delete)
                                Text("创建自定义角色（需平台开关）").tag(NativeChannelRoleFlow.Operation.create)
                                Text("替换成员在本频道的增量角色").tag(NativeChannelRoleFlow.Operation.memberRoles)
                                Text("替换本频道指定角色的成员").tag(NativeChannelRoleFlow.Operation.roleMembers)
                            }
                            if operation != .create && operation != .memberRoles {
                                Picker("原角色",selection:$selected) {
                                    Text("请选择原角色").tag("")
                                    ForEach(flow.roles) { row in Text("\(row.name) · \(row.id) · 层级 \(row.position)\(row.system ? " · 系统" : "")").tag(row.id) }
                                }
                            }
                            if operation == .create || operation == .edit {
                                TextField("名称（系统 EVERYONE 不提交名称）",text:$name)
                                TextField("原权限位十六进制，例如原列表中的 0x…",text:$permissions)
                                    .font(.callout.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                                Text("不预填权限、不自动扩大权限；原服务核对权限子集与层级。")
                                if operation == .create || flow.roles.first(where:{$0.id == selected})?.everyone == false {
                                    TextField("颜色十六进制（空为无颜色）",text:$color).textInputAutocapitalization(.never)
                                    Toggle("独立展示角色",isOn:$options.hoist)
                                    Toggle("允许提及此角色",isOn:$options.mentionable)
                                    if operation == .edit {
                                        TextField("角色层级（必须低于本人原最高层级）",text:$position).keyboardType(.numberPad)
                                        Toggle("角色启用",isOn:$options.enabled)
                                    } else { TextField("创建时展示等级（可选，最多8字符）",text:$displayLevel) }
                                }
                            }
                            if operation == .memberRoles { TextField("原成员编号",text:$member).keyboardType(.numberPad) }
                            if operation == .memberRoles || operation == .roleMembers {
                                TextField("完整替换编号列表，逗号分隔；空表示清空",text:$completeIDs,axis:.vertical)
                                    .lineLimit(3...8).font(.callout.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                                Toggle("改为整个原组织范围（不是仅当前频道）",isOn:$options.guildScope)
                                Toggle("设置这些增量角色的到期时间",isOn:$timed)
                                if timed { DatePicker("到期时间",selection:$expiry,in:Date()...,displayedComponents:[.date,.hourAndMinute]) }
                                Text("这是完整替换，不是追加。未列出的所选范围增量将撤销；空集合清空对应增量。整组织与当前频道不能互换。未设置到期即无到期；系统派生角色不在替换集合中。")
                                    .foregroundStyle(.red)
                            }
                            TextField("理由（必填）",text:$reason,axis:.vertical).lineLimit(2...6)
                            Button("生成提交前确认") {
                                let ids=completeIDs.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? [] : completeIDs.split(separator:",",omittingEmptySubsequences:false).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
                                let rawColor=color.trimmingCharacters(in:.whitespacesAndNewlines)
                                if !rawColor.isEmpty && Int(rawColor,radix:16) == nil { localIssue=true;return }
                                options.color=rawColor.isEmpty ? nil : Int(rawColor,radix:16)
                                options.position=Int(position);options.displayLevel=displayLevel.isEmpty ? nil : displayLevel
                                options.expiresAt=timed ? expiry : nil
                                localIssue = !flow.prepare(operation,target:target,name:name,permissions:permissions,ids:ids,reason:reason,options:options)
                            }.nativeChannelFlowAction().disabled(!flow.canPrepare(operation,target:target))
                            if localIssue { NativeChannelFlowNotice(title:Text("请核对原角色、目标编号、权限位与理由；未生成或发送请求。"),symbol:"exclamationmark.circle") }
                        }
                    }
                    if flow.state == .reviewing {
                        Section("明确确认") {
                            Text(flow.reviewedSummary).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                            Text("提交的是上面已冻结的原请求，而不是之后编辑的输入。")
                            Button("确认提交此角色变更",role:.destructive) { Task { await flow.confirm() } }.nativeChannelFlowAction()
                            Button("取消未发送的请求") { flow.cancelReview() }
                        }
                    }
                }
                .confirmationDialog("只在原服务确认 NOT_FOUND 后重试相同字节与请求编号；不会创建新的角色请求。",isPresented:$retryConfirmation) {
                    Button("确认重试原请求",role:.destructive) { Task { await flow.retryOriginal() } }
                    Button("取消",role:.cancel) {}
                }
            } else { VStack { Text("当前角色管理来源不可用");Button("重新读取原权限") { Task { await open() } } } }
        }
        .nativeChannelFlowPage()
        .navigationTitle("频道角色管理")
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
