import SwiftUI

struct WorkshopOwnedAccountLink: View {
    let browser: WorkshopOwnedBrowser?
    var body: some View {
        NavigationLink { WorkshopOwnedDestination(browser: browser) } label: {
            Label { workshopText("title") } icon: { Image(systemName: "square.stack.3d.up") }
        }.accessibilityIdentifier("account.workshopOwned")
    }
}
struct WorkshopOwnedDestination: View {
    let browser: WorkshopOwnedBrowser?
    var body: some View {
        Group {
            if let browser { WorkshopOwnedLibraryView(browser: browser).id(browser.identity) }
            else { WorkshopOwnedUnavailableView() }
        }.modifier(WorkshopOwnedNavigationTitle(key: "title"))
    }
}
private struct WorkshopOwnedUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label { workshopText("unavailable.title") } icon: { Image(systemName: "icloud.slash") }
        } description: { workshopText("unavailable.detail") }
            .accessibilityIdentifier("workshopOwned.unavailable")
    }
}
@MainActor struct WorkshopOwnedLibraryView: View {
    let browser: WorkshopOwnedBrowser
    @State private var navigation: WorkshopOwnedNavigationState
    init(browser: WorkshopOwnedBrowser, navigation: WorkshopOwnedNavigationState? = nil) {
        self.browser = browser; _navigation = State(initialValue: navigation ?? WorkshopOwnedNavigationState(browser: browser))
    }
    var body: some View {
        @Bindable var navigation = navigation
        let presentation = navigation.listPermit
        List {
            WorkshopOwnedScopeSection()
            switch browser.phase {
            case .idle, .loading:
                ProgressView { workshopText("loading") }.accessibilityIdentifier("workshopOwned.loading")
            case .notEnabled: WorkshopOwnedUnavailableView()
            case .empty: workshopText("empty").accessibilityIdentifier("workshopOwned.empty")
            case .failed, .invalidated:
                WorkshopOwnedFailureView(issue: browser.issue)
                if browser.phase != .invalidated {
                    Button("action.retry") { navigation.scheduleList(presentation) }.accessibilityIdentifier("workshopOwned.retry")
                }
            case .ready:
                if browser.hasMore { workshopText("hasMore").font(.footnote).fixedSize(horizontal: false, vertical: true) }
                ForEach(browser.rows) { item in
                    Button { navigation.select(claimId: item.id, presentation: presentation) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            workshopText("freeClaim").font(.headline)
                            Text(verbatim: item.claimId).font(.caption).foregroundStyle(.secondary)
                            workshopText("status." + item.status.rawValue)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("workshopOwned.row.\(item.id)")
                }
            }
            if let time = browser.checkedAt {
                Section { Text(verbatim: time) } header: { workshopText("checkedAt") }
            }
        }
        .modifier(WorkshopOwnedNavigationTitle(key: "title"))
        .onAppear { navigation.scheduleList(navigation.listAppeared()) }
        .refreshable { [permit = navigation.listPermit] in if let action = navigation.offerList(permit) { await action() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigation.scheduleList(presentation) } label: {
                    Label { workshopText("refresh") } icon: { Image(systemName: "arrow.clockwise") }
                }.disabled(browser.phase == .loading || browser.phase == .invalidated)
                    .accessibilityIdentifier("workshopOwned.refresh")
            }
        }
        .navigationDestination(item: $navigation.selection) { selection in WorkshopOwnedDetailView(browser: browser, claimId: selection.id, navigation: navigation) }
        .onDisappear { navigation.listDisappeared() }
    }
}
@MainActor struct WorkshopOwnedDetailView: View {
    let navigation: WorkshopOwnedNavigationState
    let browser: WorkshopOwnedBrowser
    let claimId: String
    init(browser: WorkshopOwnedBrowser, claimId: String, navigation: WorkshopOwnedNavigationState) {
        self.browser = browser; self.claimId = claimId; self.navigation = navigation
    }
    var body: some View {
        @Bindable var navigation = navigation
        let presentation = navigation.detailPermit
        Form {
            WorkshopOwnedScopeSection()
            if browser.detailLoading {
                ProgressView { workshopText("loading") }.accessibilityIdentifier("workshopOwned.detailLoading")
            } else if let response = browser.detail {
                if response.metadata.availability == .notEnabled { WorkshopOwnedUnavailableView() }
                else if let item = response.item, item.claimId == claimId {
                    Section {
                        WorkshopOwnedValueRow(key: "claimId", value: item.claimId)
                        workshopText("status." + item.status.rawValue).accessibilityIdentifier("workshopOwned.status")
                        WorkshopOwnedValueRow(key: "acquiredAt", value: item.acquiredAt)
                        WorkshopOwnedValueRow(key: "validUntil", value: item.validUntil)
                        WorkshopOwnedValueRow(key: "checkedAt", value: response.metadata.checkedAt)
                    } header: { workshopText("metadata") }
                    Section {
                        workshopText("publication." + item.publicationStatus.rawValue).fixedSize(horizontal: false, vertical: true)
                    } header: { workshopText("publication") }
                    if browser.packageBrowser != nil {
                        Button { navigation.openPackage(presentation: presentation) } label: { workshopText("package.open") }
                            .accessibilityIdentifier("workshopOwned.package.open")
                    }
                    Section { workshopText("contentUnavailable").fixedSize(horizontal: false, vertical: true) }
                }
            } else if let issue = browser.detailIssue {
                WorkshopOwnedFailureView(issue: issue)
                if issue != .staleSession {
                    Button("action.retry") { navigation.scheduleDetail(presentation, claimId: claimId) }
                        .accessibilityIdentifier("workshopOwned.detailRetry")
                }
            }
        }
        .modifier(WorkshopOwnedNavigationTitle(key: "detail"))
        .onAppear { navigation.scheduleDetail(navigation.detailAppeared(claimId: claimId), claimId: claimId) }
        .refreshable { [permit = navigation.detailPermit] in if let action = navigation.offerDetail(permit, claimId: claimId) { await action() } }
        .navigationDestination(isPresented: $navigation.showsPackage) {
            if let packageBrowser = browser.packageBrowser { WorkshopOwnedPackageView(browser: packageBrowser, claimId: claimId, navigation: navigation) }
        }
        .onDisappear { navigation.detailDisappeared() }
    }
}
private struct WorkshopOwnedScopeSection: View {
    var body: some View {
        Section {
            workshopText("scope").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            workshopText("purchasesUnavailable").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
private struct WorkshopOwnedValueRow: View {
    let key: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            workshopText(key).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value)
        }.fixedSize(horizontal: false, vertical: true)
    }
}
private struct WorkshopOwnedFailureView: View {
    let issue: WorkshopOwnedIssue?
    private var key: String {
        switch issue {
        case .unauthorized, .staleSession: return "error.session"
        case .disabled: return "unavailable.detail"
        case .forbidden: return "error.forbidden"
        case .notFound: return "error.notFound"
        case .invalid, .malformed: return "error.malformed"
        default: return "error.unavailable"
        }
    }
    var body: some View { workshopText(key).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("workshopOwned.error") }
}
private func workshopText(_ key: String) -> Text { Text(LocalizedStringKey("workshopOwned." + key), tableName: "WorkshopOwned") }
private struct WorkshopOwnedNavigationTitle: ViewModifier {
    let key: String
    @Environment(\.locale) private var locale
    func body(content: Content) -> some View {
        content.navigationTitle(String(localized: LocalizedStringResource(
            String.LocalizationValue(stringLiteral: "workshopOwned." + key), table: "WorkshopOwned", locale: locale)))
    }
}
