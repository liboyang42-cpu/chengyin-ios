import SwiftUI

/// Edits local drafts only. The parent chapter binding enforces current session, FULL scope,
/// pending/unknown locks and review invalidation. These forms never construct a transport.
@MainActor struct ProjectEditRichBlockEditor: View {
    @ObservedObject var model: ProjectEditModel
    @Binding var block: ProjectEditBlock
    let chapterID: String
    var chapterOverride: Binding<ProjectEditChapter>? = nil
    var allowsStoryConditionSource = false
    private var nodes: [ProjectEditNode] { (chapterOverride ?? model.chapter(chapterID)).wrappedValue.nodes }
    private var beat: ProjectEditNarrativeBeat? { ProjectEditNarrativeBeat(rawValue: block.fieldText("beat")) }
    private func text(_ key: String, integer: Bool = false) -> Binding<String> {
        Binding(get: { block.fieldText(key) }, set: { if integer { block.setIntegerField(key, $0) } else { block.setField(key, $0.isEmpty ? nil : .string($0)) } })
    }
    private func value(_ key: String) -> Binding<ProjectEditJSON?> { Binding(get: { block.sourceFields?[key] }, set: { block.setField(key, $0) }) }
    var body: some View {
        Form {
            switch block.kind {
            case .text, .voice, .reveal:
                Section("projectEdit.rich.content") {
                    TextField("projectEdit.story", text: $block.content, axis: .vertical).lineLimit(4...12)
                        .accessibilityIdentifier("projectEdit.rich.content")
                    if block.kind == .voice {
                        Picker("projectEdit.rich.speaker", selection: text("who")) {
                            ForEach(Array(ProjectEditRichStoryContract.voices.enumerated()), id: \.offset) { index, voice in
                                Text(LocalizedStringKey("projectEdit.rich.voice." + String(index))).tag(voice)
                            }
                        }
                    } else {
                        TextField("projectEdit.rich.speaker", text: text("who"))
                    }
                    if block.kind == .text {
                        Picker("projectEdit.rich.effect", selection: Binding(get: { block.sourceFields?["level"]?.integer ?? 0 }, set: { block.setField("level", .number(Decimal($0))) })) {
                            ForEach(0...3, id: \.self) { Text(String($0)).tag($0) }
                        }
                    }
                }
                if block.kind == .text { narrativeSection }
                if block.kind == .voice || (block.kind == .text && !block.isNarrative) {
                    Section("projectEdit.rich.condition") {
                        ProjectEditStoryConditionEditor(condition: value("when"), plain: true, ending: false)
                        if block.kind == .voice && allowsStoryConditionSource {
                            ProjectStoryConditionEntry(model: model, chapterID: chapterID, block: $block)
                                .id([Data(chapterID.utf8), Data(block.id.utf8)])
                        }
                    }
                }
            case .node:
                Section("projectEdit.rich.location") {
                    Text(verbatim: nodes.first { $0.id == block.nodeID }?.name ?? "")
                    Toggle("projectEdit.rich.locationRequired", isOn: Binding(get: { block.sourceFields?["locationRequired"] != .bool(false) }, set: { block.setField("locationRequired", .bool($0)) }))
                    Text("projectEdit.rich.storyGameHint").font(.caption).foregroundStyle(.secondary)
                }
            case .image, .audio:
                Section { ProjectEditReferenceField(title: LocalizedStringKey(block.kind == .image ? "projectEdit.imageReference" : "projectEdit.audioReference"), value: $block.url, identifier: "projectEdit.rich.media") }
            case .dream:
                Section("projectEdit.rich.album") {
                    TextField("projectEdit.rich.albumTitle", text: text("title")).accessibilityIdentifier("projectEdit.rich.albumTitle")
                    ForEach(block.dreamImages.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            TextField("projectEdit.imageReference", text: image(index, "url"))
                                .accessibilityIdentifier("projectEdit.rich.image.\(index)")
                            TextField("projectEdit.rich.imageCaption", text: image(index, "line"), axis: .vertical)
                            Button("projectEdit.rich.removeImage", role: .destructive) { block.removeDreamImage(index: index) }
                        }
                    }
                    Button("projectEdit.rich.addImage") { block.appendDreamImage() }.disabled(block.dreamImages.count >= 6)
                        .accessibilityIdentifier("projectEdit.rich.addImage")
                    Text("projectEdit.rich.albumHint").font(.caption).foregroundStyle(.secondary)
                }
            case .mood:
                Section {
                    Picker("projectEdit.rich.mood", selection: Binding(get: { (try? ProjectEditRichStoryContract.normalizedMood(block.fieldText("mood"))) ?? block.fieldText("mood") }, set: { block.setField("mood", .string($0)) })) {
                        ForEach(ProjectEditRichStoryContract.moods, id: \.self) { mood in Text(LocalizedStringKey("projectEdit.rich.mood." + mood)).tag(mood) }
                    }
                }
            case .thought:
                Section {
                    ProjectThoughtReferencePicker(model: model, block: $block, chapterID: chapterID)
                    TextField("projectEdit.rich.thoughtKey", text: text("thoughtKey")).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("projectEdit.rich.thoughtHint").font(.caption).foregroundStyle(.secondary)
                }
            case .odd:
                Section {
                    Picker("projectEdit.rich.effect", selection: Binding(get: { block.sourceFields?["level"]?.integer ?? 0 }, set: { block.setField("level", .number(Decimal($0))) })) {
                        ForEach(0...3, id: \.self) { Text(String($0)).tag($0) }
                    }
                }
            }
        }.disabled(!model.fullEdit).navigationTitle(Text(LocalizedStringKey("projectEdit.rich.kind." + block.kind.rawValue)))
            .navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
    }
    private func image(_ index: Int, _ field: String) -> Binding<String> {
        Binding(get: { block.dreamImages.indices.contains(index) ? block.dreamImages[index][field]?.text ?? "" : "" }, set: { block.setDreamImage(index: index, field: field, value: $0) })
    }
    @ViewBuilder private var narrativeSection: some View {
        Section("projectEdit.rich.narrative") {
            Toggle("projectEdit.rich.nodeNarrative", isOn: Binding(get: { block.isNarrative }, set: { enabled in
                block.selectBeat(enabled ? .brief : nil)
                if enabled { block.nodeID = nodes.first?.id ?? "" }
            })).disabled(nodes.isEmpty)
            if let beat {
                Picker("projectEdit.rich.beat", selection: Binding(get: { beat }, set: { block.selectBeat($0) })) {
                    ForEach(ProjectEditNarrativeBeat.allCases) { item in Text(LocalizedStringKey("projectEdit.rich.beat." + item.rawValue)).tag(item) }
                }
                Picker("projectEdit.rich.field", selection: Binding(get: { block.fieldText("field") }, set: { block.selectNarrativeField($0) })) {
                    ForEach(beat.fields, id: \.self) { field in Text(LocalizedStringKey("projectEdit.rich.field." + field)).tag(field) }
                }
                Picker("projectEdit.rich.targetNode", selection: $block.nodeID) {
                    Text("projectEdit.rich.selectNode").tag("")
                    ForEach(nodes) { Text(verbatim: $0.name).tag($0.id) }
                }
                let field = block.fieldText("field")
                if beat == .enter && ["q", "a"].contains(field) { TextField("projectEdit.rich.questionID", text: text("qid")).textInputAutocapitalization(.never).autocorrectionDisabled() }
                if beat.supportsNPC { TextField("projectEdit.rich.npcID", text: text("npcId", integer: true)).keyboardType(.numberPad) }
                if beat == .deliver {
                    Toggle("projectEdit.rich.claimLater", isOn: Binding(get: { block.sourceFields?["claimLater"] == .bool(true) }, set: { block.setField("claimLater", .bool($0)) }))
                }
                if ["brief.carry", "outcome.fact", "revisit.change"].contains(beat.rawValue + "." + field) {
                    ProjectEditStoryConditionEditor(condition: value("when"), plain: false, ending: false)
                }
                Text(LocalizedStringKey(beat.afterNode ? "projectEdit.rich.afterNodeHint" : "projectEdit.rich.beforeNodeHint"))
                    .font(.caption).foregroundStyle(.secondary)
                Text("projectEdit.rich.narrativeHint").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor struct ProjectEditStoryConditionEditor: View {
    @Binding var condition: ProjectEditJSON?
    let plain: Bool
    let ending: Bool
    var endingContext: ProjectEndingConditionContext? = nil
    private var object: [String: ProjectEditJSON] { condition?.object ?? [:] }
    private var op: String { object["op"]?.text ?? "HAS_TAG" }
    private func text(_ key: String, integer: Bool = false) -> Binding<String> {
        Binding(get: {
            if let text = object[key]?.text { return text }
            if case .number(let n)? = object[key] { return NSDecimalNumber(decimal: n).stringValue }
            return ""
        }, set: { text in
            var value = object
            if integer, let n = Int(text), String(n) == text { value[key] = .number(Decimal(n)) }
            else { value[key] = .string(text) }
            condition = .object(value)
        })
    }
    var body: some View {
        Toggle("projectEdit.rich.conditionEnabled", isOn: Binding(get: { condition != nil && condition != .null }, set: { condition = $0 ? .object(["op": .string("HAS_TAG"), "value": .string("")]) : nil }))
        if condition != nil && condition != .null {
            if !plain {
                Picker("projectEdit.rich.operator", selection: Binding(get: { op }, set: { condition = .object(["op": .string($0)]) })) {
                    ForEach(ProjectEditRichStoryContract.conditionOps, id: \.self) { Text(LocalizedStringKey("projectEdit.rich.op." + $0)).tag($0) }
                }
            }
            if let endingContext, ending && ["HAS_TAG", "NODE_COMPLETED"].contains(op) {
                ProjectEndingConditionEntry(context: endingContext).id(endingContext.id)
            }
            if op == "HAS_TAG" {
                TextField("projectEdit.rich.tag", text: text("value")).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text(LocalizedStringKey(plain || ending ? "projectEdit.rich.tagThoughtHint" : "projectEdit.rich.tagHint")).font(.caption).foregroundStyle(.secondary)
            } else if op == "NODE_COMPLETED" {
                TextField("projectEdit.rich.savedNodeID", text: text("nodeId", integer: true)).keyboardType(.numberPad)
                Text("projectEdit.rich.savedNodeHint").font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("projectEdit.rich.stateVariable", text: text("var")).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("projectEdit.rich.stateValue", text: text("value", integer: true)).keyboardType(.numbersAndPunctuation)
                Text("projectEdit.rich.stateHint").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor struct ProjectEditChapterStorySettings: View {
    @Binding var chapter: ProjectEditChapter
    let isFirst: Bool
    var model: ProjectEditModel? = nil
    private var ending: [String: ProjectEditJSON]? { chapter.preserved["ending"]?.object }
    private var conditions: [ProjectEditJSON] { ending?["when"]?.array ?? [] }
    var body: some View {
        Section("projectEdit.rich.chapterRole") {
            Toggle("projectEdit.rich.opening", isOn: Binding(get: { chapter.preserved["opening"] == .bool(true) }, set: { value in
                chapter.preserved["opening"] = .bool(value)
                if value { chapter.preserved["ending"] = nil }
            })).disabled(!isFirst || ending != nil)
            Toggle("projectEdit.rich.ending", isOn: Binding(get: { ending != nil }, set: { value in
                chapter.preserved["ending"] = value ? .object(["fallback": .bool(true)]) : nil
                if value { chapter.preserved["opening"] = .bool(false) }
            })).disabled(!chapter.nodes.isEmpty || chapter.preserved["opening"] == .bool(true))
            if ending != nil {
                Toggle("projectEdit.rich.fallback", isOn: Binding(get: { ending?["fallback"] == .bool(true) }, set: { value in
                    var row = ending ?? [:]; row["fallback"] = .bool(value)
                    if !value && row["when"] == nil { row["when"] = .array([]) }
                    chapter.preserved["ending"] = .object(row)
                }))
                if ending?["fallback"] != .bool(true) {
                    ForEach(conditions.indices, id: \.self) { index in
                        ProjectEditStoryConditionEditor(condition: condition(index), plain: false, ending: true,
                            endingContext: model.map { .init(model: $0, chapterID: chapter.id, index: index) })
                        Button("projectEdit.rich.removeCondition", role: .destructive) { var rows = conditions; guard rows.indices.contains(index) else { return }; rows.remove(at: index); setConditions(rows) }
                    }
                    Button("projectEdit.rich.addCondition") { setConditions(conditions + [.object(["op": .string("HAS_TAG"), "value": .string("")])]) }.disabled(conditions.count >= 16)
                }
            }
            Text("projectEdit.rich.chapterRoleHint").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func setConditions(_ values: [ProjectEditJSON]) { var row = ending ?? [:]; row["when"] = .array(values); chapter.preserved["ending"] = .object(row) }
    private func condition(_ index: Int) -> Binding<ProjectEditJSON?> {
        Binding(get: { conditions.indices.contains(index) ? conditions[index] : nil }, set: { value in
            var rows = conditions; guard rows.indices.contains(index) else { return }
            if let value { rows[index] = value } else { rows.remove(at: index) }; setConditions(rows)
        })
    }
}

struct ProjectEditRichBlockSummary: View {
    let block: ProjectEditBlock
    var nodes: [ProjectEditNode] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(block.isNarrative ? "projectEdit.rich.narrative" : "projectEdit.rich.kind." + block.kind.rawValue)).font(.caption).foregroundStyle(.secondary)
            if !block.content.isEmpty { Text(verbatim: block.content) }
            if !block.url.isEmpty { Text(verbatim: block.url).font(.caption) }
            if block.kind == .dream { Text(verbatim: block.fieldText("title")); ForEach(block.dreamImages.indices, id: \.self) { index in
                Text(verbatim: block.dreamImages[index]["url"]?.text ?? "").font(.caption)
                Text(verbatim: block.dreamImages[index]["line"]?.text ?? "")
            } }
            if block.kind == .mood { Text(verbatim: block.fieldText("mood")) }
            if block.kind == .thought { Text(verbatim: block.fieldText("thoughtKey")) }
            if block.kind == .odd { Text(verbatim: block.fieldText("level")) }
            if !block.fieldText("who").isEmpty { LabeledContent("projectEdit.rich.speaker", value: block.fieldText("who")) }
            if block.isNarrative {
                Text(verbatim: block.fieldText("beat") + " / " + block.fieldText("field")).font(.caption)
                LabeledContent("projectEdit.rich.targetNode", value: nodes.first { $0.id == block.nodeID }?.name ?? block.nodeID)
                if !block.fieldText("qid").isEmpty { LabeledContent("projectEdit.rich.questionID", value: block.fieldText("qid")) }
                if !block.fieldText("npcId").isEmpty { LabeledContent("projectEdit.rich.npcID", value: block.fieldText("npcId")) }
                if block.sourceFields?["claimLater"] == .bool(true) { Text("projectEdit.rich.claimLater") }
            }
            if let condition = block.sourceFields?["when"]?.object {
                Text(verbatim: [condition["op"]?.text, condition["var"]?.text, condition["value"]?.text,
                    condition["value"]?.integer.map(String.init), condition["nodeId"]?.integer.map(String.init)].compactMap { $0 }.joined(separator: " ")).font(.caption)
            }
        }
    }
}
