import SwiftUI

extension SessionExpiryNoticeContext {
    @MainActor init(session: AppSession) {
        self.init(session: session.authChannelSnapshot, errorKey: session.errorKey)
    }
}

/// Native counterpart of the mini-program's 登录已过期，请重新进入 after a failed silent relogin:
/// one alert on the expiry transition, offering sign-in again or guest browsing.
@MainActor private struct SessionExpiryNoticeModifier: ViewModifier {
    @ObservedObject var session: AppSession
    let onContinueAsGuest: () -> Void
    @State private var presentation = SessionExpiryPresentationState()
    private var current: SessionExpiryNoticeContext { .init(session: session) }

    func body(content: Content) -> some View {
        content
            .onAppear { observe(current) }
            .onChange(of: current) { _, value in observe(value) }
            .background {
                if let value = presentation.active {
                    SessionExpiryPresentationOwner(session: session, presentation: $presentation, value: value)
                        .id(value.id)
                }
            }
    }
    private func observe(_ current: SessionExpiryNoticeContext) {
        if presentation.observe(current) { onContinueAsGuest() }
    }
}

/// Keep this presenter stable when the same prompt advances to sign-in. Every binding
/// callback retains its original UUID, so late dismissal cannot clear a later recovery.
@MainActor private struct SessionExpiryPresentationOwner: View {
    @ObservedObject var session: AppSession
    @Binding var presentation: SessionExpiryPresentationState
    let value: SessionExpiryPrompt
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .alert(Text("authEntry.expiry.title", tableName: "AuthEntry"),
                   isPresented: Binding(get: { presentation.prompt == value }, set: { visible in
                       if !visible { presentation.dismissPrompt(value) }
                   }), presenting: value) { original in
                Button { _ = presentation.beginSignIn(original, current: .init(session: session)) } label: {
                    Text("authEntry.expiry.signIn", tableName: "AuthEntry")
                }.accessibilityIdentifier("authEntry.expiry.signIn")
                Button(role: .cancel) { presentation.dismissPrompt(original) } label: {
                    Text("authEntry.expiry.browse", tableName: "AuthEntry")
                }.accessibilityIdentifier("authEntry.expiry.browse")
            } message: { _ in Text("authEntry.expiry.message", tableName: "AuthEntry") }
            .sheet(isPresented: Binding(get: { presentation.signIn == value }, set: { visible in
                if !visible { presentation.dismissSignIn(value) }
            })) { LoginView(intent: .player).environmentObject(session) }
    }
}

extension View {
    @MainActor func sessionExpiryNotice(session: AppSession, onContinueAsGuest: @escaping () -> Void) -> some View {
        modifier(SessionExpiryNoticeModifier(session: session, onContinueAsGuest: onContinueAsGuest))
    }
}
