import SwiftUI

@MainActor struct TemplateMiniGameConfigurationView: View {
    @ObservedObject var model: TemplateAuthoringModel
    let game: TemplateAdvancedGame
    private var section: String { game.section }
    var body: some View {
        Group {
            if game.isReasoning {
                TemplateAuthoringField("prompt", text: binding("prompt"), multiline: true)
                Text(LocalizedStringKey("playkitAuthor.instructions." + game.rawValue)).font(.footnote)
                if game == .sort {
                    TemplateAuthoringField("maxAttempts", text: binding("maxAttempts"))
                    Text("creatorRoot.sortAttempts").font(.footnote)
                    sortEditor
                }
                else if game == .match { matchEditor }
                else { classifyEditor }
            } else {
                TemplateAuthoringField("kicker", text: binding("kicker"))
                if game == .compass {
                    TemplateAuthoringField("bearing", text: binding("bearing"))
                    TemplateAuthoringField("tolerance", text: binding("tolerance"))
                    TemplateAuthoringField("holdSeconds", text: binding("holdSeconds"))
                    TemplateAuthoringField("compassHint", text: binding("hint"), multiline: true)
                    Text("playkitAuthor.compass.boundary").font(.footnote)
                } else {
                    TemplateAuthoringField("seconds", text: binding("seconds"))
                    Text("playkitAuthor.shout.boundary").font(.footnote)
                }
                TemplateAuthoringField("xp", text: binding("xp"))
            }
            NavigationLink("playkitAuthor.preview") { TemplateMiniGamePreviewView(draft: model.draft.advanced, game: game) }
                .disabled(!model.draft.advanced.miniGameIssues(game).isEmpty)
        }
    }
    private func binding(_ key: String) -> Binding<String> {
        .init(get: { model.draft.advanced.text(section, key) }, set: { model.draft.advanced.set(section, key, .string($0)) })
    }
    private func rows(_ field: String) -> [TemplateAuthoringJSON] { model.draft.advanced.rows(section, field) }
    private func rowField(_ field: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let values = rows(field)
            if values.indices.contains(index) {
                Text(verbatim: values[index].object?["id"]?.string ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                TextField("playkitAuthor.rowLabel", text: .init(get: {
                    let current = rows(field); return current.indices.contains(index) ? current[index].object?["label"]?.string ?? "" : ""
                }, set: { model.draft.advanced.setRow(section, field, index: index, key: "label", text: $0) }), axis: .vertical)
            }
        }
    }
    @ViewBuilder private var sortEditor: some View {
        let items = rows("items")
        ForEach(Array(items.enumerated()), id: \.offset) { index, _ in
            VStack(alignment: .leading) {
                rowField("items", index: index)
                HStack {
                    Button { model.draft.advanced.moveRow(section, "items", from: index, to: index - 1) } label: { Label("playkit.sort.up", systemImage: "arrow.up") }.disabled(index == 0)
                    Button { model.draft.advanced.moveRow(section, "items", from: index, to: index + 1) } label: { Label("playkit.sort.down", systemImage: "arrow.down") }.disabled(index == items.count - 1)
                    Spacer()
                    Button("playkitAuthor.remove", role: .destructive) { model.draft.advanced.removeRow(section, "items", index: index) }.disabled(items.count <= 2)
                }.buttonStyle(.borderless)
            }
        }
        Button("playkitAuthor.addItem") { model.draft.advanced.appendRow(section, "items", prefix: "item", maximum: 8) }.disabled(items.count >= 8)
    }
    @ViewBuilder private var matchEditor: some View {
        let left = rows("left"), right = rows("right")
        ForEach(0..<max(left.count, right.count), id: \.self) { index in
            VStack(alignment: .leading) {
                Text(verbatim: String(index + 1)).font(.caption)
                HStack(alignment: .top) {
                    VStack(alignment: .leading) { Text("playkitAuthor.left").font(.caption); rowField("left", index: index) }
                    Image(systemName: "link").accessibilityHidden(true)
                    VStack(alignment: .leading) { Text("playkitAuthor.right").font(.caption); rowField("right", index: index) }
                }
                Button("playkitAuthor.removePair", role: .destructive) {
                    model.draft.advanced.removeRow(section, "left", index: index)
                    model.draft.advanced.removeRow(section, "right", index: index)
                }.buttonStyle(.borderless).disabled(min(left.count, right.count) <= 2)
            }
        }
        if left.count != right.count {
            Button("playkitAuthor.balancePairs") {
                let target = min(6, max(left.count, right.count))
                while rows("left").count < target { model.draft.advanced.appendRow(section, "left", prefix: "left", maximum: 6) }
                while rows("right").count < target { model.draft.advanced.appendRow(section, "right", prefix: "right", maximum: 6) }
            }
        } else {
            Button("playkitAuthor.addPair") {
                model.draft.advanced.appendRow(section, "left", prefix: "left", maximum: 6)
                model.draft.advanced.appendRow(section, "right", prefix: "right", maximum: 6)
            }.disabled(left.count >= 6)
        }
    }
    @ViewBuilder private var classifyEditor: some View {
        let bins = rows("bins"), items = rows("items")
        Text("playkitAuthor.categories").font(.headline)
        ForEach(Array(bins.enumerated()), id: \.offset) { index, _ in
            HStack {
                rowField("bins", index: index)
                Button("playkitAuthor.remove", role: .destructive) { model.draft.advanced.removeRow(section, "bins", index: index) }.buttonStyle(.borderless).disabled(bins.count <= 2)
            }
        }
        Button("playkitAuthor.addCategory") { model.draft.advanced.appendRow(section, "bins", prefix: "bin", maximum: 4) }.disabled(bins.count >= 4)
        Text("playkitAuthor.items").font(.headline)
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            VStack(alignment: .leading) {
                rowField("items", index: index)
                if let id = item.object?["id"]?.string {
                    Picker("playkitAuthor.correctCategory", selection: Binding(get: {
                        model.draft.advanced.value[section]?.object?["answer"]?.object?[id]?.string ?? ""
                    }, set: { model.draft.advanced.setClassification(itemID: id, binID: $0) })) {
                        Text("playkit.choose").tag("")
                        ForEach(Array(bins.enumerated()), id: \.offset) { _, bin in
                            if let key = bin.object?["id"]?.string { Text(verbatim: bin.object?["label"]?.string ?? key).tag(key) }
                        }
                    }
                }
                Button("playkitAuthor.remove", role: .destructive) { model.draft.advanced.removeRow(section, "items", index: index) }.buttonStyle(.borderless).disabled(items.count <= 2)
            }
        }
        Button("playkitAuthor.addItem") { model.draft.advanced.appendRow(section, "items", prefix: "item", maximum: 10) }.disabled(items.count >= 10)
    }
}

@MainActor struct TemplateMiniGamePreviewView: View {
    let draft: TemplateAdvancedDraft; let game: TemplateAdvancedGame
    @State private var previewPayload: [String: PlayWireValue]?
    private var segment: PlayWireValue? { try? draft.miniPreviewSegment(game) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("playkitAuthor.previewBoundary").font(.callout)
                if let segment, let kind = PlayKitScreenKind(rawValue: game.section) {
                    if game.isReasoning {
                        if let prompt = segment["prompt"].text { Text(verbatim: prompt).font(.title2.bold()) }
                        PlayKitReasoningForm(kind: kind, segment: segment, enabled: true, onDirty: {}, requestReview: { _, payload, _ in previewPayload = payload })
                        if let previewPayload { Text("playkitAuthor.previewPayload").font(.headline); PlayKitPayloadReadback(payload: previewPayload) }
                    } else {
                        PlayKitSensorChallengeView(kind: kind, segment: segment, enabled: false, active: false, onDirty: {}, requestReview: { _, _, _ in })
                        Text("playkitAuthor.sensorPreviewBoundary").font(.footnote)
                    }
                } else { Text("playkit.configurationInvalid") }
            }.padding()
        }.navigationTitle("playkitAuthor.preview").privacySensitive()
    }
}
