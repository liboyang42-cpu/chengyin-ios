import SwiftUI

@MainActor struct TemplateAuthoringCompletionFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    var body: some View {
        Group {
            if [.text, .choice].contains(model.draft.validationMethod) {
                TemplateAuthoringField("questionName", text: model.optional(\.questionName), multiline: true)
                TemplateAuthoringField("questionImg", text: model.optional(\.questionImg))
                TemplateAuthoringField("questionAudio", text: model.optional(\.questionAudio))
            }
            if model.draft.validationMethod == .text { TemplateAuthoringField("questionAnswer", text: model.optional(\.questionAnswer)) }
            if model.draft.validationMethod == .choice {
                TemplateAuthoringField("questionA", text: model.optional(\.questionA))
                TemplateAuthoringField("questionB", text: model.optional(\.questionB))
                TemplateAuthoringField("questionC", text: model.optional(\.questionC))
                TemplateAuthoringField("questionD", text: model.optional(\.questionD))
                Picker("templateAuthor.field.correctAnswer", selection: model.optional(\.correctAnswer)) {
                    Text("templateAuthor.choose").tag("")
                    ForEach(["A", "B", "C", "D"], id: \.self) { Text(verbatim: $0).tag($0) }
                }
            }
            if [.text, .choice, .gps].contains(model.draft.validationMethod) {
                TemplateAuthoringField("hint1", text: model.optional(\.hint1))
                TemplateAuthoringField("hint2", text: model.optional(\.hint2))
                TemplateAuthoringField("answerReveal", text: model.optional(\.answerReveal))
            }
            if model.draft.validationMethod == .photo {
                TemplateAuthoringField("photoRequireDesc", text: model.optional(\.photoRequireDesc), multiline: true)
                Toggle("templateAuthor.photoReview", isOn: .init(get: { model.draft.photoReview == 1 }, set: { model.draft.photoReview = $0 ? 1 : 0 }))
            }
        }
    }
}
@MainActor struct TemplateAuthoringRewardStoryFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    var body: some View {
        Section("templateAuthor.reward") {
            Toggle("templateAuthor.moduleEnabled", isOn: $model.draft.rewardEnabled)
            if model.draft.rewardEnabled {
                TemplateAuthoringField("feedbackText", text: model.optional(\.feedbackText), multiline: true)
                TemplateAuthoringField("couponId", text: model.number(\.couponId))
                TemplateAuthoringField("medalName", text: model.optional(\.medalName))
                TemplateAuthoringField("medalImg", text: model.optional(\.medalImg))
            }
        }
        Section("templateAuthor.story") {
            Toggle("templateAuthor.moduleEnabled", isOn: $model.draft.storyEnabled)
            if model.draft.storyEnabled {
                TemplateAuthoringField("storyText", text: model.optional(\.storyText), multiline: true)
                TemplateAuthoringField("storyImg", text: model.optional(\.storyImg))
                NavigationLink("templateAuthor.storyTimeline") { TemplateAuthoringStoryView(model: model) }
            }
        }
        Section("templateAuthor.voice") {
            Toggle("templateAuthor.moduleEnabled", isOn: $model.draft.voiceEnabled)
            if model.draft.voiceEnabled {
                TemplateAuthoringField("audioUrl", text: model.optional(\.audioUrl))
                TemplateAuthoringField("audioDuration", text: model.number(\.audioDuration))
            }
        }
    }
}
@MainActor struct TemplateAuthoringStoryView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @State private var beats: [TemplateStoryBeat] = []
    @State private var invalid = false
    var body: some View {
        Form {
            if invalid { Section { Text("templateAuthor.storyInvalid") } }
            ForEach($beats) { $beat in
                Section {
                    TemplateAuthoringField("beatTag", text: $beat.tag)
                    TemplateAuthoringField("beatText", text: $beat.text, multiline: true)
                    TemplateAuthoringField("beatImages", text: .init(get: { beat.imgs.joined(separator: "\n") }, set: { beat.imgs = $0.split(separator: "\n").map(String.init) }), multiline: true)
                }
            }.onDelete { beats.remove(atOffsets: $0) }.onMove { beats.move(fromOffsets: $0, toOffset: $1) }
            Section { Button("templateAuthor.addBeat", systemImage: "plus") { beats.append(.init()) }.accessibilityIdentifier("templateAuthor.addBeat") }
        }.disabled(!model.canEdit || invalid)
            .navigationTitle("templateAuthor.storyTimeline")
            .toolbar { EditButton() }
            .onAppear { do { beats = try model.draft.storyBeats() } catch { invalid = true } }
            .onChange(of: beats) { _, next in do { try model.draft.setStory(next) } catch { invalid = true } }
    }
}

@MainActor struct TemplateAuthoringAdvancedView: View {
    @ObservedObject var model: TemplateAuthoringModel
    private var selected: TemplateAdvancedGame? { model.draft.advanced.selected }
    var body: some View {
        Form {
            Section("templateAuthor.advanced") {
                Picker("templateAuthor.game", selection: Binding<String>(get: { selected?.rawValue ?? "" }, set: { raw in
                    let game = TemplateAdvancedGame(rawValue: raw); model.draft.advanced.select(game)
                    if game != nil { model.draft.validationMethod = .manual }
                })) {
                    Text("templateAuthor.legacy").tag("")
                    ForEach(TemplateAdvancedGame.allCases) { Text(LocalizedStringKey($0.labelKey)).tag($0.rawValue) }
                }.accessibilityIdentifier("templateAuthor.gamePicker")
                Text("templateAuthor.advancedScope").font(.caption).foregroundStyle(.secondary)
            }
            if let game = selected {
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
                Section("playkitAuthor.presentation") {
                    Picker("playkitAuthor.presentation", selection: Binding(get: { model.draft.advanced.explicitPresentation }, set: { model.draft.advanced.setPresentation($0) })) {
                        Text("playkitAuthor.presentation.default").tag("")
                        Text("playkitAuthor.presentation.inline").tag("inline")
                        Text("playkitAuthor.presentation.focused").tag("fullscreen")
                    }
                    if !game.allowsInline { Text("playkitAuthor.presentation.focusedRequired").font(.footnote) }
                }
            }
            Section("creatorRoot.rules") {
                NavigationLink("creatorRoot.rules") { TemplateRootAuthoringView(model: model) }
            }
            Section("creator.modules") {
                ForEach(TemplateCreatorFamily.allCases) { family in
                    NavigationLink { TemplateCreatorConfigurationView(model: model, family: family) } label: {
                        HStack { Text(LocalizedStringKey(family.labelKey)); Spacer(); if model.draft.advanced.enabled(family.rawValue) { Image(systemName: "checkmark.circle.fill") } }
                    }
                }
                Text("creator.coexist").font(.caption).foregroundStyle(.secondary)
            }
            Section("templateAuthor.timer") {
                Toggle("templateAuthor.moduleEnabled", isOn: .init(get: { model.draft.advanced.enabled("timer") }, set: { model.draft.advanced.set("timer", "enabled", .bool($0)) }))
                    .disabled(selected?.supportsTimer == false)
                if selected?.supportsTimer == false { Text("templateAuthor.timerUnsupported").foregroundStyle(.secondary) }
                if model.draft.advanced.enabled("timer") { field("timer", "durationSeconds") }
            }
            if !model.draft.advanced.issues.isEmpty { Section("templateAuthor.validationTitle") { ForEach(Array(Set(model.draft.advanced.issues)).sorted(), id: \.self) { Text(LocalizedStringKey($0)) } } }
        }.disabled(!model.canEdit).navigationTitle("templateAuthor.advanced")
    }
    private func field(_ section: String, _ key: String) -> some View {
        TemplateAuthoringField(key, text: .init(get: { model.draft.advanced.text(section, key) }, set: { model.draft.advanced.set(section, key, .string($0)) }))
    }
    private func nested(_ side: String, _ field: String) -> some View {
        TemplateAuthoringField(side + "." + field, text: .init(get: { model.draft.advanced.value["coinFlip"]?.object?[side]?.object?[field]?.string ?? "" }, set: { model.draft.advanced.setNested("coinFlip", side, field, $0) }))
    }
}

