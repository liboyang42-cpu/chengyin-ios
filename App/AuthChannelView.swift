import SwiftUI

/// Standalone native sheet. The caller owns the coordinator/session bridge and legal
/// document navigation. Missing legal release content is visible, never a hidden code
/// switch that disables all phone functionality. No live endpoint is provided here.
@MainActor
struct AuthChannelView: View {
    @StateObject private var model: AuthChannelModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focus: Field?
    private enum Field { case phone, code }
    private let sessionSnapshot: AuthChannelSessionSnapshot
    private let onOpenAgreement: (() -> Void)?
    private let onOpenPrivacy: (() -> Void)?
    private let legalReleaseContentVerified: Bool

    init(coordinator: AuthChannelCoordinator, sessionSnapshot: AuthChannelSessionSnapshot,
         legalReleaseContentVerified: Bool = false,
         onOpenAgreement: (() -> Void)? = nil, onOpenPrivacy: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: AuthChannelModel(coordinator: coordinator))
        self.sessionSnapshot = sessionSnapshot
        self.legalReleaseContentVerified = legalReleaseContentVerified
        self.onOpenAgreement = onOpenAgreement; self.onOpenPrivacy = onOpenPrivacy
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("auth.channels.phone", text: $model.phone)
                        .keyboardType(.phonePad).textContentType(.telephoneNumber)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .phone)
                        .disabled(model.state.isWorking)
                        .accessibilityIdentifier("auth.channels.phone")
                    TextField("auth.channels.code", text: $model.code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .code)
                        .disabled(model.state.isWorking)
                        .accessibilityIdentifier("auth.channels.code")
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Button { focus = nil; model.sendCode() } label: {
                            HStack {
                                Text(smsButtonKey)
                                Spacer()
                                if model.state.work == .sendingSMS { ProgressView() }
                                else if model.coordinator.smsCooldownRemaining > 0 {
                                    Text(model.coordinator.smsCooldownRemaining, format: .number)
                                        .monospacedDigit().accessibilityLabel(Text("auth.channels.cooldownSeconds"))
                                        .accessibilityValue(Text(model.coordinator.smsCooldownRemaining, format: .number))
                                }
                            }
                        }
                        .disabled(!model.canStart || model.coordinator.smsCooldownRemaining > 0 || !validPhone)
                        .accessibilityIdentifier("auth.channels.sendCode")
                    }
                    Button {
                        focus = nil; model.signIn()
                    } label: {
                        HStack {
                            Text("auth.signIn")
                            Spacer()
                            if model.state.work == .phoneLogin { ProgressView() }
                        }
                    }
                    .disabled(!model.canStart || !validPhone || !validCode)
                    .accessibilityIdentifier("auth.channels.phoneSignIn")
                } header: { Text("auth.channels.phoneTitle") }
                  footer: { Text("auth.channels.codeLifetime") }
                if model.state.smsSent {
                    Section { Label("auth.channels.smsSent", systemImage: "checkmark.circle") }
                }
                if let issue = model.state.issue {
                    Section {
                        Text(LocalizedStringKey(issue.localizationKey))
                            .foregroundStyle(issue == .appleIncomplete ? Color.secondary : Color.red)
                            .accessibilityIdentifier("auth.channels.error")
                    }
                }
                Section {
                    if model.coordinator.appleConfigurationVerified {
                        AuthChannelAppleButton(model: model)
                            .id(colorScheme)
                            .frame(minHeight: 50)
                            .accessibilityIdentifier("auth.channels.appleSignIn")
                        if model.state.work == .appleAuthorization || model.state.work == .appleExchange {
                            ProgressView("auth.channels.appleWorking")
                        }
                    } else {
                        Label("auth.channels.appleNotConfigured", systemImage: "info.circle")
                    }
                }
                if !model.coordinator.isConfigured {
                    Section { Label("auth.notConfigured", systemImage: "info.circle") }
                }
                Section {
                    Text("auth.channels.legalConsent")
                    Button("auth.channels.userAgreement") { focus = nil; onOpenAgreement?() }
                        .disabled(onOpenAgreement == nil)
                        .frame(minHeight: 44)
                    Button("auth.channels.privacyPolicy") { focus = nil; onOpenPrivacy?() }
                        .disabled(onOpenPrivacy == nil)
                        .frame(minHeight: 44)
                    if !legalReleaseContentVerified || onOpenAgreement == nil || onOpenPrivacy == nil {
                        Label("auth.channels.legalPending", systemImage: "exclamationmark.triangle")
                    }
                }
            }
            .navigationTitle("auth.channels.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { model.clear(); dismiss() }
                }
            }
            .onChange(of: model.phone) { _, value in
                let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(11))
                if value != digits { model.phone = digits }
                model.phoneChanged()
            }
            .onChange(of: model.code) { _, value in
                let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                if value != digits { model.code = digits }
            }
            .onChange(of: model.state.signedIn) { _, signedIn in
                if signedIn { model.clear(); dismiss() }
            }
            .onChange(of: sessionSnapshot) { _, _ in model.clear(); dismiss() }
            .onDisappear { model.clear() }
        }
    }
    private var validPhone: Bool { (try? AuthChannelInput.phone(model.phone)) != nil }
    private var validCode: Bool { (try? AuthChannelInput.code(model.code)) != nil }
    private var smsButtonKey: LocalizedStringKey {
        if model.state.work == .sendingSMS { return "auth.channels.sendingCode" }
        if model.state.nextSMSAllowedAt != nil { return "auth.channels.resendCode" }
        return "auth.channels.sendCode"
    }
}
