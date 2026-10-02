import SwiftUI

@MainActor struct TemplateCreatorConfigurationView: View {
    @ObservedObject var model: TemplateAuthoringModel
    let family: TemplateCreatorFamily
    private var issues: [TemplateCreatorIssue] { model.draft.advanced.creatorIssues(family) }
    var body: some View {
        Form {
            Section {
                Toggle("templateAuthor.moduleEnabled", isOn: Binding(get: { model.draft.advanced.enabled(family.rawValue) }, set: { model.draft.advanced.setCreatorEnabled(family, $0) }))
                Text(LocalizedStringKey(family.providerKey)).font(.footnote).foregroundStyle(.secondary)
            }
            if model.draft.advanced.enabled(family.rawValue) {
                TemplateCreatorFieldsView(model: model, family: family, fields: TemplateCreatorSchema.fields(family), path: [])
                Section("creator.review") {
                    NavigationLink("creator.rehearse") { TemplateCreatorRehearsalView(draft: model.draft.advanced, family: family) }.disabled(!issues.isEmpty)
                    Text("creator.localOnly").font(.footnote)
                }
                if !issues.isEmpty {
                    Section("templateAuthor.validationTitle") {
                        ForEach(issues) { issue in VStack(alignment: .leading) {
                            Text(LocalizedStringKey(issue.labelKey))
                            Text(verbatim: issue.path).font(.caption).foregroundStyle(.secondary)
                        } }
                    }
                }
            }
        }.navigationTitle(LocalizedStringKey(family.labelKey)).disabled(!model.canEdit)
            .accessibilityIdentifier("creator.form." + family.rawValue)
    }
}

@MainActor private struct TemplateCreatorFieldsView: View {
    @ObservedObject var model: TemplateAuthoringModel
    let family: TemplateCreatorFamily
    let fields: [TemplateCreatorField]
    let path: [TemplateCreatorPath]
    var body: some View {
        ForEach(fields) { field in
            TemplateCreatorFieldView(model: model, family: family, field: field, path: path + [.field(field.id)])
        }
    }
}

@MainActor private struct TemplateCreatorFieldView: View {
    @ObservedObject var model: TemplateAuthoringModel
    let family: TemplateCreatorFamily
    let field: TemplateCreatorField
    let path: [TemplateCreatorPath]
    private var current: TemplateAuthoringJSON { model.draft.advanced.creatorValue(family, path: path) ?? field.initial }
    private var object: [String: TemplateAuthoringJSON] { model.draft.advanced.creatorValue(family, path: Array(path.dropLast()))?.object ?? [:] }
    private func write(_ entry: TemplateAuthoringJSON?) { model.draft.advanced.setCreatorValue(family, path: path, entry: entry) }
    private var text: Binding<String> { Binding(get: {
        if let value = current.string { return value }
        if let value = current.number { return value.rounded() == value ? String(format: "%.0f", value) : String(value) }
        return ""
    }, set: { write(.string($0)) }) }
    private var rows: [TemplateAuthoringJSON] { current.array ?? [] }
    private var hidden: Bool {
        if family == .qa && field.id == "options" && object["mode"]?.string != "PICK" { return true }
        if family == .qa && field.id == "answerText" && object["mode"]?.string != "TYPE" { return true }
        if family == .profile && path.count > 1 {
            if ["options", "override"].contains(field.id) && object["kind"]?.string == "text" { return true }
            if field.id == "maxLength" && object["kind"]?.string == "pick" { return true }
            if field.id == "required" && object["kind"] != nil { return true }
        }
        if field.id == "var" && ["ADD_TAG", "HAS_TAG", "NODE_COMPLETED"].contains(object["op"]?.string ?? "") { return true }
        if field.id == "nodeId" && object["op"]?.string != "NODE_COMPLETED" { return true }
        if field.id == "value" && object["op"]?.string == "NODE_COMPLETED" { return true }
        if family == .hiddenObject && field.id == "r" { return true }
        if family == .compare && field.id == "effects" { return true }
        return false
    }
    var body: some View {
        if !hidden {
            if family == .compare && field.id == "maxAttempts" {
                Toggle("creator.compare.limitAttempts", isOn: Binding(get: { current != .null }, set: { write($0 ? .number(3) : nil) }))
                    .accessibilityIdentifier("creator.compare.limitAttempts")
                if current != .null { control.accessibilityIdentifier("creator.field.compare.maxAttempts") }
                else { Text("creator.compare.unlimited").font(.footnote) }
            } else { control.accessibilityIdentifier("creator.field." + family.rawValue + "." + field.id) }
        }
    }
    @ViewBuilder private var control: some View {
        switch field.kind {
        case .text(let max, let required, _):
            VStack(alignment: .leading) {
                TextField(LocalizedStringKey(field.labelKey), text: text, axis: .vertical).textInputAutocapitalization(.never)
                HStack { if required { Text("creator.required") }; Spacer(); Text(verbatim: "\(text.wrappedValue.utf16.count)/\(max)") }.font(.caption).foregroundStyle(.secondary)
            }
        case .number(let min, let max, let integer):
            VStack(alignment: .leading) {
                TextField(LocalizedStringKey(field.labelKey), text: text).keyboardType(.numbersAndPunctuation)
                if max < 1e15 { Text(verbatim: "\(min.formatted()) … \(max.formatted())").font(.caption).foregroundStyle(.secondary) }
                if integer { Text("creator.integer").font(.caption).foregroundStyle(.secondary) }
                if family == .hiddenObject && ["x", "y"].contains(field.id) {
                    Slider(value: Binding(get: { current.number ?? 0.5 }, set: { write(.number($0)) }), in: 0...1)
                }
            }
        case .choice(let choices):
            Picker(LocalizedStringKey(field.labelKey), selection: text) {
                ForEach(choices, id: \.self) { value in Text(LocalizedStringKey("creator.choice." + (value.isEmpty ? "empty" : value))).tag(value) }
            }
        case .toggle:
            Toggle(LocalizedStringKey(field.labelKey), isOn: Binding(get: { current.bool }, set: { write(.bool($0)) }))
        case .stateValue:
            TextField(LocalizedStringKey(["ADD_TAG", "HAS_TAG"].contains(object["op"]?.string ?? "") ? "creator.field.tagValue" : field.labelKey), text: text)
                .textInputAutocapitalization(.never)
        case .object(let fields):
            if field.id == "override" {
                Toggle(LocalizedStringKey(field.labelKey), isOn: Binding(get: { current.object != nil }, set: { write($0 ? .object(TemplateCreatorSchema.defaults(fields)) : nil) }))
            }
            if current.object != nil {
                NavigationLink(LocalizedStringKey(field.labelKey)) {
                    Form { TemplateCreatorFieldsView(model: model, family: family, fields: fields, path: path) }.navigationTitle(LocalizedStringKey(field.labelKey))
                }
            }
        case .rows(let fields, let minimum, let maximum, _):
            NavigationLink {
                List {
                    ForEach(rows.indices, id: \.self) { index in
                        NavigationLink {
                            Form { TemplateCreatorFieldsView(model: model, family: family, fields: fields, path: path + [.index(index)]) }
                                .navigationTitle(LocalizedStringKey(field.labelKey))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: rowLabel(index))
                                Text(verbatim: "\(index + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.onDelete { indexes in var copy = rows; for index in indexes.sorted(by: >) { copy.remove(at: index) }; write(.array(copy)) }
                        .onMove { source, destination in var copy = rows; copy.move(fromOffsets: source, toOffset: destination); write(.array(copy)) }
                    Button("creator.add") { model.draft.advanced.addCreatorRow(family, path: path, field: field) }.disabled(rows.count >= maximum)
                    Text(verbatim: "\(rows.count) / \(minimum)…\(maximum)").font(.caption)
                }.toolbar { EditButton() }.navigationTitle(LocalizedStringKey(field.labelKey))
            } label: { LabeledContent(LocalizedStringKey(field.labelKey), value: String(rows.count)) }
        case .strings(_, let max, let length): stringRows(max: max, length: length)
        case .poems:
            NavigationLink {
                List {
                    ForEach(rows.indices, id: \.self) { index in
                        NavigationLink {
                            Form {
                                TemplateCreatorFieldView(model: model, family: family, field: .init("poemLines", .strings(min: 1, max: 4, length: 24), .array([])), path: path + [.index(index)])
                            }.navigationTitle("creator.field.poemLines")
                        } label: { Text(verbatim: (rows[index].array ?? []).compactMap(\.string).joined(separator: " / ")) }
                    }.onDelete { indexes in var copy = rows; for index in indexes.sorted(by: >) { copy.remove(at: index) }; write(.array(copy)) }
                    Button("creator.add") { var copy = rows; copy.append(.array([.string("")])); write(.array(copy)) }.disabled(rows.count >= 60)
                }.navigationTitle(LocalizedStringKey(field.labelKey))
            } label: { LabeledContent(LocalizedStringKey(field.labelKey), value: String(rows.count)) }
        }
    }
    private func rowLabel(_ index: Int) -> String {
        let row = rows[index].object ?? [:]
        return ["label", "title", "name", "line", "key", "id", "op", "url"].compactMap { row[$0]?.string }.first(where: { !$0.isEmpty }) ?? String(index + 1)
    }
    private func stringRows(max: Int, length: Int) -> some View {
        VStack(alignment: .leading) {
            Text(LocalizedStringKey(field.labelKey)).font(.headline)
            ForEach(rows.indices, id: \.self) { index in
                HStack {
                    TextField(LocalizedStringKey(field.labelKey), text: Binding(get: { rows.indices.contains(index) ? rows[index].string ?? "" : "" }, set: { value in var copy = rows; guard copy.indices.contains(index) else { return }; copy[index] = .string(value); write(.array(copy)) }))
                    Button { var copy = rows; guard copy.indices.contains(index) else { return }; copy.remove(at: index); write(.array(copy)) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("creator.remove")
                }
            }
            Button("creator.add") { var copy = rows; copy.append(.string("")); write(.array(copy)) }.disabled(rows.count >= max)
            Text(verbatim: "≤ \(max) × \(length)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
