import SwiftUI

@MainActor extension TemplateAuthoringModel {
    private func legacyHintLeaseIsCurrent(_ session: TemplateAuthoringSession?, _ identity: TemplateAuthoringIdentity, _ generation: UUID) -> Bool {
        canReadLegacyHints && coordinator.session == session && coordinator.identity == identity && legacyHintGeneration == generation
    }
    func legacyHintMethodBinding() -> Binding<TemplateAuthoringMethod> {
        let session = coordinator.session, identity = coordinator.identity, generation = legacyHintGeneration
        return .init(get: {
            self.legacyHintLeaseIsCurrent(session, identity, generation) ? self.draft.validationMethod : .manual
        }, set: { method in
            guard self.canEdit, self.legacyHintLeaseIsCurrent(session, identity, generation), self.draft.finishEnabled,
                  self.draft.advanced.enabledGames.isEmpty else { return }
            self.legacyHintGeneration = UUID()
            self.draft.validationMethod = method
            self.changed()
        })
    }
    func legacyHintToggle() -> Binding<Bool> {
        let session = coordinator.session, identity = coordinator.identity, generation = legacyHintGeneration
        return .init(get: {
            self.legacyHintLeaseIsCurrent(session, identity, generation) && self.draft.legacyHintControlsVisible && self.draft.legacyHintsAreEnabled
        }, set: { enabled in
            guard self.canEdit, self.legacyHintLeaseIsCurrent(session, identity, generation), self.draft.setLegacyHintsEnabled(enabled) else { return }
            self.legacyHintGeneration = UUID()
            self.changed()
        })
    }
    func legacyHint(_ field: TemplateLegacyHintField) -> Binding<String> {
        let session = coordinator.session, identity = coordinator.identity, generation = legacyHintGeneration
        return .init(get: {
            guard self.legacyHintLeaseIsCurrent(session, identity, generation), self.draft.legacyHintControlsVisible,
                  self.draft.legacyHintsAreEnabled else { return "" }
            return self.draft[keyPath: field.draftPath] ?? ""
        }, set: { text in
            guard self.canEdit, self.legacyHintLeaseIsCurrent(session, identity, generation), self.draft.setLegacyHint(field, to: text) else { return }
            self.changed()
        })
    }
}

@MainActor struct TemplateLegacyHintFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    var body: some View {
        if model.draft.legacyHintControlsVisible {
            Toggle("templateLegacyHints.enabled", isOn: model.legacyHintToggle())
                .disabled(!model.canEdit).accessibilityIdentifier("templateLegacyHints.enabled")
            Text("templateLegacyHints.clearNotice").font(.caption).foregroundStyle(.secondary)
            if model.draft.legacyHintsAreEnabled {
                ForEach(TemplateLegacyHintField.allCases) { field in
                    TemplateAuthoringField(field.rawValue, text: model.legacyHint(field), multiline: true).disabled(!model.canEdit)
                }
            }
        }
    }
}
