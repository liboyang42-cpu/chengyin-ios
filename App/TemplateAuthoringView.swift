import SwiftUI
import Combine

@MainActor final class TemplateAuthoringModel: ObservableObject {
    let coordinator: TemplateAuthoringCoordinator
    @Published var draft = TemplateAuthoringDraft()
    @Published var review: TemplateAuthoringReview?
    @Published var revision = 0
    @Published var busy = false
    @Published private(set) var optionMediaIssue: String?
    @Published private(set) var ruleSteps = TemplateAuthoringRuleSteps(raw: nil)
    @Published private(set) var ruleStepIssue: String?
    @Published private(set) var ruleInputRevisions: [UUID: UUID] = [:]
    private var optionMediaGeneration = 0
    private(set) var storyEditorGeneration = 0
    var legacyHintGeneration = UUID()
    private(set) var metadataGeneration = UUID()
    private(set) var mediaReviewGeneration = UUID()
    var mediaReviewControllers: [WeakTemplateMediaReviewController] = []
    var mediaImageSelectionApproved: () -> Bool = { false }
    var mediaFixtureMode: String?
    private var epoch: TemplateAuthoringSession?
    private var draftIdentity: TemplateAuthoringIdentity?
#if DEBUG
    // Bounded, non-observable input facts. Only the explicitly synthetic fixture probe displays them.
    private let gameInputProbeID = UUID()
    private var gameInputAttempts = 0
    private var gameInputEvents: [String] = []
    func gameInputProbe(_ game: TemplateAdvancedGame) -> String {
        "model=\(gameInputProbeID.uuidString);attempts=\(gameInputAttempts);canEdit=\(canEdit);modelEnabled=\(draft.advanced.enabled(game.section));coordinatorEnabled=\(coordinator.draft.advanced.enabled(game.section));locked=\(coordinator.locked);events=\(gameInputEvents.joined(separator: "|"))"
    }
#endif
    init(coordinator: TemplateAuthoringCoordinator) { self.coordinator = coordinator }
    // A pending/terminal write locks edits but must not blank the same owner's retained hints.
    var canReadLegacyHints: Bool { coordinator.session != nil && epoch == coordinator.session && draftIdentity == coordinator.identity }
    var canReadMetadataDraft: Bool { coordinator.session != nil && epoch == coordinator.session && draftIdentity == coordinator.identity }
    var canReadStoryDraft: Bool { coordinator.session != nil && epoch == coordinator.session && draftIdentity == coordinator.identity }
    var canEdit: Bool { coordinator.session != nil && epoch == coordinator.session && draftIdentity == coordinator.identity && !coordinator.locked && coordinator.restore == .missing }
    func load() {
        retireMediaReviews()
        metadataGeneration = UUID()
        storyEditorGeneration += 1
        legacyHintGeneration = UUID()
        // Child editors mutate the shared local draft while the parent Form is offscreen.
        // Preserve those edits before a same-owner reappearance reload, never across identity changes.
        if canEdit, draft != coordinator.draft { coordinator.change(draft) }
        coordinator.synchronizeSession(); coordinator.open()
        draft = coordinator.draft; epoch = coordinator.session; draftIdentity = coordinator.identity
        resetRuleSteps()
        review = nil; optionMediaIssue = nil; revision += 1
    }
    func changed() {
        metadataGeneration = UUID()
        guard canEdit else { draft = coordinator.draft; return }
        if ruleSteps.storedText != draft.ruleInstructions { resetRuleSteps() }
        coordinator.change(draft); review = nil; revision += 1
        refreshMediaReviews()
    }
    /// Optional-module manager commits only its captured draft and retires media/timeline callbacks first.
    @discardableResult func commitOptionalModuleChange(_ change: TemplateOptionalModules.Change, matching scope: TemplateOptionalModules) -> Bool {
        guard canEdit, !busy, review == nil, let next = scope.applying(change, to: draft) else { return false }
        retireMediaReviews(); storyEditorGeneration += 1
        draft = next; changed(); reloadMediaReviews(); return true
    }
    func setGameEnabled(_ game: TemplateAdvancedGame, _ enabled: Bool) {
#if DEBUG
        gameInputAttempts += 1
        let inputAllowed = canEdit, previous = draft.advanced.enabled(game.section)
        defer {
            gameInputEvents.append("game=\(game.rawValue),requested=\(enabled),allowed=\(inputAllowed),before=\(previous),after=\(draft.advanced.enabled(game.section)),saved=\(coordinator.draft.advanced.enabled(game.section))")
            gameInputEvents = Array(gameInputEvents.suffix(3))
        }
#endif
        guard canEdit else { return }
        draft.advanced.setGameEnabled(game, enabled)
        if enabled { draft.validationMethod = .manual }
        // A pushed editor can outlive the parent Form's onChange observation.
        // Commit before returning to the parent, whose task reloads the coordinator.
        changed()
    }
    func restore() {
        retireMediaReviews()
        metadataGeneration = UUID()
        storyEditorGeneration += 1; legacyHintGeneration = UUID(); optionMediaGeneration += 1
        optionMediaIssue = nil; coordinator.restoreDraft(); draft = coordinator.draft
        resetRuleSteps(); revision += 1; reloadMediaReviews()
    }
    func discard() {
        retireMediaReviews()
        metadataGeneration = UUID()
        storyEditorGeneration += 1; legacyHintGeneration = UUID(); optionMediaGeneration += 1
        optionMediaIssue = nil; coordinator.discardLocal(); draft = coordinator.draft
        resetRuleSteps(); revision += 1; reloadMediaReviews()
    }
    func save() { guard canEdit else { return }; coordinator.change(draft); coordinator.saveLocal(); revision += 1 }
    func prepare(_ intent: TemplateAuthoringIntent) { guard canEdit else { return }; metadataGeneration = UUID(); coordinator.change(draft); coordinator.prepare(intent); review = coordinator.review; revision += 1 }
    func cancel() { coordinator.cancelReview(); review = nil; revision += 1 }
    func confirm(_ value: TemplateAuthoringReview) async { busy = true; review = nil; await coordinator.confirm(value); busy = false; revision += 1 }
    func leave() {
        // Retained child callbacks must expire even when the same draft returns later.
        retireMediaReviews()
        metadataGeneration = UUID()
        storyEditorGeneration += 1; legacyHintGeneration = UUID(); optionMediaGeneration += 1
        coordinator.leaveScreen(); review = nil
    }
    private func retireMediaReviews() {
        mediaReviewGeneration = UUID()
        mediaReviewControllers = mediaReviewControllers.filter { $0.value != nil }
        mediaReviewControllers.forEach { $0.value?.retire() }
    }
    func mediaReferencesWillChange() { mediaReviewControllers.forEach { $0.value?.referencesWillChange() } }
    func refreshMediaReviews() { mediaReviewControllers.forEach { $0.value?.refresh() } }
    private func reloadMediaReviews() { mediaReviewControllers.forEach { $0.value?.reload() } }
    private func resetRuleSteps() {
        ruleSteps = .init(raw: draft.ruleInstructions); ruleStepIssue = nil; ruleInputRevisions = [:]
    }
    func ruleStep(_ id: UUID) -> Binding<String> {
        let bindingEpoch = epoch, bindingIdentity = draftIdentity
        return .init(get: {
            // Keep the same owner's locked review text visible; mutation still requires canEdit.
            guard self.epoch != nil, self.epoch == self.coordinator.session, self.epoch == bindingEpoch,
                  self.draftIdentity == self.coordinator.identity, self.draftIdentity == bindingIdentity,
                  self.ruleSteps.storedText == self.draft.ruleInstructions else { return "" }
            return self.ruleSteps.text(for: id) ?? ""
        }, set: { text in
            guard self.canEdit, self.epoch == bindingEpoch, self.draftIdentity == bindingIdentity,
                  self.ruleSteps.text(for: id) != nil else { return }
            self.changeRuleSteps(rejectedRowID: id) { try $0.update(id: id, text: text) }
        })
    }
    func addRuleStep() { changeRuleSteps { try $0.add() } }
    func removeRuleStep(_ id: UUID) { changeRuleSteps { try $0.remove(id: id) } }
    private func changeRuleSteps(rejectedRowID: UUID? = nil, _ edit: (inout TemplateAuthoringRuleSteps) throws -> Void) {
        guard canEdit, ruleSteps.storedText == draft.ruleInstructions else { return }
        do {
            var next = ruleSteps
            try edit(&next)
            ruleSteps = next; draft.ruleInstructions = next.storedText; ruleStepIssue = nil
            ruleInputRevisions = ruleInputRevisions.filter { next.text(for: $0.key) != nil }
            changed()
        } catch TemplateAuthoringRuleSteps.EditError.asciiLength {
            ruleStepIssue = "templateRules.asciiLimit"
            // Rejecting the model write alone leaves TextField's native editing buffer ahead.
            // Recreate only this control from the unchanged accepted row, never truncate source.
            if let rejectedRowID { ruleInputRevisions[rejectedRowID] = UUID() }
        } catch TemplateAuthoringRuleSteps.EditError.rowLimit {
            ruleStepIssue = "templateRules.rowLimit"
        } catch { /* Unsupported or stale rows remain unchanged. */ }
    }
    func optional(_ path: WritableKeyPath<TemplateAuthoringDraft, String?>) -> Binding<String> {
        let isMedia = path == \.questionImg || path == \.questionAudio || path == \.audioUrl
        let mediaGeneration = mediaReviewGeneration
        return .init(get: {
            if isMedia && (!self.canReadStoryDraft || self.mediaReviewGeneration != mediaGeneration) { return "" }
            return self.draft[keyPath: path] ?? ""
        }, set: {
            if isMedia {
                guard self.canEdit, self.mediaReviewGeneration == mediaGeneration else { return }
                self.mediaReferencesWillChange()
            }
            self.draft[keyPath: path] = $0.isEmpty ? nil : $0
        })
    }
    func number(_ path: WritableKeyPath<TemplateAuthoringDraft, Int?>) -> Binding<String> {
        .init(get: { self.draft[keyPath: path].map(String.init) ?? "" }, set: { self.draft[keyPath: path] = Int($0) })
    }
    func optionMedia(_ letter: TemplateChoiceOptionMedia.Letter, _ kind: TemplateChoiceOptionMedia.Kind) -> Binding<String> {
        let bindingEpoch = epoch, bindingIdentity = draftIdentity
        let bindingGeneration = optionMediaGeneration
        let mediaGeneration = mediaReviewGeneration
        return .init(get: {
            // A write-only lock must not hide this owner's unchanged media references.
            guard self.epoch != nil, self.epoch == self.coordinator.session, self.epoch == bindingEpoch,
                  self.draftIdentity == self.coordinator.identity, self.draftIdentity == bindingIdentity,
                  self.optionMediaGeneration == bindingGeneration, self.mediaReviewGeneration == mediaGeneration else { return "" }
            return self.draft.choiceOptionMedia.text(letter, kind) ?? ""
        }, set: { text in
            guard self.canEdit, self.epoch == bindingEpoch, self.draftIdentity == bindingIdentity,
                  self.optionMediaGeneration == bindingGeneration, self.mediaReviewGeneration == mediaGeneration, self.draft.validationMethod == .choice,
                  self.draft.choiceOptionMedia.isSupported else { return }
            do {
                self.mediaReferencesWillChange()
                try self.draft.setChoiceOptionMedia(letter, kind, to: text)
                self.optionMediaIssue = nil
                self.changed()
            } catch { self.optionMediaIssue = "templateAuthor.optionMedia.limit" }
        })
    }
}

/// Host within the existing navigation stack. Intro/name/edit are replacement steps.
@MainActor struct TemplateAuthoringView: View {
    @Environment(\.locale) private var locale
    private enum Step { case intro, name, edit }
    @StateObject private var model: TemplateAuthoringModel
    @StateObject private var media: TemplateMediaReviewController
    @State private var step: Step = .intro
    @State private var preview = false
    @State private var discard = false
    let sessionRevision: UInt64
    let metadataReader: (any DiscoveryReading)?
    private let onSavedDraft: ((TemplateAuthoringSavedDraft) -> Void)?
    private let canReturnSavedDraft: (TemplateAuthoringSavedDraft) -> Bool
    init(coordinator: TemplateAuthoringCoordinator, sessionRevision: UInt64, metadataReader: (any DiscoveryReading)? = nil,
         imageSelectionApproved: @escaping () -> Bool = { false }, mediaFixtureMode: String? = nil,
         onSavedDraft: ((TemplateAuthoringSavedDraft) -> Void)? = nil,
         canReturnSavedDraft: @escaping (TemplateAuthoringSavedDraft) -> Bool = { _ in false }) {
        let value = TemplateAuthoringModel(coordinator: coordinator)
        value.mediaImageSelectionApproved = imageSelectionApproved; value.mediaFixtureMode = mediaFixtureMode
        _model = StateObject(wrappedValue: value)
        _media = StateObject(wrappedValue: .init(model: value, imageSelectionApproved: imageSelectionApproved, fixtureMode: mediaFixtureMode))
        self.sessionRevision = sessionRevision; self.metadataReader = metadataReader
        self.onSavedDraft = onSavedDraft; self.canReturnSavedDraft = canReturnSavedDraft
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
            if let onSavedDraft {
                Section {
                    Text("projectNodeCreate.draftOnly", tableName: "ProjectNodeTemplateCreation")
                    if let saved = model.coordinator.savedDraft {
                        Text(verbatim: "#" + String(saved.memberTemplateID.rawValue))
                        Button(action: { onSavedDraft(saved) }, label: { Text("projectNodeCreate.return", tableName: "ProjectNodeTemplateCreation") })
                            .disabled(!canReturnSavedDraft(saved)).accessibilityIdentifier("projectNodeCreate.return")
                    } else if model.coordinator.locked {
                        Text("projectNodeCreate.noReceipt", tableName: "ProjectNodeTemplateCreation")
                    }
                }
            }
        }
        .navigationTitle("templateAuthor.title")
        .modifier(TemplateAuthoringExitGuard(model: model, overlaysOpen: { preview || discard || media.review != nil }))
        .disabled(model.busy)
        .task { model.load(); media.reload() }
        .onChange(of: model.draft) { _, _ in model.changed() }
        .onChange(of: sessionRevision) { _, _ in preview = false; step = .intro; model.load(); media.reload() }
        .onDisappear { media.retire(); model.leave() }
        .preference(key: TemplateAuthoringSavedResultPreferenceKey.self, value: TemplateAuthoringSavedResultObservation.capture(model: model, eligible: onSavedDraft == nil))
        .preference(key: TemplateAuthoringPublishResultPreferenceKey.self, value: TemplateAuthoringPublishResultObservation.capture(model: model, eligible: onSavedDraft == nil))
        .modifier(TemplateMediaReviewPresentation(controller: media))
        .sheet(isPresented: $preview) {
            TemplateConfiguredRehearsalPreview(model: model) { TemplateAuthoringPreviewView(draft: model.draft) }
        }
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
            TemplateAuthoringIntroExperience(model: model, reader: metadataReader, onContinue: { step = .name })
        }
    }
    private var name: some View {
        Section("templateAuthor.nameStep") {
            TextField("templateAuthor.field.title", text: $model.draft.title).accessibilityIdentifier("templateAuthor.field.title")
            TemplateBasicFieldClearButton(model: model, field: .title)
            Button("templateAuthor.continue") { step = .edit }.disabled(!model.draft.canSave || !model.canEdit).accessibilityIdentifier("templateAuthor.continue")
        }
    }
    @ViewBuilder private var editor: some View {
        Group {
            Section("templateAuthor.basics") {
                TemplateAuthoringField("title", text: $model.draft.title)
                TemplateBasicFieldClearButton(model: model, field: .title)
                TemplateAuthoringField("description", text: $model.draft.description, multiline: true)
                TemplateBasicFieldClearButton(model: model, field: .description)
                TemplateAuthoringMetadataFields(model: model, reader: metadataReader)
                TemplateAuthoringField("difficulty", text: model.optional(\.difficulty))
                TemplateAuthoringVenueField(model: model)
                TemplateAuthoringField("requiredMaterials", text: model.optional(\.requiredMaterials))
                TemplateAuthoringField("categoryId", text: model.number(\.categoryId))
                TemplateAuthoringRuleFields(model: model)
                TemplateAuthoringField("imgUrl", text: model.optional(\.imgUrl))
                TemplateBasicFieldClearButton(model: model, field: .cover)
                Text("templateAuthor.mediaHint").font(.caption).foregroundStyle(.secondary)
                Toggle("templateAuthor.sync", isOn: .init(get: { model.draft.isSync == 1 }, set: { model.draft.isSync = $0 ? 1 : 0 }))
            }
            Section("templateAuthor.finish") {
                Toggle("templateAuthor.moduleEnabled", isOn: $model.draft.finishEnabled)
                if model.draft.finishEnabled {
                    Picker("templateAuthor.finish", selection: model.legacyHintMethodBinding()) {
                        ForEach(TemplateAuthoringMethod.allCases) { Text(LocalizedStringKey($0.labelKey)).tag($0) }
                    }.disabled(!model.draft.advanced.enabledGames.isEmpty).accessibilityIdentifier("templateAuthor.method")
                    TemplateAuthoringCompletionFields(model: model)
                    NavigationLink("templateAuthor.advanced") { TemplateAuthoringAdvancedView(model: model) }.accessibilityIdentifier("creatorComposition.open")
                }
            }
            TemplateAuthoringRewardStoryFields(model: model)
            Section {
                NavigationLink("templateModules.title") { TemplateOptionalModuleManager(model: model) }
                    .accessibilityIdentifier("templateModules.open")
            }
            Section(String(localized: LocalizedStringResource("templateMedia.title", defaultValue: "Local media review", locale: locale))) {
                TemplateMediaReviewFields(controller: media)
            }
            Section {
                Button("templateAuthor.saveLocal") { model.save() }.accessibilityIdentifier("templateAuthor.saveLocal")
                Button("templateAuthor.preview") { preview = true }.disabled(!model.draft.publishIssues.isEmpty || model.draft.validationMethod == .preference).accessibilityIdentifier("templateAuthor.preview")
                if model.draft.validationMethod.isLocalConfigurationOnly { Text("templateAuthor.localConfigurationOnly") }
                Button("templateAuthor.reviewDraft") { model.prepare(.saveDraft) }.disabled(!model.draft.canSave || model.draft.validationMethod.isLocalConfigurationOnly).accessibilityIdentifier("templateAuthor.reviewDraft")
                if onSavedDraft == nil {
                    Button("templateAuthor.reviewPublish") { model.prepare(.publish) }.disabled(!model.draft.publishIssues.isEmpty || model.draft.validationMethod.isLocalConfigurationOnly).accessibilityIdentifier("templateAuthor.reviewPublish")
                }
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
    let accessibilityID: String?
    init(_ key: String, text: Binding<String>, multiline: Bool = false, accessibilityID: String? = nil) {
        self.key = key; _text = text; self.multiline = multiline; self.accessibilityID = accessibilityID
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey("templateAuthor.field." + key)).font(.subheadline)
            TextField(LocalizedStringKey("templateAuthor.field." + key), text: $text, axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 3...10 : 1...1).accessibilityIdentifier(accessibilityID ?? "templateAuthor.field." + key)
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

@MainActor struct TemplateAuthoringPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let draft: TemplateAuthoringDraft
    @Environment(\.templateConfiguredRehearsals) private var configuredRehearsals
    var body: some View {
        List {
            Section { Text("templateAuthor.previewNotice").foregroundStyle(.secondary); Text(verbatim: draft.title).font(.title2); Text(verbatim: draft.description) }
            Section("templateAuthor.finish") {
                Text(LocalizedStringKey(draft.validationMethod.labelKey))
                if draft.validationMethod.rawValue == 7 {
                    TemplateSensorDraftPreviewContent(draft: draft.sensorDraft ?? .init())
                }
                if let question = draft.questionName { Text(verbatim: question) }
                if draft.validationMethod == .choice { ForEach([draft.questionA, draft.questionB, draft.questionC, draft.questionD].compactMap { $0 }, id: \.self) { Text(verbatim: $0) } }
                if draft.validationMethod == .choice {
                    TemplateChoiceOptionMediaFields(configuration: draft.choiceOptionMedia,
                        field: { letter, kind in .constant(draft.choiceOptionMedia.text(letter, kind) ?? "") }, readOnly: true)
                }
                if let configuredRehearsals, configuredRehearsals.offersLegacyQuestion {
                    TemplateConfiguredLegacyRehearsalPreviewButton(controller: configuredRehearsals)
                }
                ForEach(draft.advanced.enabledGames) { game in
                    Text(LocalizedStringKey(game.labelKey))
                    if let configuredRehearsals, configuredRehearsals.route(for: game) != nil {
                        TemplateConfiguredRehearsalPreviewButton(controller: configuredRehearsals, game: game)
                    }
                    else if game.isMiniProgramAddition { NavigationLink("playkitAuthor.preview") { TemplateMiniGamePreviewView(draft: draft.advanced, game: game) } }
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
                    if let story = try? draft.preparedStoryText() { Text(verbatim: story) }
                    ForEach((try? draft.storyBeats()) ?? []) { beat in
                        VStack(alignment: .leading) { if !beat.tag.isEmpty { Text(verbatim: beat.tag).font(.caption) }; Text(verbatim: beat.text); if !beat.imgs.isEmpty { Label("templateAuthor.linkedMedia", systemImage: "photo") } }
                    }
                }
            }
            if let raw = draft.preferenceJson { Section("templateAuthor.preference.title") { TemplatePreferencePreviewView(raw: raw) } }
            if draft.rewardEnabled { Section("templateAuthor.reward") {
                Text("templateAuthor.rewardPreview")
                if let style = draft.medalStyle, !(draft.medalName ?? "").isEmpty || !(draft.medalImg ?? "").isEmpty {
                    LabeledContent("templateAuthor.field.medalStyle", value: style)
                }
            } }
        }.navigationTitle("templateAuthor.preview")
            .toolbar { ToolbarItem(placement: .cancellationAction) { if let configuredRehearsals {
                TemplateConfiguredRehearsalCloseButton(controller: configuredRehearsals)
            } else { Button("templateAuthor.close") { dismiss() } } } }
    }
}

// These actions affect only the current unsaved basic fields.
enum TemplateBasicClearField {
    case title, description, cover, questionImage, questionAudio
    case optionMedia(TemplateChoiceOptionMedia.Letter)
    var rawValue: String {
        switch self {
        case .title: return "title"
        case .description: return "description"
        case .cover: return "cover"
        case .questionImage: return "questionImage"
        case .questionAudio: return "questionAudio"
        case .optionMedia(let letter): return "optionMedia." + letter.rawValue
        }
    }
    func value(in draft: TemplateAuthoringDraft) -> String {
        switch self {
        case .title: return draft.title
        case .description: return draft.description
        case .cover: return draft.imgUrl ?? ""
        case .questionImage, .questionAudio:
            guard draft.finishEnabled, [.text, .choice].contains(draft.validationMethod) else { return "" }
            switch self { case .questionImage: return draft.questionImg ?? ""; default: return draft.questionAudio ?? "" }
        case .optionMedia(let letter):
            let media = draft.choiceOptionMedia
            guard draft.finishEnabled, draft.validationMethod == .choice, media.isSupported,
                  TemplateChoiceOptionRows(draft: draft).letters.contains(letter),
                  Self.hasUniqueMediaKeys(draft.questionOptionMediaJson) else { return "" }
            return [media.text(letter, .image), media.text(letter, .audio)].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        }
    }
    func label(_ locale: Locale) -> String {
        let chinese = locale.language.languageCode?.identifier == "zh"
        switch self {
        case .title: return chinese ? "清空标题" : "Clear title"
        case .description: return chinese ? "清空描述" : "Clear description"
        case .cover: return chinese ? "清空封面引用" : "Clear cover reference"
        case .questionImage: return chinese ? "清空题干配图引用" : "Clear question image reference"
        case .questionAudio: return chinese ? "清空题干音频引用" : "Clear question audio reference"
        case .optionMedia(let letter): return chinese ? "清空选项 \(letter.rawValue) 媒体引用" : "Clear option \(letter.rawValue) media references"
        }
    }
    // The existing projection validates the schema. This narrow lexical guard also
    // rejects duplicate or escaped-alias keys before an explicit edit rewrites JSON.
    private static func hasUniqueMediaKeys(_ raw: String?) -> Bool {
        guard let raw, !raw.isEmpty else { return true }
        let bytes = Array(raw.utf8)
        var index = 0, objects: [Set<Data>] = []
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 123 { objects.append([]); index += 1 }
            else if byte == 125 {
                guard !objects.isEmpty else { return false }; objects.removeLast(); index += 1
            } else if byte == 34 {
                let start = index; index += 1
                var closed = false
                while index < bytes.count {
                    let value = bytes[index]; index += 1
                    if value == 92 { guard index < bytes.count else { return false }; index += 1 }
                    else if value == 34 { closed = true; break }
                }
                guard closed else { return false }
                var next = index
                while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
                if next < bytes.count && bytes[next] == 58 {
                    guard !objects.isEmpty,
                          let key = try? JSONDecoder().decode(String.self, from: Data(bytes[start..<index])),
                          objects[objects.count - 1].insert(Data(key.utf8)).inserted else { return false }
                }
            } else { index += 1 }
        }
        return objects.isEmpty
    }
}

@MainActor final class TemplateBasicFieldClearController: ObservableObject {
    private let model: TemplateAuthoringModel
    let field: TemplateBasicClearField
    private var observation: AnyCancellable?
    private var visible = false, active = false
    @Published private(set) var generation = UUID()
    init(model: TemplateAuthoringModel, field: TemplateBasicClearField) {
        self.model = model; self.field = field
        observation = model.objectWillChange.sink { [weak self] _ in self?.generation = UUID() }
    }
    var canClear: Bool {
        visible && active && model.canEdit && !model.busy && model.review == nil &&
        model.coordinator.review == nil && !field.value(in: model.draft).isEmpty
    }
    func appear(sceneIsActive: Bool) {
        if !visible || active != sceneIsActive { generation = UUID() }
        visible = true; active = sceneIsActive
    }
    func disappear() { visible = false; active = false; generation = UUID() }
    func sceneChanged(isActive: Bool) {
        let next = visible && isActive
        if next != active { generation = UUID() }
        active = next
    }
    func clearAction() -> () -> Void {
        let stamp = generation, session = model.coordinator.session, identity = model.coordinator.identity
        let metadata = model.metadataGeneration, media = model.mediaReviewGeneration
        let source = TemplateSamplePreview.snapshot(model.draft)
        return { [weak self] in
            guard let self, self.canClear, self.generation == stamp, session != nil,
                  self.model.coordinator.session == session, self.model.coordinator.identity == identity,
                  self.model.metadataGeneration == metadata, self.model.mediaReviewGeneration == media,
                  source != nil, source == TemplateSamplePreview.snapshot(self.model.draft) else { return }
            switch self.field {
            case .title: self.model.draft.title = ""
            case .description: self.model.draft.description = ""
            case .cover: self.model.draft.imgUrl = nil
            case .questionImage:
                self.model.mediaReferencesWillChange()
                self.model.draft.questionImg = nil
            case .questionAudio:
                self.model.mediaReferencesWillChange()
                self.model.draft.questionAudio = nil
            case .optionMedia(let letter):
                do {
                    var next = self.model.draft
                    try next.setChoiceOptionMedia(letter, .image, to: "")
                    try next.setChoiceOptionMedia(letter, .audio, to: "")
                    self.model.mediaReferencesWillChange()
                    self.model.draft = next
                } catch { return }
            }
            self.model.changed()
        }
    }
}

@MainActor struct TemplateBasicFieldClearButton: View {
    @StateObject private var controller: TemplateBasicFieldClearController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    init(model: TemplateAuthoringModel, field: TemplateBasicClearField) {
        _controller = StateObject(wrappedValue: .init(model: model, field: field))
    }
    var body: some View {
        Button(controller.field.label(locale), action: controller.clearAction())
            .disabled(!controller.canClear)
            .accessibilityIdentifier("templateBasicClear." + controller.field.rawValue)
            .onAppear { controller.appear(sceneIsActive: scenePhase == .active) }
            .onDisappear { controller.disappear() }
            .onChange(of: scenePhase) { _, phase in controller.sceneChanged(isActive: phase == .active) }
    }
}
