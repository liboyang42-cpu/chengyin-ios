import SwiftUI
import Combine

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
                NavigationLink { TemplateLowHPPresetView(model: model) } label: { TemplateLowHPPresetEntryLabel() }
                    .accessibilityIdentifier("templateLowHP.open")
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

struct TemplateLowHPPresetConfiguration {
    struct Option: Identifiable, Equatable {
        let field: TemplateRelaxField
        let operation: String
        var id: String { field.rawValue + ":" + operation }
        var row: TemplateAuthoringJSON {
            .object(["when": .object(TemplateAuthorCondition().value), "relax": .object([field.rawValue: .string(operation)])])
        }
    }
    let original: TemplateAdvancedDraft
    let options: [Option]
    private(set) var selectedID = ""
    private(set) var isSupported = true
    private var rows: [TemplateAuthoringJSON] = []
    private var managedIndex: Int?
    init(_ draft: TemplateAdvancedDraft) {
        original = draft; options = Self.makeOptions(draft)
        if let raw = draft.value["variants"] {
            guard let array = raw.array else { isSupported = false; return }
            rows = array
        }
        for (index, raw) in rows.enumerated() {
            guard let condition = raw.object?["when"]?.object,
                  condition["var"]?.string == "sys.hp", condition["op"]?.string == "LTE",
                  condition["value"]?.number == 3 else { continue }
            // Only an exact currently available preset is managed here. Leave custom or
            // ambiguous low-HP rules to the existing full editor rather than replacing them.
            guard managedIndex == nil, let known = options.first(where: { $0.row == raw }) else {
                isSupported = false; return
            }
            managedIndex = index; selectedID = known.id
        }
    }
    private static func makeOptions(_ draft: TemplateAdvancedDraft) -> [Option] {
        var result: [Option] = []
        for field in draft.eligibleRelaxFields {
            // No option can activate a disabled capability or device-only experience.
            if [.compassTolerance, .compassHold, .shout].contains(field) { continue }
            guard draft.value[field.section]?.object?["enabled"] == .bool(true),
                  let base = draft.value[field.section]?.object?[field.field]?.number,
                  base.isFinite, base > 0 else { continue }
            var operations: [String] = []
            switch field {
            case .timer: operations = ["+30"]
            case .typingTime: operations = ["+15"]
            case .shakeTime:
                if draft.value["ballShake"]?.object?["timed"] == .bool(true) { operations = ["+5"] }
            case .sortAttempts, .pictureAttempts, .typingAttempts, .qaAttempts, .hiddenAttempts, .stopwatchAttempts:
                operations = ["+2", "=0"]
            case .quiet, .countdown, .shakeGoal:
                let delta = max(1, (base / 3).rounded())
                if delta < 100000 { operations = ["-" + String(Int(delta))] }
            case .reaction: operations = ["+150"]
            case .stopwatchTolerance, .estimateTolerance:
                let delta = base.rounded()
                if delta >= 1 && delta < 100000 { operations = ["+" + String(Int(delta))] }
            case .compassTolerance, .compassHold, .shout: break
            }
            for operation in operations {
                let option = Option(field: field, operation: operation)
                var probe = draft; probe.value["variants"] = .array([option.row])
                // Existing domain validation owns field bounds, enabled dependencies and direction.
                if probe.rootCreatorIssues.isEmpty { result.append(option) }
            }
        }
        return result
    }
    func applying(_ selection: String) -> TemplateAdvancedDraft? {
        guard isSupported else { return nil }
        var kept = rows
        if selection.isEmpty {
            if let managedIndex { kept.remove(at: managedIndex) }
        } else {
            guard let option = options.first(where: { $0.id == selection }) else { return nil }
            if let managedIndex { kept[managedIndex] = option.row }
            else {
                guard kept.count < 16 else { return nil }
                kept.append(option.row)
            }
        }
        var next = original
        if !kept.isEmpty || original.value["variants"] != nil { next.value["variants"] = .array(kept) }
        guard next.rootCreatorIssues.isEmpty else { return nil }
        return next
    }
}

@MainActor final class TemplateLowHPPresetController: ObservableObject {
    private let model: TemplateAuthoringModel
    private var observation: AnyCancellable?
    private var generation = UUID(), metadata = UUID(), media = UUID()
    private var owner: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var source: Data?
    private(set) var isVisible = false
    private var sceneActive = false
    @Published private(set) var configuration: TemplateLowHPPresetConfiguration?
    @Published private(set) var selection = ""
    @Published private(set) var didApply = false
    init(model: TemplateAuthoringModel) {
        self.model = model
        observation = model.objectWillChange.sink { [weak self] _ in self?.retire() }
    }
    private var canLoad: Bool { isVisible && sceneActive && model.canEdit && !model.busy && model.review == nil }
    private var isCurrent: Bool {
        canLoad && owner != nil && owner == model.coordinator.session && identity == model.coordinator.identity &&
        metadata == model.metadataGeneration && media == model.mediaReviewGeneration &&
        source != nil && source == TemplateSamplePreview.snapshot(model.draft)
    }
    var visibleConfiguration: TemplateLowHPPresetConfiguration? { isCurrent ? configuration : nil }
    var preview: TemplateAdvancedDraft? { visibleConfiguration?.applying(selection) }
    var canApply: Bool { preview.map { $0 != model.draft.advanced } ?? false }
    func viewAppeared(sceneIsActive: Bool) {
        isVisible = true; sceneActive = sceneIsActive
        guard sceneActive else { retire(); return }
        if configuration == nil { reload() }
    }
    func viewDisappeared() { isVisible = false; retire() }
    func sceneChanged(isActive: Bool) {
        let becameActive = !sceneActive && isActive; sceneActive = isActive
        guard isVisible && sceneActive else { retire(); return }
        if becameActive { reload() }
    }
    func reload() {
        retire()
        guard canLoad, let bytes = TemplateSamplePreview.snapshot(model.draft) else { return }
        owner = model.coordinator.session; identity = model.coordinator.identity
        metadata = model.metadataGeneration; media = model.mediaReviewGeneration; source = bytes
        let value = TemplateLowHPPresetConfiguration(model.draft.advanced)
        configuration = value; selection = value.selectedID
    }
    func retire() {
        generation = UUID(); source = nil; owner = nil; identity = nil; configuration = nil; selection = ""; didApply = false
    }
    var selectionBinding: Binding<String> {
        let stamp = generation
        return .init(get: { [weak self] in
            guard let self, self.generation == stamp, let config = self.visibleConfiguration, config.isSupported else { return "" }
            return self.selection
        }, set: { [weak self] value in
            guard let self, self.generation == stamp, let config = self.visibleConfiguration, config.isSupported,
                  value.isEmpty || config.options.contains(where: { $0.id == value }) else { return }
            self.selection = value; self.didApply = false
        })
    }
    func applyAction() -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.generation == stamp, self.canApply, let next = self.preview else { return }
            let owner = self.owner, identity = self.identity
            var draft = self.model.draft; draft.advanced = next
            self.model.draft = draft; self.model.changed()
            guard self.canLoad, self.model.coordinator.session == owner, self.model.coordinator.identity == identity else { return }
            self.reload(); self.didApply = true
        }
    }
    func cancelAction(_ dismiss: @escaping () -> Void) -> () -> Void {
        let stamp = generation, owner = model.coordinator.session, identity = model.coordinator.identity
        return { [weak self] in
            guard let self, self.isVisible, self.sceneActive, self.generation == stamp,
                  self.model.coordinator.session == owner, self.model.coordinator.identity == identity else { return }
            self.retire(); dismiss()
        }
    }
    func reloadAction() -> () -> Void {
        let stamp = generation, owner = model.coordinator.session, identity = model.coordinator.identity
        return { [weak self] in
            guard let self, self.generation == stamp, self.model.coordinator.session == owner,
                  self.model.coordinator.identity == identity else { return }
            self.reload()
        }
    }
}

enum TemplateLowHPPresetText: CaseIterable {
    case title, scope, choice, off, empty, retained, unsupported, preview, rule, noMatch, apply, applied, cancel, reload
    func value(_ locale: Locale) -> String {
        let chinese = locale.language.languageCode?.identifier == "zh"
        switch self {
        case .title: return chinese ? "低HP放宽预设" : "Low-HP easing preset"
        case .scope: return chinese ? "仅应用到当前未保存草稿，不会保存、启动玩法或提交。" : "Apply to the current unsaved draft only. This does not save, run gameplay or submit."
        case .choice: return chinese ? "HP ≤ 3 时的放宽方式" : "Adjustment when HP ≤ 3"
        case .off: return chinese ? "不使用此预设" : "No preset"
        case .empty: return chinese ? "当前没有可安全放宽的配置。请先完成并启用玩法配置。" : "No valid adjustments are available. Configure and enable an eligible game first."
        case .retained: return chinese ? "其他规则及其顺序保持不变，预演仅应用首个命中规则。" : "Other rules and their order are retained. Preview applies the first matching rule only."
        case .unsupported: return chinese ? "存在自定义、未知或不可用的低HP规则，请在原规则编辑器检查；本页不会覆盖。" : "A custom, unknown or unavailable low-HP rule needs the full rule editor. This page will not overwrite it."
        case .preview: return chinese ? "HP为3的本地预演" : "Local preview at HP 3"
        case .rule: return chinese ? "首个命中规则" : "First matching rule"
        case .noMatch: return chinese ? "未命中规则" : "No matching rule"
        case .apply: return chinese ? "应用到当前草稿" : "Apply to current draft"
        case .applied: return chinese ? "已应用到草稿，尚未保存或发布。" : "Applied to the draft. Not saved or published."
        case .cancel: return chinese ? "取消未应用的选择" : "Cancel unapplied selection"
        case .reload: return chinese ? "重新读取当前配置" : "Reload current configuration"
        }
    }
}

@MainActor struct TemplateLowHPPresetEntryLabel: View {
    @Environment(\.locale) private var locale
    var body: some View { Text(verbatim: TemplateLowHPPresetText.title.value(locale)) }
}

@MainActor struct TemplateLowHPPresetView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateLowHPPresetController
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    init(model: TemplateAuthoringModel) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model))
    }
    private func text(_ key: TemplateLowHPPresetText) -> String { key.value(locale) }
    var body: some View {
        Form {
            Section { Text(verbatim: text(.scope)); Text(verbatim: text(.retained)).font(.footnote) }
            if let config = controller.visibleConfiguration, config.isSupported {
                Section {
                    Picker(text(.choice), selection: controller.selectionBinding) {
                        Text(verbatim: text(.off)).tag("")
                        ForEach(config.options) { option in
                            Text("\(Text(LocalizedStringKey(option.field.labelKey))) \(option.operation)").tag(option.id)
                        }
                    }.accessibilityIdentifier("templateLowHP.choice")
                    if config.options.isEmpty { Text(verbatim: text(.empty)) }
                }
                if let draft = controller.preview, let evaluated = try? draft.rehearsedVariant(sample: .init()) {
                    Section(text(.preview)) {
                        if let index = evaluated.index { LabeledContent(text(.rule), value: String(index + 1)) }
                        else { Text(verbatim: text(.noMatch)) }
                        ForEach(TemplateRelaxField.allCases) { field in
                            if draft.text(field.section, field.field) != evaluated.draft.text(field.section, field.field) {
                                LabeledContent(LocalizedStringKey(field.labelKey), value: draft.text(field.section, field.field) + " → " + evaluated.draft.text(field.section, field.field))
                            }
                        }
                    }.accessibilityIdentifier("templateLowHP.preview")
                }
                if controller.preview == nil { Text(verbatim: text(.unsupported)) }
                Button(text(.apply), action: controller.applyAction()).disabled(!controller.canApply)
                    .accessibilityIdentifier("templateLowHP.apply")
                if controller.didApply { Text(verbatim: text(.applied)).accessibilityIdentifier("templateLowHP.applied") }
            } else {
                Text(verbatim: text(.unsupported))
                Button(text(.reload), action: controller.reloadAction()).accessibilityIdentifier("templateLowHP.reload")
            }
            Button(text(.cancel), action: controller.cancelAction { dismiss() }).accessibilityIdentifier("templateLowHP.cancel")
        }.navigationTitle(text(.title))
            .onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }
            .onDisappear { controller.viewDisappeared() }
            .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
    }
}
