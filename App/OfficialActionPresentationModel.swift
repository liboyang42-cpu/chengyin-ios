import SwiftUI

/// One original action sheet. Retiring UI cancels only its lease, never a durable lock.
@MainActor final class OfficialActionPresentationModel: ObservableObject {
    let coordinator: OfficialActionCoordinator
    let command: OfficialActionCommand
    private let identity: OfficialActionIdentity?
    @Published private(set) var review: OfficialActionReview?
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var receipt: OfficialActionReceipt?
    @Published private(set) var rejectionReason: String?
    private var presentation: OfficialActionPresentation?
    private var visible = false
    private var active = false
    private var ended = false
    private var task: Task<Void, Never>?
    private var operation: UUID?

    init(coordinator: OfficialActionCoordinator, command: OfficialActionCommand) {
        self.coordinator = coordinator; self.command = command
        identity = coordinator.identity
        presentation = coordinator.beginPresentation()
    }
    func isBound(to coordinator: OfficialActionCoordinator, command: OfficialActionCommand) -> Bool {
        self.coordinator === coordinator && self.command == command
    }
    var canConfirm: Bool {
        guard visible, active, !ended, !busy, review != nil, receipt == nil,
              let presentation else { return false }
        return coordinator.enabled && coordinator.ownsPresentation(presentation)
    }
    var canReview: Bool {
        guard visible, active, !ended, !busy, review == nil, receipt == nil,
              let presentation else { return false }
        return coordinator.enabled && coordinator.ownsPresentation(presentation)
    }
    func readAgain() {
        guard canReview, let presentation else { return }
        prepare(presentation)
    }
    func appear(isActive: Bool) {
        guard !ended else { return }
        visible = true
        sceneChanged(isActive: isActive)
    }
    func sceneChanged(isActive: Bool) {
        guard visible, !ended else { return }
        guard isActive else { active = false; retire(); return }
        guard !active else { synchronizeIdentity(); return }
        guard coordinator.identity == identity else { invalidateIdentity(); return }
        active = true
        let lease: OfficialActionPresentation
        if let presentation {
            guard coordinator.resumePresentation(presentation) else { invalidateIdentity(); return }
            lease = presentation
        } else { invalidateIdentity(); return }
        prepare(lease)
    }
    func synchronizeIdentity() {
        guard coordinator.identity == identity else { invalidateIdentity(); return }
    }
    func disappear() {
        ended = true; visible = false; active = false
        retire()
    }
    private func invalidateIdentity() {
        ended = true; active = false
        retire(); message = "officialAction.stale"
    }
    private func retire() {
        operation = nil; task?.cancel(); task = nil
        if let presentation { coordinator.cancelReview(presentation: presentation) }
        busy = false; review = nil; receipt = nil; message = nil; rejectionReason = nil
    }
    private func isCurrent(_ id: UUID, _ lease: OfficialActionPresentation) -> Bool {
        visible && active && !ended && operation == id && !Task.isCancelled &&
            coordinator.identity == identity && coordinator.ownsPresentation(lease)
    }
    private func finish(_ id: UUID) {
        guard operation == id else { return }
        operation = nil; task = nil; busy = false
    }
    private func prepare(_ lease: OfficialActionPresentation) {
        let id = UUID(); operation = id; busy = true
        review = nil; receipt = nil; message = nil; rejectionReason = nil
        task = Task { [weak self, coordinator, command] in
            defer { self?.finish(id) }
            guard self?.isCurrent(id, lease) == true else { return }
            do {
                let value = try await coordinator.prepare(command, presentation: lease)
                guard let self, self.isCurrent(id, lease) else { return }
                self.review = value
            } catch {
                guard let self, self.isCurrent(id, lease) else { return }
                self.message = self.issue(error)
            }
        }
    }
    func submit(_ review: OfficialActionReview) {
        guard canConfirm, self.review == review, let lease = presentation else { return }
        // Reserve synchronously, before Task scheduling, so duplicate taps cannot queue a write.
        let id = UUID(); operation = id; busy = true; message = nil; rejectionReason = nil
        task = Task { [weak self, coordinator] in
            defer { self?.finish(id) }
            guard self?.isCurrent(id, lease) == true else { return }
            do {
                let result = try await coordinator.confirm(review, presentation: lease)
                guard let self, self.isCurrent(id, lease) else { return }
                self.receipt = result
            } catch {
                guard let self, self.isCurrent(id, lease) else { return }
                if case let OfficialActionFailure.rejected(_, reason) = error { self.rejectionReason = reason }
                self.message = self.issue(error); self.review = nil
            }
        }
    }
    private func issue(_ error: Error) -> String {
        switch error {
        case OfficialActionFailure.disabled: return "officialAction.disabled"
        case OfficialActionFailure.locked: return "officialAction.locked"
        case OfficialActionFailure.unknown: return "officialAction.unknown"
        case OfficialActionFailure.storage: return "officialAction.storage"
        case OfficialActionFailure.stale: return "officialAction.stale"
        case OfficialActionFailure.forbidden: return "officialAction.forbidden"
        default: return coordinator.state == .unknown ? "officialAction.unknown" : "officialAction.rejected"
        }
    }
}
