import SwiftUI

@MainActor struct NativeChannelMentionEntry: View {
    let source: NativeChannelMentionTargets
    let original: NativeChannelMessageTextReference?
    let canApply: () -> Bool
    let apply: ([NativeChannelMessageID],[NativeChannelMessageID],Bool) -> Bool
    @State private var members: Set<NativeChannelMessageID> = []
    @State private var roles: Set<NativeChannelMessageID> = []
    @State private var everyone = false
    @State private var rejected = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            if source.isCurrent {
                Section("同一原频道的提及目标") {
                    Text("频道 \(source.binding.channelID.rawValue)。选择仅更新原文本草稿；最终仍需在原输入框确认发送。不会新建发送器或自动发送。").font(Theme.Font.label).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let issue=source.issue { Text(issue) }
                    if source.busy { ProgressView() }
                    Button("读取原成员名单") { Task { await source.readMembers() } }.disabled(!source.canReadMembers)
                    Button("读取原角色") { Task { await source.readRoles() } }.disabled(!source.canReadRoles)
                    if !canApply() { Text("当前有原请求待确认或发送权限不可用。可以回读目标来源供原请求恢复，但不能替换其提及对象或新建发送。") }
                    Text("名单读取有独立权限。这里不提供任意编号注入；原服务最终按当前可见性与屏蔽关系过滤收件人。")
                }
                Section("成员（最多20个）") {
                    ForEach(source.members) { row in
                        Toggle("\(row.name) · \(row.id.rawValue)",isOn:selection(row.id,in: $members))
                            .disabled(members.count >= 20 && !members.contains(row.id))
                    }
                    if source.canReadMore { Button("读取下一页原名单") { Task { await source.readMembers(next:true) } } }
                }
                Section("角色（最多20个）") {
                    ForEach(source.roles) { row in
                        Toggle("\(row.name) · \(row.id.rawValue)",isOn:selection(row.id,in:$roles))
                            .disabled((!row.mentionable && !source.allowsEveryone) || (roles.count >= 20 && !roles.contains(row.id)))
                    }
                    Text("不可提及角色需原 MENTION_EVERYONE 权限；角色 ID 不代表成员 ID。")
                }
                Section("所有人") {
                    Toggle("提及本频道所有当前可见成员",isOn:$everyone).disabled(!source.allowsEveryone)
                    Text("仅原 MENTION_EVERYONE 允许。原服务还有每日频率限制，并过滤屏蔽关系；不把发送成功当提醒已送达。")
                }
                Section("确认草稿目标") {
                    Text("成员："+members.map(\.rawValue).sorted().joined(separator:", "))
                    Text("角色："+roles.map(\.rawValue).sorted().joined(separator:", "))
                    Text(everyone ? "包括本频道所有当前可见成员" : "不提及所有人")
                    if let reply=original?.replyToID { Text("保留原引用消息：\(reply.rawValue)") }
                    Button("采用这些目标，返回原输入框确认发送") {
                        let orderedMembers=members.sorted { $0.rawValue < $1.rawValue },orderedRoles=roles.sorted { $0.rawValue < $1.rawValue }
                        if canApply() && apply(orderedMembers,orderedRoles,everyone) { dismiss() } else { rejected=true }
                    }
                    .nativeChannelPrimaryAction().disabled(!canApply())
                    Button("清空待选成员、角色与所有人") { members=[];roles=[];everyone=false }
                    if rejected { Text("当前来源或原发送授权已变化，未替换草稿，也未发送。") }
                }
            } else { Text("原频道权限已变化，提及选择不可用。") }
        }
        .nativeChannelScreen()
        .navigationTitle("选择原提及目标")
        .toolbar { Button("取消") { dismiss() } }
        .onAppear { members=Set(original?.memberIDs ?? []);roles=Set(original?.roleIDs ?? []);everyone=original?.mentionEveryone ?? false }
        .privacySensitive()
    }
    private func selection(_ id: NativeChannelMessageID,in value: Binding<Set<NativeChannelMessageID>>) -> Binding<Bool> {
        Binding(get:{ value.wrappedValue.contains(id) },set:{ selected in if selected { value.wrappedValue.insert(id) } else { value.wrappedValue.remove(id) } })
    }
}
