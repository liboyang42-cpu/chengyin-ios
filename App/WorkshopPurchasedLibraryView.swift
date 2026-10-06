import SwiftUI

struct WorkshopPurchasedAccountLink: View {
    let browser: WorkshopPurchasedBrowser?
    let makeProfessional: WorkshopPaidProfessionalControllerFactory
    let makeText: WorkshopPaidInstalledTextControllerFactory
    let makeInstall: WorkshopPaidInstallControllerFactory
    init(browser: WorkshopPurchasedBrowser?, makeInstall: @escaping WorkshopPaidInstallControllerFactory = { _ in nil }, makeText: @escaping WorkshopPaidInstalledTextControllerFactory = { _ in nil }, makeProfessional: @escaping WorkshopPaidProfessionalControllerFactory = { _ in nil }) { self.browser = browser; self.makeInstall = makeInstall; self.makeText = makeText; self.makeProfessional = makeProfessional }
    var body: some View {
        NavigationLink {
            if let browser { WorkshopPurchasedLibraryView(browser: browser, makeInstall: makeInstall, makeText: makeText, makeProfessional: makeProfessional).id(browser.identity) }
            else { PurchasedUnavailableView().modifier(PurchasedTitle("title")) }
        } label: { Label { purchasedText("title") } icon: { Image(systemName: "checkmark.seal") } }
            .accessibilityIdentifier("account.workshopPurchased")
    }
}
@MainActor struct WorkshopPurchasedLibraryView: View {
    let browser: WorkshopPurchasedBrowser
    @State private var navigation: WorkshopPurchasedNavigationState
    let makeProfessional: WorkshopPaidProfessionalControllerFactory
    let makeText: WorkshopPaidInstalledTextControllerFactory
    let makeInstall: WorkshopPaidInstallControllerFactory
    init(browser: WorkshopPurchasedBrowser, navigation: WorkshopPurchasedNavigationState? = nil, makeInstall: @escaping WorkshopPaidInstallControllerFactory = { _ in nil }, makeText: @escaping WorkshopPaidInstalledTextControllerFactory = { _ in nil }, makeProfessional: @escaping WorkshopPaidProfessionalControllerFactory = { _ in nil }) {
        self.browser = browser; self.makeInstall = makeInstall; self.makeText = makeText; self.makeProfessional = makeProfessional; _navigation = State(initialValue: navigation ?? WorkshopPurchasedNavigationState(browser: browser))
    }
    var body: some View {
        @Bindable var navigation = navigation
        let displayed = navigation.listAppearance
        let rendered = displayed.permit
        List {
            Section { purchasedText("scope").font(.footnote).fixedSize(horizontal: false, vertical: true) }
            switch browser.phase {
            case .idle, .loading: ProgressView { purchasedText("loading") }
            case .notEnabled: PurchasedUnavailableView()
            case .empty: purchasedText("empty")
            case .failed, .invalidated:
                purchasedText(browser.phase == .invalidated ? "sessionChanged" : "failed")
                if browser.phase != .invalidated { Button { navigation.scheduleList(rendered) } label: { purchasedText("retry") } }
            case .ready:
                ForEach(browser.rows) { item in
                    Button { navigation.select(licenseId: item.id, presentation: rendered) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: item.moduleId).font(.headline)
                            Text(verbatim: item.purchasedVersionId).font(.caption)
                            purchasedText("status." + item.status.rawValue)
                            purchasedText("perpetual").font(.caption)
                        }.fixedSize(horizontal: false, vertical: true)
                    }.accessibilityIdentifier("workshopPurchased.row." + item.id)
                }
                if let cursor = browser.nextCursor {
                    Button { navigation.scheduleList(rendered, before: cursor) } label: { purchasedText("next") }
                }
            }
            if let checkedAt = browser.checkedAt { Section { Text(verbatim: checkedAt) } header: { purchasedText("checkedAt") } }
        }
        .modifier(PurchasedTitle("title"))
        .privacySensitive()
        .onAppear { navigation.scheduleList(navigation.listViewAppeared(displayed)) }
        .onDisappear { navigation.listViewDisappeared(displayed) }
        .refreshable { if let action = navigation.offerList(rendered) { await action() } }
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { navigation.scheduleList(rendered) } label: { Label { purchasedText("refresh") } icon: { Image(systemName: "arrow.clockwise") } }
                .disabled(browser.phase == .loading || browser.phase == .invalidated)
        } }
        .navigationDestination(item: $navigation.selection) { selection in
            WorkshopPurchasedDetailView(browser: browser, licenseId: selection.id, navigation: navigation, makeInstall: makeInstall, makeText: makeText, makeProfessional: makeProfessional).id(selection.id)
        }
    }
}
@MainActor struct WorkshopPurchasedDetailView: View {
    let browser: WorkshopPurchasedBrowser
    let licenseId: String
    let navigation: WorkshopPurchasedNavigationState
    let makeProfessional: WorkshopPaidProfessionalControllerFactory
    let makeText: WorkshopPaidInstalledTextControllerFactory
    let makeInstall: WorkshopPaidInstallControllerFactory
    init(browser: WorkshopPurchasedBrowser, licenseId: String, navigation: WorkshopPurchasedNavigationState, makeInstall: @escaping WorkshopPaidInstallControllerFactory = { _ in nil }, makeText: @escaping WorkshopPaidInstalledTextControllerFactory = { _ in nil }, makeProfessional: @escaping WorkshopPaidProfessionalControllerFactory = { _ in nil }) {
        self.browser = browser; self.licenseId = licenseId; self.navigation = navigation; self.makeInstall = makeInstall; self.makeText = makeText; self.makeProfessional = makeProfessional
    }
    var body: some View {
        let displayed = navigation.detailAppearance
        let rendered = displayed.permit
        Form {
            if browser.detailLoading { ProgressView { purchasedText("loading") } }
            else if let detail = browser.detail, detail.item.id == licenseId {
                let item = detail.item
                Section {
                    PurchasedFact("license", item.licenseId); PurchasedFact("module", item.moduleId)
                    PurchasedFact("version", item.purchasedVersionId); PurchasedFact("contentHash", item.contentHash)
                    purchasedText("status." + item.status.rawValue).accessibilityIdentifier("workshopPurchased.status")
                    PurchasedFact("acquiredAt", item.acquiredAt); PurchasedFact("checkedAt", detail.checkedAt)
                    purchasedText("perpetual").font(.headline)
                    purchasedText("durationScope").fixedSize(horizontal: false, vertical: true)
                } header: { purchasedText("record") }
                Section {
                    PurchasedFact("termsVersion", item.termsVersion); PurchasedFact("termsHash", item.termsHash)
                    PurchasedPolicy("commercialUse", item.commercialUse.rawValue)
                    PurchasedPolicy("adaptation", item.adaptation.rawValue)
                    PurchasedPolicy("translation", item.translation.rawValue)
                    purchasedText("exactVersion"); purchasedText("redistributionProhibited")
                    ForEach(item.allowedRegions, id: \.self) { Text(verbatim: $0) }
                    PurchasedLimit("themeLimit", item.themeLimit); PurchasedLimit("merchantLimit", item.merchantLimit); PurchasedLimit("runLimit", item.runLimit)
                } header: { purchasedText("frozenTerms") }
                Section {
                    purchasedText("purchaseUnavailable").fixedSize(horizontal: false, vertical: true)
                } header: { purchasedText("currentBoundary") }
                WorkshopPaidInstallEntry(item: item, makeController: makeInstall, makeProfessional: makeProfessional, makeText: makeText)
            } else if let issue = browser.detailIssue {
                purchasedText(issue == .staleSession ? "sessionChanged" : issue == .notFound ? "notFound" : "failed")
                if issue != .staleSession { Button { navigation.scheduleDetail(rendered, licenseId: licenseId) } label: { purchasedText("retry") } }
            }
        }
        .modifier(PurchasedTitle("detail"))
        .privacySensitive()
        .onAppear { navigation.scheduleDetail(navigation.detailViewAppeared(displayed, licenseId: licenseId), licenseId: licenseId) }
        .onDisappear { navigation.detailViewDisappeared(displayed) }
        .refreshable { if let action = navigation.offerDetail(rendered, licenseId: licenseId) { await action() } }
    }
}
private struct PurchasedFact: View {
    let key: String, value: String
    init(_ key: String, _ value: String) { self.key = key; self.value = value }
    var body: some View { VStack(alignment: .leading, spacing: 4) { purchasedText(key).font(.caption).foregroundStyle(.secondary); Text(verbatim: value) }.fixedSize(horizontal: false, vertical: true) }
}
private struct PurchasedPolicy: View {
    let key: String, policy: String
    init(_ key: String, _ policy: String) { self.key = key; self.policy = policy }
    var body: some View { VStack(alignment: .leading) { purchasedText(key).font(.caption); purchasedText("policy." + policy) } }
}
private struct PurchasedLimit: View {
    let key: String, value: WorkshopPurchasedItem.Limit
    init(_ key: String, _ value: WorkshopPurchasedItem.Limit) { self.key = key; self.value = value }
    var body: some View { VStack(alignment: .leading) { purchasedText(key).font(.caption); if value.unlimited { purchasedText("explicitUnlimited") } else { Text(verbatim: String(value.maximum)) } } }
}
private struct PurchasedUnavailableView: View {
    var body: some View { ContentUnavailableView { Label { purchasedText("unavailable") } icon: { Image(systemName: "icloud.slash") } } description: { purchasedText("unavailableDetail") } }
}
private struct PurchasedTitle: ViewModifier {
    let key: String
    @Environment(\.locale) private var locale
    init(_ key: String) { self.key = key }
    func body(content: Content) -> some View { content.navigationTitle(String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: "workshopPurchased." + key), table: "WorkshopPurchased", locale: locale))) }
}
private func purchasedText(_ key: String) -> Text { Text(LocalizedStringKey("workshopPurchased." + key), tableName: "WorkshopPurchased") }
