import SwiftUI

/// Source `pages/coop/withdraw`: the retired bank-card form now only explains that withdrawals are handled
/// offline by platform support. The single action opens the configured support contact; nothing is submitted.
@MainActor struct CoopWithdrawNoticeView: View {
    let isSignedIn: Bool
    @State private var showsSupport = false
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("cooperation.withdraw.title").font(.title3.bold())
                    Text("cooperation.withdraw.subtitle").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if isSignedIn {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.text.bubble.right").font(.largeTitle).foregroundStyle(.secondary)
                        Text("cooperation.finance.withdraw").font(.headline)
                        Text("cooperation.withdraw.detail").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                        .accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("cooperation.withdraw.notice")
                }
                Section {
                    Button { showsSupport = true } label: { Text("cooperation.finance.withdraw").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("cooperation.withdraw.contact")
                }
            } else {
                Section { Text("cooperation.login").accessibilityIdentifier("cooperation.withdraw.login") }
            }
        }
        .appNavigationTitle("cooperation.withdraw.title")
        .onChange(of: isSignedIn) { _, signedIn in if !signedIn { showsSupport = false } }
        .sheet(isPresented: $showsSupport) { WithdrawalSupportContactView() }
        .accessibilityIdentifier("cooperation.withdraw")
    }
}

/// Source `pages/coop/withdraw/records`: a compatibility shell that forwards to the bank-card withdrawal
/// records (`subpackageMember/tixianjilu`). Without a composed wallet reader it shows the source's
/// open-failure state with a retry instead of a blank page.
@MainActor struct CoopWithdrawRecordsShell: View {
    let reader: WalletCommerceReader?
    @State private var attempt = 0
    var body: some View {
        Group {
            if let reader {
                WalletWithdrawalsView(reader: reader)
                    .safeAreaInset(edge: .top) {
                        Text("cooperation.withdrawRecords.subtitle").font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 4)
                            .background(.bar)
                    }
                    .id(attempt)
            } else {
                List {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("cooperation.withdrawRecords.failed.title").font(.headline)
                        Text("cooperation.withdrawRecords.failed.detail").font(.footnote).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("cooperation.withdrawRecords.failed")
                    Button("cooperation.refresh") { attempt += 1 }.accessibilityIdentifier("cooperation.withdrawRecords.retry")
                }
            }
        }
        .appNavigationTitle("cooperation.withdrawRecords.title")
        .accessibilityIdentifier("cooperation.withdrawRecords")
    }
}

/// Legacy `pages/coop/withdraw` and `pages/coop/withdraw/records` routes are deep links in the source;
/// natively they hang off the cooperation business section next to profit share details.
@MainActor struct CoopWithdrawEntryLinks: View {
    let isSignedIn: Bool
    @Environment(\.coopWalletReader) private var walletReader
    var body: some View {
        NavigationLink { CoopWithdrawNoticeView(isSignedIn: isSignedIn) } label: { Text("cooperation.withdraw.entry") }
            .accessibilityIdentifier("cooperation.withdraw.open")
        NavigationLink { CoopWithdrawRecordsShell(reader: walletReader) } label: { Text("cooperation.withdrawRecords.title") }
            .accessibilityIdentifier("cooperation.withdrawRecords.open")
    }
}
