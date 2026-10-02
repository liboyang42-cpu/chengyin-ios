import SwiftUI

struct LoginView: View {
    let intent: RegistrationIntent
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var showsOtherSignIn=false
    @FocusState private var focusedField: Field?
    private enum Field { case username, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(intent == .merchant ? LocalizedStringKey("auth.merchantNotice") : LocalizedStringKey("auth.playerNotice"))
                }
                if session.operationalMarket == .china {
                Section("auth.existingAccount") {
                    TextField("auth.username",text:$username)
                        .textContentType(.username).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().submitLabel(.next)
                        .focused($focusedField,equals:.username)
                        .onSubmit { focusedField = .password }
                    SecureField("auth.password",text:$password)
                        .textContentType(.password).submitLabel(.go)
                        .focused($focusedField,equals:.password)
                        .onSubmit { submit() }
                    Button { submit() } label: {
                        HStack {
                            Text("auth.signIn")
                            Spacer()
                            if session.isWorking { ProgressView() }
                        }
                    }
                    .disabled(!session.canUsePassword || session.isWorking || username.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || password.isEmpty)
                    .accessibilityIdentifier("auth.signIn")
                }
                } else { Section { Text("region.usLoginPending").accessibilityIdentifier("region.auth.pending") } }
                if !session.isConfigured {
                    Section { Label("auth.notConfigured",systemImage:"info.circle") }
                }
                if let key=session.errorKey {
                    Section { Text(LocalizedStringKey(key)).foregroundStyle(.red).accessibilityIdentifier("auth.error") }
                }
                if session.operationalMarket == .china {
                    WeChatAppAuthSection(coordinator: session.weChatAuth, context: session.authChannelSnapshot)
                }
                Section {
                    Button("auth.channels.title") { session.weChatAuth.cancel(); password="";showsOtherSignIn=true }
                        .disabled(session.isWorking)
                        .accessibilityIdentifier("auth.otherChannels")
                    Text("auth.registrationPending").foregroundStyle(.secondary)
                }
            }
            .appNavigationTitle("auth.title")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("action.close") {
                        session.cancelPendingLogin();password="";dismiss()
                    }
                }
            }
            .sheet(isPresented:$showsOtherSignIn) {
                AuthChannelView(coordinator:session.authChannels,sessionSnapshot:session.authChannelSnapshot,domesticPhoneVisible:session.supportsDomesticPhoneInput)
            }
            .interactiveDismissDisabled(session.isWorking)
            .onChange(of:session.account?.id) { _,newID in if newID != nil { password="";dismiss() } }
            .onDisappear { password=""; session.weChatAuth.cancel() }
        }
    }
    private func submit() {
        guard session.canUsePassword, !session.isWorking,
              !username.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, !password.isEmpty else { return }
        focusedField=nil
        let name=username, credential=password
        Task { await session.login(username:name,password:credential);password="" }
    }
}
