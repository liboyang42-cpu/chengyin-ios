import SwiftUI

/// The exact pending ID is captured when review opens. A later result, dismissal,
/// owner change or disabled authority cannot turn an old confirmation into a send.
@MainActor struct OrdinaryIMSendReceiptRecoveryView: View {
    let clientMessageID: String
    let state: OrdinaryIMReceiptReadState
    let canRead: Bool
    let canRetry: Bool
    let read: () -> Void
    let resend: (String) -> Void
    @State private var reviewedID: String?
    @State private var showingConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            if state == .reading {
                ProgressView { Text("ordinary.receipt.reading", tableName: "OrdinaryIMSendReceipt").font(Theme.Font.body).fixedSize(horizontal: false, vertical: true) }
            } else {
                Text(state == .notFound ? "ordinary.receipt.notFound" : "ordinary.receipt.pending",
                     tableName: "OrdinaryIMSendReceipt").fixedSize(horizontal: false, vertical: true).font(.footnote)
                Button { read() } label: { Text("ordinary.receipt.read", tableName: "OrdinaryIMSendReceipt").font(Theme.Font.button).fixedSize(horizontal: false, vertical: true) }
                    .disabled(!canRead).accessibilityIdentifier("ordinary.receipt.read")
            }
            if state == .notFound {
                Button {
                    guard canRetry else { return }
                    reviewedID = clientMessageID; showingConfirmation = true
                } label: { Text("ordinary.receipt.reviewRetry", tableName: "OrdinaryIMSendReceipt").font(Theme.Font.button).fixedSize(horizontal: false, vertical: true) }
                    .disabled(!canRetry).accessibilityIdentifier("ordinary.receipt.reviewRetry")
            }
        }
        .confirmationDialog(Text("ordinary.receipt.confirmTitle", tableName: "OrdinaryIMSendReceipt"),
                            isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button {
                guard canRetry, state == .notFound, let reviewedID, reviewedID == clientMessageID else { return }
                self.reviewedID = nil; resend(reviewedID)
            } label: { Text("ordinary.receipt.confirm", tableName: "OrdinaryIMSendReceipt") }
            Button(role: .cancel) { reviewedID = nil } label: { Text("ordinary.receipt.cancel", tableName: "OrdinaryIMSendReceipt") }
        } message: { Text("ordinary.receipt.confirmHint", tableName: "OrdinaryIMSendReceipt") }
        .onChange(of: clientMessageID) { _, _ in clear() }
        .onChange(of: canRetry) { _, allowed in if !allowed { clear() } }
        .onChange(of: state) { _, state in if state != .notFound { clear() } }
        .onDisappear { clear() }
    }
    private func clear() { reviewedID = nil; showingConfirmation = false }
}
