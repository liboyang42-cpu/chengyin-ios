import SwiftUI

@MainActor struct TemplateRootAuthoringView: View {
    @ObservedObject var model: TemplateAuthoringModel
    private var issues: [TemplateRootIssue] { model.draft.advanced.rootCreatorIssues }
    var body: some View {
        Form {
            Section("creatorRoot.rules") {
                Text("creatorRoot.separateCount").font(.footnote)
                Picker("creatorRoot.mistakeTier", selection: Binding(get: { model.draft.advanced.value["mistakeTier"]?.string ?? "" }, set: { model.draft.advanced.value["mistakeTier"] = $0.isEmpty ? nil : .string($0) })) {
                    Text("creatorRoot.defaultTier").tag("")
                    ForEach(["easy", "medium", "hard"], id: \.self) { Text(LocalizedStringKey("creator.choice." + $0)).tag($0) }
                }
                Text("creatorRoot.damageServer").font(.footnote)
                Picker("playkitAuthor.presentation", selection: Binding(get: { model.draft.advanced.explicitPresentation }, set: { model.draft.advanced.setPresentation($0) })) {
                    Text("playkitAuthor.presentation.default").tag(""); Text("playkitAuthor.presentation.inline").tag("inline"); Text("playkitAuthor.presentation.focused").tag("fullscreen")
                }
            }
            Section("creatorRoot.variants") {
                Text("creatorRoot.firstMatch").font(.footnote)
                ForEach(Array(model.draft.advanced.rootVariants.enumerated()), id: \.offset) { index, _ in
                    NavigationLink { TemplateVariantEditor(model: model, index: index) } label: { HStack { Text("creatorRoot.variant"); Text(verbatim: String(index + 1)) } }
                }.onDelete { indexes in var rows = model.draft.advanced.rootVariants; for index in indexes.sorted(by: >) { rows.remove(at: index) }; model.draft.advanced.value["variants"] = .array(rows) }
                    .onMove { from, to in var rows = model.draft.advanced.rootVariants; rows.move(fromOffsets: from, toOffset: to); model.draft.advanced.value["variants"] = .array(rows) }
                Button("creatorRoot.addVariant") { model.draft.advanced.appendRootVariant() }.disabled(model.draft.advanced.rootVariants.count >= 16)
                if model.draft.advanced.value["variants"] != nil { Button("creatorRoot.clearVariants", role: .destructive) { model.draft.advanced.value.removeValue(forKey: "variants") } }
            }
            Section("creatorRoot.roleViews") {
                Toggle("templateAuthor.moduleEnabled", isOn: Binding(get: { model.draft.advanced.enabled("roleViews") }, set: { model.draft.advanced.setRoleViewsEnabled($0) }))
                Text("creatorRoot.roleViewsLimit").font(.footnote)
                if model.draft.advanced.enabled("roleViews") {
                    ForEach(["A", "B"], id: \.self) { role in NavigationLink { TemplateRoleViewEditor(model: model, role: role) } label: { HStack { Text("creatorRoot.roleLabel"); Text(verbatim: role) } } }
                }
            }
            Section { NavigationLink("creatorRoot.rehearse") { TemplateRootRehearsalView(draft: model.draft.advanced) }.disabled(!model.draft.advanced.issues.isEmpty) }
            if !issues.isEmpty { Section("templateAuthor.validationTitle") { ForEach(issues) { issue in VStack(alignment: .leading) { Text(LocalizedStringKey(issue.labelKey)); Text(verbatim: issue.path).font(.caption) } } } }
        }.navigationTitle("creatorRoot.rules").toolbar { EditButton() }.disabled(!model.canEdit)
    }
}

@MainActor private struct TemplateVariantEditor: View {
    @ObservedObject var model: TemplateAuthoringModel
    let index: Int
    @State private var newField: TemplateRelaxField?
    private var row: [String: TemplateAuthoringJSON] { let rows = model.draft.advanced.rootVariants; return rows.indices.contains(index) ? rows[index].object ?? [:] : [:] }
    private var relax: [String: TemplateAuthoringJSON] { row["relax"]?.object ?? [:] }
    var body: some View {
        Form {
            Section("creatorRoot.when") {
                TemplateConditionEditor(value: Binding(get: { row["when"]?.object ?? [:] }, set: { model.draft.advanced.setRootVariant(index, key: "when", entry: .object($0)) }))
            }
            Section("creatorRoot.relaxChanges") {
                ForEach(relax.keys.sorted(), id: \.self) { key in
                    VStack(alignment: .leading) {
                        if let field = TemplateRelaxField(rawValue: key) { Text(LocalizedStringKey(field.labelKey)) }
                        else { Text(verbatim: key) }
                        HStack {
                            TemplateRelaxOperationEditor(value: Binding(get: { relax[key]?.string ?? "" }, set: { var fields = relax; fields[key] = .string($0); model.draft.advanced.setRootVariant(index, key: "relax", entry: .object(fields)) }), field: TemplateRelaxField(rawValue: key))
                            Button { var fields = relax; fields.removeValue(forKey: key); model.draft.advanced.setRootVariant(index, key: "relax", entry: .object(fields)) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("creator.remove")
                        }
                    }
                }
                Picker("creatorRoot.addField", selection: $newField) {
                    Text("creator.choose").tag(nil as TemplateRelaxField?)
                    ForEach(model.draft.advanced.eligibleRelaxFields.filter { relax[$0.rawValue] == nil }) { field in Text(LocalizedStringKey(field.labelKey)).tag(Optional(field)) }
                }
                Button("creator.add") {
                    guard let field = newField else { return }; var fields = relax; fields[field.rawValue] = .string(field.initialOperation); model.draft.advanced.setRootVariant(index, key: "relax", entry: .object(fields)); newField = nil
                }.disabled(newField == nil)
                Text("creatorRoot.eligibleOnly").font(.footnote)
            }
            let issues = model.draft.advanced.rootCreatorIssues.filter { $0.path.hasPrefix("variants[\(index + 1)]") }
            if !issues.isEmpty { Section("templateAuthor.validationTitle") { ForEach(issues) { issue in Text(LocalizedStringKey(issue.labelKey)) } } }
        }.navigationTitle("creatorRoot.variant")
    }
}

private struct TemplateRelaxOperationEditor: View {
    @Binding var value: String
    let field: TemplateRelaxField?
    private var sign: String { value.first.map(String.init) ?? "+" }
    var body: some View {
        VStack(alignment: .leading) {
            Picker("creatorRoot.operation", selection: Binding(get: { sign }, set: { value = $0 + ($0 == "=" ? "0" : String(value.dropFirst())) })) {
                if field?.lowers == true { Text("creatorRoot.subtract").tag("-") }
                else { Text("creatorRoot.add").tag("+"); if field?.attempts == true { Text("creatorRoot.unlimited").tag("=") } }
            }
            if sign != "=" { TextField("creatorRoot.amount", text: Binding(get: { String(value.dropFirst()) }, set: { value = sign + $0 })).keyboardType(.numberPad) }
        }
    }
}

private struct TemplateConditionEditor: View {
    @Binding var value: [String: TemplateAuthoringJSON]
    private func text(_ key: String) -> Binding<String> { Binding(get: { value[key]?.string ?? value[key]?.number.map { String(format: "%.0f", $0) } ?? "" }, set: { value[key] = .string($0) }) }
    private var op: String { value["op"]?.string ?? "" }
    var body: some View {
        Picker("creator.field.op", selection: text("op")) { ForEach(TemplateAuthorCondition.operations, id: \.self) { Text(LocalizedStringKey("creator.choice." + $0)).tag($0) } }
        if op == "NODE_COMPLETED" { TextField("creator.field.nodeId", text: text("nodeId")).keyboardType(.numberPad) }
        else if op == "HAS_TAG" { TextField("creator.field.tagValue", text: text("value")).textInputAutocapitalization(.never) }
        else {
            TextField("creator.field.var", text: text("var")).textInputAutocapitalization(.never)
            TextField("creator.field.value", text: text("value")).keyboardType(.numbersAndPunctuation)
        }
        Text("creatorRoot.conditionScope").font(.footnote)
    }
}

@MainActor private struct TemplateRoleViewEditor: View {
    @ObservedObject var model: TemplateAuthoringModel
    let role: String
    private var fields: [String: TemplateAuthoringJSON] { model.draft.advanced.value["roleViews"]?.object ?? [:] }
    private var views: [TemplateAuthoringJSON] { fields["views"]?.array ?? [] }
    private var viewIndex: Int? { views.firstIndex { $0.object?["roleId"]?.string == role } }
    private var view: [String: TemplateAuthoringJSON] { viewIndex.map { views[$0].object ?? [:] } ?? [:] }
    private var items: [TemplateAuthoringJSON] { view["items"]?.array ?? [] }
    private func write(_ key: String, _ entry: TemplateAuthoringJSON) {
        guard let index = viewIndex else { return }; var rows = views; var fields = view; fields[key] = entry; rows[index] = .object(fields); model.draft.advanced.set("roleViews", "views", .array(rows))
    }
    private func binding(_ key: String) -> Binding<String> { Binding(get: { view[key]?.string ?? "" }, set: { write(key, .string($0)) }) }
    var body: some View {
        Form {
            Section {
                TextField("creatorRoot.roleLabel", text: Binding(get: {
                    (fields["roles"]?.array ?? []).first { $0.object?["id"]?.string == role }?.object?["label"]?.string ?? ""
                }, set: { text in
                    var roles = fields["roles"]?.array ?? []; guard let index = roles.firstIndex(where: { $0.object?["id"]?.string == role }) else { return }
                    var value = roles[index].object ?? [:]; value["label"] = .string(text); roles[index] = .object(value); model.draft.advanced.set("roleViews", "roles", .array(roles))
                }))
                TextField("creator.field.title", text: binding("title"), axis: .vertical)
                TextField("creator.field.body", text: binding("body"), axis: .vertical)
                Text("creatorRoot.roleTextLimit").font(.caption)
            }
            Section("creatorRoot.roleItems") {
                ForEach(items.indices, id: \.self) { index in
                    VStack {
                        itemField(index, "label"); itemField(index, "text")
                    }
                }.onDelete { indexes in var copy = items; for index in indexes.sorted(by: >) { copy.remove(at: index) }; write("items", .array(copy)) }
                Button("creator.add") { var copy = items; copy.append(.object(["label": .string(""), "text": .string("")])); write("items", .array(copy)) }.disabled(items.count >= 8)
            }
            if viewIndex == nil { Text("creatorRoot.validation.roles") }
        }.navigationTitle("creatorRoot.roleViews")
    }
    private func itemField(_ index: Int, _ key: String) -> some View {
        TextField(LocalizedStringKey(key == "label" ? "creator.field.label" : "creatorRoot.itemText"), text: Binding(get: { items.indices.contains(index) ? items[index].object?[key]?.string ?? "" : "" }, set: { text in
            var copy = items; guard copy.indices.contains(index) else { return }; var row = copy[index].object ?? [:]; row[key] = .string(text); copy[index] = .object(row); write("items", .array(copy))
        }), axis: .vertical)
    }
}

@MainActor struct TemplateD20ConfigurationView: View {
    @ObservedObject var model: TemplateAuthoringModel
    private func binding(_ key: String) -> Binding<String> { Binding(get: { model.draft.advanced.text("diceRoll", key) }, set: { model.draft.advanced.set("diceRoll", key, .string($0)) }) }
    var body: some View {
        TextField("creatorRoot.dc", text: binding("dc")).keyboardType(.numberPad)
        TextField("creatorRoot.modifier", text: binding("modifier")).keyboardType(.numbersAndPunctuation)
        Picker("creatorRoot.rollMode", selection: binding("rollMode")) { ForEach(["normal", "advantage", "disadvantage"], id: \.self) { Text(LocalizedStringKey("creatorRoot.roll." + $0)).tag($0) } }
        TextField("creator.field.successText", text: binding("successText"), axis: .vertical)
        TextField("creator.field.failText", text: binding("failText"), axis: .vertical)
        Text("creatorRoot.d20Bounds").font(.footnote)
        NavigationLink("creatorRoot.d20Preview") { TemplateD20RehearsalView(draft: model.draft.advanced) }.disabled(!model.draft.advanced.legacyVariantIssues.isEmpty)
    }
}
