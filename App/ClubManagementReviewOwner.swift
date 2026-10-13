import SwiftUI
import UIKit

/// Retained by the management journey; a review belongs to one visible detail visit.
@MainActor final class ClubManagementReviewOwner: ObservableObject {
    struct Context: Equatable {
        let clubID: Int
        let identity: ClubReadIdentity?
        let revision: UInt64
        let access: ObjectIdentifier
        let coordinator: ObjectIdentifier
    }
    struct Item: Identifiable, Equatable {
        var id: UUID { confirmation.id }
        let attachment: UUID
        let context: Context
        let confirmation: ClubManagementConfirmation
    }
    @Published private(set) var item: Item?
    @Published private(set) var isPresented = false
    @Published private(set) var attachment: UUID?
    private(set) var context: Context?
    private(set) var visible = false
    private var covered = false
    private var claimed: UUID?

    func appear(_ context: Context) {
        if self.context != context { retire() }
        self.context = context
        if attachment == nil { attachment = UUID() }
        visible = true; covered = false
    }
    func hide(_ attachment: UUID) { if self.attachment == attachment { visible = false } }
    func cover(_ attachment: UUID) {
        guard self.attachment == attachment, item != nil else { return }
        covered = true
    }
    func isAttached(_ attachment: UUID, context: Context, active: Bool) -> Bool {
        active && self.attachment == attachment && self.context == context && (visible || covered)
    }
    func stage(_ confirmation: ClubManagementConfirmation, attachment: UUID, context: Context, active: Bool) -> Bool {
        guard visible, isAttached(attachment, context: context, active: active), item == nil,
              confirmation.clubID == context.clubID, confirmation.identity == context.identity else { return false }
        item = Item(attachment: attachment, context: context, confirmation: confirmation)
        claimed = nil; isPresented = true
        return true
    }
    func current(_ expected: Item, context: Context, active: Bool) -> Bool {
        isPresented && item == expected && isAttached(expected.attachment, context: context, active: active) && context == expected.context
    }
    @discardableResult func cancel(_ expected: Item) -> Bool {
        guard isPresented, item == expected else { return false }
        isPresented = false; claimed = nil
        return true
    }
    func claim(_ expected: Item, context: Context, active: Bool) -> Bool {
        guard current(expected, context: context, active: active), claimed == nil else { return false }
        claimed = expected.id; isPresented = false
        return true
    }
    func dismissed(_ expected: Item) {
        guard item == expected, !isPresented else { return }
        item = nil
    }
    func permitsDispatch(_ expected: Item, context: Context, active: Bool) -> Bool {
        claimed == expected.id && expected.context == context && isAttached(expected.attachment, context: context, active: active)
    }
    func binding(_ expected: Item, context: @escaping () -> Context, active: @escaping () -> Bool,
                 cancelled: @escaping (Item) -> Void) -> Binding<Bool> {
        Binding(get: { self.current(expected, context: context(), active: active()) }, set: { presented in
            guard !presented, self.cancel(expected) else { return }
            cancelled(expected)
        })
    }
    @discardableResult func depart(_ attachment: UUID) -> Bool {
        guard self.attachment == attachment else { return false }
        retire(); return true
    }
    func retire() { item = nil; isPresented = false; attachment = nil; context = nil; visible = false; covered = false; claimed = nil }
}

/// Created only for a non-nil immutable review, outside every lazy row.
@MainActor struct ClubManagementReviewPresentation<Content: View>: View {
    let item: ClubManagementReviewOwner.Item
    @ObservedObject var owner: ClubManagementReviewOwner
    let context: () -> ClubManagementReviewOwner.Context
    let active: () -> Bool
    let cancelled: (ClubManagementReviewOwner.Item) -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(isPresented: owner.binding(item, context: context, active: active, cancelled: cancelled),
                   onDismiss: { owner.dismissed(item) }) {
                content()
            }
    }
}

@MainActor struct ClubManagementReviewLifetime: UIViewControllerRepresentable {
    let covered: () -> Void
    let departed: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(covered: covered, departed: departed) }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.covered = covered; controller.departed = departed }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.departed() }
    @MainActor final class Controller: UIViewController {
        var covered: () -> Void
        var departed: () -> Void
        private var wasAttached = false
        init(covered: @escaping () -> Void, departed: @escaping () -> Void) {
            self.covered = covered; self.departed = departed
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil { wasAttached = true } else if wasAttached { departed() }
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            var current: UIViewController? = self
            while let controller = current {
                if controller.isBeingDismissed || controller.isMovingFromParent { departed(); return }
                if controller.presentedViewController != nil { covered(); return }
                current = controller.parent
            }
        }
    }
}
