import SwiftUI

@MainActor final class TemplateAuthoringModel: ObservableObject {
    let coordinator: TemplateAuthoringCoordinator
    @Published var draft = TemplateAuthoringDraft()
    @Published var review: TemplateAuthoringReview?
    @Published var revision = 0
    @Published var busy = false
    private var epoch: TemplateAuthoringSession?
    init(coordinator: TemplateAuthoringCoordinator) { self.coordinator = coordinator }
    var canEdit: Bool { coordinator.session != nil && epoch == coordinator.session && !coordinator.locked && coordinator.restore == .missing }
    func load() { coordinator.synchronizeSession(); coordinator.open(); draft = coordinator.draft; epoch = coordinator.session; review = nil; revision += 1 }
    func changed() {
        guard canEdit else { draft = coordinator.draft; return }
        coordinator.change(draft); review = nil; revision += 1
    }
    func setGameEnabled(_ game: TemplateAdvancedGame, _ enabled: Bool) {
        guard canEdit else { return }
        draft.advanced.setGameEnabled(game, enabled)
        if enabled { draft.validationMethod = .manual }
        // A pushed editor can outlive the parent Form's onChange observation.
        // Commit before returning to the parent, whose task reloads the coordinator.
        changed()
    }
    func restore() { coordinator.restoreDraft(); draft = coordinator.draft; revision += 1 }
    func discard() { coordinator.discardLocal(); draft = coordinator.draft; revision += 1 }
    func save() { guard canEdit else { return }; coordinator.change(draft); coordinator.saveLocal(); revision += 1 }
    func prepare(_ intent: TemplateAuthoringIntent) { guard canEdit else { return }; coordinator.change(draft); coordinator.prepare(intent); review = coordinator.review; revision += 1 }
    func cancel() { coordinator.cancelReview(); review = nil; revision += 1 }
    func confirm(_ value: TemplateAuthoringReview) async { busy = true; review = nil; await coordinator.confirm(value); busy = false; revision += 1 }
    func leave() { coordinator.leaveScreen(); review = nil }
    func optional(_ path: WritableKeyPath<TemplateAuthoringDraft, String?>) -> Binding<String> {
        .init(get: { self.draft[keyPath: path] ?? "" }, set: { self.draft[keyPath: path] = $0.isEmpty ? nil : $0 })
    }
    func number(_ path: WritableKeyPath<TemplateAuthoringDraft, Int?>) -> Binding<String> {
        .init(get: { self.draft[keyPath: path].map(String.init) ?? "" }, set: { self.draft[keyPath: path] = Int($0) })
    }
}

/// Host within the existing navigation stack. Intro/name/edit are replacement steps.
@MainActor struct TemplateAuthoringView: View {
    private enum Step { case intro, name, edit }
    @StateObject private var model: TemplateAuthoringModel
    @State private var step: Step = .intro
    @State private var preview = false
    @State private var discard = false
    let sessionRevision: UInt64
    init(coordinator: TemplateAuthoringCoordinator, sessionRevision: UInt64) {
        _model = StateObject(wrappedValue: .init(coordinator: coordinator)); self.sessionRevision = sessionRevision
    }
    var body: some View {
        Form {
            Section {
                QuestifyStatusBadge(title: "templateAuthor.localBadge", systemImage: "square.and.pencil")
                Text(LocalizedStringKey(model.coordinator.canSubmit ? "templateAuthor.httpReview" : "templateAuthor.unavailable")).foregroundStyle(.secondary)
                if model.coordinator.session == nil { Text("templateAuthor.signIn").accessibilityIdentifier("templateAuthor.signIn") }
            }
            restoreSection
            if model.coordinator.session != nil {
                switch step {
                case .intro: intro
                case .name: name
                case .edit: editor
                }
            }
            if let key = model.coordinator.messageKey { Section { Text(LocalizedStringKey(key)).accessibilityIdentifier("templateAuthor.status") } }
        }
        .navigationTitle("templateAuthor.title")
        .disabled(model.busy)
        .task { model.load() }
        .onChange(of: model.draft) { _, _ in model.changed() }
        .onChange(of: sessionRevision) { _, _ in preview = false; step = .intro; model.load() }
        .onDisappear { model.leave() }
        .sheet(isPresented: $preview) { NavigationStack { TemplateAuthoringPreviewView(draft: model.draft) } }
        .sheet(item: $model.review, onDismiss: { model.cancel() }) { value in
            NavigationStack { TemplateAuthoringReviewView(review: value, canSimulate: model.coordinator.canSimulate, canSubmit: model.coordinator.canSubmit, confirm: { Task { await model.confirm(value) } }, cancel: { model.cancel() }) }
        }
        .confirmationDialog("templateAuthor.discardQuestion", isPresented: $discard, titleVisibility: .visible) {
            Button("templateAuthor.discard", role: .destructive) { model.discard() }
            Button("templateAuthor.cancel", role: .cancel) {}
        }
    }
    @ViewBuilder private var restoreSection: some View {
        if model.coordinator.restore != .missing {
            Section("templateAuthor.restoreTitle") {
                if case .ready = model.coordinator.restore {
                    Text("templateAuthor.restoreMessage")
                    Button("templateAuthor.restore") { model.restore(); step = .edit }
                        .disabled(model.coordinator.locked).accessibilityIdentifier("templateAuthor.restore")
                } else { Text("templateAuthor.restoreFailed") }
                Button("templateAuthor.discard", role: .destructive) { discard = true }.disabled(model.coordinator.locked)
            }
        }
    }
    private var intro: some View {
        Section("templateAuthor.introTitle") {
            Text("templateAuthor.introBody")
            Label("templateAuthor.introFinish", systemImage: "checkmark.circle")
            Label("templateAuthor.introStory", systemImage: "book")
            Label("templateAuthor.introReward", systemImage: "gift")
            Button("templateAuthor.begin") { step = .name }.disabled(!model.canEdit).accessibilityIdentifier("templateAuthor.begin")
        }
    }
    private var name: some View {
        Section("templateAuthor.nameStep") {
            TextField("templateAuthor.field.title", text: $model.draft.title).accessibilityIdentifier("templateAuthor.field.title")
            Button("templateAuthor.continue") { step = .edit }.disabled(!model.draft.canSave || !model.canEdit).accessibilityIdentifier("templateAuthor.continue")
        }
    }
    @ViewBuilder private var editor: some View {
        Group {
            Section("templateAuthor.basics") {
                TemplateAuthoringField("title", text: $model.draft.title)
                TemplateAuthoringField("description", text: $model.draft.description, multiline: true)
                TemplateAuthoringField("players", text: model.optional(\.players))
                TemplateAuthoringField("duration", text: model.number(\.duration))
                TemplateAuthoringField("difficulty", text: model.optional(\.difficulty))
                TemplateAuthoringField("usageLocation", text: model.optional(\.usageLocation))
                TemplateAuthoringField("requiredMaterials", text: model.optional(\.requiredMaterials))
                TemplateAuthoringField("categoryId", text: model.number(\.categoryId))
                TemplateAuthoringField("activityCategoryids", text: model.optional(\.activityCategoryids))
                TemplateAuthoringField("ruleInstructions", text: model.optional(\.ruleInstructions), multiline: true)
                TemplateAuthoringField("imgUrl", text: model.optional(\.imgUrl))
                Text("templateAuthor.mediaHint").font(.caption).foregroundStyle(.secondary)
                Toggle("templateAuthor.sync", isOn: .init(get: { model.draft.isSync == 1 }, set: { model.draft.isSync = $0 ? 1 : 0 }))
            }
            Section("templateAuthor.finish") {
                Toggle("templateAuthor.moduleEnabled", isOn: $model.draft.finishEnabled)
                if model.draft.finishEnabled {
                    Picker("templateAuthor.finish", selection: $model.draft.validationMethod) {
                        ForEach(TemplateAuthoringMethod.allCases) { Text(LocalizedStringKey($0.labelKey)).tag($0) }
                    }.disabled(!model.draft.advanced.enabledGames.isEmpty)
                    TemplateAuthoringCompletionFields(model: model)
                    NavigationLink("templateAuthor.advanced") { TemplateAuthoringAdvancedView(model: model) }.accessibilityIdentifier("creatorComposition.open")
                }
            }
            TemplateAuthoringRewardStoryFields(model: model)
            Section {
                Button("templateAuthor.saveLocal") { model.save() }.accessibilityIdentifier("templateAuthor.saveLocal")
                Button("templateAuthor.preview") { preview = true }.disabled(!model.draft.publishIssues.isEmpty).accessibilityIdentifier("templateAuthor.preview")
                Button("templateAuthor.reviewDraft") { model.prepare(.saveDraft) }.disabled(!model.draft.canSave).accessibilityIdentifier("templateAuthor.reviewDraft")
                Button("templateAuthor.reviewPublish") { model.prepare(.publish) }.disabled(!model.draft.publishIssues.isEmpty).accessibilityIdentifier("templateAuthor.reviewPublish")
            }
            if !model.draft.publishIssues.isEmpty {
                Section("templateAuthor.validationTitle") { ForEach(Array(Set(model.draft.publishIssues)).sorted(), id: \.self) { Text(LocalizedStringKey($0)).foregroundStyle(.secondary) } }
            }
        }.disabled(!model.canEdit)
    }
}

struct TemplateAuthoringField: View {
    let key: String
    @Binding var text: String
    let multiline: Bool
    init(_ key: String, text: Binding<String>, multiline: Bool = false) { self.key = key; _text = text; self.multiline = multiline }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey("templateAuthor.field." + key)).font(.subheadline)
            TextField(LocalizedStringKey("templateAuthor.field." + key), text: $text, axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 3...10 : 1...1).accessibilityIdentifier("templateAuthor.field." + key)
                .textInputAutocapitalization(.sentences)
        }.padding(.vertical, 3)
    }
}

struct TemplateAuthoringReviewView: View {
    let review: TemplateAuthoringReview
    let canSimulate: Bool
    let canSubmit: Bool
    let confirm: () -> Void
    let cancel: () -> Void
    var body: some View {
        Form {
            Section("templateAuthor.reviewTitle") {
                Text(verbatim: review.title).font(.headline)
                Text(review.request.path.hasSuffix("publish") ? "templateAuthor.publishReview" : "templateAuthor.draftReview")
                Text(LocalizedStringKey(canSubmit ? "templateAuthor.httpReview" : "templateAuthor.unavailable"))
                if let id = review.draft?.originalTemplateID { LabeledContent("templateAuthor.original", value: String(id.rawValue)) }
            }
            if let draft = review.draft, !draft.advanced.enabledConfigurationLabelKeys.isEmpty {
                Section("creatorComposition.review") {
                    ForEach(draft.advanced.enabledConfigurationLabelKeys, id: \.self) { key in
                        Text(LocalizedStringKey(key)).accessibilityIdentifier("creatorComposition.review." + key)
                    }
                    if draft.advanced.hasRootAuthoringConfiguration { Text("creatorRoot.rules") }
                    Text("creatorComposition.presentationScope").font(.caption).foregroundStyle(.secondary)
                }
            }
            if canSimulate {
                Section { Text("templateAuthor.fixtureNotice"); Button("templateAuthor.confirmSimulation", action: confirm).accessibilityIdentifier("templateAuthor.confirmSimulation") }
            } else if canSubmit {
                Section { Button("templateAuthor.confirmRequest", action: confirm).accessibilityIdentifier("templateAuthor.confirmRequest") }
            }
        }.navigationTitle("templateAuthor.reviewTitle")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("templateAuthor.cancel", action: cancel).accessibilityIdentifier("templateAuthor.cancelReview") } }
    }
}

struct TemplateAuthoringPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let draft: TemplateAuthoringDraft
    var body: some View {
        List {
            Section { Text("templateAuthor.previewNotice").foregroundStyle(.secondary); Text(verbatim: draft.title).font(.title2); Text(verbatim: draft.description) }
            Section("templateAuthor.finish") {
                Text(LocalizedStringKey(draft.validationMethod.labelKey))
                if let question = draft.questionName { Text(verbatim: question) }
                if draft.validationMethod == .choice { ForEach([draft.questionA, draft.questionB, draft.questionC, draft.questionD].compactMap { $0 }, id: \.self) { Text(verbatim: $0) } }
                ForEach(draft.advanced.enabledGames) { game in
                    Text(LocalizedStringKey(game.labelKey))
                    if game.isMiniProgramAddition { NavigationLink("playkitAuthor.preview") { TemplateMiniGamePreviewView(draft: draft.advanced, game: game) } }
                    else if game == .dice && draft.advanced.diceMode == "d20" { NavigationLink("creatorRoot.d20Preview") { TemplateD20RehearsalView(draft: draft.advanced) } }
                    else { Text("templateAuthor.noGameplay").foregroundStyle(.secondary) }
                }
            }
            if draft.advanced.hasRootAuthoringConfiguration {
                Section("creatorRoot.rules") { NavigationLink("creatorRoot.rehearse") { TemplateRootRehearsalView(draft: draft.advanced) } }
            }
            if !draft.advanced.enabledCreatorFamilies.isEmpty {
                Section("creator.modules") {
                    ForEach(draft.advanced.enabledCreatorFamilies) { family in
                        NavigationLink(LocalizedStringKey(family.labelKey)) { TemplateCreatorRehearsalView(draft: draft.advanced, family: family) }
                    }
                }
            }
            if draft.storyEnabled {
                Section("templateAuthor.story") {
                    if let story = draft.storyText { Text(verbatim: story) }
                    ForEach((try? draft.storyBeats()) ?? []) { beat in
                        VStack(alignment: .leading) { if !beat.tag.isEmpty { Text(verbatim: beat.tag).font(.caption) }; Text(verbatim: beat.text); if !beat.imgs.isEmpty { Label("templateAuthor.linkedMedia", systemImage: "photo") } }
                    }
                }
            }
            if draft.rewardEnabled { Section("templateAuthor.reward") { Text("templateAuthor.rewardPreview") } }
        }.navigationTitle("templateAuthor.preview")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("templateAuthor.close") { dismiss() } } }
    }
}
