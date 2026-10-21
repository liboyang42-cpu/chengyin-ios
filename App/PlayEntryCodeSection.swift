import SwiftUI

/// Where the play page can show the ticket entry code (mini-program `openEntryQr`).
/// `registrationID` is only present when play was opened from the ticket wallet.
struct PlayEntryCodeContext {
    let registrationID: Int?
    /// 去票夹; nil hides the button.
    var openTicketWallet: (() -> Void)?
}

/// 入场码 row. Reuses the existing approval-gated `VerificationCodeView` (`api/verify/dyncode/issue`);
/// without a registration it explains 从票夹进入才能出示入场码 instead of guessing a ticket.
@MainActor struct PlayEntryCodeSection: View {
    let context: PlayEntryCodeContext
    @Environment(\.verificationCodeFactory) private var codeFactory
    @State private var explainMissing = false

    var body: some View {
        Section {
            if let registration = context.registrationID, registration > 0 {
                NavigationLink {
                    if let codeFactory {
                        VerificationCodeView(model: codeFactory(.init(kind: .ticket, id: registration)))
                    } else {
                        ContentUnavailableView {
                            Label("verificationCode.ticket.title", systemImage: "ticket")
                        } description: {
                            Text("verificationCode.phase.disabled").accessibilityIdentifier("verificationCode.disabled")
                        }
                    }
                } label: { Label("playx.entryCode.open", systemImage: "qrcode") }
                    .accessibilityIdentifier("playx.entryCode.open")
            } else {
                Button { explainMissing = true } label: { Label("playx.entryCode.open", systemImage: "qrcode") }
                    .accessibilityIdentifier("playx.entryCode.open")
            }
        }
        .alert("playx.entryCode.missing.title", isPresented: $explainMissing) {
            if let open = context.openTicketWallet {
                Button("playx.entryCode.missing.wallet") { open() }
            }
            Button("playx.entryCode.missing.later", role: .cancel) {}
        } message: {
            Text("playx.entryCode.missing.body")
        }
    }
}

#if DEBUG
/// `--play-entry-code-scenario ticket|missing`. The verification-code factory is not injected,
/// so the ticket path shows the disabled state instead of issuing a code.
@MainActor struct PlayEntryCodeFixtureHost: View {
    @State private var walletOpened = false
    private let registrationID: Int?
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--play-entry-code-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "missing"
        registrationID = scenario == "ticket" ? 501 : nil
    }
    var body: some View {
        NavigationStack {
            List {
                PlayEntryCodeSection(context: .init(registrationID: registrationID, openTicketWallet: { walletOpened = true }))
                if walletOpened { Text("playx.entryCode.fixtureWallet").accessibilityIdentifier("playx.entryCode.fixtureWallet") }
            }
        }
        .environment(\.verificationCodeFactory, nil)
    }
}
#endif
