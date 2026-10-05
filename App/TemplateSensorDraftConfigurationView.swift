import SwiftUI

@MainActor extension TemplateAuthoringModel {
    func selectSensorKind(_ kind: TemplateSensorDraft.Kind) {
        guard canEdit, draft.id == nil, draft.validationMethod.rawValue == 7 else { return }
        var value = draft.sensorDraft ?? .init()
        guard value.canEdit else { return }
        value.select(kind); draft.sensorDraft = value; changed()
    }
    func setSensorInput(_ parameter: TemplateSensorDraft.Parameter, _ text: String) {
        guard canEdit, draft.id == nil, draft.validationMethod.rawValue == 7 else { return }
        var value = draft.sensorDraft ?? .init()
        guard value.canEdit else { return }
        value.set(parameter, text: text); draft.sensorDraft = value; changed()
    }
}

@MainActor struct TemplateSensorDraftConfigurationFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    @FocusState private var focusedParameter: String?
    private var value: TemplateSensorDraft { model.draft.sensorDraft ?? .init() }
    var body: some View {
        if model.canEdit, model.draft.id == nil, model.draft.validationMethod.rawValue == 7 {
            Text("sensorDraft.scope").font(.caption).foregroundStyle(.secondary)
            if value.canEdit {
                Picker("sensorDraft.type", selection: Binding<String>(get: { value.selectedType ?? "" }, set: {
                    guard let kind = TemplateSensorDraft.Kind(rawValue: $0) else { return }
                    model.selectSensorKind(kind)
                })) {
                    Text("sensorDraft.choose").tag("")
                    ForEach(TemplateSensorDraft.Kind.allCases) { kind in Text(LocalizedStringKey(kind.labelKey)).tag(kind.rawValue) }
                }.accessibilityIdentifier("sensorDraft.type")
                ForEach(value.kind?.parameters ?? [], id: \.rawValue) { parameter in
                    VStack(alignment: .leading) {
                        Text(LocalizedStringKey(parameter.labelKey))
                        TextField(LocalizedStringKey(parameter.labelKey), text: Binding(get: { value.input(parameter) }, set: { model.setSensorInput(parameter, $0) }))
                            .focused($focusedParameter, equals: parameter.rawValue)
                            .keyboardType(.numberPad).accessibilityIdentifier("sensorDraft.input." + parameter.rawValue)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    if focusedParameter == parameter.rawValue {
                                        Spacer()
                                        Button("action.done") { focusedParameter = nil }
                                            .accessibilityIdentifier("sensorDraft.keyboardDone")
                                    }
                                }
                            }
                        Text("1…\(parameter.maximum)").font(.caption).foregroundStyle(.secondary)
                        if value.integer(parameter) == nil { Text("sensorDraft.invalidField").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } else { Text("sensorDraft.preserved").foregroundStyle(.secondary).accessibilityIdentifier("sensorDraft.preserved") }
            NavigationLink("sensorDraft.preview") { TemplateSensorDraftPreviewView(model: model) }
                .accessibilityIdentifier("sensorDraft.preview")
        }
    }
}

@MainActor struct TemplateSensorDraftPreviewView: View {
    @ObservedObject var model: TemplateAuthoringModel
    var body: some View {
        List {
            if model.canEdit, model.draft.id == nil, model.draft.validationMethod.rawValue == 7 {
                TemplateSensorDraftPreviewContent(draft: model.draft.sensorDraft ?? .init())
            } else { Text("sensorDraft.unavailable") }
        }.navigationTitle("sensorDraft.preview")
    }
}

struct TemplateSensorDraftPreviewContent: View {
    let draft: TemplateSensorDraft
    var body: some View {
        Text("sensorDraft.scope").foregroundStyle(.secondary)
        if !draft.canEdit { Text("sensorDraft.preserved").accessibilityIdentifier("sensorDraft.preview.preserved") }
        else if let kind = draft.kind {
            Text(LocalizedStringKey(kind.labelKey))
            ForEach(kind.parameters, id: \.rawValue) { parameter in
                LabeledContent {
                    if draft.input(parameter).isEmpty { Text("sensorDraft.missing") }
                    else { Text(verbatim: draft.input(parameter)) }
                } label: { Text(LocalizedStringKey(parameter.labelKey)) }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("sensorDraft.preview.value." + parameter.rawValue)
                .accessibilityValue(draft.input(parameter).isEmpty ? Text("sensorDraft.missing") : Text(verbatim: draft.input(parameter)))
                if draft.integer(parameter) == nil { Text("sensorDraft.invalidField").foregroundStyle(.secondary) }
            }
            Text(LocalizedStringKey(draft.isValid ? "sensorDraft.valid" : "sensorDraft.invalid")).accessibilityIdentifier("sensorDraft.preview.status")
        } else { Text("sensorDraft.choose") }
    }
}
