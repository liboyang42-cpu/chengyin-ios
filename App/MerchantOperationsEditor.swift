import SwiftUI

@MainActor
struct MerchantOperationsEditor: View {
    @ObservedObject var model: MerchantOperationsViewModel
    var templateAssistFactory: ((MerchantOperationsCoordinator) -> MerchantTemplateAssistFlow)? = nil
    @State private var assist: MerchantTemplateAssistPresentation?
    var imageContext: ((MerchantImageField) -> RetainedImageSelectionContext?)? = nil
    private var coordinator: MerchantOperationsCoordinator { model.coordinator }
    private var isExample: Bool { coordinator.reader.isOfflineExample }
    var body: some View {
        Form {
            Section { MerchantOperationsBoundary(isExample: isExample) }
            if let draft = coordinator.draft {
                fields(draft)
                if let blocker = draft.blocker { Section { Text(LocalizedStringKey(blocker)).foregroundStyle(.secondary).accessibilityIdentifier("merchant.operations.blocker") } }
            }
            if coordinator.exampleSaved { Section { Label("merchant.operations.exampleSaved", systemImage: "checkmark.circle").accessibilityIdentifier("merchant.operations.exampleSaved") } }
            if let issue = coordinator.issue { Section { MerchantOperationsIssueView(issue: issue) } }
            if coordinator.isLocked { Section { Text("merchant.operations.unknownOutcome") } }
            Section {
                Button("merchant.operations.reviewDraft") { model.prepare() }
                    .disabled(!coordinator.canReview).accessibilityIdentifier("merchant.operations.review")
                if !isExample { Text("merchant.operations.localDraftOnly").font(.footnote).foregroundStyle(.secondary) }
                if coordinator.isBusy { ProgressView("merchant.loading") }
            }
        }
        .disabled(coordinator.isBusy)
        .accessibilityIdentifier("merchant.operations.editor")
        .sheet(item: $assist) { presentation in MerchantTemplateAssistSheet(document: model, flow: presentation.flow) }
    }
    @ViewBuilder private func fields(_ draft: MerchantOperationsDraft) -> some View {
        switch draft {
        case .npcMapPoint:
            MerchantNPCMapPointFields(document: model)
        case .businessStatus:
            Section("merchant.operations.businessStatus") {
                Picker("merchant.operations.businessStatus", selection: Binding<MerchantBusinessStatus>(get: {
                    if case .businessStatus(let value) = coordinator.draft { return value.status }; return .closed
                }, set: { status in
                    guard case .businessStatus(var value) = coordinator.draft else { return }
                    value.status = status; model.edit(.businessStatus(value))
                })) {
                    ForEach(MerchantBusinessStatus.allCases, id: \.rawValue) { value in Text(LocalizedStringKey(value.titleKey)).tag(value) }
                }.pickerStyle(.segmented).accessibilityIdentifier("merchant.operations.status.picker")
                Text("merchant.operations.statusHint").font(.footnote).foregroundStyle(.secondary)
            }
        case .profile(let value):
            MerchantOperationsMediaPreview(source: value.logo, title: "merchant.operations.logo", isExample: isExample)
            Section("merchant.operations.profile") {
                profileField("merchant.operations.name", \.name, "name")
                profileField("merchant.operations.description", \.description, "description", multiline: true)
                profileField("merchant.operations.derivatives", \.derivatives, "derivatives")
                TextField("merchant.operations.derivativeBenefits", text: Binding(get: {
                    guard case .profile(let current) = coordinator.draft else { return "" }
                    return current.derivativeBenefits ?? ""
                }, set: { text in
                    guard case .profile(var current) = coordinator.draft else { return }
                    current.derivativeBenefits = text; model.edit(.profile(current))
                }), axis: .vertical).accessibilityIdentifier("merchant.operations.field.derivativeBenefits")
                Text("merchant.operations.benefitsHint").font(.footnote).foregroundStyle(.secondary)
                profileField("merchant.operations.website", \.website, "website")
                profileField("merchant.operations.preference", \.preference, "preference")
                Text("merchant.operations.profileWhitelist").font(.footnote).foregroundStyle(.secondary)
            }
            MerchantBrandImagesEntry(document: model)
            MerchantStoreHoursEditor(model: model)
            mediaSection("merchant.operations.logo", field: .logo)
        case .decor(let value):
            MerchantOperationsMediaPreview(source: value.coverImage, title: "merchant.operations.cover", isExample: isExample)
            Section("merchant.operations.decor") {
                decorField("merchant.operations.slogan", \.slogan, "slogan")
                decorField("merchant.operations.cityRole", \.cityRole, "cityRole")
                Text("merchant.featuredClear.draftHint").font(.footnote).foregroundStyle(.secondary)
                MerchantStoreIndustryPicker(document: model)
                if let type = value.featuredType, let id = value.featuredID { LabeledContent("merchant.operations.featured", value: "\(type) / \(id)") }
                MerchantFeaturedClearControl(model: model, source: value)
                MerchantFeaturedActivityPicker(document: model)
            }
            Section("merchant.operations.tags") {
                ForEach(Array(value.tags.enumerated()), id: \.offset) { index, tag in
                    Text(verbatim: tag)
                        .accessibilityIdentifier("merchant.operations.tags.value." + String(index))
                }
                MerchantDecorTagEditor(model: model)
            }
            mediaSection("merchant.operations.cover", field: .coverImage)
        case .gallery(let value):
            Section("merchant.operations.gallery") {
                Text("merchant.operations.galleryHint").font(.footnote)
                ForEach(Array(value.gallery.enumerated()), id: \.offset) { index, reference in
                    MerchantOperationsMediaPreview(source: reference, title: "merchant.operations.galleryImage", isExample: isExample)
                    HStack {
                        Label { Text("merchant.operations.galleryImage"); Text(index + 1, format: .number) } icon: { Image(systemName: "photo") }
                        Spacer()
                        Button(role: .destructive) {
                            guard case .gallery(var value) = coordinator.draft, value.gallery.indices.contains(index) else { return }
                            value.gallery.remove(at: index); model.edit(.gallery(value))
                        } label: { Image(systemName: "minus.circle").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("merchant.operations.removeImage")
                        .accessibilityIdentifier("merchant.operations.gallery.remove." + String(index))
                    }
                }
                if isExample {
                    Button("merchant.operations.addExampleImage") {
                        guard case .gallery(var value) = coordinator.draft, value.gallery.count < 9 else { return }
                        value.gallery.append("synthetic-gallery-" + UUID().uuidString); model.edit(.gallery(value))
                    }.disabled(value.gallery.count >= 9).accessibilityIdentifier("merchant.operations.gallery.add")
                }
                imageControls(.gallery)
            }
        case .story:
            Section("merchant.operations.story") {
                TextField("merchant.operations.storyBody", text: Binding(get: {
                    guard case .story(let value) = coordinator.draft else { return "" }; return value.profile.description
                }, set: { text in
                    guard case .story(var value) = coordinator.draft else { return }; value.profile.description = text; model.edit(.story(value))
                }), axis: .vertical).lineLimit(8...18).accessibilityIdentifier("merchant.operations.field.story")
                Text("merchant.operations.storyHint").font(.footnote).foregroundStyle(.secondary)
            }
        case .cooperation(let value):
            Section("merchant.operations.cooperation") {
                coopField("merchant.operations.capacity", \.capacity, "capacity", number: true)
                if value.clearsCapacity { Text("merchant.coopCapacityClear.draftHint").font(.footnote).foregroundStyle(.secondary) }
                coopField("merchant.operations.availableTime", \.availableTime, "availableTime")
                Picker("merchant.operations.chargeType", selection: Binding<Int?>(get: {
                    guard case .cooperation(let value) = coordinator.draft else { return nil }; return value.chargeType
                }, set: { selected in
                    guard case .cooperation(var value) = coordinator.draft else { return }; value.chargeType = selected; model.edit(.cooperation(value))
                })) {
                    Text("merchant.operations.unspecified").tag(Int?.none)
                    Text("merchant.operations.charge.free").tag(Int?.some(0))
                    Text("merchant.operations.charge.paid").tag(Int?.some(1))
                    if let raw = value.chargeType, ![0, 1].contains(raw) { Text("merchant.operations.review.unknown").tag(Int?.some(raw)) }
                }
                coopField("merchant.operations.demand", \.demand, "demand")
                Text("merchant.operations.coopPreserved").font(.footnote).foregroundStyle(.secondary)
            }
        case .character(let value):
            if !value.avatar.hasPrefix("px1:") {
                MerchantOperationsMediaPreview(source: value.avatar, title: "merchant.operations.avatar", isExample: isExample)
            }
            MerchantNPCPresetSection(document: model)
            Section("merchant.operations.character") {
                LabeledContent("merchantPreset.lastReview") {
                    Text(LocalizedStringKey(value.reviewKey)).accessibilityIdentifier("merchant.operations.character.review")
                }
                if let reason = value.rejectionReason {
                    Text(verbatim: reason).textSelection(.enabled).accessibilityIdentifier("merchantPreset.rejectionReason")
                }
                characterField("merchant.operations.name", \.name, "characterName")
                characterField("merchant.operations.greeting", \.greeting, "greeting")
                characterField("merchant.operations.persona", \.persona, "persona")
                characterField("merchant.operations.knowledge", \.knowledge, "knowledge")
                Text("merchantPreset.fieldLimits").font(.footnote).foregroundStyle(.secondary)
                if value.persona.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("merchantPreset.emptyPersona").font(.footnote).foregroundStyle(.secondary)
                }
                Text("merchant.operations.characterReviewHint").font(.footnote).foregroundStyle(.secondary)
            }
            mediaSection("merchant.operations.avatar", field: .avatar)
            MerchantNPCGreetingPreviewEntry(document: model).id(coordinator.draftIdentity)
            MerchantNPCKnowledgeDraftEntry(document: model).id(coordinator.draftIdentity)
            MerchantNPCMapPointEntry(document: model)
        case .template(let value):
            Section {
                Button("merchant.assist.title", systemImage: "sparkles") {
                    let flow = templateAssistFactory?(coordinator) ?? MerchantTemplateAssistFlow(coordinator: coordinator, client: nil)
                    assist = .init(flow: flow)
                }.disabled(!coordinator.isCurrent || coordinator.isLocked || coordinator.confirmation != nil)
                    .accessibilityIdentifier("merchant.assist.open")
            }
            MerchantOperationsMediaPreview(source: value.imgURL, title: "merchant.operations.cover", isExample: isExample)
            Section("merchant.operations.template") {
                templateField("merchant.operations.titleField", \.title, "title")
                templateField("merchant.operations.description", \.description, "templateDescription")
                Picker("merchant.operations.method", selection: Binding<Int>(get: { currentTemplate?.method?.rawValue ?? 0 }, set: { raw in
                    guard var value = currentTemplate else { return }; value.method = MerchantTemplateMethod(rawValue: raw); model.edit(.template(value))
                })) {
                    Text("merchant.operations.chooseMethod").tag(0)
                    ForEach(MerchantTemplateMethod.allCases, id: \.rawValue) { method in Text(LocalizedStringKey(method.titleKey)).tag(method.rawValue) }
                }.accessibilityIdentifier("merchant.operations.method")
            }
            Section("merchant.templateMetadata.title") {
                templateField("merchant.templateMetadata.duration", \.gameDurationMinutes, "gameDurationMinutes")
                templateField("merchant.templateMetadata.players", \.players, "players")
                Text("merchant.templateMetadata.scopeHint").font(.footnote).foregroundStyle(.secondary)
                Text("merchant.templateMetadata.omissionHint").font(.footnote).foregroundStyle(.secondary)
            }
            Section("merchant.preparation.title") {
                Picker("merchant.preparation.venueLabel", selection: Binding(get: { currentTemplate?.usageLocation ?? "" }, set: { text in
                    guard var value = currentTemplate else { return }
                    value.usageLocation = text; model.edit(.template(value))
                })) {
                    Text("merchant.preparation.unspecified").tag("").disabled(true)
                    if !value.usageLocation.isEmpty, MerchantTemplateVenueChoice(rawValue: value.usageLocation) == nil {
                        Text(verbatim: value.usageLocation).tag(value.usageLocation)
                    }
                    ForEach(MerchantTemplateVenueChoice.allCases, id: \.rawValue) { choice in
                        Text(LocalizedStringKey(choice.titleKey)).tag(choice.rawValue)
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("merchant.preparation.venue")
                if !value.usageLocation.isEmpty, MerchantTemplateVenueChoice(rawValue: value.usageLocation) == nil {
                    Text("merchant.preparation.unknownVenue").font(.footnote).foregroundStyle(.secondary)
                }
                templateField("merchant.preparation.materials", \.requiredMaterials, "requiredMaterials")
                Text("merchant.preparation.hint").font(.footnote).foregroundStyle(.secondary)
                Text("merchant.preparation.omissionHint").font(.footnote).foregroundStyle(.secondary)
            }
            MerchantTemplateCategoryPicker(document: model)
            MerchantTemplateStoryTimelineFields(model: model)
            MerchantTemplateRuleStepsFields(model: model)
            MerchantTemplateParticipationPlanFields(model: model)
            MerchantTemplateExitPlanFields(model: model)
            if value.method == .secretWord { Section { templateField("merchant.operations.answer", \.questionAnswer, "answer") } }
            if value.method == .quiz {
                Section("merchant.operations.quiz") {
                    templateField("merchant.operations.question", \.questionName, "question")
                    templateField("merchant.operations.optionA", \.optionA, "optionA")
                    templateField("merchant.operations.optionB", \.optionB, "optionB")
                    templateField("merchant.operations.optionC", \.optionC, "optionC")
                    templateField("merchant.operations.optionD", \.optionD, "optionD")
                    Picker("merchant.operations.correctAnswer", selection: Binding(get: { currentTemplate?.correctAnswer ?? "" }, set: { answer in
                        guard var value = currentTemplate else { return }; value.correctAnswer = answer; model.edit(.template(value))
                    })) {
                        Text("merchant.operations.unspecified").tag("")
                        ForEach(["A", "B", "C", "D"], id: \.self) { Text(verbatim: $0).tag($0) }
                    }
                }
            }
            MerchantTemplateHintsFields(model: model)
            Section {
                templateField("merchant.operations.feedback", \.feedbackText, "feedback")
                Text("merchant.operations.templateOwnerOnly").font(.footnote).foregroundStyle(.secondary)
                Text("merchant.operations.templateOmissions").font(.footnote).foregroundStyle(.secondary)
            }
            mediaSection("merchant.operations.cover", field: .imgUrl)
        }
    }
    private var currentDecor: MerchantStoreDecor? { if case .decor(let value) = coordinator.draft { return value }; return nil }
    private var currentTemplate: MerchantNodeTemplate? { if case .template(let value) = coordinator.draft { return value }; return nil }
    private func mediaSection(_ title: LocalizedStringKey, field: MerchantImageField) -> some View {
        Section(title) { imageControls(field) }
    }
    @ViewBuilder private func imageControls(_ field: MerchantImageField) -> some View {
        if field == .gallery {
            MerchantGalleryBatchView(batch: model.galleryBatch, binding: model.galleryBatchBinding,
                available: gallerySelectionAvailable)
        } else if let context = imageContext?(field) {
            RetainedImageSelectionView(context: context) { image in
                guard coordinator.isCurrent, !coordinator.isBusy, !coordinator.isLocked,
                      coordinator.confirmation == nil, context.currentScope() == context.scope,
                      case .merchant(_, let expectedField) = context.scope.destination, expectedField == field,
                      let draft = coordinator.draft,
                      let updated = try? image.applying(to: draft, expectedScope: context.scope) else { return false }
                model.edit(updated)
                return coordinator.draft == updated
            }.id(context.scope.accessRevision)
            .disabled(coordinator.confirmation != nil || coordinator.isLocked)
        } else { Label("merchant.operations.uploadDisabled", systemImage: "photo").font(.footnote).foregroundStyle(.secondary) }
    }
    private var gallerySelectionAvailable: Bool {
        guard !model.galleryBatch.active, !model.galleryBatch.blocked,
              case .gallery(let value) = coordinator.draft, value.gallery.count < 9,
              let context = imageContext?(.gallery) else { return false }
        return context.picker.enabled && context.uploads.uploader.isConfigured && !context.uploads.locked
    }
    private func profileField(_ title: LocalizedStringKey, _ key: WritableKeyPath<MerchantStoreProfile, String>, _ id: String, multiline: Bool = false) -> some View {
        TextField(title, text: Binding(get: { if case .profile(let value) = coordinator.draft { return value[keyPath: key] }; return "" }, set: { text in
            guard case .profile(var value) = coordinator.draft else { return }; value[keyPath: key] = text; model.edit(.profile(value))
        }), axis: multiline ? .vertical : .horizontal).accessibilityIdentifier("merchant.operations.field." + id)
    }
    private func decorField(_ title: LocalizedStringKey, _ key: WritableKeyPath<MerchantStoreDecor, String>, _ id: String) -> some View {
        TextField(title, text: Binding(get: { currentDecor?[keyPath: key] ?? "" }, set: { text in
            guard var value = currentDecor else { return }; value[keyPath: key] = text; model.edit(.decor(value))
        }), axis: .vertical).accessibilityIdentifier("merchant.operations.field." + id)
    }
    private func coopField(_ title: LocalizedStringKey, _ key: WritableKeyPath<MerchantCoopSettings, String>, _ id: String, number: Bool = false) -> some View {
        TextField(title, text: Binding(get: { if case .cooperation(let value) = coordinator.draft { return value[keyPath: key] }; return "" }, set: { text in
            guard case .cooperation(var value) = coordinator.draft else { return }; value[keyPath: key] = text; model.edit(.cooperation(value))
        }), axis: .vertical).keyboardType(number ? .numberPad : .default).accessibilityIdentifier("merchant.operations.field." + id)
    }
    private func characterField(_ title: LocalizedStringKey, _ key: WritableKeyPath<MerchantStoreCharacter, String>, _ id: String) -> some View {
        TextField(title, text: Binding(get: { if case .character(let value) = coordinator.draft { return value[keyPath: key] }; return "" }, set: { text in
            guard case .character(var value) = coordinator.draft else { return }; value[keyPath: key] = text; model.edit(.character(value))
        }), axis: .vertical).accessibilityIdentifier("merchant.operations.field." + id)
    }
    private func templateField(_ title: LocalizedStringKey, _ key: WritableKeyPath<MerchantNodeTemplate, String>, _ id: String) -> some View {
        TextField(title, text: Binding(get: { currentTemplate?[keyPath: key] ?? "" }, set: { text in
            guard var value = currentTemplate else { return }; value[keyPath: key] = text; model.edit(.template(value))
        }), axis: .vertical).accessibilityIdentifier("merchant.operations.field." + id)
    }
}

@MainActor
struct MerchantOperationsConfirmationView: View {
    @ObservedObject var model: MerchantOperationsViewModel
    let confirmation: MerchantOperationsConfirmation
    private var isExample: Bool { model.coordinator.reader.isOfflineExample }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(LocalizedStringKey(confirmation.draft.localOnlyReview ? "merchant.participation.localOnly" : (isExample ? "merchant.operations.confirmExampleBody" : (model.coordinator.reader.canSave ? "merchant.operations.confirmLiveHint" : "merchant.operations.liveDisabled"))))
                    Text("merchant.operations.reviewNoApproval").font(.footnote).foregroundStyle(.secondary)
                    Text(LocalizedStringKey(confirmation.draft.destination.titleKey)).font(.headline)
                }
                if let change = MerchantStoreIndustryChange(baseline: model.coordinator.baseline, draft: confirmation.draft) {
                    MerchantStoreIndustryReview(change: change)
                }
                if let avatar = MerchantNPCCharacterAvatarSnapshot(draft: confirmation.draft) {
                    if let preset = avatar.preset {
                        Section("merchant.operations.avatar") {
                            MerchantNPCPresetArtwork(avatar: preset).frame(width: 192, height: 192)
                                .clipShape(RoundedRectangle(cornerRadius: 20)).frame(maxWidth: .infinity)
                            Text(LocalizedStringKey(preset.titleKey)).accessibilityIdentifier("merchantPreset.review." + preset.id)
                        }
                    } else {
                        MerchantOperationsMediaPreview(source: avatar.rawValue, title: "merchant.operations.avatar", isExample: isExample)
                    }
                    Section {
                        Text(verbatim: avatar.rawValue).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("merchantPreset.review.rawValue")
                    }
                }
                Section("merchant.operations.frozenDraft") {
                    if case .cooperation(let value) = confirmation.draft, value.clearsCapacity {
                        Text("merchant.coopCapacityClear.review").fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("merchant.coopCapacityClear.review")
                    }
                    if case .decor(let value) = confirmation.draft, value.featuredType == 1, let id = value.featuredID, id > 0 {
                        LabeledContent("merchant.featuredPicker.reviewActivity", value: String(id))
                        Text("merchant.featuredPicker.finalValidation").font(.footnote)
                    }
                    if case .decor(let value) = confirmation.draft, value.featuredType == 0, value.featuredID == nil {
                        Text("merchant.featuredClear.review").fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("merchant.featuredClear.review")
                    }
                    ForEach(confirmation.draft.reviewLines) { line in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey(line.key)).font(.caption).foregroundStyle(.secondary)
                            if line.key == "merchant.operations.businessStatus", let raw = Int(line.value), let status = MerchantBusinessStatus(rawValue: raw) {
                                Text(LocalizedStringKey(status.titleKey))
                            } else if line.key == "merchant.operations.chargeType", ["0", "1"].contains(line.value) {
                                Text(LocalizedStringKey(line.value == "0" ? "merchant.operations.charge.free" : "merchant.operations.charge.paid"))
                            } else { Text(verbatim: line.value.isEmpty ? "—" : line.value).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                    if case .template(let value) = confirmation.draft, let method = value.method { Text(LocalizedStringKey(method.titleKey)) }
                }
                if case .template(let template) = confirmation.draft {
                    Section("merchant.templateMetadata.title") {
                        LabeledContent("merchant.templateMetadata.duration", value: template.gameDurationMinutes.trimmingCharacters(in: .whitespacesAndNewlines))
                            .accessibilityIdentifier("merchant.templateMetadata.review.duration")
                        LabeledContent("merchant.templateMetadata.players", value: template.players.trimmingCharacters(in: .whitespacesAndNewlines))
                            .accessibilityIdentifier("merchant.templateMetadata.review.players")
                        Text("merchant.templateMetadata.omissionHint").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if case .template(let template) = confirmation.draft {
                    Section("merchant.preparation.title") {
                        LabeledContent("merchant.preparation.venueLabel") {
                            if let choice = MerchantTemplateVenueChoice(rawValue: template.usageLocation) {
                                Text(LocalizedStringKey(choice.titleKey))
                            } else { Text(verbatim: template.usageLocation) }
                        }.accessibilityIdentifier("merchant.preparation.review.venue")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("merchant.preparation.materials").font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: template.requiredMaterials.trimmingCharacters(in: .whitespacesAndNewlines))
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("merchant.preparation.review.materials")
                        }
                        Text("merchant.preparation.omissionHint").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if case .template(let template) = confirmation.draft, let plan = template.participationPlan {
                    MerchantTemplateParticipationPlanReview(plan: plan)
                }
                if case .template(let template) = confirmation.draft {
                    MerchantTemplateCategoryReview(categories: template.categories)
                    MerchantTemplateStoryTimelineReview(timeline: template.storyTimeline)
                    MerchantTemplateRuleStepsReview(rules: template.ruleSteps)
                    MerchantTemplateHintsReview(hints: template.hints)
                }
                if case .template(let template) = confirmation.draft, let plan = template.exitPlan {
                    MerchantTemplateExitPlanReview(plan: plan)
                }
                Section {
                    Button(LocalizedStringKey(confirmation.draft.localOnlyReview ? "merchant.participation.localOnlyAction" : (isExample ? "merchant.operations.confirmExample" : (model.coordinator.reader.canSave ? "merchant.operations.confirmLive" : "merchant.operations.liveDisabled")))) {
                        Task { await model.confirm(confirmation) }
                    }.disabled(confirmation.draft.localOnlyReview || !model.coordinator.reader.canSave || model.coordinator.isBusy).accessibilityIdentifier("merchant.operations.confirm")
                }
            }
            .appNavigationTitle("merchant.operations.reviewDraft")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { model.cancel() }.accessibilityIdentifier("merchant.operations.confirm.cancel") } }
        }
    }
}


private struct MerchantOperationsMediaPreview: View {
    let source: String?
    let title: LocalizedStringKey
    let isExample: Bool
    var body: some View {
        Section {
            QuestifyImageEntityCard(imageSource: isExample ? nil : source, title: "", fallbackTitle: title, minimumHeight: 180) {
                if isExample { Text("merchant.operations.syntheticArtwork") }
                else if QuestifyCardArtwork.safeURL(source) == nil { Text("merchant.operations.noImage") }
            }
            .listRowInsets(EdgeInsets())
        }
    }
}


/// Uses the existing draft identity, dirty-state guard and immutable review.
@MainActor
private struct MerchantTemplateParticipationPlanFields: View {
    @ObservedObject var model: MerchantOperationsViewModel
    private var template: MerchantNodeTemplate? {
        if case .template(let value) = model.coordinator.draft { return value }
        return nil
    }
    var body: some View {
        Section("merchant.participation.title") {
            Text("merchant.participation.localOnly").font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("merchant.participation.boundary")
            if let plan = template?.participationPlan {
                field("merchant.participation.duration", \.durationMinutes, "duration")
                field("merchant.participation.capacity", \.maximumParticipants, "capacity")
                Picker("merchant.participation.staffing", selection: Binding(get: {
                    template?.participationPlan?.staffing ?? .unspecified
                }, set: { value in update { $0.staffing = value } })) {
                    ForEach(MerchantTemplateParticipationPlan.Staffing.allCases, id: \.rawValue) { value in
                        Text(LocalizedStringKey(value.titleKey)).tag(value)
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("merchant.participation.staffing")
                if let blocker = plan.blocker {
                    Text(LocalizedStringKey(blocker)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("merchant.participation.blocker")
                }
                Button("merchant.participation.remove", role: .destructive) {
                    guard var value = template else { return }
                    value.participationPlan = nil; model.edit(.template(value))
                }.accessibilityIdentifier("merchant.participation.remove")
            } else {
                Button("merchant.participation.add") {
                    guard var value = template else { return }
                    value.participationPlan = .init(); model.edit(.template(value))
                }.accessibilityIdentifier("merchant.participation.add")
            }
        }
    }
    private func update(_ edit: (inout MerchantTemplateParticipationPlan) -> Void) {
        guard var value = template, var plan = value.participationPlan else { return }
        edit(&plan); value.participationPlan = plan; model.edit(.template(value))
    }
    private func field(_ title: LocalizedStringKey, _ path: WritableKeyPath<MerchantTemplateParticipationPlan, String>, _ id: String) -> some View {
        TextField(title, text: Binding(get: { template?.participationPlan?[keyPath: path] ?? "" }, set: { text in
            update { $0[keyPath: path] = text }
        })).keyboardType(.numberPad).accessibilityIdentifier("merchant.participation." + id)
    }
}

@MainActor
private struct MerchantTemplateParticipationPlanReview: View {
    let plan: MerchantTemplateParticipationPlan
    var body: some View {
        Section("merchant.participation.reviewTitle") {
            LabeledContent("merchant.participation.duration", value: plan.durationMinutes.trimmingCharacters(in: .whitespacesAndNewlines))
                .accessibilityIdentifier("merchant.participation.review.duration")
            LabeledContent("merchant.participation.capacity", value: plan.maximumParticipants.trimmingCharacters(in: .whitespacesAndNewlines))
                .accessibilityIdentifier("merchant.participation.review.capacity")
            LabeledContent("merchant.participation.staffing") { Text(LocalizedStringKey(plan.staffing.titleKey)) }
                .accessibilityIdentifier("merchant.participation.review.staffing")
            Text("merchant.participation.reviewBoundary").font(.footnote).foregroundStyle(.secondary)
        }
    }
}


@MainActor
private struct MerchantTemplateExitPlanFields: View {
    @ObservedObject var model: MerchantOperationsViewModel
    private var template: MerchantNodeTemplate? {
        if case .template(let value) = model.coordinator.draft { return value }
        return nil
    }
    var body: some View {
        Section("merchant.exitPlan.title") {
            Text("merchant.participation.localOnly").font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("merchant.exitPlan.boundary")
            if let plan = template?.exitPlan {
                field("merchant.exitPlan.offline", \.offlineAlternative, "offline")
                field("merchant.exitPlan.failureExit", \.failureExit, "failureExit")
                Text("merchant.exitPlan.instructionsHint").font(.footnote).foregroundStyle(.secondary)
                if let blocker = plan.blocker {
                    Text(LocalizedStringKey(blocker)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("merchant.exitPlan.blocker")
                }
                Button("merchant.exitPlan.remove", role: .destructive) {
                    guard var value = template else { return }
                    value.exitPlan = nil; model.edit(.template(value))
                }.accessibilityIdentifier("merchant.exitPlan.remove")
            } else {
                Button("merchant.exitPlan.add") {
                    guard var value = template else { return }
                    value.exitPlan = .init(); model.edit(.template(value))
                }.accessibilityIdentifier("merchant.exitPlan.add")
            }
        }
    }
    private func field(_ title: LocalizedStringKey, _ path: WritableKeyPath<MerchantTemplateExitPlan, String>, _ id: String) -> some View {
        TextField(title, text: Binding(get: { template?.exitPlan?[keyPath: path] ?? "" }, set: { text in
            guard var value = template, var plan = value.exitPlan else { return }
            plan[keyPath: path] = text; value.exitPlan = plan; model.edit(.template(value))
        }), axis: .vertical).accessibilityIdentifier("merchant.exitPlan." + id)
    }
}

@MainActor
private struct MerchantTemplateExitPlanReview: View {
    let plan: MerchantTemplateExitPlan
    var body: some View {
        Section("merchant.exitPlan.reviewTitle") {
            VStack(alignment: .leading, spacing: 6) {
                Text("merchant.exitPlan.offline").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: plan.offlineAlternative.trimmingCharacters(in: .whitespacesAndNewlines))
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("merchant.exitPlan.review.offline")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("merchant.exitPlan.failureExit").font(.caption).foregroundStyle(.secondary)
                Text(verbatim: plan.failureExit.trimmingCharacters(in: .whitespacesAndNewlines))
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("merchant.exitPlan.review.failureExit")
            }
            Text("merchant.exitPlan.reviewBoundary").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct MerchantTemplateRuleStepsFields: View {
    @ObservedObject var model: MerchantOperationsViewModel
    private var template: MerchantNodeTemplate? {
        if case .template(let value) = model.coordinator.draft { return value }; return nil
    }
    private func edit(_ action: (inout MerchantTemplateRuleSteps) -> Void) {
        guard var value = template else { return }
        action(&value.ruleSteps); model.edit(.template(value))
    }
    var body: some View {
        if let rules = template?.ruleSteps {
            Section("merchant.ruleSteps.title") {
                Text("merchant.ruleSteps.playerVisible").font(.footnote).foregroundStyle(.secondary)
                ForEach(rules.rows.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("merchant.ruleSteps.step \(index + 1)").font(.caption).foregroundStyle(.secondary)
                        TextField("merchant.ruleSteps.instruction", text: Binding(get: {
                            guard let rows = template?.ruleSteps.rows, rows.indices.contains(index) else { return "" }
                            return rows[index]
                        }, set: { text in edit { $0.update(at: index, text: text) } }))
                            .accessibilityLabel(Text("merchant.ruleSteps.step \(index + 1)"))
                            .accessibilityIdentifier("merchant.ruleSteps.field.\(index)")
                        Button(role: .destructive) { edit { $0.remove(at: index) } } label: {
                            Label("merchant.ruleSteps.remove", systemImage: "minus.circle")
                        }.buttonStyle(.borderless).disabled(rules.rows.count <= 1)
                            .accessibilityLabel(Text("merchant.ruleSteps.removeStep \(index + 1)"))
                            .accessibilityIdentifier("merchant.ruleSteps.remove.\(index)")
                    }
                }
                Button("merchant.ruleSteps.add", systemImage: "plus") { edit { $0.add() } }
                    .disabled(!rules.canAdd).accessibilityIdentifier("merchant.ruleSteps.add")
                Text("merchant.ruleSteps.limits").font(.footnote).foregroundStyle(.secondary)
                Text("merchant.ruleSteps.emptyHint").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct MerchantTemplateRuleStepsReview: View {
    let rules: MerchantTemplateRuleSteps
    var body: some View {
        Section("merchant.ruleSteps.title") {
            Text("merchant.ruleSteps.playerVisible").font(.footnote).foregroundStyle(.secondary)
            if rules.isClearing {
                Text("merchant.ruleSteps.clearReview").accessibilityIdentifier("merchant.ruleSteps.review.clear")
            } else if let text = rules.wireValue, !text.isEmpty {
                Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("merchant.ruleSteps.review.text")
            } else {
                Text("merchant.ruleSteps.emptyReview").accessibilityIdentifier("merchant.ruleSteps.review.empty")
            }
        }
    }
}

@MainActor
private struct MerchantTemplateHintsFields: View {
    @ObservedObject var model: MerchantOperationsViewModel
    private var template: MerchantNodeTemplate? {
        if case .template(let value) = model.coordinator.draft { return value }; return nil
    }
    private func edit(_ action: (inout MerchantTemplateHints) -> Void) {
        guard var value = template else { return }
        action(&value.hints); model.edit(.template(value))
    }
    var body: some View {
        if let value = template {
            Section("merchant.hints.title") {
                Toggle("merchant.hints.enabled", isOn: Binding(get: { template?.hints.enabled ?? false }, set: { enabled in
                    edit { $0.setEnabled(enabled) }
                })).disabled(!MerchantTemplateHints.supports(value.method) && !value.hints.enabled)
                    .accessibilityIdentifier("merchant.hints.enabled")
                Text("merchant.hints.scope").font(.footnote).foregroundStyle(.secondary)
                if !MerchantTemplateHints.supports(value.method) {
                    Text("merchant.hints.unsupported").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("merchant.hints.unsupported")
                }
                if value.hints.enabled {
                    ForEach(MerchantTemplateHints.Field.allCases) { field in
                        TextField(LocalizedStringKey(field.titleKey), text: Binding(get: { template?.hints.text(field) ?? "" }, set: { text in
                            edit { $0.update(field, text: text) }
                        }), axis: .vertical)
                            .disabled(!MerchantTemplateHints.supports(value.method))
                            .accessibilityIdentifier("merchant.hints.field.\(field.rawValue)")
                    }
                }
                Text("merchant.hints.clearHint").font(.footnote).foregroundStyle(.secondary)
            }
            if value.hints.enabled && MerchantTemplateHints.supports(value.method) {
                MerchantTemplateHintsPreview(hints: value.hints).id(model.coordinator.draftIdentity)
            }
        }
    }
}

private struct MerchantTemplateHintsPreview: View {
    let hints: MerchantTemplateHints
    @State private var revealed = 0
    var body: some View {
        Section("merchant.hints.previewTitle") {
            Text("merchant.hints.previewBoundary").font(.footnote).foregroundStyle(.secondary)
            ForEach(Array(hints.previewStages.prefix(revealed))) { field in
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(field.titleKey)).font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: hints.text(field)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("merchant.hints.preview.\(field.rawValue)")
                }
            }
            if hints.previewStages.isEmpty {
                Text("merchant.hints.previewEmpty")
            } else if revealed < hints.previewStages.count {
                Button(LocalizedStringKey(hints.previewStages[revealed] == .answerReveal ? "merchant.hints.revealAnswer" : "merchant.hints.revealNext")) {
                    revealed = min(revealed + 1, hints.previewStages.count)
                }.accessibilityIdentifier("merchant.hints.preview.next")
            }
            Button("merchant.hints.restart") { revealed = 0 }
                .disabled(revealed == 0).accessibilityIdentifier("merchant.hints.preview.restart")
        }.onChange(of: hints) { _, _ in revealed = 0 }
    }
}

private struct MerchantTemplateHintsReview: View {
    let hints: MerchantTemplateHints
    var body: some View {
        Section("merchant.hints.title") {
            Text("merchant.hints.reviewBoundary").font(.footnote).foregroundStyle(.secondary)
            ForEach(MerchantTemplateHints.Field.allCases) { field in
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(field.titleKey)).font(.caption).foregroundStyle(.secondary)
                    if hints.clearedFields.contains(field) {
                        Text("merchant.hints.clearReview").accessibilityIdentifier("merchant.hints.review.clear.\(field.rawValue)")
                    } else if let text = hints.fields[field.rawValue], !text.isEmpty {
                        Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("merchant.hints.review.\(field.rawValue)")
                    } else { Text("merchant.hints.empty") }
                }
            }
        }
    }
}

@MainActor
private struct MerchantTemplateStoryTimelineFields: View {
    @ObservedObject var model: MerchantOperationsViewModel
    private var template: MerchantNodeTemplate? {
        if case .template(let value) = model.coordinator.draft { return value }; return nil
    }
    private func edit(_ action: (inout MerchantTemplateStoryTimeline) -> Void) {
        guard var value = template else { return }
        action(&value.storyTimeline); model.edit(.template(value))
    }
    var body: some View {
        if let timeline = template?.storyTimeline {
            Section("merchant.storyTimeline.title") {
                Toggle("merchant.storyTimeline.enabled", isOn: Binding(get: { template?.storyTimeline.enabled ?? false }, set: { enabled in
                    edit { $0.setEnabled(enabled) }
                })).disabled(!timeline.isEditable).accessibilityIdentifier("merchant.storyTimeline.enabled")
                Text("merchant.storyTimeline.scope").font(.footnote).foregroundStyle(.secondary)
                if !timeline.isEditable {
                    Text("merchant.storyTimeline.opaque").accessibilityIdentifier("merchant.storyTimeline.opaque")
                } else if timeline.enabled {
                    ForEach(Array(timeline.beats.enumerated()), id: \.element.id) { index, beat in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("merchant.storyTimeline.beat \(index + 1)").font(.headline)
                            TextField("merchant.storyTimeline.body", text: Binding(get: {
                                template?.storyTimeline.beats.first(where: { $0.id == beat.id })?.text ?? ""
                            }, set: { text in edit { $0.update(beat.id, text: text) } }), axis: .vertical)
                                .accessibilityIdentifier("merchant.storyTimeline.body.\(beat.id)")
                            TextField("merchant.storyTimeline.tag", text: Binding(get: {
                                template?.storyTimeline.beats.first(where: { $0.id == beat.id })?.tag ?? ""
                            }, set: { tag in edit { $0.update(beat.id, tag: tag) } }))
                                .accessibilityIdentifier("merchant.storyTimeline.tag.\(beat.id)")
                            if beat.imageReferenceCount > 0 {
                                Text("merchant.storyTimeline.images \(beat.imageReferenceCount)").font(.footnote)
                            }
                            HStack {
                                Button("merchant.storyTimeline.up", systemImage: "arrow.up") { edit { $0.move(beat.id, offset: -1) } }
                                    .disabled(index == 0).accessibilityLabel(Text("merchant.storyTimeline.moveEarlier \(index + 1)"))
                                    .accessibilityIdentifier("merchant.storyTimeline.up.\(beat.id)")
                                Button("merchant.storyTimeline.down", systemImage: "arrow.down") { edit { $0.move(beat.id, offset: 1) } }
                                    .disabled(index == timeline.beats.count - 1).accessibilityLabel(Text("merchant.storyTimeline.moveLater \(index + 1)"))
                                    .accessibilityIdentifier("merchant.storyTimeline.down.\(beat.id)")
                                Button(role: .destructive) { edit { $0.remove(beat.id) } } label: {
                                    Label("merchant.storyTimeline.remove", systemImage: "minus.circle")
                                }.disabled(timeline.beats.count <= 1).accessibilityLabel(Text("merchant.storyTimeline.removeMoment \(index + 1)"))
                                    .accessibilityIdentifier("merchant.storyTimeline.remove.\(beat.id)")
                            }.buttonStyle(.borderless)
                        }
                    }
                    Button("merchant.storyTimeline.add", systemImage: "plus") { edit { $0.add() } }
                        .accessibilityIdentifier("merchant.storyTimeline.add")
                }
                Text("merchant.storyTimeline.clearHint").font(.footnote).foregroundStyle(.secondary)
            }
            if timeline.enabled && timeline.isEditable {
                Section("merchant.storyTimeline.preview") {
                    Text("merchant.storyTimeline.previewBoundary").font(.footnote).foregroundStyle(.secondary)
                    MerchantTemplateStoryTimelineContent(timeline: timeline, prefix: "merchant.storyTimeline.preview")
                }
            }
        }
    }
}

private struct MerchantTemplateStoryTimelineContent: View {
    let timeline: MerchantTemplateStoryTimeline
    let prefix: String
    var body: some View {
        if timeline.previewBeats.isEmpty { Text("merchant.storyTimeline.empty") }
        ForEach(Array(timeline.previewBeats.enumerated()), id: \.element.id) { index, beat in
            VStack(alignment: .leading, spacing: 6) {
                Text("merchant.storyTimeline.beat \(index + 1)").font(.caption).foregroundStyle(.secondary)
                if !beat.tag.isEmpty { Text(verbatim: beat.tag).font(.headline) }
                Text(verbatim: beat.text).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(prefix).body.\(index)")
                if beat.imageReferenceCount > 0 { Text("merchant.storyTimeline.images \(beat.imageReferenceCount)") }
            }
        }
        if timeline.projectionIsShortened {
            Text("merchant.storyTimeline.projectionHint").font(.footnote)
                .accessibilityIdentifier("\(prefix).projection")
        }
    }
}

private struct MerchantTemplateStoryTimelineReview: View {
    let timeline: MerchantTemplateStoryTimeline
    var body: some View {
        Section("merchant.storyTimeline.title") {
            if !timeline.isEditable { Text("merchant.storyTimeline.opaque") }
            else {
                if timeline.clearsSource {
                    Text("merchant.storyTimeline.clearReview").accessibilityIdentifier("merchant.storyTimeline.review.clear")
                }
                MerchantTemplateStoryTimelineContent(timeline: timeline, prefix: "merchant.storyTimeline.review")
                if timeline.removedImageCount > 0 {
                    Text("merchant.storyTimeline.removedImages \(timeline.removedImageCount)")
                        .accessibilityIdentifier("merchant.storyTimeline.review.removedImages")
                }
                if !timeline.removedBeats.isEmpty {
                    Text("merchant.storyTimeline.removedBeats").font(.headline)
                    ForEach(timeline.removedBeats) { beat in
                        VStack(alignment: .leading, spacing: 4) {
                            if !beat.tag.isEmpty { Text(verbatim: beat.tag).font(.caption) }
                            Text(verbatim: beat.text).fixedSize(horizontal: false, vertical: true)
                            if beat.imageReferenceCount > 0 { Text("merchant.storyTimeline.images \(beat.imageReferenceCount)") }
                        }.accessibilityIdentifier("merchant.storyTimeline.review.removed.\(beat.id)")
                    }
                }
            }
        }
    }
}
