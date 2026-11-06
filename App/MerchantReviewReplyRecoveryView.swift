import SwiftUI

@MainActor private final class MerchantReviewReplyRecoveryModel: ObservableObject {
    let recovery: MerchantReviewReplyRecovery
    @Published var revision = 0
    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore) {
        recovery = .init(reader: reader, journal: journal)
    }
    func refresh(_ pending: MerchantReviewReplyRecovery.Pending, access: MerchantBusinessAccess) async {
        revision += 1
        await recovery.refresh(pending, access: access)
        revision += 1
    }
    func more() async { revision += 1; await recovery.loadMore(); revision += 1 }
    func invalidate() { recovery.invalidate(); revision += 1 }
}

/// Plain native recovery entry for the existing merchant reviews workspace.
@MainActor struct MerchantReviewReplyRecoverySection: View {
    let reader: any MerchantBusinessReading
    let journal: any MerchantBusinessIntentStore
    let access: MerchantBusinessAccess
    @Environment(\.locale) private var locale
    var body: some View {
        let pending = Result { try MerchantReviewReplyRecovery(reader: reader, journal: journal).pending(access: access) }
        switch pending {
        case .success(let rows) where !rows.isEmpty:
            Section("merchant.reviewRecovery.section") {
                ForEach(rows) { row in
                    NavigationLink {
                        MerchantReviewReplyRecoveryView(reader: reader, journal: journal, access: access, pending: row)
                    } label: {
                        Text("merchant.reviewRecovery.open \(row.reviewID)")
                    }.accessibilityIdentifier("merchant.reviewRecovery.open.\(row.reviewID)")
                    // Versionless historical records keep the existing current-state scan only.
                    if row.intent.reviewOriginal?.version == 1 {
                        NavigationLink {
                            MerchantReviewOriginalRecoveryEntry(reader: reader, journal: journal, access: access, intent: row.intent)
                        } label: {
                            Text(verbatim: MerchantReviewOriginalRecoveryCopy.open(reviewID: row.reviewID, locale: locale))
                        }.accessibilityIdentifier("merchant.reviewOriginalRecovery.open.\(row.reviewID)")
                    }
                }
            }
        case .failure:
            Section {
                Text("merchant.reviewRecovery.listFailed")
            }
        default: EmptyView()
        }
    }
}

@MainActor private struct MerchantReviewReplyRecoveryView: View {
    let reader: any MerchantBusinessReading
    let access: MerchantBusinessAccess
    let pending: MerchantReviewReplyRecovery.Pending
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @StateObject private var model: MerchantReviewReplyRecoveryModel
    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore,
         access: MerchantBusinessAccess, pending: MerchantReviewReplyRecovery.Pending) {
        self.reader = reader; self.access = access; self.pending = pending
        _model = StateObject(wrappedValue: .init(reader: reader, journal: journal))
    }
    var body: some View {
        let recovery = model.recovery
        List {
            Section {
                Text("merchant.reviewRecovery.unknown")
                    .accessibilityIdentifier("merchant.reviewRecovery.unknown")
            }
            if recovery.isBusy { ProgressView() }
            if let result = recovery.result {
                switch result {
                case .current(let row):
                    Section("merchant.reviewRecovery.current") {
                        Text(row.fields.mbText("status") ?? "")
                        if let reply = row.fields.mbText("merchantReply") { Text(verbatim: reply) }
                        else { Text("merchant.reviewRecovery.noReply").foregroundStyle(.secondary) }
                    }.accessibilityIdentifier("merchant.reviewRecovery.current")
                case .notInLoadedPages(let hasMore):
                    Text("merchant.reviewRecovery.notFound")
                    if hasMore {
                        Button("merchant.reviewRecovery.more") { Task { await model.more() } }
                            .disabled(recovery.isBusy).accessibilityIdentifier("merchant.reviewRecovery.more")
                    }
                }
            }
            if recovery.failure != nil {
                Text("merchant.reviewRecovery.failed")
                    .accessibilityIdentifier("merchant.reviewRecovery.error")
            }
            Button("merchant.reviewRecovery.refresh") {
                Task { await model.refresh(pending, access: access) }
            }.disabled(recovery.isBusy || scenePhase != .active)
                .accessibilityIdentifier("merchant.reviewRecovery.refresh")
        }
        .appNavigationTitle("merchant.reviewRecovery.title")
        .task { if scenePhase == .active { await model.refresh(pending, access: access) } }
        .onDisappear { model.invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.invalidate() } }
        .onChange(of: reader.scope) { _, _ in model.invalidate() }
        .onChange(of: reader.authorizationGeneration) { _, _ in model.invalidate() }
    }
}

