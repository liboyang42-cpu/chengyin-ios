import SwiftUI

struct TemplateRootRehearsalView: View {
    let draft: TemplateAdvancedDraft
    @State private var sample = TemplateRootSampleState()
    @State private var role = "A"
    @State private var applied: Int?
    @State private var changes: [String: String] = [:]
    @State private var evaluated = false
    private var conditions: [TemplateAuthorCondition] { draft.rootVariants.compactMap { $0.object?["when"]?.object }.map(TemplateAuthorCondition.init) }
    private var variables: [String] { Set(conditions.filter { !["HAS_TAG", "NODE_COMPLETED"].contains($0.op) }.compactMap { $0.value["var"]?.string }).sorted() }
    private var tags: [String] { Set(conditions.filter { $0.op == "HAS_TAG" }.compactMap { $0.value["value"]?.string }).sorted() }
    private var nodes: [Int] { Set(conditions.filter { $0.op == "NODE_COMPLETED" }.compactMap { $0.value["nodeId"]?.integer }).sorted() }
    var body: some View {
        Form {
            Section { Text("creator.localOnly").font(.headline); Text("creatorRoot.rehearsalLimit").font(.footnote) }
            if let tier = draft.value["mistakeTier"]?.string { Section("creatorRoot.mistakeTier") { Text(LocalizedStringKey("creator.choice." + tier)); Text("creatorRoot.damageServer").font(.footnote) } }
            if !draft.rootVariants.isEmpty {
                Section("creatorRoot.sampleState") {
                    ForEach(variables, id: \.self) { key in
                        Stepper(value: Binding(get: { sample.values[key] ?? 0 }, set: { sample.values[key] = $0; evaluated = false }), in: -99...99) { LabeledContent(key, value: String(sample.values[key] ?? 0)) }
                    }
                    ForEach(tags, id: \.self) { tag in Toggle(tag, isOn: Binding(get: { sample.tags.contains(tag) }, set: { if $0 { sample.tags.insert(tag) } else { sample.tags.remove(tag) }; evaluated = false })) }
                    ForEach(nodes, id: \.self) { node in Toggle("\(node)", isOn: Binding(get: { sample.completedNodes.contains(node) }, set: { if $0 { sample.completedNodes.insert(node) } else { sample.completedNodes.remove(node) }; evaluated = false })) }
                    Button("creator.evaluate") { evaluate() }
                }
                if evaluated {
                    Section("creatorRoot.snapshot") {
                        if let applied { HStack { Text("creatorRoot.matchedRule"); Text(verbatim: String(applied + 1)) } }
                        else { Text("creatorRoot.noMatch") }
                        ForEach(changes.keys.sorted(), id: \.self) { key in LabeledContent(LocalizedStringKey("creatorRoot.relax." + key), value: changes[key] ?? "") }
                        Text("creatorRoot.frozenPreview").font(.footnote)
                    }
                }
            }
            if draft.enabled("roleViews") {
                Section("creatorRoot.roleViews") {
                    Picker("creatorRoot.roleLabel", selection: $role) { Text(verbatim: "A").tag("A"); Text(verbatim: "B").tag("B") }.pickerStyle(.segmented)
                    let fields = draft.value["roleViews"]?.object ?? [:]
                    if let view = (fields["views"]?.array ?? []).first(where: { $0.object?["roleId"]?.string == role })?.object {
                        Text(verbatim: view["title"]?.string ?? "").font(.title2)
                        Text(verbatim: view["body"]?.string ?? "")
                        ForEach(Array((view["items"]?.array ?? []).enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading) { Text(verbatim: item.object?["label"]?.string ?? "").font(.headline); Text(verbatim: item.object?["text"]?.string ?? "") }
                        }
                    }
                    Text("creatorRoot.roleViewsLimit").font(.footnote)
                }
            }
            Button("creator.reset") { sample = .init(); role = "A"; applied = nil; changes = [:]; evaluated = false }
        }.navigationTitle("creatorRoot.rehearse")
    }
    private func evaluate() {
        for key in variables where sample.values[key] == nil { sample.values[key] = 0 }
        guard let result = try? draft.rehearsedVariant(sample: sample) else { return }
        applied = result.index; evaluated = true; changes = [:]
        if let index = result.index, let fields = draft.rootVariants[index].object?["relax"]?.object {
            for key in fields.keys { guard let field = TemplateRelaxField(rawValue: key) else { continue }; changes[key] = draft.text(field.section, field.field) + " → " + result.draft.text(field.section, field.field) }
        }
    }
}

struct TemplateD20RehearsalView: View {
    let draft: TemplateAdvancedDraft
    @State private var sample: TemplateD20Rehearsal?
    var body: some View {
        Form {
            Section { Text("creator.localOnly"); Text("creatorRoot.d20RuntimeLimit").font(.footnote) }
            Section("creatorRoot.d20") {
                LabeledContent("creatorRoot.dc", value: draft.text("diceRoll", "dc"))
                LabeledContent("creatorRoot.modifier", value: draft.text("diceRoll", "modifier"))
                Text(LocalizedStringKey("creatorRoot.roll." + draft.text("diceRoll", "rollMode")))
                Button("creatorRoot.showSample") { sample = try? TemplateD20Rehearsal(draft: draft) }
                if let sample {
                    LabeledContent("creatorRoot.pips", value: sample.values.map(String.init).joined(separator: ", "))
                    LabeledContent("creatorRoot.kept", value: String(sample.kept)); LabeledContent("creatorRoot.total", value: String(sample.total))
                    Text(LocalizedStringKey(sample.success ? "creator.success" : "creator.failure"))
                    Text(verbatim: sample.text)
                }
            }
            Button("creator.reset") { sample = nil }
        }.navigationTitle("creatorRoot.d20Preview")
    }
}
