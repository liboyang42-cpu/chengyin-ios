import SwiftUI

/// F31 explicit, bounded picker over the SAME original F16 partitions; no recommendation, contact discovery or automatic selection.
@MainActor struct NativeFriendPickerView: View {
    @Environment(\.themeDomain) private var domain
    let flow: any NativeFriendPickerSource
    @State private var search = ""
    private var visible: [NativeFriendPickerItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? flow.items : flow.items.filter { $0.friend.displayName.localizedCaseInsensitiveContains(query) || $0.friend.nickname.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        Section {
            Picker("原好友分区", selection: Binding(get: { flow.section }, set: { next in search = ""; Task { await flow.chooseSection(next) } })) {
                Text("一起玩").tag(NativeFriendDirectorySection.together)
                Text("近期活跃").tag(NativeFriendDirectorySection.recent)
                Text("全部").tag(NativeFriendDirectorySection.all)
            }.disabled(flow.busy || flow.hasPickerReview)
            Text("“近期活跃”只表示原15分钟活跃事实，不表示实时在线或位置。").font(Theme.Font.label)
            TextField("搜索当前完整分区的昵称或本人备注", text: $search).disabled(flow.busy)
            ForEach(visible) { row in
                Button { flow.toggle(row) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Space.s1) {
                            Text(verbatim: row.friend.displayName).fixedSize(horizontal: false, vertical: true)
                            if row.friend.friendRemark != nil { Text(verbatim: row.friend.nickname).font(Theme.Font.label) }
                            if row.alreadyMember { Text(flow.alreadyMemberLabel).font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: domain)) }
                        }
                        Spacer()
                        Image(systemName: flow.selected.contains(row) ? "checkmark.circle.fill" : "circle")
                    }
                }.disabled(!flow.canWrite || row.alreadyMember || (!flow.selected.contains(row) && flow.selected.count >= 10) || flow.hasPickerReview)
            }
            if visible.isEmpty && !flow.busy { Text("当前分区没有符合搜索的可读好友。") }
            Text("已明确选择 \(flow.selected.count)/10 人；不会自动扩大选择。").font(Theme.Font.label)
            Button("查看定向邀请确认") { flow.prepareCreate() }.disabled(!flow.canWrite || flow.selected.isEmpty || flow.hasPickerReview)
        } header: { Text("选择原好友") }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .onChange(of: flow.isCurrent) { _, valid in if !valid { search = "" } }
        .onDisappear { search = "" }
        .privacySensitive()
        .tint(Theme.Color.accent(in: domain))
    }
}
