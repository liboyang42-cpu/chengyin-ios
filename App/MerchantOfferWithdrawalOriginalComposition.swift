import Foundation
import SwiftUI

/// A single factory owns the exact EXISTING legacy lock URL. It does not discover
/// unknown roots or infer a grant from a role label. Production approvals default nil.
@MainActor final class MerchantOfferWithdrawalOriginalComposition {
    struct Identity: Equatable {
        let actorID: Int
        let merchantID: Int
        let ownerID: Int
        let namespace: String
        let epoch: UInt64
    }
    let storageNamespace: String
    let store: MerchantOfferWithdrawalUnifiedStore
    let journal: MerchantOfferWithdrawalOriginalJournal
    init(legacyLockURL: URL, storageNamespace: String, historicalRoots: [URL] = [], compatibilityApproved: @escaping () -> Bool = { false }) {
        self.storageNamespace = storageNamespace
        store = MerchantOfferWithdrawalUnifiedStore(url: legacyLockURL)
        journal = MerchantOfferWithdrawalOriginalJournal(store: store, historicalRoots: historicalRoots, compatibilityApproved: compatibilityApproved)
    }
    /// Only an independently verified original read grant may mount this recovery view.
    /// No current offer row is needed; the saved identity supplies the original offer/UUID.
    func recovery(api: APIConfiguration, transport: any HTTPTransport, identity: Identity,
                  token: @escaping () -> String?, current: @escaping () -> Identity?,
                  readApproved: @escaping () -> Bool = { false },
                  authorize: @escaping () async throws -> Void,
                  unauthorized: @escaping () -> Void) -> AnyView {
        guard identity.namespace == storageNamespace else { return AnyView(Text("原存储身份不匹配，保留旧锁。")) }
        return AnyView(MerchantOfferWithdrawalOriginalRecoveryView(journal: journal, identity: identity,
            realm: api.baseURL.absoluteString, current: { current() == identity && readApproved() }, authorize: authorize,
            makeFlow: { [journal] p in
                guard current() == identity, readApproved(), p.accountID == identity.actorID,
                      p.merchantID == identity.merchantID, p.namespace == identity.namespace,
                      p.realm == api.baseURL.absoluteString else { return nil }
                return MerchantOfferWithdrawalOriginalFlow(api: api, transport: transport, journal: journal,
                    actorID: identity.actorID, merchantID: identity.merchantID, ownerID: identity.ownerID,
                    offerID: p.offerID, namespace: identity.namespace, token: token,
                    current: { current() == identity && readApproved() },
                    // Recovery host has no write grant, even after an original result is acknowledged.
                    allowed: { readApproved() && [MerchantOfferWithdrawalOriginalFlow.base + "current", MerchantOfferWithdrawalOriginalFlow.base + "result"].contains($0) },
                    authorize: authorize, unauthorized: unauthorized)
            }))
    }
}

@MainActor private struct MerchantOfferWithdrawalOriginalRecoveryView: View {
    let journal: MerchantOfferWithdrawalOriginalJournal
    let identity: MerchantOfferWithdrawalOriginalComposition.Identity
    let realm: String
    let current: () -> Bool
    let authorize: () async throws -> Void
    let makeFlow: (MerchantOfferWithdrawalOriginalPending) -> MerchantOfferWithdrawalOriginalFlow?
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var records: [MerchantOfferWithdrawalOriginalPending] = []
    @State private var issue: String?
    @State private var generation = UUID()
    @State private var activeFlow: MerchantOfferWithdrawalOriginalFlow?
    var body: some View {
        List {
            Text("只读取本人持久原请求。旧锁没有 UUID 时仍为 UNKNOWN；不重新发送退出。")
            if let issue { Text(issue) }
            if current() && scenePhase == .active {
                ForEach(records, id: \.requestID) { p in
                    Button("原供给 #\(p.offerID) · \(p.requestID.uuidString)") {
                        activeFlow?.invalidate(); activeFlow = makeFlow(p)
                    }
                }
                Button("重新核对本地原请求") { generation = UUID() }
            } else { Text("当前身份或读取授权未确认。") }
        }
        .onAppear { visible = true; generation = UUID() }
        .task(id: generation) { await load() }
        .sheet(isPresented: Binding(get: { activeFlow != nil && current() }, set: { if !$0 { activeFlow?.invalidate(); activeFlow = nil } })) {
            if let activeFlow, current() { MerchantOfferWithdrawalOriginalView(flow: activeFlow) }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { retire() } }
        .onChange(of: current()) { _, valid in if !valid { retire() } }
        .onDisappear { visible = false; retire() }
    }
    private func retire() {
        activeFlow?.invalidate(); activeFlow = nil; records = []; issue = nil; generation = UUID()
    }
    private func load() async {
        let stamp = generation; records = []; issue = nil
        guard visible, current(), scenePhase == .active else { return }
        do {
            try await authorize()
            guard !Task.isCancelled, generation == stamp, visible, current(), scenePhase == .active else { return }
            records = try journal.entries(account: identity.actorID, merchant: identity.merchantID, namespace: identity.namespace, realm: realm)
            if records.isEmpty { issue = "本地可识别原 UUID 记录为空，不代表旧 UNKNOWN 锁已解除。" }
        } catch {
            guard !Task.isCancelled, generation == stamp, visible, current(), scenePhase == .active else { return }
            records = []; issue = "原请求读取未确认，持久记录及旧锁保留。"
        }
    }
}
