import SwiftUI

/// A read-only consumer of the existing independent host grant. No completion API is exposed.
@MainActor struct MerchantReviewOriginalRecoveryAccess {
    let reader: MerchantReviewOriginalReceiptReader
    let isCurrent: () -> Bool
}

@MainActor final class MerchantReviewOriginalRecoveryModel: ObservableObject {
    let intent: MerchantBusinessIntent
    private let reader: any MerchantBusinessReading
    private let journal: any MerchantBusinessIntentStore
    private let access: MerchantBusinessAccess
    private let scope: MerchantBusinessScope?
    private let authorization: UUID?
    private let realm: String?
    private var active = false
    private var capability: MerchantReviewOriginalRecoveryAccess?
    private var value: MerchantReviewOriginalReceipt?
    @Published private(set) var generation = UUID()
    @Published private(set) var busy = false
    @Published private(set) var failure: MerchantBusinessFailure?
    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore,
         access: MerchantBusinessAccess, intent: MerchantBusinessIntent) {
        self.reader = reader; self.journal = journal; self.access = access; self.intent = intent
        scope = reader.scope; authorization = reader.authorizationGeneration; realm = reader.journalRealm
    }
    func belongs(to reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore) -> Bool {
        self.reader === reader && self.journal === journal
    }
    private func validateSource() throws {
        guard reader.isConfigured, let scope, reader.scope == scope,
              reader.scope?.realm.utf8.elementsEqual(scope.realm.utf8) == true,
              let authorization, reader.authorizationGeneration == authorization,
              let realm, reader.journalRealm?.utf8.elementsEqual(realm.utf8) == true,
              intent.realm.utf8.elementsEqual(realm.utf8), intent.accountID == scope.accountID,
              intent.merchantID == access.merchantID else { throw MerchantBusinessFailure.stale }
        try access.require(["merchant:marketing:write"])
        guard intent.reviewOriginal?.version == 1,
              let id = Int(intent.target.dropFirst(7)), id > 0, intent.target == "review:\(id)" else {
            throw MerchantBusinessFailure.unknown
        }
        let rows = try journal.intents()
        guard rows.filter({ $0 == intent }).count == 1,
              rows.filter({ $0.sameTarget(as: intent) }).count == 1,
              rows.filter({ $0.realm == intent.realm && $0.accountID == intent.accountID && $0.requestID == intent.requestID }).count == 1 else {
            throw MerchantBusinessFailure.journal
        }
    }
    var receipt: MerchantReviewOriginalReceipt? {
        guard active, !busy, failure == nil, (try? validateSource()) != nil,
              capability?.isCurrent() == true, value?.intent == intent else { return nil }
        return value
    }
    func begin() -> UUID {
        retire(); active = true; return generation
    }
    func allows(_ ticket: UUID) -> Bool {
        active && generation == ticket && (try? validateSource()) != nil
    }
    func retire() {
        active = false; generation = UUID(); capability = nil; value = nil; busy = false; failure = nil
    }
    func refresh(ticket: UUID,
                 makeAccess: (@escaping () -> Bool) -> MerchantReviewOriginalRecoveryAccess?) async {
        guard active, generation == ticket, !busy, !Task.isCancelled else { return }
        value = nil; capability = nil; failure = nil; busy = true
        defer { if generation == ticket { busy = false } }
        do {
            try validateSource()
            guard let next = makeAccess({ [weak self] in self?.allows(ticket) == true }), next.isCurrent() else {
                throw MerchantBusinessFailure.disabled
            }
            capability = next
            let receipt = try await next.reader.read(intent)
            guard !Task.isCancelled, allows(ticket), next.isCurrent(), receipt.intent == intent else { return }
            value = receipt
        } catch {
            guard active, generation == ticket, !Task.isCancelled else { return }
            value = nil; capability = nil
            failure = error as? MerchantBusinessFailure ?? .unknown
        }
    }
}

/// The existing pending-intent row supplies the original identity, not a current review row.
@MainActor struct MerchantReviewOriginalRecoveryEntry: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @StateObject private var model: MerchantReviewOriginalRecoveryModel
    @State private var retry = UInt64(0)
    private let reader: any MerchantBusinessReading
    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore,
         access: MerchantBusinessAccess, intent: MerchantBusinessIntent) {
        self.reader = reader
        _model = StateObject(wrappedValue: .init(reader: reader, journal: journal, access: access, intent: intent))
    }
    private struct ReadKey: Hashable {
        let revision: String
        let scope: MerchantBusinessScope?
        let authorization: UUID?
        let active: Bool
        let retry: UInt64
    }
    private func copy(_ en: String, _ zh: String) -> String {
        MerchantReviewOriginalRecoveryCopy.localized(en, zh, locale: locale)
    }
    var body: some View {
        let key = ReadKey(revision: session.merchantReviewOriginalRecoveryRevision, scope: reader.scope,
                          authorization: reader.authorizationGeneration, active: scenePhase == .active, retry: retry)
        List {
            Section {
                Text(verbatim: copy("This only reads the original request result. The saved record and lock are kept; no reply is sent again.",
                                    "这里只读取原请求结果，保留原记录和锁，不重新发送回复操作。"))
                LabeledContent(copy("Original target", "原目标"), value: model.intent.target)
                LabeledContent(copy("Original action", "原操作"), value: MerchantReviewOriginalRecoveryCopy.action(model.intent.reviewOriginal?.action, locale: locale))
                LabeledContent(copy("Original request", "原请求"), value: model.intent.requestID)
            }
            if model.busy { ProgressView() }
            if scenePhase == .active, let receipt = model.receipt {
                Section {
                    if receipt.state == .applied {
                        Text(verbatim: copy("The server audit confirms this original action was applied. This is not the current reply text or current visibility. The local lock is still kept.",
                                            "服务端审计确认该原操作已执行。这不是当前回复内容或当前可见状态，本地锁仍保留。"))
                            .accessibilityIdentifier("merchant.reviewOriginalRecovery.applied")
                    } else {
                        Text(verbatim: copy("The original result remains unknown. An absent audit does not mean the action failed, and does not allow retrying it.",
                                            "原结果仍未知。未找到审计不代表操作失败，也不允许据此重发。"))
                            .accessibilityIdentifier("merchant.reviewOriginalRecovery.unknown")
                    }
                }
            }
            if let failure = model.failure {
                Text(verbatim: failure == .disabled
                     ? copy("Original receipt reading has not been independently enabled. The saved record and lock are kept.", "原回执读取尚未获独立启用，原记录和锁保留。")
                     : copy("The original receipt could not be verified. The saved record and lock are kept; you can retry the read.", "暂时无法核实原回执，原记录和锁保留，可重新读取。"))
                    .accessibilityIdentifier("merchant.reviewOriginalRecovery.failed")
            }
            Button(copy("Read original result again", "重新读取原结果")) { retry &+= 1 }
                .disabled(model.busy || scenePhase != .active)
                .accessibilityIdentifier("merchant.reviewOriginalRecovery.retry")
        }
        .navigationTitle(copy("Original reply result", "原回复操作结果"))
        .privacySensitive()
        .task(id: key) {
            guard key.active else { model.retire(); return }
            let ticket = model.begin()
            await model.refresh(ticket: ticket) { current in
                guard let access = session.makeMerchantReviewOriginalRecoveryAccess(isCurrent: current),
                      model.belongs(to: session.merchantBusinessReader, journal: session.merchantBusinessJournal) else { return nil }
                return access
            }
        }
        .onDisappear { model.retire() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.retire() } }
    }
}

enum MerchantReviewOriginalRecoveryCopy {
    static func localized(_ en: String, _ zh: String, locale: Locale) -> String {
        locale.language.languageCode?.identifier == "zh" ? zh : en
    }
    static func open(reviewID: Int, locale: Locale) -> String {
        localized("Read original reply result #\(reviewID)", "读取原回复操作结果 #\(reviewID)", locale: locale)
    }
    static func action(_ action: MerchantReviewReplyOriginal.Action?, locale: Locale) -> String {
        switch action {
        case .reply: return localized("Reply", "回复", locale: locale)
        case .update: return localized("Update reply", "修改回复", locale: locale)
        case .delete: return localized("Delete reply", "删除回复", locale: locale)
        case nil: return localized("Unknown original action", "原操作未知", locale: locale)
        }
    }
}
