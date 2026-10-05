import SwiftUI

@MainActor struct TemplateAuthoringCompletionFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    var body: some View {
        Group {
            if model.draft.validationMethod == .preference { TemplatePreferenceDraftEditor(model: model) }
            if model.draft.validationMethod.rawValue == 7 {
                TemplateSensorDraftConfigurationFields(model: model)
            }
            TemplateAuthoringQAFields(method: model.draft.validationMethod, field: { model.optional($0.draftPath) }, includesHints: false)
            TemplateLegacyHintFields(model: model)
            if model.draft.validationMethod == .choice {
                TemplateChoiceOptionMediaFields(configuration: model.draft.choiceOptionMedia,
                    field: { model.optionMedia($0, $1) }, issueKey: model.optionMediaIssue).disabled(!model.canEdit)
            }
            if model.draft.validationMethod == .photo {
                TemplateAuthoringField("photoRequireDesc", text: model.optional(\.photoRequireDesc), multiline: true)
                Toggle("templateAuthor.photoReview", isOn: .init(get: { model.draft.photoReview == 1 }, set: { model.draft.photoReview = $0 ? 1 : 0 }))
            }
        }
    }
}
/// Shared choice attachment fields for local editing and owner-scoped inspection.
/// References stay as text: rendering, playback and uploading require separate capabilities.
@MainActor struct TemplateChoiceOptionMediaFields: View {
    let configuration: TemplateChoiceOptionMedia
    let field: (TemplateChoiceOptionMedia.Letter, TemplateChoiceOptionMedia.Kind) -> Binding<String>
    var readOnly = false
    var issueKey: String?
    var body: some View {
        Group {
            Text("templateAuthor.optionMedia.title").font(.headline)
            Text("templateAuthor.optionMedia.scope").font(.caption).foregroundStyle(.secondary)
            if !configuration.isSupported {
                Text("templateAuthor.optionMedia.unsupported").accessibilityIdentifier("templateAuthor.optionMedia.unsupported")
            }
            if let issueKey { Text(LocalizedStringKey(issueKey)).foregroundStyle(.red).accessibilityIdentifier("templateAuthor.optionMedia.limit") }
            ForEach(TemplateChoiceOptionMedia.Letter.allCases) { letter in
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(letter.labelKey)).font(.subheadline)
                    ForEach(TemplateChoiceOptionMedia.Kind.allCases) { kind in
                        TextField(LocalizedStringKey(kind.labelKey), text: field(letter, kind))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("templateAuthor.optionMedia." + letter.rawValue + "." + kind.rawValue)
                        if readOnly && configuration.isSupported && configuration.text(letter, kind) == nil {
                            Text("templateOwnerConfig.missing").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.disabled(readOnly || !configuration.isSupported)
    }
}
/// Same professional QA fields for local authors and scoped read-only owner inspection.
@MainActor struct TemplateAuthoringQAFields: View {
    let method: TemplateAuthoringMethod
    let field: (TemplateQAField) -> Binding<String>
    var readOnly = false
    var annotation: (TemplateQAField) -> String? = { _ in nil }
    var includesHints = true
    var body: some View {
        Group {
            if [.text, .choice].contains(method) {
                entry(.questionName, multiline: true); entry(.questionImg); entry(.questionAudio)
            }
            if method == .text { entry(.questionAnswer) }
            if method == .choice {
                entry(.questionA); entry(.questionB); entry(.questionC); entry(.questionD)
                if readOnly { entry(.correctAnswer) }
                else {
                    Picker("templateAuthor.field.correctAnswer", selection: field(.correctAnswer)) {
                        Text("templateAuthor.choose").tag("")
                        ForEach(["A", "B", "C", "D"], id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                }
            }
            if includesHints && [.text, .choice, .gps].contains(method) { entry(.hint1); entry(.hint2); entry(.answerReveal) }
        }.disabled(readOnly)
    }
    private func entry(_ key: TemplateQAField, multiline: Bool = false) -> some View {
        VStack(alignment: .leading) {
            TemplateAuthoringField(key.rawValue, text: field(key), multiline: multiline)
            if let label = annotation(key) { Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
@MainActor struct TemplateStoryBeatFields: View {
    @Binding var tag: String
    @Binding var text: String
    @Binding var images: String
    var accessibilityPrefix: String? = nil
    var body: some View {
        TemplateAuthoringField("beatTag", text: $tag, accessibilityID: accessibilityPrefix.map { $0 + ".tag" })
        TemplateAuthoringField("beatText", text: $text, multiline: true, accessibilityID: accessibilityPrefix.map { $0 + ".text" })
        TemplateAuthoringField("beatImages", text: $images, multiline: true, accessibilityID: accessibilityPrefix.map { $0 + ".images" })
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
                Picker("templateAuthor.field.medalStyle", selection: $model.draft.medalStyle) {
                    Text("templateOwnerConfig.missing").tag(Optional<String>.none)
                    Text("templateAuthor.medalStyle.glow").tag(Optional("glow"))
                    Text("templateAuthor.medalStyle.enamel").tag(Optional("enamel"))
                    if let raw = model.draft.medalStyle, !["glow", "enamel"].contains(raw) {
                        Text(verbatim: raw).tag(Optional(raw))
                    }
                }
            }
        }
        Section("templateAuthor.story") {
            Toggle("templateAuthor.moduleEnabled", isOn: $model.draft.storyEnabled)
            if model.draft.storyEnabled {
                if model.draft.storyTimelineEdited == true {
                    Text("templateStory.derivedSummary").font(.caption).foregroundStyle(.secondary)
                    if let summary = try? model.draft.preparedStoryText() { Text(verbatim: summary).accessibilityIdentifier("templateStory.summary") }
                    if let issue = model.draft.storyProjectionIssue { Text(LocalizedStringKey(issue)).foregroundStyle(.red) }
                } else { TemplateAuthoringField("storyText", text: model.optional(\.storyText), multiline: true) }
                TemplateAuthoringField("storyImg", text: model.optional(\.storyImg))
                NavigationLink("templateAuthor.storyTimeline") { TemplateAuthoringStoryView(model: model) }.accessibilityIdentifier("templateStory.open")
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
    @StateObject private var editor: TemplateStoryEditor
    init(model: TemplateAuthoringModel) {
        self.model = model; _editor = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        Form {
            Section {
                Text("templateStory.scope").font(.caption).foregroundStyle(.secondary)
                if let issue = editor.visibleIssueKey { Text(LocalizedStringKey(issue)).foregroundStyle(.red).accessibilityIdentifier("templateStory.issue") }
            }
            ForEach(Array(editor.visibleBeats.enumerated()), id: \.element.id) { index, beat in
                Section {
                    TemplateStoryBeatFields(tag: editor.text(beat.id, \.tag), text: editor.text(beat.id, \.text), images: editor.images(beat.id), accessibilityPrefix: "templateStory.beat.\(index)")
                    LabeledContent("templateStory.imageCount", value: "\(beat.imgs.count) / \(TemplateAuthoringStory.maximumImagesPerBeat)")
                        .accessibilityIdentifier("templateStory.beat.\(index).imageCount")
                    if beat.imgs.count > TemplateAuthoringStory.maximumImagesPerBeat { Text("templateStory.historicalImages").font(.caption).foregroundStyle(.secondary) }
                }
            }.onDelete { editor.remove($0) }.onMove { editor.move($0, to: $1) }
                .deleteDisabled(editor.beats.count <= 1)
            Section { Button("templateAuthor.addBeat", systemImage: "plus") { editor.add() }.accessibilityIdentifier("templateAuthor.addBeat") }
        }.disabled(!editor.canEdit)
            .navigationTitle("templateAuthor.storyTimeline")
            .toolbar { EditButton().disabled(!editor.canEdit) }
            .onAppear { editor.load() }
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
