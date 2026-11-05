import SwiftUI

@MainActor final class NativeBlacklistViewModel: ObservableObject {
    let flow: NativeBlacklistFlow
    init(_ flow: NativeBlacklistFlow) { self.flow = flow; flow.onChange = { [weak self] in self?.objectWillChange.send() } }
}
/// Ordinary owner management, intentionally independent of conversations and numeric peer entry.
@MainActor struct NativeBlacklistView: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @StateObject private var model: NativeBlacklistViewModel
    @State private var settlement: NativeBlacklistCommand?
    @State private var confirmingSettlement = false
    @State private var visit: UUID?
    @State private var visible = false
    init(flow: NativeBlacklistFlow) { _model = StateObject(wrappedValue: NativeBlacklistViewModel(flow)) }
    private var flow: NativeBlacklistFlow { model.flow }
    var body: some View {
        Form {
            Section { text("blacklist.ownerOnly"); text("blacklist.noRestore").font(Theme.Font.label) }
            if flow.busy { ProgressView().accessibilityIdentifier("blacklist.loading") }
            if flow.phase == .closed { text("blacklist.closed").accessibilityIdentifier("blacklist.closed") }
            if let issue = flow.issue { text(issue).foregroundStyle(Theme.Color.textSecondary(in: domain)).accessibilityIdentifier("blacklist.issue") }
            if flow.phase == .failed {
                Button { performPresented { await flow.load() } } label: { text("blacklist.retry") }.disabled(flow.busy).accessibilityIdentifier("blacklist.retry")
            }
            if flow.phase == .ready {
                Section {
                    if flow.items.isEmpty { text("blacklist.empty").accessibilityIdentifier("blacklist.empty") }
                    ForEach(flow.items) { item in
                        VStack(alignment: .leading, spacing: Theme.Space.s2) {
                            Text(verbatim: "\(item.nickname) · #\(item.peerID)").fixedSize(horizontal: false, vertical: true)
                            Button { performPresented { await flow.reviewUnblock(item) } } label: { text("blacklist.review") }
                                .disabled(!flow.canReview).accessibilityIdentifier("blacklist.review.\(item.peerID)")
                        }.accessibilityIdentifier("blacklist.row.\(item.peerID)")
                    }
                    if flow.nextCursor != nil {
                        Button { performPresented { await flow.loadMore() } } label: { text("blacklist.more") }.disabled(flow.busy).accessibilityIdentifier("blacklist.more")
                    }
                }
            }
            if let review = flow.review, let item = flow.selected {
                Section {
                    Text(verbatim: "\(item.nickname) · #\(review.peerID)").accessibilityIdentifier("blacklist.exactPeer")
                    Text(verbatim: "#\(review.expectedBlockID) · \(review.requestID.uuidString)")
                        .font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    text("blacklist.confirmImpact")
                    Button(role: .destructive) { performPresented { await flow.confirm(expected: review) } } label: { text("blacklist.confirm") }
                        .disabled(!flow.canConfirm).accessibilityIdentifier("blacklist.confirm")
                    Button { flow.cancelReview() } label: { text("blacklist.cancel") }.disabled(flow.busy).accessibilityIdentifier("blacklist.cancel")
                }
            }
            if let original = flow.pendingCommand {
                Section {
                    text("blacklist.unknown")
                    Text(verbatim: "#\(original.peerID) · #\(original.expectedBlockID) · \(original.requestID.uuidString)")
                        .font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blacklist.original")
                    Button { performPresented { await flow.recover() } } label: { text("blacklist.recover") }
                        .disabled(!flow.canRecover).accessibilityIdentifier("blacklist.recover")
                    Button { settlement = original; confirmingSettlement = true } label: { text("blacklist.settle") }
                        .disabled(!flow.canSettle).accessibilityIdentifier("blacklist.settle")
                }
            }
            if let result = flow.result {
                Section {
                    text(result.outcome == "APPLIED" ? "blacklist.applied" : "blacklist.rejected").accessibilityIdentifier("blacklist.outcome")
                    Text(verbatim: "#\(result.peerID) · \(result.requestID)")
                        .font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blacklist.resultIdentity")
                    text("blacklist.historical").font(Theme.Font.label)
                    if let current = flow.current {
                        text(current.blocked ? "blacklist.currentBlocked" : "blacklist.currentUnblocked").accessibilityIdentifier("blacklist.current")
                        if let blockID = current.blockID { Text(verbatim: "#\(blockID)").font(Theme.Font.label) }
                    } else { text("blacklist.currentFailure") }
                    Button { performPresented { await flow.retryReadback() } } label: { text("blacklist.refreshCurrent") }.disabled(flow.busy)
                        .accessibilityIdentifier("blacklist.refreshCurrent")
                    Button { performPresented { await flow.load() } } label: { text("blacklist.returnList") }.disabled(flow.busy)
                        .accessibilityIdentifier("blacklist.returnList")
                }
            }
        }
        .formStyle(.grouped)
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .navigationTitle(localized("blacklist.title"))
        .navigationBarTitleDisplayMode(.inline)
        .privacySensitive()
        .accessibilityIdentifier("blacklist.home")
        .onAppear { visible = true; if scenePhase == .active { visit = UUID(); performPresented { await flow.load() } } }
        .onDisappear { visible = false; close() }
        .onChange(of: scenePhase) { _, phase in
            close()
            if phase == .active, visible { visit = UUID(); performPresented { await flow.load() } }
        }
        .onChange(of: flow.isCurrent) { _, current in if !current { close() } }
        .toolbar {
            Button { performPresented { await flow.load() } } label: { Image(systemName: "arrow.clockwise") }
                .disabled(flow.busy || flow.review != nil || flow.pending != nil).accessibilityIdentifier("blacklist.refresh")
        }
        .confirmationDialog(localized("blacklist.settleTitle"), isPresented: $confirmingSettlement, titleVisibility: .visible) {
            Button(localized("blacklist.settleConfirm"), role: .destructive) {
                guard let original = settlement else { return }; settlement = nil
                performPresented { await flow.settleOriginal(confirmed: original) }
            }
            Button(localized("blacklist.cancel"), role: .cancel) { settlement = nil }
        } message: {
            if let original = settlement { Text(verbatim: "#\(original.peerID) · #\(original.expectedBlockID) · \(original.requestID.uuidString)") }
            text("blacklist.settleImpact")
        }
        .tint(Theme.Color.accent(in: domain))
    }
    private func performPresented(_ action: @escaping @MainActor () async -> Void) {
        guard visible, scenePhase == .active, let capturedVisit = visit else { return }
        let capturedFlow = flow
        Task { @MainActor in
            guard visible, scenePhase == .active, visit == capturedVisit, flow === capturedFlow else { return }
            await action()
        }
    }
    private func close() { visit = nil; settlement = nil; confirmingSettlement = false; flow.invalidate() }
    private func text(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "NativeBlacklist") }
    private func localized(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "NativeBlacklist", locale: locale))
    }
}
