import SwiftUI

struct ProjectEditCompletionRulesForm: View {
    @Binding var rules: ProjectEditCompletionRules
    let city: Bool
    let fullEdit: Bool
    let totalNodes: Int
    var body: some View {
        Section("projectEdit.completion.title") {
            if rules.readOnly {
                Label("projectEdit.completion.readOnly", systemImage: "lock")
                    .accessibilityIdentifier("projectEdit.completion.readOnly")
            } else {
                if city {
                    Picker("projectEdit.completion.mode", selection: $rules.mode) {
                        Text("projectEdit.completion.all").tag("ALL")
                        Text("projectEdit.completion.atLeast").tag("AT_LEAST")
                    }.accessibilityIdentifier("projectEdit.completion.mode")
                    if rules.mode == "AT_LEAST" {
                        TextField("projectEdit.completion.count", text: $rules.requiredCount)
                            .keyboardType(.numberPad).accessibilityIdentifier("projectEdit.completion.count")
                    }
                }
                Toggle("projectEdit.completion.enabled", isOn: $rules.bingoEnabled)
                    .accessibilityIdentifier("projectEdit.completion.enabled")
                Text("projectEdit.completion.serverConditions").font(.caption).foregroundStyle(.secondary)
                if let key = rules.validationIssue(totalNodes: totalNodes) { Label(LocalizedStringKey(key), systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                if rules.bingoEnabled, rules.cells.count == 9 {
                    ForEach(ProjectEditCompletionRules.displayOrder, id: \.self) { position in
                        DisclosureGroup {
                            TextField("projectEdit.completion.label", text: $rules.cells[position].label)
                                .accessibilityIdentifier("projectEdit.completion.label.\(position)")
                            TextField("projectEdit.completion.coupon", text: $rules.cells[position].couponID)
                                .keyboardType(.numberPad).accessibilityIdentifier("projectEdit.completion.coupon.\(position)")
                            Text("projectEdit.completion.couponHint").font(.caption).foregroundStyle(.secondary)
                            TextField("projectEdit.completion.feedback", text: $rules.cells[position].feedbackText, axis: .vertical)
                                .accessibilityIdentifier("projectEdit.completion.feedback.\(position)")
                        } label: {
                            Text(LocalizedStringKey("projectEdit.completion.condition." + String(position)))
                        }.accessibilityIdentifier("projectEdit.completion.cell.\(position)")
                    }
                }
            }
        }.disabled(!fullEdit || rules.readOnly)
    }
}

struct ProjectEditCompletionRulesSummary: View {
    let draft: ProjectEditDraft
    private var rules: ProjectEditCompletionRules { (draft.completionRules ?? .init(raw: draft.preserved["completeRuleJson"])).forProduct(draft.product) }
    var body: some View {
        Section("projectEdit.completion.title") {
            if rules.readOnly { Text("projectEdit.completion.readOnly") }
            else {
                Text(LocalizedStringKey(rules.mode == "AT_LEAST" ? "projectEdit.completion.atLeast" : "projectEdit.completion.all"))
                if rules.mode == "AT_LEAST" { Text(verbatim: rules.requiredCount) }
                Text(LocalizedStringKey(rules.bingoEnabled ? "projectEdit.completion.enabled" : "projectEdit.completion.disabled"))
                if rules.bingoEnabled, rules.cells.count == 9 {
                    ForEach(ProjectEditCompletionRules.displayOrder, id: \.self) { position in
                        VStack(alignment: .leading) {
                            Text(LocalizedStringKey("projectEdit.completion.condition." + String(position)))
                            Text(verbatim: rules.cells[position].label)
                            if !rules.cells[position].couponID.isEmpty {
                                LabeledContent("projectEdit.completion.coupon", value: rules.cells[position].couponID)
                            }
                            Text(verbatim: rules.cells[position].feedbackText)
                        }
                    }
                }
            }
        }
    }
}
