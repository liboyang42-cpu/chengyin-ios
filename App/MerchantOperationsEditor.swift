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
            MerchantStoreHoursEditor(model: model)
            mediaSection("merchant.operations.logo", field: .logo)
        case .decor(let value):
            MerchantOperationsMediaPreview(source: value.coverImage, title: "merchant.operations.cover", isExample: isExample)
            Section("merchant.operations.decor") {
                decorField("merchant.operations.slogan", \.slogan, "slogan")
                decorField("merchant.operations.cityRole", \.cityRole, "cityRole")
                Text("merchant.operations.decorPreserved").font(.footnote).foregroundStyle(.secondary)
                if let category = value.categoryID { LabeledContent("merchant.operations.category", value: String(category)) }
                if let type = value.featuredType, let id = value.featuredID { LabeledContent("merchant.operations.featured", value: "\(type) / \(id)") }
            }
            Section("merchant.operations.tags") {
                TextField("merchant.operations.tags", text: Binding(get: { currentDecor?.tags.joined(separator: ";") ?? "" }, set: { raw in
                    guard var value = currentDecor else { return }; value.tags = raw.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }; model.edit(.decor(value))
                }), axis: .vertical).accessibilityIdentifier("merchant.operations.field.tags")
                Text("merchant.operations.tagsHint").font(.footnote).foregroundStyle(.secondary)
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
            MerchantOperationsMediaPreview(source: value.avatar, title: "merchant.operations.avatar", isExample: isExample)
            Section("merchant.operations.character") {
                Text(LocalizedStringKey(value.reviewKey)).accessibilityIdentifier("merchant.operations.character.review")
                characterField("merchant.operations.name", \.name, "characterName")
                characterField("merchant.operations.greeting", \.greeting, "greeting")
                characterField("merchant.operations.persona", \.persona, "persona")
                characterField("merchant.operations.knowledge", \.knowledge, "knowledge")
                Text("merchant.operations.characterReviewHint").font(.footnote).foregroundStyle(.secondary)
            }
            mediaSection("merchant.operations.avatar", field: .avatar)
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
        if let context = imageContext?(field) {
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
                    Text(LocalizedStringKey(isExample ? "merchant.operations.confirmExampleBody" : (model.coordinator.reader.canSave ? "merchant.operations.confirmLiveHint" : "merchant.operations.liveDisabled")))
                    Text("merchant.operations.reviewNoApproval").font(.footnote).foregroundStyle(.secondary)
                    Text(LocalizedStringKey(confirmation.draft.destination.titleKey)).font(.headline)
                }
                Section("merchant.operations.frozenDraft") {
                    ForEach(confirmation.draft.reviewLines) { line in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey(line.key)).font(.caption).foregroundStyle(.secondary)
                            if line.key == "merchant.operations.chargeType", ["0", "1"].contains(line.value) {
                                Text(LocalizedStringKey(line.value == "0" ? "merchant.operations.charge.free" : "merchant.operations.charge.paid"))
                            } else { Text(verbatim: line.value.isEmpty ? "—" : line.value).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                    if case .template(let value) = confirmation.draft, let method = value.method { Text(LocalizedStringKey(method.titleKey)) }
                }
                Section {
                    Button(LocalizedStringKey(isExample ? "merchant.operations.confirmExample" : (model.coordinator.reader.canSave ? "merchant.operations.confirmLive" : "merchant.operations.liveDisabled"))) {
                        Task { await model.confirm(confirmation) }
                    }.disabled(!model.coordinator.reader.canSave || model.coordinator.isBusy).accessibilityIdentifier("merchant.operations.confirm")
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
