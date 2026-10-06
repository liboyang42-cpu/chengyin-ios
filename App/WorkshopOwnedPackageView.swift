import SwiftUI

@MainActor struct WorkshopOwnedPackageView: View {
    let navigation: WorkshopOwnedNavigationState
    let browser: WorkshopOwnedPackageBrowser
    let claimId: String
    init(browser: WorkshopOwnedPackageBrowser, claimId: String, navigation: WorkshopOwnedNavigationState) {
        self.browser = browser; self.claimId = claimId; self.navigation = navigation
    }
    var body: some View {
        let displayed = navigation.packageAppearance
        let presentation = displayed.permit
        Form {
            Section { packageText("scope").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            switch browser.phase {
            case .idle, .loading: ProgressView { packageText("loading") }.accessibilityIdentifier("workshopOwned.package.loading")
            case .unavailable: packageText("unavailable").fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("workshopOwned.package.unavailable")
            case .failed, .invalidated:
                packageText(browser.issue == .staleSession ? "sessionChanged" : "error").fixedSize(horizontal: false, vertical: true)
                if browser.phase != .invalidated { Button("action.retry") { navigation.schedulePackage(presentation, claimId: claimId) } }
            case .ready:
                if let value = browser.value, value.claimId == claimId, let info = value.packageInfo {
                    Section {
                        PackageValueRow(key: "version", value: info.versionLabel)
                        PackageValueRow(key: "schema", value: String(info.schemaVersion))
                        PackageValueRow(key: "contentHash", value: info.contentHash)
                        PackageValueRow(key: "termsVersion", value: info.termsVersion)
                        PackageValueRow(key: "termsHash", value: info.termsHash)
                        PackageValueRow(key: "validUntil", value: info.validUntil)
                        PackageValueRow(key: "checkedAt", value: value.checkedAt)
                    } header: { packageText("snapshot") }
                    Section {
                        PackagePolicyRow(key: "commercialUse", value: info.commercialUse.rawValue)
                        PackagePolicyRow(key: "adaptation", value: info.adaptation.rawValue)
                        PackagePolicyRow(key: "translation", value: info.translation.rawValue)
                        packageText("exactVersionOnly").fixedSize(horizontal: false, vertical: true)
                        packageText("redistributionProhibited").fixedSize(horizontal: false, vertical: true)
                    } header: { packageText("frozenRights") }
                    Section { ForEach(info.allowedRegions, id: \.self) { Text(verbatim: $0) } } header: { packageText("regions") }
                    Section {
                        PackageLimitRow(key: "themeLimit", limit: info.themeLimit)
                        PackageLimitRow(key: "merchantLimit", limit: info.merchantLimit)
                        PackageLimitRow(key: "runLimit", limit: info.runLimit)
                        packageText("limitNotice").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } header: { packageText("limits") }
                    Section {
                        PackageValueRow(key: "bindingCount", value: String(info.requiredBindingCount))
                        packageText("manifestUnavailable").fixedSize(horizontal: false, vertical: true)
                        packageText("editorUnavailable").fixedSize(horizontal: false, vertical: true)
                    } header: { packageText("nextSteps") }
                }
            }
        }
        .modifier(PackageNavigationTitle())
        .onAppear { navigation.schedulePackage(navigation.packageViewAppeared(displayed, claimId: claimId), claimId: claimId) }
        .onDisappear { navigation.packageViewDisappeared(displayed) }
        .refreshable { [permit = presentation] in if let action = navigation.offerPackage(permit, claimId: claimId) { await action() } }
        .id(ObjectIdentifier(displayed))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigation.schedulePackage(presentation, claimId: claimId) } label: {
                    Label { packageText("refresh") } icon: { Image(systemName: "arrow.clockwise") }
                }.disabled(browser.phase == .invalidated).accessibilityIdentifier("workshopOwned.package.refresh")
            }
        }
    }
}
private struct PackageValueRow: View {
    let key: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            packageText(key).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
private struct PackagePolicyRow: View {
    let key: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            packageText(key).font(.caption).foregroundStyle(.secondary)
            packageText("policy." + value)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
private struct PackageLimitRow: View {
    let key: String
    let limit: WorkshopOwnedPackage.Limit
    var body: some View {
        LabeledContent {
            if limit.unlimited { packageText("unlimited") } else { Text(verbatim: String(limit.maximum)) }
        } label: { packageText(key) }
    }
}
private func packageText(_ key: String) -> Text { Text(LocalizedStringKey("workshopOwned.package." + key), tableName: "WorkshopOwned") }
private struct PackageNavigationTitle: ViewModifier {
    @Environment(\.locale) private var locale
    func body(content: Content) -> some View {
        content.navigationTitle(String(localized: LocalizedStringResource("workshopOwned.package.title", table: "WorkshopOwned", locale: locale)))
    }
}
