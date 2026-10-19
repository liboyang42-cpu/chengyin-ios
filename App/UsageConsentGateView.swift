import SwiftUI

/// UserDefaults holds only the agreed document versions and pending request IDs, never tokens.
final class UserDefaultsUsageConsentStorage: UsageConsentStorage {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    func set(_ value: Data?, forKey key: String) { defaults.set(value, forKey: key) }
}

enum UsageConsentEnvironment {
    /// DEBUG launches that carry any argument (every UI test does) start with consent treated as
    /// given in memory, so existing entry flows stay unchanged; `--uitesting-usage-consent-pending`
    /// exercises the real gate with isolated storage. Plain launches and Release use UserDefaults.
    static var policy: UsageConsentPolicy {
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitesting-usage-consent-pending") { return UsageConsentPolicy(storage: UsageConsentFixtureStorage.pending) }
        if args.count > 1 { return UsageConsentPolicy(storage: UsageConsentFixtureStorage.granted) }
#endif
        return UsageConsentPolicy(storage: UserDefaultsUsageConsentStorage())
    }
}

#if DEBUG
/// Per-process memory only, so UI tests never read or write the real stored choice.
enum UsageConsentFixtureStorage {
    static let pending = MemoryUsageConsentStorage()
    static let granted: MemoryUsageConsentStorage = {
        let storage = MemoryUsageConsentStorage(); try? UsageConsentPolicy(storage: storage).agree(agreementChecked: true); return storage
    }()
}

final class MemoryUsageConsentStorage: UsageConsentStorage {
    private var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ value: Data?, forKey key: String) { values[key] = value }
}
#endif

/// Mini-program components/cy/privacy-gate. The sheet cannot be swiped away while a decision is pending.
struct UsageConsentGateView: View {
    let market: RegionalMarket?
    let onAgree: () -> Void
    let onDecline: () -> Void
    @State private var checked = false
    @State private var showsCheckRequired = false
    @State private var document: AuthEntryLegalSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("authEntry.gate.body", tableName: "AuthEntry")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("authEntry.gate.body")
                    Button { document = AuthEntryLegalSheet(type: .privacyPolicy) } label: { Text("authEntry.gate.openPrivacyGuide", tableName: "AuthEntry") }
                        .accessibilityIdentifier("authEntry.gate.privacyGuide")
                    Button { document = AuthEntryLegalSheet(type: .userAgreement) } label: { Text("authEntry.gate.openAgreement", tableName: "AuthEntry") }
                        .accessibilityIdentifier("authEntry.gate.agreement")
                    Toggle(isOn: $checked) { Text("authEntry.gate.checkbox", tableName: "AuthEntry") }
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("authEntry.gate.checkbox")
                    if showsCheckRequired && !checked {
                        Text("authEntry.gate.checkRequired", tableName: "AuthEntry").foregroundStyle(.red)
                            .accessibilityIdentifier("authEntry.gate.checkRequired")
                    }
                    HStack(spacing: 12) {
                        Button(action: onDecline) { Text("authEntry.gate.decline", tableName: "AuthEntry").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("authEntry.gate.decline")
                        Button {
                            guard checked else { showsCheckRequired = true; return }
                            onAgree()
                        } label: { Text("authEntry.gate.agree", tableName: "AuthEntry").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!checked)
                            .accessibilityIdentifier("authEntry.gate.agree")
                    }
                    Text("authEntry.gate.localOnly", tableName: "AuthEntry").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle(Text("authEntry.gate.title", tableName: "AuthEntry"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $document) { sheet in
                NavigationStack {
                    SettingsLegalDocumentView(type: sheet.type, market: market, reader: SettingsBundledLegalReader())
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { document = nil } } }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

/// Local wrapper so this file never claims a global Identifiable conformance for a Core type.
struct AuthEntryLegalSheet: Identifiable { let type: SettingsLegalType; var id: String { type.rawValue } }

/// Shown once per launch to a signed-out user who has not agreed to the current versions.
/// Declining keeps guest browsing (mini-program: no wx.login, public lists still load).
private struct UsageConsentLaunchGate: ViewModifier {
    let signedIn: Bool
    let market: RegionalMarket?
    let onDecline: () -> Void
    @State private var presented = false
    @State private var declinedThisLaunch = false
    private let policy = UsageConsentEnvironment.policy

    func body(content: Content) -> some View {
        content
            .onAppear { presented = UsageConsentGateDecision.showAtLaunch(granted: policy.granted, signedIn: signedIn, declinedThisLaunch: declinedThisLaunch) }
            .sheet(isPresented: $presented) {
                UsageConsentGateView(market: market, onAgree: {
                    try? policy.agree(agreementChecked: true); presented = false
                }, onDecline: {
                    policy.decline(); declinedThisLaunch = true; presented = false; onDecline()
                })
            }
    }
}

extension View {
    func usageConsentLaunchGate(signedIn: Bool, market: RegionalMarket?, onDecline: @escaping () -> Void) -> some View {
        modifier(UsageConsentLaunchGate(signedIn: signedIn, market: market, onDecline: onDecline))
    }
}

/// Sign-in surfaces require the current agreement first; reopening the gate is always explicit.
struct UsageConsentSignInRequirement: View {
    let market: RegionalMarket?
    @Binding var granted: Bool
    @State private var presented = false
    private let policy = UsageConsentEnvironment.policy

    var body: some View {
        Section {
            Text("authEntry.gate.requiredForSignIn", tableName: "AuthEntry")
                .accessibilityIdentifier("authEntry.gate.requiredForSignIn")
            Button { presented = true } label: { Text("authEntry.gate.review", tableName: "AuthEntry") }
                .accessibilityIdentifier("authEntry.gate.review")
        }
        .sheet(isPresented: $presented) {
            UsageConsentGateView(market: market, onAgree: {
                try? policy.agree(agreementChecked: true); granted = policy.granted; presented = false
            }, onDecline: { policy.decline(); granted = false; presented = false })
        }
    }
}
