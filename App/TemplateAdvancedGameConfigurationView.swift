import SwiftUI

/// Opening or enabling one game never disables any other configured family.
@MainActor struct TemplateAdvancedGameConfigurationView: View {
    @ObservedObject var model: TemplateAuthoringModel
    let game: TemplateAdvancedGame
#if DEBUG
    @State private var inputProbeSnapshot = ""
#endif
    var body: some View {
        Form {
            Section {
                Toggle("templateAuthor.moduleEnabled", isOn: Binding(get: { model.draft.advanced.enabled(game.section) }, set: { enabled in
                    model.setGameEnabled(game, enabled)
                })).accessibilityIdentifier("creatorComposition.enabled." + game.rawValue)
                Text("creatorComposition.coexist").font(.caption).foregroundStyle(.secondary)
            }
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-template-authoring") &&
                ProcessInfo.processInfo.arguments.contains("--template-author-compound") &&
                ProcessInfo.processInfo.arguments.contains("--template-author-toggle-probe") {
                Section {
                    Button { inputProbeSnapshot = model.gameInputProbe(game) } label: {
                        Text(verbatim: "Inspect synthetic game toggle")
                    }
                    .accessibilityIdentifier("creatorComposition.probe." + game.rawValue)
                    .accessibilityValue(inputProbeSnapshot.isEmpty ? model.gameInputProbe(game) : inputProbeSnapshot)
                }.font(.caption).dynamicTypeSize(.large)
            }
#endif
            Section(LocalizedStringKey(game.labelKey)) {
                if game.isMiniProgramAddition { TemplateMiniGameConfigurationView(model: model, game: game) }
                else {
                field(game.section, "kicker")
                field(game.section, "xp")
                switch game {
                case .coin:
                    nested("heads", "label"); nested("heads", "action"); nested("tails", "label"); nested("tails", "action")
                case .dice:
                    Picker("creatorRoot.diceMode", selection: Binding(get: { model.draft.advanced.diceMode }, set: { model.draft.advanced.setDiceMode($0) })) {
                        Text("creatorRoot.d6").tag("d6"); Text("creatorRoot.d20").tag("d20")
                    }
                    if model.draft.advanced.diceMode == "d20" { TemplateD20ConfigurationView(model: model) }
                    else {
                    field(game.section, "diceCount")
                    ForEach(0..<6, id: \.self) { index in
                        TextField(LocalizedStringKey("templateAuthor.diceFace." + String(index + 1)), text: .init(get: {
                            let faces = model.draft.advanced.value["diceRoll"]?.object?["faces"]?.array ?? []
                            return faces.indices.contains(index) ? faces[index].string ?? "" : ""
                        }, set: { model.draft.advanced.setFace(index, $0) }))
                    }
                    }
                case .react: field(game.section, "rounds"); field(game.section, "goalMs")
                case .shake:
                    field(game.section, "goal")
                    Toggle("templateAuthor.field.timed", isOn: .init(get: { model.draft.advanced.value[game.section]?.object?["timed"]?.bool ?? false }, set: { model.draft.advanced.set(game.section, "timed", .bool($0)) }))
                    if model.draft.advanced.value[game.section]?.object?["timed"]?.bool == true { field(game.section, "seconds") }
                case .quiet: field(game.section, "sub"); field(game.section, "seconds")
                case .countdown: field(game.section, "seconds"); field(game.section, "doneText")
                case .stopwatch: field(game.section, "targetSeconds"); field(game.section, "toleranceMs"); field(game.section, "tries")
                case .sort, .match, .classify, .compass, .shout: EmptyView()
                }
                }
            }
            if !model.draft.advanced.issues.isEmpty {
                Section("templateAuthor.validationTitle") {
                    ForEach(Array(Set(model.draft.advanced.issues)).sorted(), id: \.self) { Text(LocalizedStringKey($0)) }
                }
            }
        }.disabled(!model.canEdit).navigationTitle(LocalizedStringKey(game.labelKey))
    }
    private func field(_ section: String, _ key: String) -> some View {
        TemplateAuthoringField(key, text: .init(get: { model.draft.advanced.text(section, key) }, set: { model.draft.advanced.set(section, key, .string($0)) }))
    }
    private func nested(_ side: String, _ field: String) -> some View {
        TemplateAuthoringField(side + "." + field, text: .init(get: { model.draft.advanced.value["coinFlip"]?.object?[side]?.object?[field]?.string ?? "" }, set: { model.draft.advanced.setNested("coinFlip", side, field, $0) }))
    }
}
