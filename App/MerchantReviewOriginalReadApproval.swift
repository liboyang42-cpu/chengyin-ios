import Foundation

/// Definition only. No shipped code issues this grant or derives it from login.
struct MerchantReviewOriginalReadApproval {
    let context: RuntimeDependencyContext
    let revision = UUID()
    /// Journal completion is distinct from observing a receipt and defaults off.
    let permitsJournalCompletion: Bool
    init(context: RuntimeDependencyContext, permitsJournalCompletion: Bool = false) throws {
        guard context.market == .china, context.role.utf8.elementsEqual(context.session.role.utf8) else {
            throw MerchantBusinessFailure.invalid
        }
        self.context = context; self.permitsJournalCompletion = permitsJournalCompletion
    }
    func matches(_ current: RuntimeDependencyContext) -> Bool {
        ContentDraftContextFence.matches(context, current)
            && context.session.role.utf8.elementsEqual(current.session.role.utf8)
    }
}
