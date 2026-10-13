import Foundation
import Observation
import SwiftUI

/// One navigation stack's visible-screen permits. Only appearance callbacks issue permits;
/// row/package actions revoke the departing screen synchronously, before pushing navigation.
@MainActor @Observable final class WorkshopOwnedNavigationState {
    struct Selection: Hashable, Identifiable {
        let id: String
        // Business claim identity is stable; a new navigation occurrence is not.
        let routeID = UUID()
    }
    struct PackageRoute: Hashable, Identifiable {
        let id: UUID
        let detailRouteID: UUID
        let claimId: String
    }
    private(set) var detailVisitID = UUID()
    private(set) var packageRoute: PackageRoute?
    var selectionBinding: Binding<Selection?> {
        let expected = selection
        return .init(get: { [weak self] in
            guard let self, self.selection == expected else { return nil }
            return expected
        }, set: { [weak self] value in
            guard let self, value == nil, let expected, self.selection == expected else { return }
            self.selection = nil
        })
    }
    func packageBinding(detailRouteID: UUID, visitID: UUID) -> Binding<PackageRoute?> {
        let expected = packageRoute
        return .init(get: { [weak self] in
            guard let self, self.isCurrentDetailVisit(routeID: detailRouteID, visitID: visitID),
                  let expected, self.isCurrentPackageVisit(expected) else { return nil }
            return expected
        }, set: { [weak self] value in
            guard let self, value == nil,
                  self.isCurrentDetailVisit(routeID: detailRouteID, visitID: visitID),
                  let expected, self.isCurrentPackageVisit(expected) else { return }
            self.showsPackage = false
        })
    }
    func isCurrentDetailVisit(routeID: UUID, visitID: UUID) -> Bool {
        selection?.routeID == routeID && detailVisitID == visitID
    }
    func isCurrentPackageVisit(_ route: PackageRoute) -> Bool {
        showsPackage && selection?.routeID == route.detailRouteID && packageRoute == route
    }
#if DEBUG
    enum SyntheticEvent: String {
        case listAppear, listAppearReturned, listDisappear, listDisappearReturned
        case detailAppear, detailAppearReturned, detailDisappear, detailDisappearReturned
        case packageAppear, packageAppearReturned, packageDisappear, packageDisappearReturned
        case selectionChanged, packageRouteChanged
    }
    struct SyntheticSnapshot {
        let event: SyntheticEvent
        let currentAppearance: Bool
        let displayedAppeared: Bool
        let displayedClosed: Bool
        let displayedLive: Bool
        let currentAppeared: Bool
        let currentClosed: Bool
        let eligible: Bool
        let list: Bool
        let detail: Bool
        let package: Bool
        let selected: Bool
        let showsPackage: Bool
    }
    @ObservationIgnored var syntheticTrace: ((SyntheticSnapshot) -> Void)? = nil
    @ObservationIgnored private var syntheticTraceCount = 0
    private func traceSynthetic(_ event: SyntheticEvent, displayed: WorkshopOwnedViewAppearance) {
        // A sealed hosted fixture opts in. Only bounded lifecycle booleans, never content or IDs.
        guard let syntheticTrace, syntheticTraceCount < 48 else { return }
        syntheticTraceCount += 1
        let current: WorkshopOwnedViewAppearance
        let eligible: Bool
        switch event {
        case .detailAppear, .detailAppearReturned, .detailDisappear, .detailDisappearReturned, .packageRouteChanged:
            current = detailAppearance; eligible = selection != nil && !showsPackage
        case .packageAppear, .packageAppearReturned, .packageDisappear, .packageDisappearReturned:
            current = packageAppearance; eligible = selection != nil && showsPackage
        default:
            current = listAppearance; eligible = selection == nil
        }
        syntheticTrace(.init(event: event, currentAppearance: current === displayed,
            displayedAppeared: displayed.syntheticAppeared, displayedClosed: displayed.syntheticClosed,
            displayedLive: displayed.permit?.isLive == true,
            currentAppeared: current.syntheticAppeared, currentClosed: current.syntheticClosed,
            eligible: eligible, list: listPermit != nil, detail: detailPermit != nil,
            package: packagePermit != nil, selected: selection != nil, showsPackage: showsPackage))
    }
#endif
    var selection: Selection? {
        willSet {
            guard selection != newValue else { return }
            detailVisitID = UUID(); packageRoute = nil
            // Back/selection bindings retire work before delayed animation callbacks.
            if let permit = listPermit { browser.leaveList(permit, closing: false) }
            listTask?.cancel(); listTask = nil; listPermit = nil
            listAppearance = WorkshopOwnedViewAppearance()
            detailAppearance = WorkshopOwnedViewAppearance()
            packageAppearance = WorkshopOwnedViewAppearance()
            packageTask?.cancel(); packageTask = nil; packagePermit = nil
            detailTask?.cancel(); detailTask = nil; detailPermit = nil
            browser.closeDetail()
            if showsPackage { showsPackage = false }
        }
        didSet {
#if DEBUG
            if oldValue != selection { traceSynthetic(.selectionChanged, displayed: listAppearance) }
#endif
        }
    }
    var showsPackage = false {
        willSet {
            guard showsPackage != newValue else { return }
            if newValue, let selection {
                packageRoute = .init(id: UUID(), detailRouteID: selection.routeID, claimId: selection.id)
            } else {
                packageRoute = nil
                // Returning from a child is a new visible visit of this same detail route.
                detailVisitID = UUID()
            }
            detailAppearance = WorkshopOwnedViewAppearance()
            packageAppearance = WorkshopOwnedViewAppearance()
            if newValue {
                if let permit = detailPermit { browser.leaveDetail(permit, closing: false) }
                detailTask?.cancel(); detailTask = nil; detailPermit = nil
            }
            if showsPackage && !newValue {
                packageTask?.cancel(); packageTask = nil; packagePermit = nil
                browser.packageBrowser?.close()
            }
        }
        didSet {
#if DEBUG
            if oldValue != showsPackage { traceSynthetic(.packageRouteChanged, displayed: detailAppearance) }
#endif
        }
    }
    private(set) var listAppearance = WorkshopOwnedViewAppearance()
    private(set) var detailAppearance = WorkshopOwnedViewAppearance()
    private(set) var packageAppearance = WorkshopOwnedViewAppearance()
    private(set) var listPermit: WorkshopOwnedPresentationPermit?
    private(set) var detailPermit: WorkshopOwnedPresentationPermit?
    private(set) var packagePermit: WorkshopOwnedPresentationPermit?
    private var listTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var packageTask: Task<Void, Never>?
    private let browser: WorkshopOwnedBrowser
    init(browser: WorkshopOwnedBrowser) { self.browser = browser }
    func listAppeared() -> WorkshopOwnedPresentationPermit? {
        guard selection == nil else { return nil }
        let permit = browser.presentList(); listPermit = permit; return permit
    }
    func listDisappeared(_ presentation: WorkshopOwnedPresentationPermit?) {
        guard let presentation, listPermit === presentation else { return }
        listTask?.cancel(); listTask = nil
        browser.leaveList(presentation, closing: selection == nil); listPermit = nil
    }
    func select(claimId: String, presentation: WorkshopOwnedPresentationPermit?) {
        guard let presentation, listPermit === presentation, presentation.isLive, browser.rows.contains(where: { $0.claimId == claimId }) else { return }
        if let permit = listPermit { browser.leaveList(permit, closing: false) }; listPermit = nil
        listTask?.cancel(); listTask = nil
        selection = .init(id: claimId)
    }
    func detailAppeared(claimId: String) -> WorkshopOwnedPresentationPermit? {
        guard selection?.id == claimId, !showsPackage else { return nil }
        let permit = browser.presentDetail(claimId: claimId); detailPermit = permit; return permit
    }
    func detailDisappeared(_ presentation: WorkshopOwnedPresentationPermit?) {
        guard let presentation, detailPermit === presentation else { return }
        detailTask?.cancel(); detailTask = nil
        browser.leaveDetail(presentation, closing: !showsPackage); detailPermit = nil
    }
    func openPackage(presentation: WorkshopOwnedPresentationPermit?) {
        guard let presentation, detailPermit === presentation, presentation.isLive, let selected = selection?.id,
              browser.packageBrowser != nil, browser.detail?.item?.claimId == selected else { return }
        if let permit = detailPermit { browser.leaveDetail(permit, closing: false) }; detailPermit = nil
        detailTask?.cancel(); detailTask = nil
        showsPackage = true
    }
    func packageAppeared(claimId: String) -> WorkshopOwnedPresentationPermit? {
        guard selection?.id == claimId, showsPackage else { return nil }
        let permit = browser.packageBrowser?.present(claimId: claimId); packagePermit = permit; return permit
    }
    func packageDisappeared(_ presentation: WorkshopOwnedPresentationPermit?) {
        guard let presentation, packagePermit === presentation else { return }
        packageTask?.cancel(); packageTask = nil
        browser.packageBrowser?.leave(presentation); packagePermit = nil
    }
    // The navigation transition creates the next presentation BEFORE SwiftUI returns to it.
    // A cached View's previous box must never be reused if Back arrives before old onDisappear.
    func listViewAppeared(_ displayed: WorkshopOwnedViewAppearance) -> WorkshopOwnedPresentationPermit? {
#if DEBUG
        traceSynthetic(.listAppear, displayed: displayed)
        defer { traceSynthetic(.listAppearReturned, displayed: displayed) }
#endif
        guard listAppearance === displayed, selection == nil else { return nil }
        return displayed.appear { listAppeared() }
    }
    func detailViewAppeared(_ displayed: WorkshopOwnedViewAppearance, claimId: String) -> WorkshopOwnedPresentationPermit? {
#if DEBUG
        traceSynthetic(.detailAppear, displayed: displayed)
        defer { traceSynthetic(.detailAppearReturned, displayed: displayed) }
#endif
        guard detailAppearance === displayed, selection?.id == claimId, !showsPackage else { return nil }
        return displayed.appear { detailAppeared(claimId: claimId) }
    }
    func packageViewAppeared(_ displayed: WorkshopOwnedViewAppearance, claimId: String) -> WorkshopOwnedPresentationPermit? {
#if DEBUG
        traceSynthetic(.packageAppear, displayed: displayed)
        defer { traceSynthetic(.packageAppearReturned, displayed: displayed) }
#endif
        guard packageAppearance === displayed, selection?.id == claimId, showsPackage else { return nil }
        return displayed.appear { packageAppeared(claimId: claimId) }
    }
    func listViewDisappeared(_ displayed: WorkshopOwnedViewAppearance) {
#if DEBUG
        traceSynthetic(.listDisappear, displayed: displayed)
        defer { traceSynthetic(.listDisappearReturned, displayed: displayed) }
#endif
        let wasPresented = displayed.permit.map { listPermit === $0 && $0.isLive } ?? false
        displayed.disappear { listDisappeared($0) }
        // A pushed parent may render its next, inactive box before disappearing.
        // Retire that callback without changing the identity of hidden content again.
        if wasPresented, listAppearance === displayed, selection == nil {
            listAppearance = WorkshopOwnedViewAppearance()
        }
    }
    func detailViewDisappeared(_ displayed: WorkshopOwnedViewAppearance) {
#if DEBUG
        traceSynthetic(.detailDisappear, displayed: displayed)
        defer { traceSynthetic(.detailDisappearReturned, displayed: displayed) }
#endif
        let presentedClaim = displayed.permit.flatMap { detailPermit === $0 && $0.isLive ? $0.claimID : nil }
        displayed.disappear { detailDisappeared($0) }
        if let presentedClaim, detailAppearance === displayed,
           selection?.id == presentedClaim, !showsPackage {
            detailAppearance = WorkshopOwnedViewAppearance()
        }
    }
    func packageViewDisappeared(_ displayed: WorkshopOwnedViewAppearance) {
#if DEBUG
        traceSynthetic(.packageDisappear, displayed: displayed)
        defer { traceSynthetic(.packageDisappearReturned, displayed: displayed) }
#endif
        let presentedClaim = displayed.permit.flatMap { packagePermit === $0 && $0.isLive ? $0.claimID : nil }
        displayed.disappear { packageDisappeared($0) }
        if let presentedClaim, packageAppearance === displayed,
           selection?.id == presentedClaim, showsPackage {
            packageAppearance = WorkshopOwnedViewAppearance()
        }
    }
    typealias ReadAction = @MainActor () async -> Void
    func offerList(_ permit: WorkshopOwnedPresentationPermit?) -> ReadAction? {
        guard let permit, listPermit === permit, let action = permit.offer() else { return nil }
        return { [browser] in await browser.load(action: action) }
    }
    func offerDetail(_ permit: WorkshopOwnedPresentationPermit?, claimId: String) -> ReadAction? {
        guard let permit, detailPermit === permit, permit.claimID == claimId, let action = permit.offer() else { return nil }
        return { [browser] in await browser.open(claimId: claimId, action: action) }
    }
    func offerPackage(_ permit: WorkshopOwnedPresentationPermit?, claimId: String) -> ReadAction? {
        guard let permit, packagePermit === permit, permit.claimID == claimId, let browser = browser.packageBrowser, let action = permit.offer() else { return nil }
        return { await browser.load(claimId: claimId, action: action) }
    }
    func scheduleList(_ permit: WorkshopOwnedPresentationPermit?) {
        guard let action = offerList(permit) else { return }; listTask?.cancel(); listTask = Task { await action() }
    }
    func scheduleDetail(_ permit: WorkshopOwnedPresentationPermit?, claimId: String) {
        guard let action = offerDetail(permit, claimId: claimId) else { return }; detailTask?.cancel(); detailTask = Task { await action() }
    }
    func schedulePackage(_ permit: WorkshopOwnedPresentationPermit?, claimId: String) {
        guard let action = offerPackage(permit, claimId: claimId) else { return }; packageTask?.cancel(); packageTask = Task { await action() }
    }
}

/// A visible View owns this prebuilt box. onAppear installs the permit synchronously,
/// so even a disappearance before SwiftUI redraw retires the correct presentation.
@MainActor @Observable final class WorkshopOwnedViewAppearance {
    private(set) var permit: WorkshopOwnedPresentationPermit?
    private var appeared = false
    private var closed = false
#if DEBUG
    var syntheticAppeared: Bool { appeared }
    var syntheticClosed: Bool { closed }
#endif
    func appear(_ issue: () -> WorkshopOwnedPresentationPermit?) -> WorkshopOwnedPresentationPermit? {
        guard !closed else { return nil }
        if !appeared { appeared = true; permit = issue() }
        return permit
    }
    func disappear(_ retire: (WorkshopOwnedPresentationPermit?) -> Void) {
        guard !closed else { return }
        closed = true; retire(permit)
    }
}


/// A retained View may really leave and return without changing its navigation route.
/// Box replacement is permitted only after its own real disappearance, never after a redraw.
@MainActor @Observable final class WorkshopOwnedMountedAppearance {
    struct Cycle {
        let id: UUID
        let appearance: WorkshopOwnedViewAppearance
    }
    /// One body evaluation's actual appearance/disappearance pair. It may record a new
    /// cycle during onAppear before SwiftUI redraws, without letting another old pair borrow it.
    @MainActor final class Callbacks {
        private weak var owner: WorkshopOwnedMountedAppearance?
        private var captured: Cycle
        init(owner: WorkshopOwnedMountedAppearance, cycle: Cycle) {
            self.owner = owner; captured = cycle
        }
        func appear(current: WorkshopOwnedViewAppearance) -> Cycle? {
            guard let owner, owner.cycle.id == captured.id,
                  owner.cycle.appearance === captured.appearance else { return nil }
            let appearing = owner.appear(current: current)
            captured = appearing
            return appearing
        }
        func disappear() -> Cycle? {
            guard let owner, owner.disappear(captured) else { return nil }
            return captured
        }
    }
    func callbacks() -> Callbacks { Callbacks(owner: self, cycle: cycle) }
    private(set) var cycle: Cycle
    private var isVisible = false
    private var didDisappear = false
    init(appearance: WorkshopOwnedViewAppearance) {
        cycle = .init(id: UUID(), appearance: appearance)
    }
    func appear(current: WorkshopOwnedViewAppearance) -> Cycle {
        if didDisappear {
            cycle = .init(id: UUID(), appearance: current)
            didDisappear = false
        }
        isVisible = true
        return cycle
    }
    @discardableResult func disappear(_ captured: Cycle) -> Bool {
        guard isVisible, cycle.id == captured.id, cycle.appearance === captured.appearance else { return false }
        isVisible = false; didDisappear = true
        return true
    }
}
