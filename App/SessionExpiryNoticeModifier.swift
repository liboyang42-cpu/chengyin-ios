import SwiftUI

/// Native counterpart of the mini-program's 登录已过期，请重新进入 after a failed silent relogin:
/// one alert on the expiry transition, offering sign-in again or guest browsing.
private struct SessionExpiryNoticeModifier: ViewModifier {
    @ObservedObject var session: AppSession
    let onContinueAsGuest: () -> Void
    @State private var lastAccountID: Int?
    @State private var presented = false
    @State private var signsIn = false

    func body(content: Content) -> some View {
        content
            .onAppear { lastAccountID = session.account?.id }
            .onChange(of: session.account?.id) { _, current in
                if SessionExpiryNotice.shouldPresent(previousAccountID: lastAccountID, currentAccountID: current, errorKey: session.errorKey) {
                    onContinueAsGuest(); presented = true
                }
                lastAccountID = current
            }
            .alert(Text("authEntry.expiry.title", tableName: "AuthEntry"), isPresented: $presented) {
                Button { signsIn = true } label: { Text("authEntry.expiry.signIn", tableName: "AuthEntry") }
                    .accessibilityIdentifier("authEntry.expiry.signIn")
                Button(role: .cancel) {} label: { Text("authEntry.expiry.browse", tableName: "AuthEntry") }
                    .accessibilityIdentifier("authEntry.expiry.browse")
            } message: { Text("authEntry.expiry.message", tableName: "AuthEntry") }
            .sheet(isPresented: $signsIn) { LoginView(intent: .player).environmentObject(session) }
    }
}

extension View {
    func sessionExpiryNotice(session: AppSession, onContinueAsGuest: @escaping () -> Void) -> some View {
        modifier(SessionExpiryNoticeModifier(session: session, onContinueAsGuest: onContinueAsGuest))
    }
}
