import SwiftUI
import Observation

/// Only the two existing owned coupon metadata operations, never arbitrary protected work.
enum OwnedCouponReadRequest: Equatable {
    case list(ownerScope: UUID, keyword: String?)
    case detail(OwnedCouponDetailSelection)
    var ownerScope: UUID {
        switch self { case .list(let scope, _): return scope; case .detail(let selection): return selection.ownerScope }
    }
}

@MainActor final class OwnedCouponReadScreenModel: ObservableObject {
    typealias OfferedRead = @MainActor () async -> Void
    private enum Value { case list([AccountCollectionCoupon]), detail(AccountCollectionCoupon) }
    @Published private var revision: UInt64 = 0
    private(set) var presentation: OwnedCouponReadLifetime?
    private(set) var isLoading = false
    private(set) var loadedRequest: OwnedCouponReadRequest?
    private var value: Value?
    private var failure: AccountCollectionIssue?
    private var offer: OwnedCouponReadLifetime?
    private var task: Task<Void, Never>?
    private var foreground = true
    private var presentedRequest: OwnedCouponReadRequest?
    func rows(for request: OwnedCouponReadRequest) -> [AccountCollectionCoupon]? {
        guard loadedRequest == request, case .list(let rows) = value else { return nil }; return rows
    }
    func detail(for request: OwnedCouponReadRequest) -> AccountCollectionCoupon? {
        guard loadedRequest == request, case .detail(let coupon) = value else { return nil }; return coupon
    }
    func issue(for request: OwnedCouponReadRequest) -> AccountCollectionIssue? { loadedRequest == request ? failure : nil }
    func selections(for request: OwnedCouponReadRequest, filter: AccountCollectionCouponFilter) -> [OwnedCouponDetailSelection] {
        guard let accepted = loadedRequest, accepted == request, let rows = rows(for: request) else { return [] }
        return rows.filter { filter.includes($0) }.map { .init(historyID: $0.id, ownerScope: accepted.ownerScope) }
    }
    @discardableResult func beginPresentation(for request: OwnedCouponReadRequest, foreground: Bool) -> OwnedCouponReadLifetime {
        presentation?.invalidate(); cancelPending()
        let permit = OwnedCouponReadLifetime(ownerScope: request.ownerScope); presentation = permit
        presentedRequest = request; self.foreground = foreground
        revision &+= 1; return permit
    }
    /// Close belongs to the offered presentation, including after another page has reopened.
    @discardableResult func endPresentation(presentation permit: OwnedCouponReadLifetime?) -> Bool {
        guard let permit, presentation === permit else { return false }
        permit.invalidate(); presentation = nil; presentedRequest = nil; cancelPending(); return true
    }
    func setForeground(_ active: Bool, request: OwnedCouponReadRequest, reader: any AccountCollectionReading,
                       presentation permit: OwnedCouponReadLifetime?) {
        guard let permit, permit.isActive, presentation === permit, presentedRequest == request else { return }
        foreground = active
        if active { schedule(request: request, reader: reader, presentation: permit) } else { cancelPending() }
    }
    private func cancelPending() {
        offer?.invalidate(); offer = nil; task?.cancel(); task = nil; isLoading = false
        // Keep accepted list rows mounted while their NavigationLink owns a pushed detail.
        // Visibility still requires the exact accepted request/owner. New reads clear them.
        revision &+= 1
    }
    func offerRead(request: OwnedCouponReadRequest, reader: any AccountCollectionReading,
                   presentation permit: OwnedCouponReadLifetime?) -> OfferedRead? {
        guard let permit, permit.isActive, presentation === permit, presentedRequest == request, foreground,
              reader.scope == request.ownerScope else { return nil }
        cancelPending(); value = nil; failure = nil; loadedRequest = nil
        let read = OwnedCouponReadLifetime(ownerScope: request.ownerScope); offer = read
        revision &+= 1
        return { [weak self] in
            guard let self, !Task.isCancelled, permit.isActive, self.presentation === permit,
                  self.foreground, read.isActive, self.offer === read else { return }
            guard reader.isAuthenticated else { self.accept(.login, request: request, read: read); return }
            guard reader.isConfigured else { self.accept(.notConfigured, request: request, read: read); return }
            guard reader.scope == request.ownerScope else { self.accept(.unavailable, request: request, read: read); return }
            self.isLoading = true; self.revision &+= 1
            defer {
                read.invalidate()
                if self.offer === read { self.offer = nil; self.task = nil; self.isLoading = false; self.revision &+= 1 }
            }
            do {
                let result: Value
                switch request {
                case .list(_, let keyword):
                    result = .list(try await reader.ownedCoupons(keyword: keyword, lifetime: read))
                case .detail(let selection):
                    guard selection.historyID > 0 else { throw APIError.invalidRequest }
                    let coupon = try await reader.ownedCoupon(id: selection.historyID, lifetime: read)
                    guard coupon.id == selection.historyID else { throw APIError.malformedResponse }
                    result = .detail(coupon)
                }
                guard !Task.isCancelled, read.isActive, self.offer === read, permit.isActive,
                      self.presentation === permit, reader.scope == request.ownerScope,
                      reader.isAuthenticated, reader.isConfigured else { return }
                self.value = result; self.loadedRequest = request
            } catch {
                guard !Task.isCancelled, !(error is CancellationError), read.isActive, self.offer === read,
                      permit.isActive, self.presentation === permit, reader.scope == request.ownerScope else { return }
                self.failure = AccountCollectionIssue(error); self.loadedRequest = request
            }
        }
    }
    private func accept(_ issue: AccountCollectionIssue, request: OwnedCouponReadRequest, read: OwnedCouponReadLifetime) {
        guard offer === read, read.isActive else { return }
        failure = issue; loadedRequest = request; read.invalidate(); offer = nil; task = nil; isLoading = false; revision &+= 1
    }
    func schedule(request: OwnedCouponReadRequest, reader: any AccountCollectionReading, presentation: OwnedCouponReadLifetime?) {
        guard let action = offerRead(request: request, reader: reader, presentation: presentation) else { return }
        task = Task { await action() }
    }
    func refresh(request: OwnedCouponReadRequest, reader: any AccountCollectionReading, presentation: OwnedCouponReadLifetime?) async {
        guard let action = offerRead(request: request, reader: reader, presentation: presentation) else { return }
        await action()
    }
}

/// A view callback captures this appearance object, never the mutable model's latest permit.
/// It is created before onAppear, so disappearing before the first redraw still closes
/// the permit synchronously installed by onAppear. A closed appearance cannot be reused.
@MainActor @Observable final class OwnedCouponReadViewPresentation {
    private(set) var permit: OwnedCouponReadLifetime?
    private(set) var isClosed = false
    func begin(model: OwnedCouponReadScreenModel, request: OwnedCouponReadRequest,
               foreground: Bool) -> OwnedCouponReadLifetime? {
        guard !isClosed else { return nil }
        if let permit { return model.presentation === permit ? permit : nil }
        let fresh = model.beginPresentation(for: request, foreground: foreground)
        permit = fresh; return fresh
    }
    func replace(model: OwnedCouponReadScreenModel, request: OwnedCouponReadRequest,
                 foreground: Bool) -> OwnedCouponReadLifetime? {
        guard !isClosed, let permit, model.presentation === permit else { return nil }
        let fresh = model.beginPresentation(for: request, foreground: foreground)
        self.permit = fresh; return fresh
    }
    @discardableResult func end(model: OwnedCouponReadScreenModel) -> Bool {
        guard !isClosed else { return false }
        isClosed = true
        return model.endPresentation(presentation: permit)
    }
}

/// Captured from a fresh accepted owned detail, before a deferred code destination.
@MainActor struct OwnedCouponCodeDestination: Identifiable {
    let selection: OwnedCouponDetailSelection
    var id: OwnedCouponDetailSelection.Identity { selection.id }
    func makeCoordinator(reader: any AccountCollectionReading,
                         factory: @MainActor (Int) -> CouponCodeCoordinator) -> CouponCodeCoordinator? {
        guard selection.historyID > 0, reader.scope == selection.ownerScope,
              reader.isAuthenticated, reader.isConfigured else { return nil }
        return factory(selection.historyID)
    }
}
@MainActor struct OwnedCouponCodeDestinationView: View {
    let destination: OwnedCouponCodeDestination
    let reader: any AccountCollectionReading
    @State private var coordinator: CouponCodeCoordinator?
    init(destination: OwnedCouponCodeDestination, reader: any AccountCollectionReading,
         factory: @MainActor (Int) -> CouponCodeCoordinator) {
        self.destination = destination; self.reader = reader
        _coordinator = State(initialValue: destination.makeCoordinator(reader: reader, factory: factory))
    }
    var body: some View {
        if !reader.isAuthenticated { AccountCollectionIssueView(issue: .login) }
        else if !reader.isConfigured { AccountCollectionIssueView(issue: .notConfigured) }
        else if reader.scope != destination.selection.ownerScope {
            Text("couponCode.stale")
        } else if let coordinator { CouponCodeView(model: coordinator) }
        else { AccountCollectionIssueView(issue: .notConfigured) }
    }
}
