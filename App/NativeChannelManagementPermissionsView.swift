import SwiftUI

private func ncmPermissionText(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "NativeChannelManagement") }

/// Server-read tri-state overwrite editor. It never computes effective membership locally.
/// Submission uses the original double-version CAS and a dedicated current permission-command lease.
@MainActor struct NativeChannelManagementPermissionsView: View {
    let model: NativeChannelManagementCoordinator
    let channelID: NativeChannelManagementID
    @State private var target = "1:0"
    @State private var allow: UInt64 = 0
    @State private var deny: UInt64 = 0
    @State private var note = ""
    @State private var reason = ""
    @State private var reviews = false
    @State private var localIssue: NativeChannelManagementError?
    var body: some View {
        Group {
            if model.isCurrent {
                if model.permissions?.channelID == channelID {
                    Form {
                        if model.busy { Section { ProgressView().frame(maxWidth: .infinity) } }
                        NativeChannelManagementIssueView(issue: localIssue ?? model.issue)
                        Section {
                            Picker(selection: $target) {
                                ncmPermissionText("everyone").tag("1:0")
                                ForEach(model.roles) { role in Text(role.name).fixedSize(horizontal: false, vertical: true).tag("2:\(role.id)") }
                            } label: { ncmPermissionText("permissionTarget") }
                            TextField(text: $note, prompt: ncmPermissionText("note"), axis: .vertical) { ncmPermissionText("note") }.lineLimit(2...5)
                        }
                        Section {
                            ForEach(NativeChannelManagementCapability.allCases.filter(\.available)) { capability in
                                Picker(selection: state(for: capability)) {
                                    ncmPermissionText("inherit").tag(0)
                                    if !capability.guildScoped && model.detail?.permissionNames.contains(capability.rawValue) == true {
                                        ncmPermissionText("allow").tag(1)
                                    }
                                    ncmPermissionText("deny").tag(2)
                                } label: { ncmPermissionText("capability.\(capability.rawValue)").fixedSize(horizontal: false, vertical: true) }
                            }
                        } header: { ncmPermissionText("permissions") }
                        Section { TextField(text: $reason, prompt: ncmPermissionText("reason"), axis: .vertical) { ncmPermissionText("reason") }.lineLimit(2...5) }
                        Section {
                            Button { prepare(remove: false) } label: { ncmPermissionText("review") }.nativeChannelFlowAction()
                        }.disabled(model.busy || model.pending != nil)
                        if original != nil {
                            Section {
                                Button(role: .destructive) { prepare(remove: true) } label: { ncmPermissionText("removeOverwrite") }
                            }.disabled(model.busy || model.pending != nil)
                        }
                        if let effective = model.effectivePermissions {
                            Section {
                                ForEach(effective.names, id: \.self) { ncmPermissionText("capability.\($0)") }
                            } header: { ncmPermissionText("myEffectivePermissions") }
                        }
                    }
                    .refreshable { await model.loadPermissions(channelID); selectOriginal() }
                } else if model.busy {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label { ncmPermissionText("d7.channelManage.permissionsLoadFailed") } icon: { Image(systemName: "lock.shield") }
                    } actions: {
                        Button { Task { await model.loadPermissions(channelID); selectOriginal() } } label: { ncmPermissionText("refresh") }
                    }
                }
            } else { NativeChannelManagementUnavailableView() }
        }
        .nativeChannelFlowPage()
        .navigationTitle(ncmPermissionText("permissions"))
        .task(id: channelID) { await model.loadPermissions(channelID); selectOriginal() }
        .onChange(of: target) { _, _ in selectOriginal() }
        .sheet(isPresented: $reviews) {
            NavigationStack { NativeChannelManagementReviewView(model: model) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
    private var original: NativeChannelManagementOverwrite? { model.permissions?.overrides.first { $0.id == target } }
    private func state(for capability: NativeChannelManagementCapability) -> Binding<Int> {
        Binding(get: { allow & capability.bit != 0 ? 1 : (deny & capability.bit != 0 ? 2 : 0) }, set: { value in
            allow &= ~capability.bit; deny &= ~capability.bit
            if value == 1 && !capability.guildScoped { allow |= capability.bit }
            if value == 2 { deny |= capability.bit }
        })
    }
    private func selectOriginal() {
        localIssue = nil
        if let original, let bits = try? original.masks() { allow = bits.allow; deny = bits.deny; note = original.note ?? "" }
        else { allow = 0; deny = 0; note = "" }
    }
    private func prepare(remove: Bool) {
        do {
            guard let channel = model.detail, let permissions = model.permissions else { throw NativeChannelManagementError.unavailable }
            let parts = target.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let type = Int(parts[0]) else { throw NativeChannelManagementError.invalidDraft }
            // Role choices only come from the current scope's real server list.
            if type == 2 && !model.roles.contains(where: { $0.id.rawValue == String(parts[1]) }) { throw NativeChannelManagementError.invalidSource }
            let row = try NativeChannelManagementOverwrite(targetType: type, targetID: String(parts[1]),
                allowBits: "0x" + String(allow, radix: 16), denyBits: "0x" + String(deny, radix: 16), note: note.isEmpty ? nil : note)
            try model.prepare(.overwrite(channel: channel, permissions: permissions, row: row, remove: remove, reason: reason))
            localIssue = nil; reviews = true
        } catch { localIssue = (error as? NativeChannelManagementError) ?? .invalidDraft }
    }
}
