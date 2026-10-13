import SwiftUI

/// A retained navigation parent may stay appeared across a quick push and Back.
/// Route return supplements a real appearance; it never manufactures visibility.
@MainActor struct WorkshopVisibleRouteReturn {
    private(set) var isVisible = false
    mutating func appear() { isVisible = true }
    mutating func disappear() { isVisible = false }
    func returned(wasEligible: Bool, isEligible: Bool, resume: () -> Void) {
        guard isVisible, !wasEligible, isEligible else { return }
        resume()
    }
}

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
    @State private var routeVisibility = WorkshopVisibleRouteReturn()
    let browser: WorkshopOwnedBrowser
    @State private var navigation: WorkshopOwnedNavigationState
    init(browser: WorkshopOwnedBrowser, navigation: WorkshopOwnedNavigationState? = nil) {
        self.browser = browser; _navigation = State(initialValue: navigation ?? WorkshopOwnedNavigationState(browser: browser))
    }
    var body: some View {
        @Bindable var navigation = navigation
        let displayed = navigation.listAppearance
        let presentation = displayed.permit
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
        // A permit box is not a view identity: retiring it must not remount the list.
        .onAppear { routeVisibility.appear(); navigation.scheduleList(navigation.listViewAppeared(displayed)) }
        .onDisappear { routeVisibility.disappear(); navigation.listViewDisappeared(displayed) }
        .onChange(of: navigation.selection == nil) { wasEligible, isEligible in
            routeVisibility.returned(wasEligible: wasEligible, isEligible: isEligible) {
                guard navigation.selection == nil, displayed.permit == nil else { return }
                navigation.scheduleList(navigation.listViewAppeared(displayed))
            }
        }
        .refreshable { [permit = presentation] in if let action = navigation.offerList(permit) { await action() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigation.scheduleList(presentation) } label: {
                    Label { workshopText("refresh") } icon: { Image(systemName: "arrow.clockwise") }
                }.disabled(browser.phase == .loading || browser.phase == .invalidated)
                    .accessibilityIdentifier("workshopOwned.refresh")
            }
        }
        .navigationDestination(item: navigation.selectionBinding) { selection in
            if navigation.selection?.routeID == selection.routeID {
                WorkshopOwnedDetailView(browser: browser, claimId: selection.id, navigation: navigation,
                    routeID: selection.routeID, visitID: navigation.detailVisitID, appearance: navigation.detailAppearance)
                    .id(navigation.detailVisitID)
            }
        }
    }
}
@MainActor struct WorkshopOwnedDetailView: View {
    @State private var routeVisibility = WorkshopVisibleRouteReturn()
    let navigation: WorkshopOwnedNavigationState
    let browser: WorkshopOwnedBrowser
    let claimId: String
    let routeID: UUID
    let visitID: UUID
    @State private var mount: WorkshopOwnedMountedAppearance
    init(browser: WorkshopOwnedBrowser, claimId: String, navigation: WorkshopOwnedNavigationState,
         routeID: UUID, visitID: UUID, appearance: WorkshopOwnedViewAppearance) {
        self.browser = browser; self.claimId = claimId; self.navigation = navigation
        self.routeID = routeID; self.visitID = visitID
        _mount = State(initialValue: WorkshopOwnedMountedAppearance(appearance: appearance))
    }
    var body: some View {
        @Bindable var navigation = navigation
        // A redraw captures the same cycle; only real hide/appear can adopt the next box.
        let callbacks = mount.callbacks()
        let displayed = mount.cycle.appearance
        let presentation = displayed.permit
        Form {
          if navigation.isCurrentDetailVisit(routeID: routeID, visitID: visitID) {
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
        }
        .modifier(WorkshopOwnedNavigationTitle(key: "detail"))
        // Only a real navigation visit changes identity; manual permit retirement does not.
        .onAppear {
            guard navigation.isCurrentDetailVisit(routeID: routeID, visitID: visitID) else { return }
            guard let appearing = callbacks.appear(current: navigation.detailAppearance) else { return }
            routeVisibility.appear(); navigation.scheduleDetail(navigation.detailViewAppeared(appearing.appearance, claimId: claimId), claimId: claimId)
        }
        .onDisappear {
            guard let departing = callbacks.disappear() else { return }
            routeVisibility.disappear()
            navigation.detailViewDisappeared(departing.appearance)
        }
        .onChange(of: navigation.selection?.id == claimId && !navigation.showsPackage) { wasEligible, isEligible in
            routeVisibility.returned(wasEligible: wasEligible, isEligible: isEligible) {
                guard navigation.isCurrentDetailVisit(routeID: routeID, visitID: visitID),
                      navigation.selection?.id == claimId && !navigation.showsPackage, displayed.permit == nil else { return }
                navigation.scheduleDetail(navigation.detailViewAppeared(displayed, claimId: claimId), claimId: claimId)
            }
        }
        .refreshable { [permit = presentation] in if let action = navigation.offerDetail(permit, claimId: claimId) { await action() } }
        .navigationDestination(item: navigation.packageBinding(detailRouteID: routeID, visitID: visitID)) { route in
            if navigation.isCurrentPackageVisit(route), let packageBrowser = browser.packageBrowser {
                WorkshopOwnedPackageView(browser: packageBrowser, claimId: route.claimId, navigation: navigation,
                    route: route, appearance: navigation.packageAppearance).id(route.id)
            }
        }
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
