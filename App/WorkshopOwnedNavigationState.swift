import Foundation
import Observation

/// One navigation stack's visible-screen permits. Only appearance callbacks issue permits;
/// row/package actions revoke the departing screen synchronously, before pushing navigation.
@MainActor @Observable final class WorkshopOwnedNavigationState {
    struct Selection: Hashable, Identifiable { let id: String }
#if DEBUG
    enum SyntheticEvent: String { case listAppear, listAppearReturned, listDisappear, listDisappearReturned }
    struct SyntheticSnapshot {
        let event: SyntheticEvent
        let currentAppearance: Bool
        let displayedLive: Bool
        let list: Bool
        let detail: Bool
        let package: Bool
        let selected: Bool
        let showsPackage: Bool
    }
    @ObservationIgnored var syntheticTrace: ((SyntheticSnapshot) -> Void)? = nil
    @ObservationIgnored private var syntheticTraceCount = 0
    private func traceSynthetic(_ event: SyntheticEvent, displayed: WorkshopOwnedViewAppearance) {
        // At most twelve new events plus the existing twelve fixed test stages.
        guard let syntheticTrace, syntheticTraceCount < 12 else { return }
        syntheticTraceCount += 1
        syntheticTrace(.init(event: event, currentAppearance: listAppearance === displayed,
            displayedLive: displayed.permit?.isLive == true, list: listPermit != nil,
            detail: detailPermit != nil, package: packagePermit != nil,
            selected: selection != nil, showsPackage: showsPackage))
    }
#endif
    var selection: Selection? {
        willSet {
            guard selection != newValue else { return }
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
    }
    var showsPackage = false {
        willSet {
            guard showsPackage != newValue else { return }
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
        guard detailAppearance === displayed, selection?.id == claimId, !showsPackage else { return nil }
        return displayed.appear { detailAppeared(claimId: claimId) }
    }
    func packageViewAppeared(_ displayed: WorkshopOwnedViewAppearance, claimId: String) -> WorkshopOwnedPresentationPermit? {
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
        let presentedClaim = displayed.permit.flatMap { detailPermit === $0 && $0.isLive ? $0.claimID : nil }
        displayed.disappear { detailDisappeared($0) }
        if let presentedClaim, detailAppearance === displayed,
           selection?.id == presentedClaim, !showsPackage {
            detailAppearance = WorkshopOwnedViewAppearance()
        }
    }
    func packageViewDisappeared(_ displayed: WorkshopOwnedViewAppearance) {
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
