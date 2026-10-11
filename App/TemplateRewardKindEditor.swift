import SwiftUI

@MainActor final class TemplateRewardKindEditor: ObservableObject {
    enum TextField: Equatable {
        case feedback, medalName, medalImage
        var kind: TemplateRewardKind { self == .feedback ? .feedback : .medal }
        var path: WritableKeyPath<TemplateAuthoringDraft, String?> {
            switch self { case .feedback: return \.feedbackText; case .medalName: return \.medalName; case .medalImage: return \.medalImg }
        }
    }
    let model: TemplateAuthoringModel
    private var session: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var mediaGeneration: UUID?
    private var generation = 0
    private var kindGenerations: [TemplateRewardKind: UUID] = [:]
    private var active = false
    @Published private(set) var enabled: Set<TemplateRewardKind> = []
    @Published private(set) var revision = 0

    init(model: TemplateAuthoringModel) { self.model = model; reload() }
    private var hasLease: Bool {
        active && model.canReadStoryDraft && session == model.coordinator.session && identity == model.coordinator.identity &&
            mediaGeneration == model.mediaReviewGeneration
    }
    var canEdit: Bool { hasLease && model.canEdit && model.draft.rewardEnabled }
    var hasSelection: Bool { hasLease && !enabled.isEmpty }
    func isEnabled(_ kind: TemplateRewardKind) -> Bool { hasLease && model.draft.rewardEnabled && enabled.contains(kind) }
    func reload() {
        generation += 1; active = true
        session = model.coordinator.session; identity = model.coordinator.identity; mediaGeneration = model.mediaReviewGeneration
        kindGenerations = Dictionary(uniqueKeysWithValues: TemplateRewardKind.allCases.map { ($0, UUID()) })
        enabled = TemplateRewardKinds.inferred(from: model.draft); revision += 1
    }
    func resume() {
        guard model.canReadStoryDraft, session == model.coordinator.session, identity == model.coordinator.identity,
              mediaGeneration == model.mediaReviewGeneration else { reload(); return }
        guard !active else { return }
        generation += 1; active = true; revision += 1
    }
    func retire() { generation += 1; active = false; revision += 1 }
    private func current(_ kind: TemplateRewardKind, generation stamp: Int, kindStamp: UUID?) -> Bool {
        hasLease && generation == stamp && kindGenerations[kind] == kindStamp
    }
    func moduleEnabled() -> Binding<Bool> {
        let stamp = generation
        return .init(get: { self.hasLease && self.generation == stamp && self.model.draft.rewardEnabled }, set: { value in
            guard self.hasLease, self.generation == stamp, self.model.canEdit, self.model.draft.rewardEnabled != value else { return }
            self.generation += 1
            self.model.draft.rewardEnabled = value
            self.model.changed()
            self.reload()
        })
    }
    func toggle(_ kind: TemplateRewardKind) -> Binding<Bool> {
        let stamp = generation, kindStamp = kindGenerations[kind]
        return .init(get: { self.current(kind, generation: stamp, kindStamp: kindStamp) && self.isEnabled(kind) }, set: { value in
            guard self.current(kind, generation: stamp, kindStamp: kindStamp), self.canEdit, self.enabled.contains(kind) != value else { return }
            // The retired type's old text/number/style controls cannot restore cleared values.
            self.kindGenerations[kind] = UUID()
            if value { self.enabled.insert(kind) }
            else {
                guard let next = TemplateRewardKinds.disabling(kind, in: self.model.draft) else { return }
                self.enabled.remove(kind)
                self.model.draft = next
                self.model.changed()
            }
            self.revision += 1
        })
    }
    func text(_ field: TextField) -> Binding<String> {
        let stamp = generation, kindStamp = kindGenerations[field.kind], original = model.optional(field.path)
        return .init(get: {
            guard self.current(field.kind, generation: stamp, kindStamp: kindStamp), self.isEnabled(field.kind) else { return "" }
            return original.wrappedValue
        }, set: { value in
            guard self.current(field.kind, generation: stamp, kindStamp: kindStamp), self.canEdit, self.isEnabled(field.kind) else { return }
            original.wrappedValue = value; self.model.changed()
        })
    }
    func coupon() -> Binding<String> {
        let stamp = generation, kindStamp = kindGenerations[.coupon], original = model.number(\.couponId)
        return .init(get: {
            guard self.current(.coupon, generation: stamp, kindStamp: kindStamp), self.isEnabled(.coupon) else { return "" }
            return original.wrappedValue
        }, set: { value in
            guard self.current(.coupon, generation: stamp, kindStamp: kindStamp), self.canEdit, self.isEnabled(.coupon) else { return }
            original.wrappedValue = value; self.model.changed()
        })
    }
    func medalStyle() -> Binding<String?> {
        let stamp = generation, kindStamp = kindGenerations[.medal]
        return .init(get: {
            guard self.current(.medal, generation: stamp, kindStamp: kindStamp), self.isEnabled(.medal) else { return nil }
            return self.model.draft.medalStyle
        }, set: { value in
            guard self.current(.medal, generation: stamp, kindStamp: kindStamp), self.canEdit, self.isEnabled(.medal) else { return }
            self.model.draft.medalStyle = value; self.model.changed()
        })
    }
}
