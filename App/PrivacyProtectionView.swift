import SwiftUI

/// Mini-program pages/privacy (route title 隐私保护): the gate summary, both document links,
/// and this device's agreement state. Signed-in revoke actions (roam location, marketing)
/// stay in Settings › Privacy and location, which already hosts them.
struct PrivacyProtectionView: View {
    let market: RegionalMarket?
    @State private var granted = UsageConsentEnvironment.policy.granted
    @State private var document: AuthEntryLegalSheet?

    var body: some View {
        Form {
            Section { Text("authEntry.gate.body", tableName: "AuthEntry").fixedSize(horizontal: false, vertical: true) }
            Section {
                ForEach(PrivacyGuideSummaryPresentation.defaultItems) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: item.title).font(.subheadline.weight(.medium))
                        Text(verbatim: item.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("privacy.guide.summaryItems")
            Section {
                Button { document = AuthEntryLegalSheet(type: .privacyPolicy) } label: { Text("authEntry.gate.openPrivacyGuide", tableName: "AuthEntry") }
                    .accessibilityIdentifier("authEntry.privacy.guide")
                // The guide text itself is not bundled yet (SettingsSourceLegalCatalog: pendingSourceText).
                Text("authEntry.privacy.guideUnavailable", tableName: "AuthEntry").font(.footnote).foregroundStyle(.secondary)
                Button { document = AuthEntryLegalSheet(type: .userAgreement) } label: { Text("authEntry.gate.openAgreement", tableName: "AuthEntry") }
                    .accessibilityIdentifier("authEntry.privacy.agreement")
            }
            Section {
                LabeledContent {
                    if granted { Text("authEntry.privacy.consentGranted", tableName: "AuthEntry") }
                    else { Text("authEntry.privacy.consentMissing", tableName: "AuthEntry") }
                } label: { Text("authEntry.privacy.consentStatus", tableName: "AuthEntry") }
                    .accessibilityIdentifier("authEntry.privacy.consentStatus")
                Text("authEntry.privacy.manage", tableName: "AuthEntry").font(.footnote).foregroundStyle(.secondary)
            }
            if !granted { UsageConsentSignInRequirement(market: market, granted: $granted) }
        }
        .navigationTitle(Text("authEntry.privacy.title", tableName: "AuthEntry"))
        .sheet(item: $document) { sheet in
            NavigationStack {
                SettingsLegalDocumentView(type: sheet.type, market: market, reader: SettingsBundledLegalReader())
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { document = nil } } }
            }
        }
    }
}
