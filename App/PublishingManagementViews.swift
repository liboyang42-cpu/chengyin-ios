import SwiftUI

@MainActor struct PublishingProjectsView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
    let service: PublishingService?
    let account: PublishingSession?
    var openResource: (PublishedResource) -> Void
    var readOnly = false
    @State private var type = "all"
    @State private var state = "all"
    @State private var owner = "all"
    @State private var rows: [PublishingProject] = []
    @State private var requests: [ProjectStateRequestContract.Saved] = []
    @State private var requestAccount: PublishingSession?
    @State private var total = 0
    @State private var unknown = 0
    @State private var busy = false
    @State private var failed = false
    @State private var review: PublishingReview?
    @State private var message = ""
    @State private var generation = 0
    private var query: PublishingRead { .projects(type: type, state: state, ownerType: owner, scope: "", pageSize: 200) }
    var body: some View {
        List {
            Section {
                Picker("publishModes.type", selection: $type) { ForEach(["all", "topic", "activity", "template"], id: \.self) { Text(LocalizedStringKey("publishModes.filter." + $0)).tag($0) } }
                Picker("publishModes.state", selection: $state) { ForEach(["all", "draft", "pending", "rejected", "running", "notStarted", "offline", "completed"], id: \.self) { Text(LocalizedStringKey("publishModes.filter." + $0)).tag($0) } }
                Picker("publishModes.owner", selection: $owner) { ForEach(["all", "member", "club", "merchant"], id: \.self) { Text(LocalizedStringKey("publishModes.filter." + $0)).tag($0) } }
            }.disabled(busy)
            if busy { ProgressView() }
            if failed { Text("publishModes.readFailed"); Button("publishModes.retry") { Task { await load() } } }
            if rows.isEmpty && !busy && !failed { Text("publishModes.empty") }
            if total > rows.count + unknown { Text("publishModes.truncated").foregroundStyle(.secondary) }
            if unknown > 0 { Text("publishModes.unknownTypes").foregroundStyle(.secondary) }
            if requestAccount == account, service?.currentSession == account, !requests.isEmpty {
                Section((chinese ? "原状态操作记录" : "Original status requests")) {
                    Text((chinese ? "列表消失不代表删除成功；只读取原请求回执，不翻转重放。" : "A missing list row does not confirm deletion. Read the original receipt without replaying the request."))
                    ForEach(requests) { saved in
                        VStack(alignment: .leading) {
                            Text(saved.title)
                            Text(saved.action == .remove ? (chinese ? "已确认的原移除请求" : "Original confirmed removal request") : (saved.submit.command?.expectedOnline == true ? (chinese ? "已确认的原下架请求" : "Original confirmed offline request") : (chinese ? "已确认的原上架请求" : "Original confirmed online request")))
                            Text(saved.id).font(.caption).textSelection(.enabled)
                            if let receipt = saved.receipt {
                                Text(receipt.applied ? (chinese ? "原 writer 已执行本次操作" : "The original writer applied this request") : receipt.terminal ? (chinese ? "原请求已结束，目标操作未执行" : "The original request ended without applying the action") : (chinese ? "结果仍未知，保持原请求锁" : "Outcome remains unknown; the original request stays locked"))
                                if let reason = receipt.originalResult?.object?["msg"]?.text { Text(reason) }
                            } else { Text((chinese ? "尚未读回原请求结果" : "The original outcome has not been read back")) }
                            Button((chinese ? "回读这次操作" : "Read this request’s outcome")) { Task { await readOutcome(saved) } }
                                .disabled(busy || service?.canReadStateReceipt != true)
                        }
                    }
                }
            }
            ForEach(rows) { project in
                Section {
                    if readOnly {
                        VStack(alignment: .leading) { Text(project.title); if let state = project.stateText { Text(state).font(.caption) } }
                    } else {
                        Button { openProject(project.resource) } label: { VStack(alignment: .leading) { Text(project.title); if let state = project.stateText { Text(state).font(.caption) } } }
                    }
                    if project.signupCount > 0 { Text("\(project.signupCount) " + appLocalized("publishModes.signups", locale: locale)) }
                    if !readOnly && project.canToggle { Button(LocalizedStringKey(project.online ? "publishModes.takeOffline" : "publishModes.putOnline")) { Task { await prepare(project, action: .toggle) } }.disabled(busy || hasPendingRequest(project.resource)) }
                    if !readOnly && project.canDelete { Button("publishModes.remove", role: .destructive) { Task { await prepare(project, action: .remove) } }.disabled(busy || hasPendingRequest(project.resource)) }
                    if !readOnly && project.canCancelWithRefund { Text("publishModes.refundHandoff").font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !message.isEmpty { Text(message).accessibilityIdentifier("publishModes.management.message") }
        }.navigationTitle(Text("publishModes.projects"))
        .task { await load() }.refreshable { await load() }
        .onChange(of: type) { _, _ in Task { await load() } }
        .onChange(of: state) { _, _ in Task { await load() } }
        .onChange(of: owner) { _, _ in Task { await load() } }
        .onChange(of: account) { _, _ in generation += 1; service?.invalidateReviews(); review = nil; rows = []; requests = []; requestAccount = nil; total = 0; message = ""; Task { await load() } }
        .onDisappear { generation += 1; if let review { service?.cancel(review) }; review = nil; busy = false }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { generation += 1; if let review { service?.cancel(review) }; review = nil; busy = false }
        }
        .sheet(item: $review) { snapshot in
            NavigationStack {
                List {
                    Section {
                        if snapshot.action == .remove {
                            Text("publishModes.removeQuestion \(snapshot.baseline?.title ?? "")").font(.headline)
                        } else if snapshot.baseline?.online == true {
                            Text("publishModes.offlineQuestion \(snapshot.baseline?.title ?? "")").font(.headline)
                        } else {
                            Text("publishModes.onlineQuestion \(snapshot.baseline?.title ?? "")").font(.headline)
                        }
                    }
                    Section {
                        Button(LocalizedStringKey(snapshot.action == .remove ? "publishModes.remove" : snapshot.baseline?.online == true ? "publishModes.takeOffline" : "publishModes.putOnline"), role: snapshot.action == .remove ? .destructive : nil) { Task { await submit(snapshot) } }.disabled(service?.mutationsConfigured != true || busy)
                        Button("publishModes.cancel", role: .cancel) { service?.cancel(snapshot); review = nil }
                    }
                }.navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
    /// The result destination must not escape into detail editors or lifecycle actions.
    func openProject(_ resource: PublishedResource) { guard !readOnly else { return }; openResource(resource) }
    private func load() async {
        generation += 1; let stamp = generation; if let review { service?.cancel(review) }; review = nil; busy = true; failed = false; rows = []
        guard let service, let account else { busy = false; failed = true; return }
        do { requests = try service.stateRequests(session: account); requestAccount = account; let page = try PublishingContracts.decodeProjects(await service.read(query, session: account)); guard stamp == generation else { return }; rows = page.rows; total = page.total; unknown = page.unknownRows.count; busy = false }
        catch { guard stamp == generation else { return }; busy = false; failed = true }
    }
    private func hasPendingRequest(_ resource: PublishedResource) -> Bool {
        guard let account, let service else { return true }
        return (try? service.hasUncertainOutcome(targetKey: "publishModes:\(resource.kind.rawValue):\(resource.value)", session: account)) ?? true
    }
    private func prepare(_ project: PublishingProject, action: PublishingProjectAction) async {
        guard !readOnly, !busy, !hasPendingRequest(project.resource), let service, let account else { return }; let stamp = generation; busy = true
        do { let value = try await service.prepareProject(project, action: action, query: query, session: account); guard stamp == generation else { service.cancel(value); return }; review = value; busy = false }
        catch { guard stamp == generation else { return }; busy = false; message = appLocalized("publishModes.conflict", locale: locale) }
    }
    private func readOutcome(_ saved: ProjectStateRequestContract.Saved) async {
        guard !busy, let service, let account else { return }
        let stamp = generation; busy = true
        do {
            _ = try await service.readStateOutcome(saved, session: account)
            guard stamp == generation, service.currentSession == account else { return }
            requests = try service.stateRequests(session: account); busy = false
            message = (chinese ? "已回读原请求；没有重新执行状态操作。" : "The original receipt was read without replaying the action.")
        } catch {
            guard stamp == generation else { return }; busy = false
            message = (chinese ? "原请求回读暂不可用，保留原记录和未知锁。" : "Readback is unavailable. The original record and uncertainty lock remain.")
        }
    }
    private func submit(_ snapshot: PublishingReview) async {
        guard !readOnly, !busy, let service else { return }; let stamp = generation; busy = true; review = nil
        let outcome = await service.submit(snapshot); guard stamp == generation, service.currentSession == account else { return }; busy = false
        if let account { requests = (try? service.stateRequests(session: account)) ?? requests; requestAccount = account }
        switch outcome {
        case .acknowledged: message = appLocalized("publishModes.acknowledged", locale: locale); await load()
        case .rejected(let text): message = text.isEmpty ? appLocalized("publishModes.rejected", locale: locale) : text
        case .notSent: message = appLocalized("publishModes.notSent", locale: locale)
        case .unknown: message = appLocalized("publishModes.unknown", locale: locale)
        }
    }
}
@MainActor struct PublishingIdentityStatusView: View {
    let service: PublishingService?
    let account: PublishingSession?
    private enum Status { case unconfigured, loading, failed, registered, notRegistered }
    @State private var status: Status = .unconfigured
    var body: some View {
        List {
            if account?.region == .unitedStates { Text("publishModes.identityUSUnsupported") }
            else {
                switch status {
                case .unconfigured: Text("publishModes.offlineNotice")
                case .loading: ProgressView()
                case .failed: Text("publishModes.readFailed")
                case .registered:
                    Text("publishModes.registered")
                    Text("publishModes.identityChange").foregroundStyle(.secondary)
                case .notRegistered:
                    Text("publishModes.notRegistered")
                    Text("publishModes.identityHandoff").foregroundStyle(.secondary)
                }
                Text("publishModes.identityPrivacy").font(.caption)
            }
        }.navigationTitle(Text("publishModes.identity"))
        .task(id: account?.epoch) {
            status = .unconfigured
            guard let account, let service, account.region == .china else { return }
            status = .loading
            do {
                let registered = try await service.identityRegistered(session: account)
                guard !Task.isCancelled, service.currentSession == account else { return }
                status = registered ? .registered : .notRegistered
            } catch {
                guard !Task.isCancelled, service.currentSession == account else { return }
                status = .failed
            }
        }
    }
}
/// Embed in full-scope ProjectEdit forms only. Existing whitelist locks remain authoritative.
struct PublishingTopicRewardsForm: View {
    @Binding var rewards: PublishingTopicRewards
    var fullEdit: Bool
    var body: some View {
        Section("publishModes.rewards") {
            Toggle("publishModes.selfPlay", isOn: $rewards.selfPlay)
            if rewards.selfPlay {
                TextField("publishModes.price", text: $rewards.selfPlayPrice).keyboardType(.decimalPad)
                TextField("publishModes.quota", text: $rewards.selfPlayQuota).keyboardType(.numberPad)
            }
            TextField("publishModes.medalName", text: $rewards.medalName)
            TextField("publishModes.medalImage", text: $rewards.medalImage).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("publishModes.uploadDisabled").font(.caption)
            TextField("publishModes.coupon", value: $rewards.couponID, format: .number).keyboardType(.numberPad)
            Text("publishModes.couponNotice").font(.caption).foregroundStyle(.secondary)
        }.disabled(!fullEdit)
    }
}
