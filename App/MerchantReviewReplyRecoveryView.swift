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
            Section(reviewRecoveryCopy(locale, "Unconfirmed review operations", "待确认的点评操作")) {
                ForEach(rows) { row in
                    NavigationLink {
                        MerchantReviewReplyRecoveryView(reader: reader, journal: journal, access: access, pending: row)
                    } label: {
                        Text(reviewRecoveryCopy(locale, "Read current review #\(row.reviewID)", "回读点评 #\(row.reviewID)"))
                    }.accessibilityIdentifier("merchant.reviewRecovery.open.\(row.reviewID)")
                }
            }
        case .failure:
            Section {
                Text(reviewRecoveryCopy(locale, "Pending operations could not be read. Refresh to try again.", "无法读取待确认操作，请刷新重试。"))
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
                Text(reviewRecoveryCopy(locale, "The original operation is still unconfirmed. Reading current server state does not confirm or retry that operation.", "原操作结果仍待确认。回读服务端现状不会确认或重试原操作。"))
                    .accessibilityIdentifier("merchant.reviewRecovery.unknown")
                Text("#\(pending.reviewID)")
            }
            if recovery.isBusy { ProgressView() }
            if let result = recovery.result {
                switch result {
                case .current(let row):
                    Section(reviewRecoveryCopy(locale, "Current server state", "服务端当前状态")) {
                        Text(row.fields.mbText("status") ?? "")
                        if let version = row.fields["version"]?.integer {
                            Text(reviewRecoveryCopy(locale, "Version: \(version)", "版本：\(version)"))
                        }
                        if let reply = row.fields.mbText("merchantReply") { Text(verbatim: reply) }
                        else { Text(reviewRecoveryCopy(locale, "No public reply is currently shown.", "当前未展示公开回复。")) }
                    }.accessibilityIdentifier("merchant.reviewRecovery.current")
                case .notInLoadedPages(let hasMore):
                    Text(reviewRecoveryCopy(locale, "The review was not found in the pages read. This does not prove the operation failed or the review was deleted.", "已回读页面中未找到该点评，不能据此认定操作失败或点评已删除。"))
                    if hasMore {
                        Button(reviewRecoveryCopy(locale, "Read more pages", "继续回读")) { Task { await model.more() } }
                            .disabled(recovery.isBusy).accessibilityIdentifier("merchant.reviewRecovery.more")
                    }
                }
            }
            if recovery.failure != nil {
                Text(reviewRecoveryCopy(locale, "The read could not be completed. Check the current account and store, then try again.", "回读未完成，请确认当前账号与门店后重试。"))
                    .accessibilityIdentifier("merchant.reviewRecovery.error")
            }
            Button(reviewRecoveryCopy(locale, "Refresh current state", "刷新当前状态")) {
                Task { await model.refresh(pending, access: access) }
            }.disabled(recovery.isBusy || scenePhase != .active)
                .accessibilityIdentifier("merchant.reviewRecovery.refresh")
        }
        .navigationTitle(reviewRecoveryCopy(locale, "Review recovery", "点评结果回读"))
        .task { if scenePhase == .active { await model.refresh(pending, access: access) } }
        .onDisappear { model.invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.invalidate() } }
        .onChange(of: reader.scope) { _, _ in model.invalidate() }
        .onChange(of: reader.authorizationGeneration) { _, _ in model.invalidate() }
    }
}

private func reviewRecoveryCopy(_ locale: Locale, _ english: String, _ chinese: String) -> String {
    locale.language.languageCode?.identifier == "zh" ? chinese : english
}
