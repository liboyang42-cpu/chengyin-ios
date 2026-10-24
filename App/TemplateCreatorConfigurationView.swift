import SwiftUI
import Combine

@MainActor struct TemplateCreatorConfigurationView: View {
    @ObservedObject var model: TemplateAuthoringModel
    let family: TemplateCreatorFamily
    private var issues: [TemplateCreatorIssue] { model.draft.advanced.creatorIssues(family) }
    private var usesHotspotPlacement: Bool { family == .hiddenObject && TemplateHotspotPlacement(model.draft.advanced).isSupported && TemplateHotspotPlacement(model.draft.advanced).sceneURL != nil }
    private var usesPredictionPlan: Bool { family == .predict && TemplatePredictionPlan(model.draft.advanced).isSupported }
    private var configurationFields: [TemplateCreatorField] { TemplateCreatorSchema.fields(family).filter { (!usesHotspotPlacement || $0.id != "hotspots") && (!usesPredictionPlan || !TemplatePredictionPlan.managedFields.contains($0.id)) } }
    var body: some View {
        Form {
            Section {
                Toggle("templateAuthor.moduleEnabled", isOn: Binding(get: { model.draft.advanced.enabled(family.rawValue) }, set: { model.draft.advanced.setCreatorEnabled(family, $0) }))
                Text(LocalizedStringKey(family.providerKey)).font(.footnote).foregroundStyle(.secondary)
            }
            if model.draft.advanced.enabled(family.rawValue) {
                if family == .check {
                    Section { NavigationLink { TemplateCheckPresetView(model: model) } label: { TemplateCheckPresetEntryLabel() } }
                }
                if family == .scan && TemplateScanResponseConfiguration(model.draft.advanced).isSupported {
                    Section { NavigationLink("templateScan.title") { TemplateScanResponseEditor(model: model) } }
                    TemplateCreatorFieldsView(model: model, family: family, fields: configurationFields.filter { !TemplateScanResponseConfiguration.managedFields.contains($0.id) }, path: [])
                } else {
                TemplateCreatorFieldsView(model: model, family: family, fields: configurationFields, path: [])
                }
                if usesHotspotPlacement {
                    Section { NavigationLink("templateHotspots.title") { TemplateHotspotPlacementView(model: model) } }
                }
                if usesPredictionPlan {
                    Section { NavigationLink("templatePrediction.title") { TemplatePredictionPlanEditor(model: model) } }
                }
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
    @ViewBuilder var body: some View {
            if TemplateChoiceMemory.isOptionPath(family, path) {
                let memory = TemplateChoiceMemory(model.draft.advanced, family: family, optionPath: path)
                if memory.isSupported {
                    TemplateChoiceMemoryFields(model: model, family: family, optionPath: path).id(memory.scopeFingerprint)
                }
            }
        ForEach(fields) { field in
            if family == .multiplayer, path.isEmpty, ["roles", "turnOrder"].contains(field.id), TemplateMultiplayerPlan(model.draft.advanced).isSupported {
                if field.id == "roles" {
                    NavigationLink("templateTeam.title") { TemplateMultiplayerPlanEditor(model: model) }
                }
            } else {
                TemplateCreatorFieldView(model: model, family: family, field: field, path: path + [.field(field.id)])
            }
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
        if family == .blindTaste && field.id == "options" && path == [.field("options")] && TemplateBlindOptions(model.draft.advanced).isSupported { return true }
        if family == .qa && field.id == "options" && object["mode"]?.string != "PICK" { return true }
        if family == .qa && field.id == "correct" && TemplateQAAnswerSelection(model.draft.advanced).isSupported { return true }
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
        if family == .photoCheck && path == [.field("frameOpacity")] && TemplatePhotoFrameConfiguration(model.draft.advanced).isSupported { return true }
        if family == .compare && field.id == "effects" { return true }
        if let step = branchStep {
            if ["outcomeCode", "outcomeLabel"].contains(field.id) && !step.terminal { return true }
            if field.id == "options" && step.terminal { return true }
        }
        return false
    }
    var body: some View {
        if !hidden {
            if family == .blindTaste && field.id == "answerKey" && path == [.field("answerKey")] {
                TemplateBlindOptionFields(model: model)
                if !TemplateBlindOptions(model.draft.advanced).isSupported { control.accessibilityIdentifier("creator.field.blindTaste.answerKey") }
            } else if family == .qa && field.id == "multi" && path == [.field("multi")] {
                if model.draft.advanced.text("qa", "mode") == "PICK" {
                    TemplateQAAnswerFields(model: model)
                    if !TemplateQAAnswerSelection(model.draft.advanced).isSupported { control.accessibilityIdentifier("creator.field.qa.multi") }
                }
            } else if family == .compare && field.id == "maxAttempts" {
                Toggle("creator.compare.limitAttempts", isOn: Binding(get: { current != .null }, set: { write($0 ? .number(3) : nil) }))
                    .accessibilityIdentifier("creator.compare.limitAttempts")
                if current != .null { control.accessibilityIdentifier("creator.field.compare.maxAttempts") }
                else { Text("creator.compare.unlimited").font(.footnote) }
            } else if usesProfileRows {
                profileRows.accessibilityIdentifier("creator.field.profile." + field.id)
            } else if field.id == "kind", let index = profileQuestionIndex, profileComposition.isSupported {
                TemplateProfileKindFields(model: model, questionIndex: index).id(profileComposition.questions[index].key)
                if profileComposition.questions[index].kind == "pick" {
                    NavigationLink("templateProfileOverride.title") { TemplateProfileOverrideEditor(model: model, questionKey: profileComposition.questions[index].key) }
                }
            } else { control.accessibilityIdentifier("creator.field." + family.rawValue + "." + field.id) }
        }
    }
    @ViewBuilder private var control: some View {
        switch field.kind {
        case .text(let max, let required, _):
            if family == .photoCheck, path == [.field("frameUrl")], TemplatePhotoFrameConfiguration(model.draft.advanced).isSupported {
                NavigationLink("templateFrame.title") { TemplatePhotoFrameEditor(model: model) }
            } else {
            VStack(alignment: .leading) {
                TextField(LocalizedStringKey(field.labelKey), text: text, axis: .vertical).textInputAutocapitalization(.never)
                HStack { if required { Text("creator.required") }; Spacer(); Text(verbatim: "\(text.wrappedValue.utf16.count)/\(max)") }.font(.caption).foregroundStyle(.secondary)
            }
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
            if field.id == "terminal", let index = branchStepIndex, let step = branchStep {
                TemplateBranchTerminalFields(model: model, stepIndex: index).id(step.id)
            } else {
                Toggle(LocalizedStringKey(field.labelKey), isOn: Binding(get: { current.bool }, set: { write(.bool($0)) }))
            }
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
            if TemplateEffectList.isEffectPath(family, path), TemplateEffectList(model.draft.advanced, family: family, path: path).isSupported {
                NavigationLink { TemplateEffectListView(model: model, family: family, path: path, titleKey: field.labelKey) }
                    label: { LabeledContent(LocalizedStringKey(field.labelKey), value: String(rows.count)) }
            } else {
            NavigationLink {
                if family == .pricePair, path == [.field("items")], TemplatePictureChoices(model.draft.advanced).isSupported {
                    TemplatePictureChoiceEditor(model: model)
                } else {
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
                    if family == .branch, path == [.field("steps")], branchComposition.isSupported {
                        TemplateBranchAddRowButton(model: model)
                    } else if field.id == "options", let index = branchStepIndex, let step = branchStep {
                        TemplateBranchAddRowButton(model: model, stepIndex: index).id(step.id)
                    } else {
                        Button("creator.add") { model.draft.advanced.addCreatorRow(family, path: path, field: field) }.disabled(rows.count >= maximum)
                    }
                    Text(verbatim: "\(rows.count) / \(minimum)…\(maximum)").font(.caption)
                }.toolbar { EditButton() }.navigationTitle(LocalizedStringKey(field.labelKey))
                }
            } label: { LabeledContent(LocalizedStringKey(field.labelKey), value: String(rows.count)) }
            }
        case .strings(_, let max, let length): stringRows(max: max, length: length)
        case .poems:
            NavigationLink {
                if family == .dailySign, TemplateDailyPoemPool(model.draft.advanced).isSupported {
                    TemplateDailyPoemEditor(model: model)
                } else {
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
                }
            } label: { LabeledContent(LocalizedStringKey(field.labelKey), value: String(rows.count)) }
        }
    }
    private var branchComposition: TemplateBranchComposition { .init(model.draft.advanced) }
    private var branchStepIndex: Int? {
        guard family == .branch, path.count == 3, path[0] == .field("steps"), case .index(let index) = path[1] else { return nil }
        return index
    }
    private var branchStep: TemplateBranchComposition.Step? {
        guard let index = branchStepIndex, branchComposition.isSupported, branchComposition.steps.indices.contains(index) else { return nil }
        return branchComposition.steps[index]
    }
    private func rowLabel(_ index: Int) -> String {
        let row = rows[index].object ?? [:]
        return ["label", "title", "name", "line", "key", "id", "op", "url"].compactMap { row[$0]?.string }.first(where: { !$0.isEmpty }) ?? String(index + 1)
    }
    private var profileComposition: TemplateProfileQuestionComposition { .init(model.draft.advanced) }
    private var profileQuestionIndex: Int? {
        guard family == .profile, path.count == 3, path[0] == .field("questions"), case .index(let index) = path[1],
              profileComposition.questions.indices.contains(index) else { return nil }
        return index
    }
    private var usesProfileRows: Bool {
        family == .profile && profileComposition.isSupported &&
            (path == [.field("questions")] || (field.id == "options" && profileQuestionIndex != nil))
    }
    @ViewBuilder private var profileRows: some View {
        if case .rows(let fields, _, _, _) = field.kind {
            NavigationLink {
                TemplateProfileQuestionRowsEditor(model: model, questionIndex: profileQuestionIndex) { index in
                    Form { TemplateCreatorFieldsView(model: model, family: family, fields: fields, path: path + [.index(index)]) }
                        .navigationTitle(LocalizedStringKey(field.labelKey))
                }
            } label: { LabeledContent(LocalizedStringKey(field.labelKey), value: String(rows.count)) }
        }
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

// Local editor conveniences; the existing check schema remains authoritative.
enum TemplateCheckLuckChoice: String, CaseIterable, Identifiable, Hashable {
    case off, high, low, both
    var id: String { rawValue }
}

struct TemplateCheckPresetConfiguration {
    enum Step: String, CaseIterable, Hashable {
        case high, low, hurt, severe
        var label: String {
            switch self {
            case .high: return "High luck +1"
            case .low: return "Low luck -1"
            case .hurt: return "Injured -1"
            case .severe: return "Severely injured -1"
            }
        }
        var condition: [String: TemplateAuthoringJSON] {
            let variable = self == .high || self == .low ? "sys.luck" : "sys.hp"
            let threshold = self == .low ? 0 : self == .hurt ? 6 : 3
            return ["var": .string(variable), "op": .string(self == .high ? "GTE" : "LTE"), "value": .number(Double(threshold))]
        }
        var row: TemplateAuthoringJSON {
            .object(["label": .string(label), "value": .number(self == .high ? 1 : -1), "when": .object(condition)])
        }
    }
    let original: TemplateAdvancedDraft
    let rows: [TemplateAuthoringJSON]
    let isSupported: Bool
    let luck: TemplateCheckLuckChoice
    let hpLadder: Bool
    private let managed: [Int: Step]

    init(_ original: TemplateAdvancedDraft) {
        self.original = original
        let fields = original.value["check"]?.object
        rows = fields?["mods"]?.array ?? []
        var supported = fields?["enabled"] == .bool(true)
            && (fields?["mods"] == nil || fields?["mods"]?.array != nil)
            && original.creatorIssues(.check).allSatisfy { !$0.path.hasPrefix("mods") }
        var found: [Int: Step] = [:]
        var seen = Set<Step>()
        for (index, row) in rows.enumerated() {
            if let step = Step.allCases.first(where: { $0.row == row }) {
                if !seen.insert(step).inserted { supported = false }
                found[index] = step
            } else if let object = row.object {
                // A familiar label or condition does not grant ownership of a custom row.
                let condition = object["when"]?.object ?? [:]
                if Step.allCases.contains(where: { step in
                    object["label"]?.string == step.label ||
                    (condition["var"] == step.condition["var"] && condition["op"] == step.condition["op"] &&
                     condition["value"]?.number == step.condition["value"]?.number)
                }) { supported = false }
            }
        }
        let partialLadder = seen.contains(.hurt) != seen.contains(.severe)
        if partialLadder { supported = false }
        managed = found; isSupported = supported
        switch (seen.contains(.high), seen.contains(.low)) {
        case (true, true): luck = .both
        case (true, false): luck = .high
        case (false, true): luck = .low
        case (false, false): luck = .off
        }
        hpLadder = seen.contains(.hurt) && seen.contains(.severe)
    }

    func applying(luck: TemplateCheckLuckChoice, hpLadder: Bool) -> TemplateAdvancedDraft? {
        guard isSupported else { return nil }
        var selected = Set<Step>()
        if luck == .high || luck == .both { selected.insert(.high) }
        if luck == .low || luck == .both { selected.insert(.low) }
        if hpLadder { selected.formUnion([.hurt, .severe]) }
        var result: [TemplateAuthoringJSON] = []
        for (index, row) in rows.enumerated() {
            if let step = managed[index] {
                if selected.remove(step) != nil { result.append(row) }
            } else { result.append(row) }
        }
        for step in Step.allCases where selected.contains(step) { result.append(step.row) }
        guard result.count <= 16 else { return nil }
        var next = original
        if !result.isEmpty || original.value["check"]?.object?["mods"] != nil {
            next.set("check", "mods", .array(result))
        }
        guard next.creatorIssues(.check).allSatisfy({ !$0.path.hasPrefix("mods") }) else { return nil }
        return next
    }

    static func modifier(in draft: TemplateAdvancedDraft, hp: Int, luck: Int) -> Int? {
        guard draft.value["check"]?.object?["enabled"] == .bool(true),
              draft.creatorIssues(.check).allSatisfy({ !$0.path.hasPrefix("mods") }) else { return nil }
        var sample = TemplateRootSampleState(); sample.values["sys.hp"] = hp; sample.values["sys.luck"] = luck
        var total = 0
        for row in draft.rows("check", "mods") {
            guard let object = row.object, let condition = object["when"]?.object,
                  let amount = object["value"]?.integer else { return nil }
            if TemplateAuthorCondition(condition).matches(sample: sample) { total += amount }
        }
        return total
    }
}

@MainActor final class TemplateCheckPresetController: ObservableObject {
    private let model: TemplateAuthoringModel
    private var observation: AnyCancellable?
    private var generation = UUID(), metadata = UUID(), media = UUID()
    private var owner: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var source: Data?
    private(set) var isVisible = false
    private var sceneActive = false
    @Published private(set) var configuration: TemplateCheckPresetConfiguration?
    @Published private(set) var luck: TemplateCheckLuckChoice = .off
    @Published private(set) var hpLadder = false
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
    var visibleConfiguration: TemplateCheckPresetConfiguration? { isCurrent ? configuration : nil }
    var preview: TemplateAdvancedDraft? { visibleConfiguration?.applying(luck: luck, hpLadder: hpLadder) }
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
        let config = TemplateCheckPresetConfiguration(model.draft.advanced)
        configuration = config; luck = config.luck; hpLadder = config.hpLadder
    }
    func retire() {
        generation = UUID(); source = nil; owner = nil; identity = nil
        configuration = nil; luck = .off; hpLadder = false; didApply = false
    }
    var luckBinding: Binding<TemplateCheckLuckChoice> {
        let stamp = generation
        return .init(get: { [weak self] in
            guard let self, self.generation == stamp, self.visibleConfiguration?.isSupported == true else { return .off }
            return self.luck
        }, set: { [weak self] value in
            guard let self, self.generation == stamp, self.visibleConfiguration?.isSupported == true else { return }
            self.luck = value; self.didApply = false
        })
    }
    var hpBinding: Binding<Bool> {
        let stamp = generation
        return .init(get: { [weak self] in
            guard let self, self.generation == stamp, self.visibleConfiguration?.isSupported == true else { return false }
            return self.hpLadder
        }, set: { [weak self] value in
            guard let self, self.generation == stamp, self.visibleConfiguration?.isSupported == true else { return }
            self.hpLadder = value; self.didApply = false
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

enum TemplateCheckPresetText {
    case title, scope, luck, off, high, low, both, ladder, warning, retained, unsupported, preview, apply, applied, cancel, reload
    func value(_ locale: Locale) -> String {
        let chinese = locale.language.languageCode?.identifier == "zh"
        switch self {
        case .title: return chinese ? "检定条件修正预设" : "Check modifier presets"
        case .scope: return chinese ? "仅应用到当前未保存草稿，不会保存、发布或发起检定。" : "Apply to the current unsaved draft only. This does not save, publish or run a check."
        case .luck: return chinese ? "幸运修正" : "Luck modifier"
        case .off: return chinese ? "关闭幸运预设" : "Luck presets off"
        case .high: return chinese ? "幸运 ≥ 3 时加1" : "Luck ≥ 3 adds 1"
        case .low: return chinese ? "幸运 ≤ 0 时减1" : "Luck ≤ 0 subtracts 1"
        case .both: return chinese ? "同时使用两档幸运修正" : "Use both luck modifiers"
        case .ladder: return chinese ? "生命值越低越困难" : "Lower HP makes checks harder"
        case .warning: return chinese ? "HP ≤ 6 减1，HP ≤ 3 再减1，两档累计最多减2。" : "HP ≤ 6 subtracts 1; HP ≤ 3 subtracts another 1. The ladder totals at most -2."
        case .retained: return chinese ? "其他条件修正与字段保持原样，所有命中修正逐项累加。" : "Other modifiers and fields are retained. All matching modifiers are added together."
        case .unsupported: return chinese ? "配置存在未知、自定义冲突、重复或超出数量限制，请使用原条件编辑器检查。本页不会覆盖。" : "Unknown, conflicting, duplicate or over-limit modifiers require the original editor. This page will not overwrite them."
        case .preview: return chinese ? "本地修正合计（其他状态使用示例值）" : "Local modifier total (other state uses sample values)"
        case .apply: return chinese ? "应用到当前草稿" : "Apply to current draft"
        case .applied: return chinese ? "已应用到草稿，尚未保存或发布。" : "Applied to the draft. Not saved or published."
        case .cancel: return chinese ? "取消未应用的选择" : "Cancel unapplied selection"
        case .reload: return chinese ? "重新读取当前配置" : "Reload current configuration"
        }
    }
}

@MainActor struct TemplateCheckPresetEntryLabel: View {
    @Environment(\.locale) private var locale
    var body: some View { Text(verbatim: TemplateCheckPresetText.title.value(locale)) }
}

@MainActor struct TemplateCheckPresetView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateCheckPresetController
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    init(model: TemplateAuthoringModel) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model))
    }
    private func text(_ key: TemplateCheckPresetText) -> String { key.value(locale) }
    private func luckText(_ choice: TemplateCheckLuckChoice) -> String {
        switch choice {
        case .off: return text(.off)
        case .high: return text(.high)
        case .low: return text(.low)
        case .both: return text(.both)
        }
    }
    var body: some View {
        Form {
            Section { Text(verbatim: text(.scope)); Text(verbatim: text(.retained)).font(.footnote) }
            if controller.visibleConfiguration?.isSupported == true {
                Section {
                    Picker(text(.luck), selection: controller.luckBinding) {
                        ForEach(TemplateCheckLuckChoice.allCases) { choice in Text(verbatim: luckText(choice)).tag(choice) }
                    }.accessibilityIdentifier("templateCheckPresets.luck")
                    Toggle(text(.ladder), isOn: controller.hpBinding).accessibilityIdentifier("templateCheckPresets.hp")
                    Text(verbatim: text(.warning)).font(.footnote)
                }
                if let draft = controller.preview {
                    Section(text(.preview)) {
                        ForEach([7, 6, 3], id: \.self) { hp in
                            ForEach([0, 3], id: \.self) { luck in
                                if let amount = TemplateCheckPresetConfiguration.modifier(in: draft, hp: hp, luck: luck) {
                                    LabeledContent("HP \(hp), \(text(.luck)) \(luck)", value: String(amount))
                                }
                            }
                        }
                    }.accessibilityIdentifier("templateCheckPresets.preview")
                } else { Text(verbatim: text(.unsupported)) }
                Button(text(.apply), action: controller.applyAction()).disabled(!controller.canApply)
                    .accessibilityIdentifier("templateCheckPresets.apply")
                if controller.didApply { Text(verbatim: text(.applied)).accessibilityIdentifier("templateCheckPresets.applied") }
            } else {
                Text(verbatim: text(.unsupported))
                Button(text(.reload), action: controller.reloadAction()).accessibilityIdentifier("templateCheckPresets.reload")
            }
            Button(text(.cancel), action: controller.cancelAction { dismiss() }).accessibilityIdentifier("templateCheckPresets.cancel")
        }.navigationTitle(text(.title))
            .onAppear { controller.viewAppeared(sceneIsActive: scenePhase == .active) }
            .onDisappear { controller.viewDisappeared() }
            .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
    }
}
