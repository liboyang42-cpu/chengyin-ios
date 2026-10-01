import SwiftUI

struct LoginView: View {
    let intent: RegistrationIntent
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?
    private enum Field { case username, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(intent == .merchant ? LocalizedStringKey("auth.merchantNotice") : LocalizedStringKey("auth.playerNotice"))
                }
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
                    .disabled(!session.isConfigured || session.isWorking || username.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || password.isEmpty)
                    .accessibilityIdentifier("auth.signIn")
                }
                if !session.isConfigured {
                    Section { Label("auth.notConfigured",systemImage:"info.circle") }
                }
                if let key=session.errorKey {
                    Section { Text(LocalizedStringKey(key)).foregroundStyle(.red).accessibilityIdentifier("auth.error") }
                }
                Section { Text("auth.registrationPending").foregroundStyle(.secondary) }
            }
            .navigationTitle("auth.title")
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("action.close") {
                        session.cancelPendingLogin();password="";dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(session.isWorking)
            .onChange(of:session.account?.id) { _,newID in if newID != nil { password="";dismiss() } }
            .onDisappear { password="" }
        }
    }
    private func submit() {
        guard session.isConfigured, !session.isWorking,
              !username.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, !password.isEmpty else { return }
        focusedField=nil
        let name=username, credential=password
        Task { await session.login(username:name,password:credential);password="" }
    }
}
