import SwiftUI

@MainActor protocol MerchantPredictionReading: AnyObject {
    var id: UUID { get }
    var isConfigured: Bool { get }
    func access() async throws -> MerchantAccess
    func inbox(access: MerchantAccess) async throws -> [MerchantPredictionRound]
}

@MainActor final class MerchantPredictionReader: MerchantPredictionReading {
    let id = UUID()
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let merchant: MerchantService
    private let predictions: MerchantPredictionReadService
    private let token: String
    private let current: () -> Bool
    private let unauthorized: () -> Void
    private var accepted: MerchantAccess?
    private var generation: UInt64 = 0
    var isConfigured: Bool { current() }
    init(configuration: APIConfiguration, transport: any HTTPTransport, token: String,
         current: @escaping () -> Bool, unauthorized: @escaping () -> Void) {
        self.configuration = configuration; self.transport = transport
        let cookieFree = CookieFreeTransport(underlying: transport)
        merchant = MerchantService(configuration: configuration, transport: cookieFree)
        predictions = MerchantPredictionReadService(configuration: configuration, transport: cookieFree)
        self.token = token; self.current = current; self.unauthorized = unauthorized
    }
    /// Admission and the pushed inbox own separate access generations.
    func isolatedReader() -> MerchantPredictionReader {
        .init(configuration: configuration, transport: transport, token: token, current: current, unauthorized: unauthorized)
    }
    private struct CookieFreeTransport: HTTPTransport {
        let underlying: any HTTPTransport
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            var exact = request; exact.httpShouldHandleCookies = false
            return try await underlying.send(exact)
        }
    }
    private func read<T>(accepts: () -> Bool, _ action: () async throws -> T) async throws -> T {
        try Task.checkCancellation(); guard current(), accepts() else { throw APIError.notConfigured }
        do {
            let value = try await action()
            try Task.checkCancellation(); guard current(), accepts() else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, current(), accepts() else { throw CancellationError() }
            if error as? APIError == .unauthorized { accepted = nil; unauthorized() }
            if error as? MerchantReadError == .accessDenied { accepted = nil }
            throw error
        }
    }
    func access() async throws -> MerchantAccess {
        generation &+= 1; let request = generation; accepted = nil
        let value = try await read(accepts: { request == generation }) { try await merchant.access(token: token) }
        accepted = value; return value
    }
    func inbox(access: MerchantAccess) async throws -> [MerchantPredictionRound] {
        guard accepted == access, access.allows(.projects) else { throw MerchantReadError.accessDenied }
        let request = generation
        return try await read(accepts: { request == generation && accepted == access }) {
            try await predictions.inbox(access: access, token: token)
        }
    }
}

@MainActor final class MerchantPredictionInboxModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, admitted, ready, denied, failed }
    struct Selection: Identifiable {
        let id = UUID()
        let snapshotID: UUID
        let round: MerchantPredictionRound
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var rows: [MerchantPredictionRound] = []
    @Published private(set) var selection: Selection?
    private let reader: any MerchantPredictionReading
    private var requestID = UUID()
    private var snapshotID = UUID()
    private var active = true
    private var closingID: UUID?
    private var presentedID: UUID?
    init(reader: any MerchantPredictionReading) { self.reader = reader }
    var canEnter: Bool { active && reader.isConfigured && (phase == .admitted || phase == .ready) }
    var hasPresentation: Bool { selection != nil || closingID != nil }
    func load(inbox: Bool = true) async {
        active = true; invalidate(); let request = requestID
        guard reader.isConfigured else { phase = .failed; return }
        phase = .loading
        do {
            let access = try await reader.access()
            guard current(request) else { return }
            guard access.allows(.projects), (access.merchantID ?? 0) > 0 else { phase = .denied; return }
            guard inbox else { phase = .admitted; return }
            let values = try await reader.inbox(access: access)
            guard current(request) else { return }
            guard Set(values.map(\.id)).count == values.count else { throw APIError.malformedResponse }
            rows = values; snapshotID = UUID(); phase = .ready
        } catch {
            guard current(request) else { return }
            phase = error as? MerchantReadError == .accessDenied ? .denied : .failed
        }
    }
    private func current(_ request: UUID) -> Bool { !Task.isCancelled && active && requestID == request && reader.isConfigured }
    private func invalidate() {
        requestID = UUID(); snapshotID = UUID(); rows = []
        if let selection, presentedID == selection.id { closingID = selection.id }
        selection = nil
    }
    func retire() { active = false; invalidate(); phase = .idle }
    func open(_ round: MerchantPredictionRound) {
        guard canEnter, phase == .ready, selection == nil, closingID == nil,
              rows.filter({ $0.id == round.id }).count == 1, rows.contains(round) else { return }
        selection = .init(snapshotID: snapshotID, round: round)
    }
    func isCurrent(_ item: Selection) -> Bool {
        canEnter && phase == .ready && selection?.id == item.id && snapshotID == item.snapshotID && rows.contains(item.round)
    }
    func close(id: UUID) {
        guard selection?.id == id else { return }
        if presentedID == id { closingID = id }
        selection = nil
    }
    func didPresent(id: UUID) { if let selection, selection.id == id, isCurrent(selection) { presentedID = id } }
    func didDismiss(id: UUID) {
        if closingID == id { closingID = nil }
        if presentedID == id { presentedID = nil }
    }
    private final class BindingOwner { var id: UUID? }
    func selectionBinding() -> Binding<Selection?> {
        let owner = BindingOwner()
        return Binding(get: { [weak self] in
            guard let self else { return nil }
            if owner.id == nil { owner.id = self.selection?.id }
            guard owner.id == self.selection?.id else { return nil }
            return self.selection
        }, set: { [weak self] value in
            guard value == nil, let id = owner.id else { return }
            self?.close(id: id)
        })
    }
}

/// Entry admission reads only access/me. Opening the inbox rechecks the server permission.
@MainActor struct SessionMerchantPredictionEntry: View {
    @ObservedObject var session: AppSession
    var body: some View {
        if let reader = session.merchantPredictionReader {
            MerchantPredictionEntry(reader: reader).id(reader.id)
        }
    }
}
@MainActor private struct MerchantPredictionEntry: View {
    let reader: MerchantPredictionReader
    @State private var inboxReader: MerchantPredictionReader
    @StateObject private var model: MerchantPredictionInboxModel
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    init(reader: MerchantPredictionReader) {
        self.reader = reader; _model = StateObject(wrappedValue: .init(reader: reader))
        _inboxReader = State(initialValue: reader.isolatedReader())
    }
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        VStack(spacing: 8) {
            // Keep the link owner mounted while its pushed inbox is visible, even
            // when foreground access revalidation temporarily hides the entry label.
            NavigationLink { MerchantPredictionInboxView(reader: inboxReader) } label: {
                Label(zh ? "竞猜待答" : "Pending predictions", systemImage: "questionmark.bubble")
            }
            .disabled(!model.canEnter).opacity(model.canEnter ? 1 : 0)
            .frame(height: model.canEnter ? nil : 0).accessibilityHidden(!model.canEnter)
            .accessibilityIdentifier("merchant.prediction.entry")
            if model.phase == .failed {
                Button(zh ? "重新核实竞猜权限" : "Retry prediction access") { Task { await model.load(inbox: false) } }
            } else if model.phase == .loading { ProgressView() }
        }
        .task { await model.load(inbox: false) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.retire() } else { Task { await model.load(inbox: false) } }
        }
    }
}

@MainActor struct MerchantPredictionInboxView: View {
    let reader: any MerchantPredictionReading
    @StateObject private var model: MerchantPredictionInboxModel
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    init(reader: any MerchantPredictionReading) { self.reader = reader; _model = StateObject(wrappedValue: .init(reader: reader)) }
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        List {
            if !reader.isConfigured { Text(zh ? "读取未启用或身份已变化" : "Read access is unavailable or changed") }
            else if model.phase == .loading || model.phase == .idle { ProgressView() }
            else if model.phase == .denied { Text(zh ? "当前商家身份没有项目管理权限" : "This merchant identity cannot manage projects") }
            else if model.phase == .failed {
                Text(zh ? "未能读取待答轮次，请重试" : "Could not read pending rounds. Retry.")
                Button(zh ? "重试" : "Retry") { Task { await model.load() } }
            } else if model.phase == .ready {
                if model.rows.isEmpty { Text(zh ? "暂无待答轮次" : "No pending rounds") }
                ForEach(model.rows) { round in
                    Button { model.open(round) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: round.nodeName.isEmpty ? (zh ? "未命名点位" : "Unnamed location") : round.nodeName).font(.headline)
                            Text(verbatim: round.question.isEmpty ? (zh ? "题面未提供" : "Question not supplied") : round.question)
                            Text(verbatim: "\(round.playDay) · \(round.betCount) \(zh ? "条参与记录" : "entries")")
                            Text(zh ? "服务器剩余自然日：\(round.daysLeft)" : "Server remaining calendar days: \(round.daysLeft)")
                        }
                    }.accessibilityIdentifier("merchant.prediction.round.\(round.id)")
                }
            }
            Section { Text(zh ? "当前仅查看待答题面；公布答案和奖励结算尚未启用。" : "Read-only questions. Publishing answers and settling rewards are not enabled.").font(.footnote) }
        }
        .navigationTitle(zh ? "竞猜待答" : "Pending predictions")
        .task { await model.load() }
        .refreshable { await model.load() }
        .onDisappear { if !model.hasPresentation { model.retire() } }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.retire() } else { Task { await model.load() } }
        }
        .sheet(item: model.selectionBinding()) { selected in
            NavigationStack {
                if model.isCurrent(selected) {
                    List {
                        Text(verbatim: selected.round.nodeName).font(.headline)
                        Text(verbatim: selected.round.playDay)
                        Text(verbatim: selected.round.question)
                        ForEach(selected.round.options) { option in
                            LabeledContent { Text(verbatim: option.label) } label: { Text(verbatim: option.key) }
                        }
                        Text(zh ? "参与记录：\(selected.round.betCount)；服务器剩余自然日：\(selected.round.daysLeft)" : "Entries: \(selected.round.betCount); server calendar days remaining: \(selected.round.daysLeft)")
                        Text(zh ? "这是收件箱快照。刷新后轮次消失不代表已由你结算成功。" : "Inbox snapshot. A round disappearing after refresh does not prove you settled it.").font(.footnote)
                    }
                } else { Text(zh ? "这份题面已失效，请返回刷新" : "This question snapshot is no longer current. Return and refresh.") }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(zh ? "完成" : "Done") { model.close(id: selected.id) } } }
            .onAppear { model.didPresent(id: selected.id) }
            .onDisappear { model.close(id: selected.id); model.didDismiss(id: selected.id) }
        }
    }
}
