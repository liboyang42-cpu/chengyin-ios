import SwiftUI

@MainActor struct TemplateAuthoringRuleFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("templateAuthor.field.ruleInstructions").font(.subheadline)
            Text("templateRules.hint").font(.caption).foregroundStyle(.secondary)
            if !model.ruleSteps.isEditable {
                Text("templateRules.historical").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("templateRules.historical")
                Text(verbatim: model.ruleSteps.storedText ?? "").textSelection(.enabled)
                    .accessibilityIdentifier("templateRules.original")
            } else {
                ForEach(Array(model.ruleSteps.rows.enumerated()), id: \.element.id) { index, row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("templateRules.step")
                            Text(verbatim: String(index + 1))
                            Spacer()
                            if model.ruleSteps.canRemove {
                                Button("templateRules.remove", role: .destructive) { model.removeRuleStep(row.id) }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("templateRules.remove.\(index)")
                                    .accessibilityLabel(Text("templateRules.removeNumber \(index + 1)"))
                            }
                        }
                        TextField("templateRules.prompt", text: model.ruleStep(row.id), axis: .vertical)
                            .lineLimit(1...6)
                            .accessibilityIdentifier("templateRules.input.\(index)")
                            .accessibilityLabel(Text("templateRules.stepNumber \(index + 1)"))
                    }
                }
                Button("templateRules.add") { model.addRuleStep() }
                    .disabled(!model.ruleSteps.canAdd).accessibilityIdentifier("templateRules.add")
            }
            if let key = model.ruleStepIssue {
                Text(LocalizedStringKey(key)).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("templateRules.issue")
            }
        }.padding(.vertical, 3)
    }
}
