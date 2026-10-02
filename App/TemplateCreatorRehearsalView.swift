import SwiftUI

@MainActor struct TemplateCreatorRehearsalView: View {
    let draft: TemplateAdvancedDraft
    let family: TemplateCreatorFamily
    @State private var rehearsal = TemplateCreatorRehearsal()
    @State private var input = ""
    @State private var selected = Set<String>()
    @State private var startedAt: Date?
    @State private var sampleIndex = 0
    @State private var profileAnswers: [String: String] = [:]
    private var fields: [String: TemplateAuthoringJSON] { draft.value[family.rawValue]?.object ?? [:] }
    private func text(_ key: String) -> String { fields[key]?.string ?? "" }
    private func rows(_ key: String) -> [[String: TemplateAuthoringJSON]] { (fields[key]?.array ?? []).compactMap(\.object) }
    var body: some View {
        Form {
            Section {
                Text("creator.localOnly").font(.headline)
                Text(LocalizedStringKey(family.providerKey)).font(.footnote)
                if !text("title").isEmpty { Text(verbatim: text("title")).font(.title2) }
            }
            Section("creator.rehearse") { interaction }
            if rehearsal.result != .ready { Section { Text(LocalizedStringKey("creator.result." + rehearsal.result.rawValue)) } }
            Section {
                Button("creator.reset") { rehearsal.reset(); input = ""; selected = []; startedAt = nil; sampleIndex = 0; profileAnswers = [:] }
                DisclosureGroup("creator.review") {
                    TemplateCreatorReviewFields(value: .object(fields), fields: TemplateCreatorSchema.fields(family))
                }
            }
        }.navigationTitle(LocalizedStringKey(family.labelKey))
            .accessibilityIdentifier("creator.rehearsal." + family.rawValue)
    }
    @ViewBuilder private var interaction: some View {
        switch family {
        case .estimate:
            Text(verbatim: text("unit")); TextField("creator.input", text: $input).keyboardType(.numbersAndPunctuation); evaluateButton
        case .blindTaste: options(rows("options"), identity: "key", label: "label", multiple: false); evaluateButton
        case .pricePair: options(rows("items"), identity: "id", label: "name", multiple: false); evaluateButton
        case .qa:
            Text(verbatim: text("lead"))
            if text("mode") == "PICK" { options(rows("options"), identity: "id", label: "label", multiple: fields["multi"]?.bool == true); evaluateButton }
            else if text("mode") == "TYPE" { TextField("creator.input", text: $input); evaluateButton }
            else { Text(verbatim: text("shotNote")); Label("creator.provider.vision", systemImage: "camera") }
        case .typeIn:
            Text(verbatim: text("target")).font(.title3)
            Button("creator.start") { startedAt = Date(); input = ""; rehearsal.reset() }
            TextField("creator.input", text: $input).disabled(startedAt == nil)
            evaluateButton.disabled(startedAt == nil)
        case .branch: branch
        case .random:
            Text(verbatim: text("deckName")); Text("creator.selectSample").font(.footnote)
            samplePicker(rows("items").count)
            if rows("items").indices.contains(sampleIndex) { let row = rows("items")[sampleIndex]; Text(verbatim: row["label"]?.string ?? ""); Text(verbatim: row["content"]?.string ?? "") }
        case .dailySign:
            let poems = fields["poems"]?.array ?? []; samplePicker(poems.count)
            if poems.indices.contains(sampleIndex) { ForEach(Array((poems[sampleIndex].array ?? []).enumerated()), id: \.offset) { _, line in Text(verbatim: line.string ?? "") } }
            Text(verbatim: text("signer")); Text(verbatim: text("sealText"))
        case .album:
            ForEach(Array(rows("images").enumerated()), id: \.offset) { _, row in
                mediaPreview(row["url"]?.string ?? "")
                Text(verbatim: row["line"]?.string ?? "")
            }
        case .profile:
            ForEach(Array(rows("questions").enumerated()), id: \.offset) { _, question in
                let key = question["key"]?.string ?? "", label = question["label"]?.string ?? ""
                if question["kind"]?.string == "pick" {
                    Picker(selection: Binding(get: { profileAnswers[key] ?? "" }, set: { profileAnswers[key] = $0 })) {
                        Text("creator.choose").tag("")
                        ForEach(Array((question["options"]?.array ?? []).enumerated()), id: \.offset) { _, option in Text(verbatim: option.object?["label"]?.string ?? "").tag(option.object?["key"]?.string ?? "") }
                    } label: { Text(verbatim: label) }
                } else { TextField(label, text: Binding(get: { profileAnswers[key] ?? "" }, set: { profileAnswers[key] = $0 })) }
            }
        case .note, .diyName:
            Text(verbatim: text("prompt")); TextField("creator.input", text: $input, axis: .vertical)
            let key = family == .note ? "presets" : "suggestions"
            ForEach(Array((fields[key]?.array ?? []).enumerated()), id: \.offset) { _, value in Button(value.string ?? "") { input = value.string ?? "" } }
            Text(verbatim: "\(input.utf16.count) / \(fields["maxLength"]?.integer ?? 40)").font(.caption)
        case .check:
            Text(verbatim: text("skill"))
            Picker("creator.selectSample", selection: $sampleIndex) { Text("creator.success").tag(0); Text("creator.failure").tag(1) }.pickerStyle(.segmented)
            Text(verbatim: text(sampleIndex == 0 ? "successText" : "failText"))
            Text("creator.effectsNotApplied").font(.footnote)
        case .slowTask:
            Picker("creator.selectSample", selection: $sampleIndex) { Text("creator.start").tag(0); Text("creator.wait").tag(1); Text("creator.unlock").tag(2) }
            Text(verbatim: text(sampleIndex == 0 ? "startLabel" : sampleIndex == 1 ? "waitHint" : "unlockText"))
        case .photoCheck:
            Label("creator.photoFrame", systemImage: "viewfinder").frame(maxWidth: .infinity, minHeight: 160).background(.quaternary)
            Text(verbatim: text("requirement")); Text(verbatim: text("shotNote"))
            Text("creator.provider.vision").font(.footnote)
        case .hiddenObject:
            hiddenObjectCanvas
            Text(verbatim: text("hint")); Text("creator.hotspotReview").font(.footnote)
            Text(verbatim: "\(rehearsal.foundTargets.count) / \(rows("hotspots").count)")
        case .predict:
            Text(verbatim: text("question")); Text(verbatim: text("hint")); options(rows("options"), identity: "key", label: "label", multiple: false)
            Text("creator.predictionNoOutcome").font(.footnote)
        case .scan:
            Text(verbatim: text("reply"))
            if text("kind") == "IMAGE" { mediaPreview(text("imageUrl")) }
            if text("kind") == "OVERLAY" { mediaPreview(text("overlayUrl")) }
            Text("creator.provider.scan").font(.footnote)
        case .silentOrder: Text(verbatim: text("rule"))
        case .musicCorner: Text(verbatim: text("trackName")); Text("creator.provider.music").font(.footnote)
        case .timeWindow: LabeledContent("creator.field.openFrom", value: text("openFrom")); LabeledContent("creator.field.openTo", value: text("openTo"))
        case .steps: LabeledContent("creator.field.goal", value: String(fields["goal"]?.integer ?? 0)); Text("creator.provider.wechatSteps")
        case .leaderboard, .multiplayer: TemplateCreatorReviewFields(value: .object(fields), fields: TemplateCreatorSchema.fields(family))
        }
    }
    @ViewBuilder private var hiddenObjectCanvas: some View {
        if let url = URL(string: text("imageUrl")), url.scheme == "https" {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit().overlay {
                        GeometryReader { geometry in
                            Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { event in
                                guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                                rehearsal.tapHiddenObject(draft: draft, x: event.location.x / geometry.size.width, y: event.location.y / geometry.size.height)
                            })
                        }
                    }.accessibilityLabel("creator.tapTargets")
                } else { Label("creator.linkedMedia", systemImage: "photo") }
            }.frame(maxHeight: 300)
        } else { Text("creator.relativeMedia") }
    }
    private var evaluateButton: some View {
        Button("creator.evaluate") { rehearsal.evaluate(family, draft: draft, text: input, selected: selected, elapsed: startedAt.map { Date().timeIntervalSince($0) }) }
    }
    private var branch: some View {
        VStack(alignment: .leading) {
            Button("creator.start") { rehearsal.startBranch(draft) }
            if let row = rows("steps").first(where: { $0["id"]?.string == rehearsal.branchStepID }) {
                Text(verbatim: row["title"]?.string ?? ""); Text(verbatim: row["body"]?.string ?? "")
                if row["terminal"]?.bool == true { Text(verbatim: row["outcomeLabel"]?.string ?? ""); Text("creator.effectsNotApplied") }
                ForEach(Array((row["options"]?.array ?? []).enumerated()), id: \.offset) { _, option in
                    Button(option.object?["label"]?.string ?? "") { rehearsal.chooseBranch(option.object?["id"]?.string ?? "", draft: draft) }
                }
            }
        }
    }
    private func options(_ rows: [[String: TemplateAuthoringJSON]], identity: String, label: String, multiple: Bool) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            let id = row[identity]?.string ?? ""
            Button { if multiple { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } } else { selected = [id] } } label: {
                HStack { Text(verbatim: row[label]?.string ?? ""); Spacer(); if selected.contains(id) { Image(systemName: "checkmark") } }
            }
        }
    }
    private func samplePicker(_ count: Int) -> some View {
        Picker("creator.selectSample", selection: $sampleIndex) { ForEach(0..<count, id: \.self) { Text(verbatim: String($0 + 1)).tag($0) } }
    }
    @ViewBuilder private func mediaPreview(_ raw: String) -> some View {
        if let url = URL(string: raw), url.scheme == "https" {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFit() }
                else { Label("creator.linkedMedia", systemImage: "photo") }
            }.frame(maxHeight: 240)
        } else { Label("creator.linkedMedia", systemImage: "photo") }
    }
}

private struct TemplateCreatorReviewFields: View {
    let value: TemplateAuthoringJSON
    let fields: [TemplateCreatorField]
    var body: some View {
        ForEach(fields) { field in
            if let raw = value.object?[field.id] {
                switch field.kind {
                case .object(let nested): DisclosureGroup(LocalizedStringKey(field.labelKey)) { AnyView(TemplateCreatorReviewFields(value: raw, fields: nested)) }
                case .rows(let nested, _, _, _): DisclosureGroup(LocalizedStringKey(field.labelKey)) {
                    ForEach(Array((raw.array ?? []).enumerated()), id: \.offset) { index, row in
                        Text(verbatim: String(index + 1)).font(.headline); AnyView(TemplateCreatorReviewFields(value: row, fields: nested))
                    }
                }
                case .strings: LabeledContent(LocalizedStringKey(field.labelKey), value: (raw.array ?? []).compactMap(\.string).joined(separator: " · "))
                case .poems: LabeledContent(LocalizedStringKey(field.labelKey), value: String(raw.array?.count ?? 0))
                case .toggle: LabeledContent(LocalizedStringKey(field.labelKey)) { Text(LocalizedStringKey(raw.bool ? "creator.yes" : "creator.no")) }
                case .choice: LabeledContent(LocalizedStringKey(field.labelKey)) { Text(LocalizedStringKey("creator.choice." + ((raw.string ?? "").isEmpty ? "empty" : raw.string!))) }
                default: LabeledContent(LocalizedStringKey(field.labelKey), value: raw.string ?? raw.number.map { String($0) } ?? "")
                }
            }
        }
    }
}
