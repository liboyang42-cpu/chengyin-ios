import SwiftUI

@MainActor protocol MerchantPredictionReading: AnyObject {
    var id: UUID { get }
    var isConfigured: Bool { get }
    var supportsReview: Bool { get }
    func makeReviewService(isCurrent: @escaping () -> Bool) -> MerchantMarketingService?
    func access() async throws -> MerchantAccess
    func inbox(access: MerchantAccess) async throws -> [MerchantPredictionInboxRound]
}
extension MerchantPredictionReading {
    var supportsReview: Bool { false }
    func makeReviewService(isCurrent: @escaping () -> Bool) -> MerchantMarketingService? { nil }
}

@MainActor final class MerchantPredictionReader: MerchantPredictionReading {
    let id = UUID()
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let merchant: MerchantService
    private let predictions: MerchantPredictionReadService
    private let token: String
    private let reviewScope: MerchantMarketingScope?
    private let current: () -> Bool
    private let unauthorized: () -> Void
    private var accepted: MerchantAccess?
    private var generation: UInt64 = 0
    var isConfigured: Bool { current() }
    var supportsReview: Bool { current() && reviewScope != nil }
    init(configuration: APIConfiguration, transport: any HTTPTransport, token: String,
         current: @escaping () -> Bool, unauthorized: @escaping () -> Void, reviewScope: MerchantMarketingScope? = nil) {
        self.configuration = configuration; self.transport = transport
        let cookieFree = CookieFreeTransport(underlying: transport)
        merchant = MerchantService(configuration: configuration, transport: cookieFree)
        predictions = MerchantPredictionReadService(configuration: configuration, transport: cookieFree)
        self.token = token; self.current = current; self.unauthorized = unauthorized; self.reviewScope = reviewScope
    }
    /// Admission and the pushed inbox own separate access generations.
    func isolatedReader() -> MerchantPredictionReader {
        .init(configuration: configuration, transport: transport, token: token, current: current, unauthorized: unauthorized, reviewScope: reviewScope)
    }
    /// Review preparation reuses only the existing read scope. There is no writer,
    /// settlement approval, or replay-store construction on this normal path.
    func makeReviewService(isCurrent: @escaping () -> Bool) -> MerchantMarketingService? {
        guard let reviewScope, current(), isCurrent() else { return nil }
        let valid = { [weak self] in self?.current() == true && isCurrent() }
        return MerchantMarketingService(configuration: configuration,
            transport: CookieFreeTransport(underlying: transport),
            gates: .init(reads: true, insight: false, settlement: false), locks: nil,
            currentSession: { valid() ? reviewScope : nil },
            onUnauthorized: { [weak self] _ in guard valid() else { return }; self?.unauthorized() })
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
    func inbox(access: MerchantAccess) async throws -> [MerchantPredictionInboxRound] {
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
        let round: MerchantPredictionInboxRound
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var rows: [MerchantPredictionInboxRound] = []
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
    func open(_ round: MerchantPredictionInboxRound) {
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
                Label("merchant.predict.title", systemImage: "questionmark.bubble")
            }
            .disabled(!model.canEnter).opacity(model.canEnter ? 1 : 0)
            .frame(height: model.canEnter ? nil : 0).accessibilityHidden(!model.canEnter)
            .accessibilityIdentifier("merchant.prediction.entry")
            if model.phase == .failed {
                Button("action.retry") { Task { await model.load(inbox: false) } }
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
            if !reader.isConfigured {
                ContentUnavailableView("merchant.predict.unavailable", systemImage: "questionmark.bubble")
            }
            else if model.phase == .loading || model.phase == .idle { ProgressView().frame(maxWidth: .infinity) }
            else if model.phase == .denied {
                // Source predict/index.wxml no-permission state.
                ContentUnavailableView {
                    Label { Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.denied.title")) } icon: { Image(systemName: "lock") }
                } description: {
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.denied.body"))
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.predict.denied")
            }
            else if model.phase == .failed {
                ContentUnavailableView {
                    Label { Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.error")) } icon: { Image(systemName: "exclamationmark.triangle") }
                } actions: {
                    Button(MerchantOpsCopy.text("merchantOps.predict.retry")) { Task { await model.load() } }
                }
                .accessibilityIdentifier("merchantOps.predict.error")
            } else if model.phase == .ready {
                if model.rows.isEmpty {
                    // Source empty state has a title only.
                    ContentUnavailableView {
                        Label { Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.empty.title")) } icon: { Image(systemName: "checkmark.circle") }
                    }
                    .accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.predict.empty")
                } else {
                    Section {
                        ForEach(model.rows) { round in
                            Button { model.open(round) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(verbatim: round.nodeName.isEmpty ? appLocalized("merchant.predict.unnamedNode", locale: locale) : round.nodeName).font(.headline)
                                    Text(verbatim: round.question.isEmpty ? "—" : round.question)
                                    MerchantPredictionRoundFacts(round: round)
                                }
                                .foregroundStyle(.primary)
                            }.accessibilityIdentifier("merchant.prediction.round.\(round.id)")
                        }
                    } header: {
                        Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.summary %lld", model.rows.count)).accessibilityIdentifier("merchantOps.predict.summary")
                    }
                }
            }
        }
        .appNavigationTitle("merchant.predict.title")
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
                        Section {
                            Text(verbatim: selected.round.question.isEmpty ? "—" : selected.round.question).font(.headline)
                            Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.round %@", selected.round.playDay))
                                .foregroundStyle(.secondary)
                        }
                        // Answer options. Publishing the answer is not wired in the app, so options are listed without an action.
                        Section {
                            ForEach(selected.round.options) { option in
                                LabeledContent { Text(verbatim: option.label) } label: { Text(verbatim: option.key) }
                                    .accessibilityIdentifier("merchant.prediction.review.option.\(option.key)")
                            }
                        }
                        Section {
                            MerchantPredictionRoundFacts(round: selected.round)
                        }
                    }
                    .navigationTitle(Text(verbatim: selected.round.nodeName.isEmpty ? appLocalized("merchant.predict.unnamedNode", locale: locale) : selected.round.nodeName))
                    .navigationBarTitleDisplayMode(.inline)
                } else {
                    ContentUnavailableView("merchant.predict.stale", systemImage: "arrow.clockwise")
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("action.done") { model.close(id: selected.id) } } }
            .onAppear { model.didPresent(id: selected.id) }
            .onDisappear { model.close(id: selected.id); model.didDismiss(id: selected.id) }
        }
    }
}

@MainActor final class MerchantPredictionReviewPreparationModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, failed, retired }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var review: MerchantPredictionReview?
    @Published private(set) var failure: MerchantMarketingFailure?
    private var generation = UUID()
    private var service: MerchantMarketingService?
    func retire() {
        generation = UUID(); service?.discardReview(); service = nil
        review = nil; failure = nil; phase = .retired
    }
    func prepare(round: MerchantPredictionInboxRound, optionKey: String,
                 reader: any MerchantPredictionReading, isCurrent: @escaping () -> Bool) async {
        retire(); let ticket = generation
        let valid = { [weak self] in self?.generation == ticket && reader.isConfigured && isCurrent() }
        guard !Task.isCancelled, valid(), reader.supportsReview else { return }
        guard let service = reader.makeReviewService(isCurrent: valid), !service.permitsSettlement else {
            phase = .failed; failure = .unavailable; return
        }
        self.service = service; phase = .loading
        do {
            let value = try await service.prepare(round: MerchantPredictionRound(inbox: round), optionKey: optionKey)
            guard !Task.isCancelled, valid() else { if generation == ticket { retire() }; return }
            review = value; phase = .ready
        } catch {
            guard !Task.isCancelled, valid() else { if generation == ticket { retire() }; return }
            failure = (error as? MerchantMarketingFailure) ?? .malformed; phase = .failed
        }
    }
}

/// Source predict/index.wxml card: "{playDay} 那一轮", the deadline badge (red on the last day) and the bet line.
@MainActor struct MerchantPredictionRoundFacts: View {
    let round: MerchantPredictionInboxRound
    var body: some View {
        let facts = MerchantPredictionInboxPresentation(daysLeft: round.daysLeft, betCount: round.betCount, optionCount: round.options.count)
        Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.round %@", round.playDay)).font(.subheadline)
        Group {
            switch facts.deadline {
            case .daysLeft(let days): Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.daysLeft %lld", days)).foregroundStyle(.orange)
            case .lastDay: Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.lastDay")).foregroundStyle(.red)
            }
        }.font(.footnote.bold()).accessibilityIdentifier("merchantOps.predict.deadline.\(round.id)")
        switch facts.bets {
        case .count(let count): Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.bets %lld", count)).font(.footnote)
        case .none: Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.noBets")).font(.footnote)
        }
        Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.options %lld", facts.optionCount)).font(.footnote).foregroundStyle(.secondary)
    }
}
