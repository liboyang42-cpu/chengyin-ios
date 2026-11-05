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
                if source.busy || source.issue != nil || !canApply() {
                    Section {
                        if source.busy { ProgressView() }
                        if let issue = source.issue {
                            Text(LocalizedStringKey(issue == "原角色来源不可用；没有从权限名称猜造角色编号。" ? "d7.channelMention.rolesFailed" : "d7.channelMention.membersFailed"))
                                .foregroundStyle(.secondary)
                        }
                        if !canApply() { Text("d7.channelMention.sendPending").foregroundStyle(.secondary) }
                    }
                }
                Section {
                    ForEach(source.members) { row in
                        Toggle(isOn: selection(row.id, in: $members)) { Text(verbatim: row.name) }
                            .disabled(members.count >= 20 && !members.contains(row.id))
                    }
                    if source.canReadMore { Button("d7.channelMention.loadMore") { Task { await source.readMembers(next: true) } } }
                    else if source.members.isEmpty { Button("d7.channelMention.loadMembers") { Task { await source.readMembers() } }.disabled(!source.canReadMembers) }
                } header: { Text("d7.channelMention.members") }
                Section {
                    ForEach(source.roles) { row in
                        Toggle(isOn: selection(row.id, in: $roles)) { Text(verbatim: row.name) }
                            .disabled((!row.mentionable && !source.allowsEveryone) || (roles.count >= 20 && !roles.contains(row.id)))
                    }
                    if source.roles.isEmpty { Button("d7.channelMention.loadRoles") { Task { await source.readRoles() } }.disabled(!source.canReadRoles) }
                } header: { Text("d7.channelMention.roles") }
                if source.allowsEveryone {
                    Section {
                        Toggle("d7.channelMention.everyone", isOn: $everyone)
                    }
                }
                Section {
                    if rejected { Text("d7.channelMention.rejected").foregroundStyle(.red) }
                    Button("d7.channelMention.apply") {
                        let orderedMembers=members.sorted { $0.rawValue < $1.rawValue },orderedRoles=roles.sorted { $0.rawValue < $1.rawValue }
                        if canApply() && apply(orderedMembers,orderedRoles,everyone) { dismiss() } else { rejected=true }
                    }
                    .nativeChannelPrimaryAction().disabled(!canApply())
                    if !members.isEmpty || !roles.isEmpty || everyone {
                        Button("d7.channelMention.clear", role: .destructive) { members=[];roles=[];everyone=false }
                    }
                }
            } else {
                ContentUnavailableView("d7.channelMention.unavailable", systemImage: "at")
            }
        }
        .nativeChannelScreen()
        .navigationTitle(Text("d7.channelMention.title"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("d7.channelMention.cancel") { dismiss() } } }
        .onAppear { members=Set(original?.memberIDs ?? []);roles=Set(original?.roleIDs ?? []);everyone=original?.mentionEveryone ?? false }
        .privacySensitive()
    }
    private func selection(_ id: NativeChannelMessageID,in value: Binding<Set<NativeChannelMessageID>>) -> Binding<Bool> {
        Binding(get:{ value.wrappedValue.contains(id) },set:{ selected in if selected { value.wrappedValue.insert(id) } else { value.wrappedValue.remove(id) } })
    }
}
