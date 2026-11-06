import SwiftUI

/// Independent of current supply lists: missing/deleted rows never hide saved UUIDs.
@MainActor struct MerchantOfferWithdrawalRecoveryEntry: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination: AnyView?
    @State private var generation = UUID()
    @State private var loading = true
    @State private var retry = UInt64(0)
    var body: some View {
        Group {
            if let destination { destination }
            else if loading { ProgressView("核对原请求读取授权…") }
            else {
                VStack(spacing: 12) {
                    Text("原撤回结果读取尚未获独立授权，或当前商家身份未确认。旧锁和原请求保留，不发送撤回。")
                    Button("重新核对读取条件") { retry &+= 1 }
                        .disabled(scenePhase != .active)
                        .accessibilityIdentifier("merchant.offerWithdrawal.originalRecovery.retry")
                }
            }
        }
        .navigationTitle("原供给撤回结果")
        .task(id: session.offerWithdrawalRecoveryEntryRevision + ":" + String(describing: scenePhase) + ":" + String(retry)) {
            let stamp = UUID(); generation = stamp; destination = nil; loading = true
            guard scenePhase == .active else { loading = false; return }
            let revision = session.offerWithdrawalRecoveryEntryRevision
            let next = await session.makeMerchantOfferWithdrawalRecoveryDestination()
            guard !Task.isCancelled, generation == stamp, scenePhase == .active,
                  session.offerWithdrawalRecoveryEntryRevision == revision else { return }
            destination = next; loading = false
        }
        .onDisappear { generation = UUID(); destination = nil }
    }
}
