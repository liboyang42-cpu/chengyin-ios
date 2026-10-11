import SwiftUI

struct MerchantProjectBrowserControls: View {
    let browser: MerchantProjectBrowser
    let canSelect: Bool
    let select: (MerchantProjectBrowserTab) -> Void
    var body: some View {
        Section("merchant.projectBrowser.title") {
            Picker("merchant.projectBrowser.kind", selection: Binding(get: { browser.tab }, set: { select($0) })) {
                ForEach(browser.tabs, id: \.rawValue) { tab in Text(LocalizedStringKey(tab.titleKey)).tag(tab) }
            }.pickerStyle(.segmented).disabled(!canSelect).accessibilityIdentifier("merchant.projectBrowser.tabs")
            LabeledContent("merchant.projectBrowser.loadedCount", value: String(browser.count(browser.tab)))
                .accessibilityIdentifier("merchant.projectBrowser.loadedCount")
            Text("merchant.projectBrowser.loadedOnly").font(.footnote).foregroundStyle(.secondary)
            Text("merchant.projectBrowser.orderHint").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
struct MerchantProjectCardContext: View {
    let project: MerchantProject
    private var facts: MerchantProjectCardFacts { .init(project) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let role = facts.role {
                Text(LocalizedStringKey("merchant.projectBrowser.role." + role.rawValue)).font(.caption)
                    .accessibilityIdentifier("merchant.projectBrowser.role." + project.id)
            }
            if let address = facts.address { Label(address, systemImage: "mappin.and.ellipse").font(.caption) }
            if let pending = facts.pendingVerifications {
                Text("merchant.projectBrowser.pendingCount \(pending)").font(.subheadline).monospacedDigit()
                    .accessibilityIdentifier("merchant.projectBrowser.pending." + project.id)
            }
            if facts.attention {
                Label("merchant.projectBrowser.attention", systemImage: "exclamationmark.circle").font(.caption)
                    .accessibilityIdentifier("merchant.projectBrowser.attention." + project.id)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
