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

/// M04 presentation only. The original models own eligibility, requests and recovery.
struct MerchantJourneyFormAppearance: ViewModifier {
    @Environment(\.themeDomain) private var domain
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.body)
            .listStyle(.insetGrouped)
            .listSectionSpacing(Theme.Space.s4)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.bgPage(in: domain))
            .tint(Theme.Color.accent(in: domain))
            .preferredColorScheme(domain.colorScheme)
    }
}

struct MerchantJourneyHeading: View {
    let title: String
    let systemImage: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Label { Text(LocalizedStringKey(title)) } icon: { Image(systemName: systemImage) }
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(LocalizedStringKey(detail)).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.s2)
    }
}

struct MerchantJourneyNotice: View {
    @Environment(\.themeDomain) private var domain
    let text: String
    var systemImage = "exclamationmark.circle"
    var body: some View {
        Label { Text(verbatim: text).fixedSize(horizontal: false, vertical: true) }
            icon: { Image(systemName: systemImage) }
            .font(.callout)
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .padding(Theme.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Color.bgRaised(in: domain), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .accessibilityElement(children: .combine)
    }
}

struct MerchantJourneyResultHeading: View {
    let title: String
    let requestID: String
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            Label { Text(verbatim: title).fixedSize(horizontal: false, vertical: true) }
                icon: { Image(systemName: "doc.text") }
                .font(.headline)
            Text(verbatim: requestID).font(.caption.monospaced()).foregroundStyle(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .contain)
    }
}

struct MerchantJourneyPrimaryAction: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.borderedProminent).controlSize(.large)
            .fixedSize(horizontal: false, vertical: true)
    }
}


/// Read-only facts retain their full original value at every Dynamic Type size.
/// The intrinsic horizontal row falls back to a vertical row before either side truncates.
struct MerchantJourneyFactRow<Value: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringKey
    let value: Value
    init(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.title = title; self.value = value()
    }
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize { vertical }
            else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s3) {
                        Text(title).foregroundStyle(.secondary).fixedSize()
                        Spacer(minLength: Theme.Space.s2)
                        value.fixedSize()
                    }
                    vertical
                }
            }
        }.font(Theme.Font.body)
            .accessibilityElement(children: .contain)
    }
    private var vertical: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            value.fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// These are existing source states, not inferred success or newly granted actions.
struct MerchantProjectStateLabel: View {
    let text: String
    let state: String?
    private var symbol: String {
        switch state {
        case "rejected": "exclamationmark.circle"
        case "pending": "clock"
        case "draft": "doc.text"
        default: "circle"
        }
    }
    var body: some View {
        Label { Text(verbatim: text) } icon: { Image(systemName: symbol) }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(state == "rejected" ? Theme.Color.danger(in: .merchant) : Theme.Color.textSecondary(in: .merchant))
            .fixedSize(horizontal: false, vertical: true)
    }
}
