import SwiftUI

@MainActor struct MerchantCityTemplateHandoffLaunch {
    let reader: any MerchantOperationsReading
    var imageHost: MerchantRetainedImageHost? = nil
    var templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)? = nil
}

/// Reload is the existing parent's cityPlacement read. Apply changes only its selected ID.
@MainActor struct MerchantCityTemplateHandoffBinding {
    let scope: () -> UUID
    let isAuthenticated: () -> Bool
    let snapshot: () -> MerchantContentSnapshot?
    let draft: () -> MerchantCityTemplateLocalDraft
    let canOpen: () -> Bool
    let canReload: () -> Bool
    let reload: () async -> Void
    let apply: (MerchantCityTemplateLocalDraft, Int, MerchantContentSnapshot) -> Bool
    var isOfflineFixture = false
}

@MainActor final class MerchantCityTemplateHandoffModel: ObservableObject {
    struct Opening: Identifiable {
        let id = UUID()
        let parent: MerchantContentSnapshot
        let local: MerchantCityTemplateLocalDraft
        let launch: MerchantCityTemplateHandoffLaunch
        let readerScope: UUID
        let merchantID: Int
    }
    private struct Candidate {
        let id: Int
        let coordinator: MerchantOperationsCoordinator
        let template: MerchantNodeTemplate
        let identity: UUID
    }
    @Published private(set) var opening: Opening?
    @Published private(set) var busy = false
    @Published private(set) var returning = false
    @Published private(set) var issue: MerchantCityTemplateReturnFailure?
    @Published private(set) var applied = false
    @Published private(set) var recoveryNeeded = false
    @Published private(set) var active = false
    private(set) var generation = 0
    private var expectedSnapshot: MerchantContentSnapshot?
    private var candidate: Candidate?
    @Published private var editor: MerchantOperationsCoordinator?

    func activate() {
        guard !active else { return }
        active = true; generation += 1
    }
    func deactivate() {
        active = false
        close()
    }
    func accepts(_ permit: Int) -> Bool { active && permit == generation }

    func open(_ launch: MerchantCityTemplateHandoffLaunch?, binding: MerchantCityTemplateHandoffBinding, permit: Int? = nil) async {
        guard active, permit == nil || permit == generation else { return }
        guard !busy, opening == nil else { return }
        issue = nil; applied = false
        guard let launch, binding.canOpen(), binding.isAuthenticated(),
              launch.reader.isConfigured, launch.reader.isAuthenticated,
              launch.reader.isOfflineExample == binding.isOfflineFixture,
              let source = binding.snapshot(), let merchantID = source.access.merchantID,
              MerchantCityTemplateHandoff.validates(source, scope: binding.scope(), merchantID: merchantID) else { issue = .unavailable; return }
        generation += 1; let ticket = generation
        let original = Opening(parent: source, local: binding.draft(), launch: launch, readerScope: launch.reader.scope, merchantID: merchantID)
        busy = true
        defer { if ticket == generation { busy = false } }
        do {
            let access = try await launch.reader.access()
            guard !Task.isCancelled, ticket == generation, binding.canOpen(),
                  owns(original, binding: binding), MerchantCityTemplateHandoff.sameSnapshot(source, binding.snapshot()),
                  access.identity.merchantID == merchantID, access.allows(.template(nil)),
                  !launch.reader.hasPending(.template(nil)) else { if ticket == generation { issue = .contextChanged }; return }
            expectedSnapshot = source; opening = original; recoveryNeeded = false
        } catch {
            if ticket == generation, !Task.isCancelled { issue = .readFailed }
        }
    }
    private func owns(_ original: Opening, binding: MerchantCityTemplateHandoffBinding) -> Bool {
        binding.isAuthenticated() && binding.scope() == original.parent.scope && binding.draft() == original.local &&
        original.launch.reader.scope == original.readerScope && original.launch.reader.isAuthenticated &&
        original.launch.reader.isOfflineExample == binding.isOfflineFixture
    }
    func isCurrent(_ original: Opening, binding: MerchantCityTemplateHandoffBinding) -> Bool {
        opening?.id == original.id && owns(original, binding: binding) &&
        (busy && returning || MerchantCityTemplateHandoff.sameSnapshot(expectedSnapshot, binding.snapshot()))
    }
    func registerEditor(_ coordinator: MerchantOperationsCoordinator, original: Opening, binding: MerchantCityTemplateHandoffBinding) {
        guard editor == nil, isCurrent(original, binding: binding), coordinator.destination == .template(nil),
              ObjectIdentifier(coordinator.reader) == ObjectIdentifier(original.launch.reader) else { return }
        editor = coordinator
    }
    func canReturn(_ coordinator: MerchantOperationsCoordinator, original: Opening, binding: MerchantCityTemplateHandoffBinding) -> Bool {
        guard editor === coordinator, !returning, !busy, isCurrent(original, binding: binding), binding.canOpen(),
              ObjectIdentifier(coordinator.reader) == ObjectIdentifier(original.launch.reader),
              coordinator.isCurrent, coordinator.loadedScope == original.readerScope, !coordinator.isBusy,
              !coordinator.isLocked, !coordinator.isDirty, coordinator.confirmation == nil,
              case .template(let id?) = coordinator.destination, id > 0,
              case .template(let value) = coordinator.draft, value.id == id, value.blocker == nil,
              coordinator.baseline == .template(value), coordinator.document == .draft(.template(value)),
              !coordinator.reader.hasPending(.template(nil)), !coordinator.reader.hasPending(.template(id)) else { return false }
        return true
    }
    /// The host starts at template(nil). Only existing confirm + authoritative ID readback can reach this state.
    func accept(_ coordinator: MerchantOperationsCoordinator, original: Opening, binding: MerchantCityTemplateHandoffBinding) async {
        guard canReturn(coordinator, original: original, binding: binding),
              case .template(let value) = coordinator.draft, let id = value.id else { return }
        candidate = .init(id: id, coordinator: coordinator, template: value, identity: coordinator.draftIdentity)
        returning = true
        await retryRead(original, binding: binding)
    }
    private func candidateIsCurrent(_ value: Candidate, original: Opening) -> Bool {
        let c = value.coordinator
        return c.isCurrent && c.loadedScope == original.readerScope && !c.isBusy && !c.isLocked && !c.isDirty &&
        c.confirmation == nil && c.draftIdentity == value.identity && c.destination == .template(value.id) &&
        c.draft == .template(value.template) && c.baseline == c.draft && c.document == .draft(.template(value.template)) &&
        !c.reader.hasPending(.template(nil)) && !c.reader.hasPending(.template(value.id))
    }
    func retryRead(_ original: Opening, binding: MerchantCityTemplateHandoffBinding) async {
        guard opening?.id == original.id else { return }
        guard !busy, returning, isCurrent(original, binding: binding), binding.canReload(),
              let candidate, candidateIsCurrent(candidate, original: original) else { issue = .contextChanged; return }
        generation += 1; let ticket = generation
        busy = true; issue = nil
        defer { if ticket == generation { busy = false } }
        do {
            let access = try await original.launch.reader.access()
            guard !Task.isCancelled, ticket == generation, owns(original, binding: binding),
                  MerchantCityTemplateHandoff.sameSnapshot(expectedSnapshot, binding.snapshot()), binding.canReload(),
                  access.identity.merchantID == original.merchantID, access.allows(.template(candidate.id)),
                  candidateIsCurrent(candidate, original: original) else { throw MerchantCityTemplateReturnFailure.contextChanged }
            recoveryNeeded = true
            await binding.reload()
            guard !Task.isCancelled, ticket == generation, opening?.id == original.id, owns(original, binding: binding),
                  candidateIsCurrent(candidate, original: original) else { throw MerchantCityTemplateReturnFailure.contextChanged }
            expectedSnapshot = binding.snapshot()
            recoveryNeeded = expectedSnapshot == nil
            guard binding.canOpen(), let refreshed = expectedSnapshot else { throw MerchantCityTemplateReturnFailure.readFailed }
            _ = try MerchantCityTemplateHandoff.returnedTemplate(id: candidate.id, snapshot: refreshed,
                scope: original.parent.scope, merchantID: original.merchantID)
            guard binding.apply(original.local, candidate.id, refreshed) else { throw MerchantCityTemplateReturnFailure.contextChanged }
            self.candidate = nil; editor = nil; opening = nil; returning = false; applied = true; expectedSnapshot = nil
        } catch {
            if ticket == generation, opening?.id == original.id, !Task.isCancelled {
                issue = error as? MerchantCityTemplateReturnFailure ?? .readFailed
            }
        }
    }
    /// Cancelling after a failed parent read must not strand a hidden, unsaved placement draft.
    /// This restores only the parent read surface; it cannot apply a saved-template ID.
    func recoverParent(binding: MerchantCityTemplateHandoffBinding, permit: Int? = nil) async {
        guard active, permit == nil || permit == generation else { return }
        guard recoveryNeeded, opening == nil, !busy, binding.canReload() else { return }
        generation += 1; let ticket = generation, scope = binding.scope(), original = binding.draft()
        busy = true; issue = nil
        defer { if ticket == generation { busy = false } }
        await binding.reload()
        guard !Task.isCancelled, ticket == generation, binding.scope() == scope,
              binding.isAuthenticated(), binding.draft() == original else { return }
        recoveryNeeded = binding.snapshot() == nil
        if recoveryNeeded { issue = .readFailed }
    }
    func presentationBinding() -> Binding<Opening?> {
        let presentedID = opening?.id
        return Binding(get: { [weak self] in
            guard let self, self.opening?.id == presentedID else { return nil }; return self.opening
        }, set: { [weak self] value in
            guard value == nil, let presentedID else { return }; self?.close(id: presentedID)
        })
    }
    func close(id: UUID) {
        guard opening?.id == id else { return }; close()
    }
    func close() {
        generation += 1; opening = nil; candidate = nil; editor = nil; expectedSnapshot = nil
        busy = false; returning = false; issue = nil
    }
}
