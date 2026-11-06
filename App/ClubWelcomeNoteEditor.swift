import SwiftUI

@MainActor struct ClubWelcomeNoteEntry: View {
    let club: ClubRecord
    let identity: ClubReadIdentity?
    let access: any ClubOperationsAccess
    let enabled: Bool
    var onConfirmed: ((ClubWelcomeNoteConfirmedReturn) -> Void)? = nil
    @State private var visit: ClubWelcomeNoteVisit?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.themeDomain) private var domain
    var body: some View {
        Section("入会欢迎语") {
            Text(verbatim: club.welcomeNote.flatMap { $0.isEmpty ? nil : $0 } ?? "尚未设置欢迎语")
            Button("编辑入会欢迎语") {
                guard visit == nil, scenePhase == .active, enabled, club.isOwner,
                      let identity, identity.isSignedIn, access.identity == identity else { return }
                visit = ClubWelcomeNoteVisit(clubID: club.id, identity: identity, access: access)
            }
            .disabled(!enabled || !club.isOwner || identity == nil || access.identity != identity)
            .accessibilityIdentifier("club.welcome.edit")
        }
        .font(Theme.Font.body)
        .listRowBackground(Theme.Generated.color("--cy-color-bg-elevated", in: domain))
        .sheet(item: Binding(get: { visit }, set: { next in
            if next == nil { visit?.retire() }; visit = next
        })) { opened in
            NavigationStack {
                ClubWelcomeNoteEditor(visit: opened, saved: { _ in
                    guard scenePhase == .active, enabled, club.isOwner, visit?.id == opened.id,
                          opened.matches(clubID: club.id, identity: identity, access: access) else { return }
                    // APPLIED is a historical acknowledgement, never a replacement current value.
                    if let result = ClubWelcomeNoteConfirmedReturn(visit: opened, access: access) { onConfirmed?(result) }
                })
            }.id(opened.id)
        }
        .onChange(of: identity) { _, _ in retire() }
        .onChange(of: club.id) { _, _ in retire() }
        .onChange(of: club.isOwner) { _, owner in if !owner { retire() } }
        .onChange(of: ObjectIdentifier(access)) { _, _ in retire() }
        .onChange(of: access.welcomeNoteRevision) { _, _ in retire() }
        .onChange(of: access.welcomeNote.map(ObjectIdentifier.init)) { _, _ in retire() }
        .onChange(of: enabled) { _, value in if !value { retire() } }
        .onChange(of: scenePhase) { _, value in if value != .active { retire() } }
        .onDisappear { retire() }
    }
    private func retire() { visit?.retire(); visit = nil }
}

@MainActor struct ClubWelcomeNoteEditor: View {
    @StateObject private var flow: ClubWelcomeNoteFlow
    @ObservedObject private var visit: ClubWelcomeNoteVisit
    let saved: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirming = false
    @Environment(\.themeDomain) private var domain
    init(visit: ClubWelcomeNoteVisit, saved: @escaping (String) -> Void) {
        self.visit = visit
        _flow = StateObject(wrappedValue: ClubWelcomeNoteFlow(clubID: visit.clubID, identity: visit.identity, access: visit.access))
        self.saved = saved
    }
    var body: some View {
        Form {
            Text("新成员首次加入后会看到这段话。仅主理人可以修改；可清空，最多 200 个 Unicode 码点。")
            TextEditor(text: $flow.draft).frame(minHeight: 150)
                .disabled(!visit.isCurrent || !flow.ownerConfirmed || flow.state == .saving || flow.state == .unknown || flow.state == .revoked)
                .accessibilityIdentifier("club.welcome.text")
            Text("\(flow.count) / 200").monospacedDigit().foregroundStyle(flow.count > 200 ? .red : .secondary)
            Button("清空文本", role: .destructive) { flow.draft = "" }
                .disabled(!visit.isCurrent || !flow.ownerConfirmed || flow.state == .saving || flow.state == .unknown || flow.state == .revoked)
            Button("保存") { guard visit.isCurrent, scenePhase == .active else { return }; confirming = true }.disabled(!flow.canSave || !visit.isCurrent)
                .accessibilityIdentifier("club.welcome.save")
            switch flow.state {
            case .loading, .saving: ProgressView()
            case .saved(let note):
                Section("本次原请求已确认") {
                    Text("这是本次提交的历史结果，当前欢迎语由管理页重新读取。")
                    Text(verbatim: note.isEmpty ? "当时已清空欢迎语" : "当时保存：" + note)
                }
            case .unknown:
                Text("本次结果仍未确认。新协议沿原请求回执恢复；旧请求没有原身份，继续保留 UNKNOWN。当前文本相同也不是这次保存的凭据，不会自动重发。")
                if let current = flow.currentNote { Text(verbatim: current.isEmpty ? "当前回读：欢迎语为空" : "当前回读：" + current) }
            case .revoked: Text("认证或主理人权限已失效；已转发的原请求仍保留保护锁，不会据错误码自动重发。")
            case .notSent: Text("本次未确认发送；请刷新原资料、检查权限后再保存。")
            case .rejected: Text("原接口拒绝了这次修改，欢迎语未按本次草稿确认保存。")
            case .unavailable: Text("当前无法确认主理人身份或读取欢迎语。")
            case .ready: EmptyView()
            }
            if flow.state != .loading && flow.state != .saving {
                Button("回读原请求并刷新当前欢迎语") { Task { await flow.load() } }
                    .accessibilityIdentifier("club.welcome.readback")
            }
            if flow.recoveryUnavailable { Text("原请求回执暂不可读；身份记录未删除，未重发保存。可从俱乐部详情的本人原请求入口继续回读。").font(.footnote) }
            if visit.isCurrent, !flow.originalResults.isEmpty {
                Section("本人原请求 · 历史事实") { ForEach(flow.originalResults) { ClubWelcomeNoteOriginalRow(value: $0) } }
            }
            if flow.ownerConfirmed && !flow.canSave && flow.state == .ready { Text("内容未变或此接口尚未单独批准写入。只读不会授权保存。").font(.footnote) }
        }
        .font(Theme.Font.body)
        .scrollContentBackground(Theme.Generated.color("--cy-color-bg-page", in: domain) != nil ? .hidden : .automatic)
        .background {
            if let background = Theme.Generated.color("--cy-color-bg-page", in: domain) { background }
        }
        .navigationTitle("入会欢迎语")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { retire(); dismiss() } } }
        .confirmationDialog("确认保存欢迎语？", isPresented: $confirming, titleVisibility: .visible) {
            Button(flow.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "确认清空" : "确认保存") {
                guard visit.isCurrent, scenePhase == .active else { return }
                Task {
                    await flow.save()
                    guard visit.isCurrent, scenePhase == .active, !Task.isCancelled else { return }
                    if case .saved(let note) = flow.state { saved(note) }
                }
            }
            Button("继续编辑", role: .cancel) {}
        } message: { Text(flow.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "清空后，新成员仍会看到俱乐部功能说明，但不再显示主理人自定义欢迎语。" : "文字将通过原接口检查并保存；以服务端回读结果为准。") }
        .task { guard visit.isCurrent, scenePhase == .active else { return }; await flow.load() }
        .onDisappear { retire() }
        .onChange(of: visit.isCurrent) { _, current in if !current { retire(); dismiss() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { retire(); dismiss() } }
    }
    private func retire() { confirming = false; visit.retire(); flow.close() }
}


/// Mounted outside the mutable detail/manage gates: losing club ownership must not
/// strand the same account's original request. It never grants settings visibility/write.
@MainActor struct ClubWelcomeNoteRecoveryEntry: View {
    let clubID: Int
    let identity: ClubReadIdentity
    let access: any ClubOperationsAccess
    var body: some View {
        if identity.isSignedIn, access.identity == identity, let service = access.welcomeNote, service.hasOriginalRequests(clubID: clubID, identity: identity) {
            NavigationLink {
                ClubWelcomeNoteOriginalHistoryView(clubID: clubID, identity: identity, access: access)
            } label: { Label("本人欢迎语原请求", systemImage: "clock.arrow.circlepath") }
                .accessibilityIdentifier("club.welcome.original.entry")
        }
    }
}
@MainActor private struct ClubWelcomeNoteOriginalHistoryView: View {
    let clubID: Int
    let identity: ClubReadIdentity
    let access: any ClubOperationsAccess
    @StateObject private var visit: ClubWelcomeNoteVisit
    init(clubID: Int, identity: ClubReadIdentity, access: any ClubOperationsAccess) {
        self.clubID = clubID; self.identity = identity; self.access = access
        _visit = StateObject(wrappedValue: ClubWelcomeNoteVisit(clubID: clubID, identity: identity, access: access))
    }
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [ClubWelcomeNoteOriginalHistory] = []
    @State private var loadedIdentity: ClubReadIdentity?
    @State private var message: String?
    @State private var busy = false
    @State private var active = false
    @State private var generation = UUID()
    @Environment(\.themeDomain) private var domain
    var body: some View {
        Form {
            Section { Text("这里只回读本人提交时绑定的原请求，不读取当前主理人的设置，不重发保存。已保存文本属于当时的历史事实；当前欢迎语可能已被后续修改。") }
            if busy { ProgressView("正在回读原请求") }
            if let message { Text(verbatim: message) }
            if active, phase == .active, visit.isCurrent, visit.service?.canRecover(identity: identity) == true, loadedIdentity == identity {
                ForEach(rows) { ClubWelcomeNoteOriginalRow(value: $0) }
            }
            Button("只回读原请求") { Task { await load() } }.disabled(busy || phase != .active || !visit.isCurrent)
                .accessibilityIdentifier("club.welcome.original.recover")
        }
        .font(Theme.Font.body)
        .scrollContentBackground(Theme.Generated.color("--cy-color-bg-page", in: domain) != nil ? .hidden : .automatic)
        .background {
            if let background = Theme.Generated.color("--cy-color-bg-page", in: domain) { background }
        }
        .navigationTitle("欢迎语原请求")
        .task { guard visit.isCurrent else { return }; active = true; await load() }
        .onDisappear { retire() }
        .onChange(of: identity) { _, _ in retire(); dismiss() }
        .onChange(of: ObjectIdentifier(access)) { _, _ in retire(); dismiss() }
        .onChange(of: access.welcomeNoteRevision) { _, _ in retire(); dismiss() }
        .onChange(of: access.welcomeNote.map(ObjectIdentifier.init)) { _, _ in retire(); dismiss() }
        .onChange(of: phase) { _, value in if value != .active { retire(); dismiss() } }
    }
    private func retire() { visit.retire(); active = false; generation = UUID(); rows = []; loadedIdentity = nil; message = nil; busy = false }
    private func load() async {
        guard active, phase == .active, !busy, visit.isCurrent, let service = visit.service else { return }
        generation = UUID(); let ticket = generation
        rows = []; loadedIdentity = nil; message = nil; busy = true
        defer { if generation == ticket { busy = false } }
        do {
            let result = try await service.recoverOriginal(clubID: clubID, identity: identity,
                viewCurrent: { visit.isCurrent && active && generation == ticket && phase == .active })
            guard visit.isCurrent, active, generation == ticket, phase == .active, service.canRecover(identity: identity), !Task.isCancelled else { return }
            rows = result; loadedIdentity = identity
            if result.isEmpty { message = "没有带原请求身份的记录。旧请求不根据当前文本补造回执。" }
        } catch {
            guard active, generation == ticket, phase == .active else { return }
            rows = []; loadedIdentity = nil
            message = "原回执暂不可读或读取授权已失效；记录仍保留。请重新登录或恢复独立回读授权后继续，不会自动重发。"
        }
    }
}
private struct ClubWelcomeNoteOriginalRow: View {
    let value: ClubWelcomeNoteOriginalHistory
    @Environment(\.themeDomain) private var domain
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Generated.length("--cy-space-1-5", in: domain)) {
            Text(verbatim: value.entry.requestID).font(.caption).textSelection(.enabled)
            if let receipt = value.receipt, receipt.state == "APPLIED", let note = receipt.welcomeNote {
                Text("已保存 · 原请求回执确认")
                Text(verbatim: note.isEmpty ? "当时已清空欢迎语" : "当时保存：" + note)
                if let audit = receipt.auditId { Text(verbatim: "原审计编号 \(audit)").font(.caption) }
            } else if let receipt = value.receipt, receipt.state == "REJECTED" {
                Text("原请求已拒绝 · 未保留本次设置变更")
                if let message = receipt.message { Text(verbatim: message) }
                if let audit = receipt.auditId { Text(verbatim: "原审计编号 \(audit)").font(.caption) }
            } else if value.entry.state == "NOT_SENT" {
                Text("未转发到网络；这条请求没有重发。")
            } else {
                Text("UNKNOWN · 保留原身份；不以当前文本推断保存结果。")
            }
        }
        .font(Theme.Font.body)
        .listRowBackground(Theme.Generated.color("--cy-color-bg-elevated", in: domain))
        .accessibilityIdentifier("club.welcome.original." + value.entry.requestID)
    }
}
