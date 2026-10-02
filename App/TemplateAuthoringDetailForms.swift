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
    var body: some View {
        Form {
            Section("templateAuthor.advanced") {
                ForEach(TemplateAdvancedGame.allCases) { game in
                    NavigationLink {
                        TemplateAdvancedGameConfigurationView(model: model, game: game)
                    } label: {
                        HStack {
                            Text(LocalizedStringKey(game.labelKey)); Spacer()
                            if model.draft.advanced.enabled(game.section) { Image(systemName: "checkmark.circle.fill") }
                        }
                    }.accessibilityIdentifier("templateAuthor.game." + game.rawValue)
                }
                Text("creatorComposition.coexist").font(.caption).foregroundStyle(.secondary)
                Text("templateAuthor.advancedScope").font(.caption).foregroundStyle(.secondary)
            }
            Section("playkitAuthor.presentation") {
                Picker("playkitAuthor.presentation", selection: Binding(get: { model.draft.advanced.explicitPresentation }, set: { model.draft.advanced.setPresentation($0) })) {
                    Text("playkitAuthor.presentation.default").tag("")
                    Text("playkitAuthor.presentation.inline").tag("inline")
                    Text("playkitAuthor.presentation.focused").tag("fullscreen")
                }.accessibilityIdentifier("creatorComposition.presentation")
                if model.draft.advanced.presentationRequiresFullscreen { Text("playkitAuthor.presentation.focusedRequired").font(.footnote) }
                Text("creatorComposition.presentationScope").font(.caption).foregroundStyle(.secondary)
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
                    .accessibilityIdentifier("creatorComposition.timerEnabled")
                if model.draft.advanced.enabled("timer") { field("timer", "durationSeconds") }
            }
            if !model.draft.advanced.issues.isEmpty { Section("templateAuthor.validationTitle") { ForEach(Array(Set(model.draft.advanced.issues)).sorted(), id: \.self) { Text(LocalizedStringKey($0)) } } }
        }.disabled(!model.canEdit).navigationTitle("templateAuthor.advanced")
    }
    private func field(_ section: String, _ key: String) -> some View {
        TemplateAuthoringField(key, text: .init(get: { model.draft.advanced.text(section, key) }, set: { model.draft.advanced.set(section, key, .string($0)) }))
    }

}

