import SwiftUI

@MainActor struct ProjectEditChapterView: View {
    @ObservedObject var model: ProjectEditModel
    let chapterID: String
    var starterLease: ProjectEditStarterController.Destination? = nil
    var chapterOverride: Binding<ProjectEditChapter>? = nil
    var chapterIsCurrent: (() -> Bool)? = nil
    let mediaScope: ProjectStoryMediaChapterScope?
    private let mediaHost: ProjectStoryMediaChapterHost
    var pendingGap: ((String?) -> AnyView)? = nil
    var pendingMaterialName: String? = nil
    let initialIssueAnchor: String?
    @StateObject private var storyImages: ProjectStoryImagePresentation
    @StateObject private var storyAudios: ProjectStoryAudioPresentation
    @StateObject private var storyTemplates: ProjectStoryTemplatePresentation
    @StateObject private var pendingNodeRemoval: ProjectPendingNodeRemovalController
    @StateObject private var audioPreview: ProjectEditorAudioPreviewController
    @Environment(\.locale) private var storyImageLocale
    @Environment(\.scenePhase) private var audioPreviewScenePhase
    init(model: ProjectEditModel, chapterID: String, starterLease: ProjectEditStarterController.Destination? = nil,
         chapterOverride: Binding<ProjectEditChapter>? = nil, chapterIsCurrent: (() -> Bool)? = nil,
         mediaScope: ProjectStoryMediaChapterScope? = nil,
         pendingGap: ((String?) -> AnyView)? = nil, pendingMaterialName: String? = nil, initialIssueAnchor: String? = nil) {
        self.initialIssueAnchor = initialIssueAnchor
        self.model = model; self.chapterID = chapterID; self.starterLease = starterLease; self.chapterOverride = chapterOverride
        self.chapterIsCurrent = chapterIsCurrent; self.mediaScope = mediaScope; self.pendingGap = pendingGap; self.pendingMaterialName = pendingMaterialName
        let host: ProjectStoryMediaChapterHost = mediaScope.map(ProjectStoryMediaChapterHost.pending) ?? (chapterOverride == nil ? .ordinary : .unavailable)
        mediaHost = host
        _storyImages = StateObject(wrappedValue: .init(editor: model, host: host))
        _storyAudios = StateObject(wrappedValue: .init(editor: model, host: host))
        _storyTemplates = StateObject(wrappedValue: .init(editor: model, host: host))
        _pendingNodeRemoval = StateObject(wrappedValue: .init(model: model, chapterID: chapterID))
        _audioPreview = StateObject(wrappedValue: .init(editor: model, chapterID: chapterID))
    }
    private func imageText(_ key: StaticString, _ fallback: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(key, defaultValue: fallback, locale: storyImageLocale))
    }
    private var chapter: Binding<ProjectEditChapter> {
        if let actual = mediaScope?.chapter(editor: model, chapterID: chapterID) { return actual }
        if let chapterOverride { return chapterOverride }
        if let starterLease { return model.starterChapter(starterLease) }
        return model.chapter(chapterID)
    }
    private var usesRealMediaChapter: Bool {
        mediaHost.allows(editor: model, chapterID: chapterID)
    }
    private var exists: Bool {
        if let chapterIsCurrent { return chapterIsCurrent() }
        if let starterLease { return model.isCurrentStarterChapter(starterLease) }
        return model.draft.chapters.contains { $0.id == chapterID }
    }
    private var usesPendingNodeRemoval: Bool {
        model.draft.product == .freeExplore && chapterOverride == nil && mediaScope == nil &&
        starterLease == nil && chapter.wrappedValue.blocks == nil
    }
    var body: some View {
        let handlesPendingRemoval = usesPendingNodeRemoval
        let removalCapture = handlesPendingRemoval ? pendingNodeRemoval.capture() : nil
        let imagePresentation = storyImages.presentation
        let audioPresentation = storyAudios.presentation
        let templateOpening = storyTemplates.opening
        let templateInsertion = usesRealMediaChapter ? storyTemplates.capture(chapterID: chapterID, before: nil) : nil
        let audioInsertion = usesRealMediaChapter ? storyAudios.captureInsertion(chapterID: chapterID, before: nil) : nil
        let imageOpening = usesRealMediaChapter ? storyImages.capture(chapterID: chapterID) : nil
        Form {
            if exists {
                if let pendingMaterialName { Section { Text("projectPending.storyPlacementScope"); Text(verbatim: pendingMaterialName) } }
                Section("projectEdit.chapterDetails") {
                    TextField("projectEdit.chapterName", text: chapter.name).accessibilityIdentifier("projectEdit.chapterName")
                    if chapter.wrappedValue.blocks == nil {
                        TextField("projectEdit.story", text: chapter.description, axis: .vertical).lineLimit(4...12)
                            .accessibilityIdentifier("projectEdit.story").id("project-issue-anchor-story")
                        if ProjectEditStarterPolicy.usesStoryEditor(product: model.draft.product, chapter: chapter.wrappedValue) || ProjectEditStoryContract.usesV2(model.draft) {
                            Button("projectEdit.enableStoryFlow") {
                                var c = chapter.wrappedValue
                                c.blocks = [.init(kind: .text, content: c.description)] + c.nodes.map { .init(kind: .node, nodeID: $0.id) }
                                chapter.wrappedValue = c
                            }.buttonStyle(.borderless).accessibilityIdentifier("projectEdit.enableStoryFlow")
                        }
                    }
                }
                ProjectEditChapterStorySettings(chapter: chapter, isFirst: model.draft.chapters.first?.id == chapterID, model: chapterOverride == nil && mediaScope == nil && starterLease == nil ? model : nil).id("project-issue-anchor-chapterSettings")
                if model.draft.product == .city && chapterOverride == nil && mediaScope == nil && starterLease == nil &&
                    model.draft.chapters.first?.id.utf8.elementsEqual(chapterID.utf8) == true {
                    ProjectInitialStateEntry(model: model, chapterID: chapterID).id(Data(chapterID.utf8))
                }
                if chapterOverride == nil && mediaScope == nil && starterLease == nil {
                    ProjectChapterAudioField(model: model, chapterID: chapterID, preview: audioPreview).id(Data(chapterID.utf8))
                }
                // The mini chapter palette is city-only. Pending new chapters keep
                // their temporary binding until the existing placement flow commits.
                if model.draft.product == .city && chapterOverride == nil {
                    ProjectChapterAtmosphereFields(model: model, chapterID: chapterID)
                } else if chapterOverride == nil && !ProjectChapterAtmosphere.canSubmit(chapter.wrappedValue) {
                    Section { ProjectChapterAtmosphereUnsupportedNotice(chapter: chapter.wrappedValue, supportsSelection: false) }
                }
                if let blocks = chapter.wrappedValue.blocks {
                    Section("projectEdit.storyFlow") {
                        ForEach(blocks) { block in
                            if let pendingGap { pendingGap(block.id) }
                            if usesRealMediaChapter { mediaGap(before: block.id) }
                            switch block.kind {
                            case .text:
                                TextField("projectEdit.story", text: blockBinding(block.id).content, axis: .vertical).lineLimit(3...12)
                                    .accessibilityIdentifier("projectEdit.block." + block.id)
                                NavigationLink("projectEdit.rich.editDetails") { ProjectEditRichBlockEditor(model: model, block: blockBinding(block.id), chapterID: chapterID, chapterOverride: chapter) }
                            case .node:
                                NavigationLink { ProjectEditRichBlockEditor(model: model, block: blockBinding(block.id), chapterID: chapterID, chapterOverride: chapter) } label: {
                                    Label { Text(verbatim: chapter.wrappedValue.nodes.first { $0.id == block.nodeID }?.name ?? "") } icon: { Image(systemName: "mappin.circle") }
                                }
                            case .image, .audio:
                                ProjectEditReferenceField(title: LocalizedStringKey(block.kind == .image ? "projectEdit.imageReference" : "projectEdit.audioReference"), value: blockBinding(block.id).url, identifier: "projectEdit.block." + block.id, showsDeferredHint: false)
                                if block.kind == .image {
                                    let replacement = usesRealMediaChapter ? storyImages.capture(chapterID: chapterID, replacing: block.id) : nil
                                    Button(imageText("projectStoryImage.replace", "Choose a replacement image")) {
                                        guard let replacement, exists else { return }; openImage(replacement)
                                    }.buttonStyle(.borderless).disabled(replacement == nil).accessibilityIdentifier("projectStoryImage.replace." + block.id)
                                }
                                if block.kind == .audio {
                                    if chapterOverride == nil && mediaScope == nil && starterLease == nil && !block.url.isEmpty {
                                        ProjectEditorAudioPreviewEntry(controller: audioPreview, destination: .storyBlock(Data(block.id.utf8)))
                                    }
                                    let opening = usesRealMediaChapter ? storyAudios.capture(chapterID: chapterID, blockID: block.id) : nil
                                    let local = usesRealMediaChapter ? storyAudios.captureBlock(chapterID: chapterID, blockID: block.id) : nil
                                    if let name = block.localAudio, name.reference.utf8.elementsEqual(block.url.utf8) {
                                        Text(verbatim: name.filename).accessibilityIdentifier("projectStoryAudio.blockName." + block.id)
                                    }
                                    if block.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(imageText("projectStoryAudio.emptyBlock", "This empty audio block stays in the local draft. It is omitted from the submitted story until an audio reference is applied."))
                                            .font(.footnote).accessibilityIdentifier("projectStoryAudio.empty." + block.id)
                                    }
                                    Button(imageText("projectStoryAudio.open", "Choose or replace an audio file")) {
                                        guard let opening, exists, storyImages.presentation == nil, storyAudios.presentation == nil, storyTemplates.opening == nil else { return }
                                        audioPreview.retire(); storyAudios.open(opening)
                                    }.buttonStyle(.borderless).disabled(opening == nil).accessibilityIdentifier("projectStoryAudio.open." + block.id)
                                    Button(imageText("projectStoryAudio.remove", "Remove this audio block"), role: .destructive) {
                                        guard let local, exists, storyImages.presentation == nil, storyAudios.presentation == nil, storyTemplates.opening == nil else { return }
                                        audioPreview.retire(); storyAudios.remove(local)
                                    }.buttonStyle(.borderless).disabled(local == nil).accessibilityIdentifier("projectStoryAudio.remove." + block.id)
                                    if opening == nil && audioPresentation == nil {
                                        Text(imageText("projectStoryAudio.unavailable", "Audio upload is not configured for this account or this chapter has not yet been saved in the editor. The existing block and reference remain editable locally."))
                                            .font(.footnote).accessibilityIdentifier("projectStoryAudio.unavailable." + block.id)
                                    }
                                }
                            case .dream, .mood, .thought, .voice, .odd, .reveal:
                                NavigationLink { ProjectEditRichBlockEditor(model: model, block: blockBinding(block.id), chapterID: chapterID, chapterOverride: chapter) } label: { ProjectEditRichBlockSummary(block: block, nodes: chapter.wrappedValue.nodes) }
                                    .accessibilityIdentifier("projectEdit.rich.block." + block.id)
                            }
                        }.onMove { from, to in
                            var c = chapter.wrappedValue; c.blocks?.move(fromOffsets: from, toOffset: to); chapter.wrappedValue = c
                        }.onDelete { offsets in
                            var c = chapter.wrappedValue
                            let deleted = offsets.compactMap { c.blocks?.indices.contains($0) == true ? c.blocks?[$0] : nil }
                            let removedIDs = Set(deleted.map(\.id))
                            for block in deleted where block.kind == .node { c.removeNode(id: block.nodeID) }
                            c.blocks?.removeAll { removedIDs.contains($0.id) }; chapter.wrappedValue = c
                        }
                        if let pendingGap { pendingGap(nil) }
                        HStack {
                            Button("projectEdit.addText") { appendBlock(.text) }.disabled(blocks.count >= 200).accessibilityIdentifier("projectStarter.addText")
                            Button("projectEdit.addImage") {
                                guard let imageOpening, exists else { return }; openImage(imageOpening)
                            }.disabled(imageOpening == nil).accessibilityIdentifier("projectStoryImage.add")
                            Button("projectEdit.addAudio") {
                                guard exists, storyImages.presentation == nil, storyAudios.presentation == nil, storyTemplates.opening == nil else { return }
                                if !usesRealMediaChapter { appendBlock(.audio) }
                                else if let audioInsertion { _ = storyAudios.insertEmpty(chapterID: chapterID, captured: audioInsertion) }
                            }.disabled(blocks.count >= 200).accessibilityIdentifier("projectStoryAudio.add")
                        }.buttonStyle(.bordered)
                        if imageOpening == nil && imagePresentation == nil {
                            Text(imageText("projectStoryImage.unavailable", "Image upload is not configured for this account or this chapter has not yet been saved in the editor. Existing references are preserved."))
                                .font(.footnote).accessibilityIdentifier("projectStoryImage.unavailable")
                        }
                        Button("projectStoryTemplate.add") {
                            guard let templateInsertion, exists, storyImages.presentation == nil, storyAudios.presentation == nil else { return }
                            _ = storyTemplates.open(templateInsertion)
                        }.disabled(templateInsertion == nil).accessibilityIdentifier("projectStoryTemplate.add")
                        if storyTemplates.state == .saveRequired {
                            Text("projectStoryTemplate.saveRequired").font(.footnote)
                                .accessibilityIdentifier("projectStoryTemplate.saveRequired")
                        }
                        if templateInsertion == nil && templateOpening == nil {
                            Text("projectStoryTemplate.unavailable").font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("projectStoryTemplate.unavailable")
                        }
                        Menu("projectEdit.rich.addBlock") {
                            ForEach(ProjectEditRichStoryContract.richKinds, id: \.self) { kind in
                                Button(LocalizedStringKey("projectEdit.rich.kind." + kind.rawValue)) { appendBlock(kind) }
                            }
                        }.disabled(blocks.count >= 200).accessibilityIdentifier("projectEdit.rich.addBlock")
                        Button("projectEdit.rich.addNarrative") {
                            guard let node = chapter.wrappedValue.nodes.last else { return }
                            var block = ProjectEditBlock(kind: .text); block.selectBeat(.outcome); block.setField("field", .string("line")); block.nodeID = node.id
                            var c = chapter.wrappedValue; c.blocks?.append(block); chapter.wrappedValue = c
                        }.disabled(blocks.count >= 200 || chapter.wrappedValue.nodes.isEmpty)
                        Text("projectEdit.storyFlowHint").font(.caption).foregroundStyle(.secondary)
                    }.id("project-issue-anchor-storyFlow")
                }
                if handlesPendingRemoval {
                    Section { ProjectPendingNodeRemovalStatus(controller: pendingNodeRemoval) }
                }
                Section("projectEdit.nodes") {
                    ForEach(chapter.wrappedValue.nodes) { node in
                        NavigationLink { ProjectEditNodeView(model: model, chapterID: chapterID, nodeID: node.id, starterLease: starterLease, chapterOverride: chapter,
                            allowsGameplayRemoval: chapterOverride == nil && mediaScope == nil && starterLease == nil) } label: {
                            Label { ProjectEditName(value: node.name, fallback: "projectEdit.untitledNode") } icon: { Image(systemName: "mappin.circle") }
                        }.accessibilityIdentifier("projectEdit.node." + node.id)
                            .deleteDisabled(handlesPendingRemoval && removalCapture == nil)
                    }.onDelete { offsets in
                        if handlesPendingRemoval {
                            pendingNodeRemoval.open(offsets: offsets, captured: removalCapture)
                            return
                        }
                        var c = chapter.wrappedValue; let ids = offsets.map { c.nodes[$0].id }
                        for id in ids { c.removeNode(id: id) }; chapter.wrappedValue = c
                    }.onMove { from, to in
                        guard chapter.wrappedValue.blocks == nil else { return }
                        var c = chapter.wrappedValue; c.nodes.move(fromOffsets: from, toOffset: to); chapter.wrappedValue = c
                    }
                    Button("projectEdit.addNode", systemImage: "plus", action: addNode).disabled(pendingGap != nil || chapter.wrappedValue.preserved["opening"] == .bool(true) || chapter.wrappedValue.preserved["ending"]?.object != nil || (model.draft.product == .city && !chapter.wrappedValue.hasRealStory) || (chapter.wrappedValue.blocks?.count ?? 0) >= 200)
                        .accessibilityIdentifier("projectEdit.addNode")
                    if model.draft.product == .city && !chapter.wrappedValue.hasRealStory { Text("projectEdit.validation.story").foregroundStyle(.secondary) }
                }.id("project-issue-anchor-nodes")
                if let key = model.coordinator.messageKey {
                    Section { Text(LocalizedStringKey(key)).accessibilityIdentifier("projectStoryAudio.localStatus") }
                }
                Section { Text("projectEdit.chapterCarryOver").foregroundStyle(.secondary) }
            } else { Text("projectEdit.signIn") }
        }.modifier(ProjectEditIssueInitialScroll(anchor: initialIssueAnchor)).disabled(!model.fullEdit)
            .appNavigationTitle(key: starterLease == nil && chapterOverride == nil ? "projectEdit.chapterDetails" : "projectEdit.storyFlow").navigationBarTitleDisplayMode(.inline)
            .toolbar { EditButton().disabled(!model.fullEdit) }
            .scrollDismissesKeyboard(.interactively)
            .sheet(item: storyImages.binding(imagePresentation)) { original in
                ProjectStoryImageAuthorView(original: original, picker: model.storyImagePicker?(), apply: { storyImages.apply($0) }, close: { storyImages.close(original) })
            }
            .sheet(item: storyAudios.binding(audioPresentation)) { original in
                ProjectStoryAudioAuthorView(original: original, picker: model.storyAudioPicker?(), apply: { storyAudios.apply($0) }, close: { storyAudios.close(original) })
            }
            .sheet(item: storyTemplates.binding(templateOpening)) { original in
                ProjectStoryTemplateView(controller: storyTemplates, original: original)
            }
            .modifier(ProjectPendingNodeRemovalPresentation(controller: pendingNodeRemoval))
            .onChange(of: model.draftMutationRevision) { _, _ in pendingNodeRemoval.synchronize(); audioPreview.synchronize() }
            .onChange(of: model.editorIncarnation) { _, _ in pendingNodeRemoval.retire(); audioPreview.retire() }
            .onChange(of: model.coordinator.session) { _, _ in audioPreview.retire() }
            .onChange(of: model.canEdit) { _, allowed in if !allowed { audioPreview.retire() } }
            .onChange(of: audioPreviewScenePhase) { _, next in if next != .active { audioPreview.retire() } }
            .onDisappear {
                pendingNodeRemoval.retire(); audioPreview.retire()
                if let templateOpening { storyTemplates.close(templateOpening) }
                if let imagePresentation { storyImages.close(imagePresentation) }
                if let audioPresentation { storyAudios.close(audioPresentation) }
            }
    }
    @ViewBuilder private func mediaGap(before blockID: String) -> some View {
        let image = storyImages.capture(chapterID: chapterID, insertingBefore: blockID)
        let audio = storyAudios.captureInsertion(chapterID: chapterID, before: blockID)
        let template = storyTemplates.capture(chapterID: chapterID, before: blockID)
        Menu(imageText("projectStoryMedia.insertBefore", "Insert before this block")) {
            Button("projectEdit.addImage") {
                guard let image, exists else { return }; openImage(image)
            }.disabled(image == nil).accessibilityIdentifier("projectStoryImage.insertBefore." + blockID)
            Button("projectEdit.addAudio") {
                guard let audio, exists, storyImages.presentation == nil, storyAudios.presentation == nil, storyTemplates.opening == nil else { return }
                _ = storyAudios.insertEmpty(chapterID: chapterID, captured: audio)
            }.disabled(audio == nil).accessibilityIdentifier("projectStoryAudio.insertBefore." + blockID)
            Button("projectStoryTemplate.add") {
                guard let template, exists, storyImages.presentation == nil, storyAudios.presentation == nil else { return }
                _ = storyTemplates.open(template)
            }.disabled(template == nil).accessibilityIdentifier("projectStoryTemplate.insertBefore." + blockID)
        }.disabled(!model.fullEdit || (image == nil && audio == nil && template == nil))
            .accessibilityIdentifier("projectStoryMedia.gap." + blockID)
    }
    private func openImage(_ opening: ProjectStoryImagePresentation.Opening) {
        guard exists, storyImages.presentation == nil, storyAudios.presentation == nil, storyTemplates.opening == nil else { return }
        storyImages.open(opening)
    }
    /// The actual button action rechecks current chapter state; disabled rendering is not a write guard.
    func addNode() {
        guard exists, model.fullEdit, pendingGap == nil else { return }
        var current = chapter.wrappedValue
        do { try current.addNode(product: model.draft.product); chapter.wrappedValue = current }
        catch { /* Existing inline story/role state explains why the action cannot proceed. */ }
    }
    private func blockBinding(_ id: String) -> Binding<ProjectEditBlock> {
        Binding(get: { chapter.wrappedValue.blocks?.first { $0.id == id } ?? .init(kind: .text) }, set: { value in
            var c = chapter.wrappedValue
            guard let index = c.blocks?.firstIndex(where: { $0.id == id }) else { return }
            c.blocks?[index] = value; chapter.wrappedValue = c
        })
    }
    private func appendBlock(_ kind: ProjectEditBlock.Kind) {
        var c = chapter.wrappedValue; guard let count = c.blocks?.count, count < 200 else { return }
        c.blocks?.append(ProjectEditRichStoryContract.defaultBlock(kind)); chapter.wrappedValue = c
    }
}

@MainActor struct ProjectEditNodeView: View {
    @ObservedObject var model: ProjectEditModel
    let chapterID: String
    let nodeID: String
    var starterLease: ProjectEditStarterController.Destination? = nil
    var chapterOverride: Binding<ProjectEditChapter>? = nil
    var initialIssueAnchor: String? = nil
    var allowsGameplayRemoval: Bool? = nil
    private var targetChapter: Binding<ProjectEditChapter> { chapterOverride ?? starterLease.map { model.starterChapter($0) } ?? model.chapter(chapterID) }
    private var node: Binding<ProjectEditNode> {
        Binding(get: { targetChapter.wrappedValue.nodes.first { $0.id == nodeID } ?? .init() }, set: { value in
            var c = targetChapter.wrappedValue
            guard let i = c.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            c.nodes[i] = value; targetChapter.wrappedValue = c
        })
    }
    var body: some View {
        let lease = model.currentReviewLease()
        let exists = targetChapter.wrappedValue.nodes.contains { $0.id == nodeID }
        Form {
            ProjectEditNodeFields(node: node)
                .descriptionEditing(.init(model: model, sourceID: "saved:\(chapterID):\(nodeID)",
                    isCurrent: { model.fullEdit && targetChapter.wrappedValue.nodes.contains { $0.id == nodeID } }))
                .merchantDraftSelection(.init(model: model, node: node,
                sourceID: "saved:\(chapterID):\(nodeID)", nodeRevision: { model.draftMutationRevision },
                isCurrent: { model.fullEdit && targetChapter.wrappedValue.nodes.contains { $0.id == nodeID } }))
            if (allowsGameplayRemoval ?? (chapterOverride == nil && starterLease == nil)) && model.draft.owner == .personal {
                ProjectNodeTemplateSelectionField(model: model, chapterID: chapterID, nodeID: nodeID)
                    .id([Data(chapterID.utf8), Data(nodeID.utf8)])
                ProjectNodeTemplateCreationField(model: model, chapterID: chapterID, nodeID: nodeID)
                    .id([Data(chapterID.utf8), Data(nodeID.utf8)])
            }
            if (allowsGameplayRemoval ?? (chapterOverride == nil && starterLease == nil)) && (node.wrappedValue.templateID ?? 0) > 0 {
                ProjectNodeGameplayRemovalField(model: model, chapterID: chapterID, nodeID: nodeID)
                    .id([Data(chapterID.utf8), Data(nodeID.utf8)])
            }
            ProjectNodeNarrativeEntry(model: model, chapterID: chapterID, nodeID: nodeID)
            if let key = model.coordinator.messageKey { Section { Text(LocalizedStringKey(key)).accessibilityIdentifier("projectPrepared.nodeSaveStatus") } }
        }.modifier(ProjectEditIssueInitialScroll(anchor: initialIssueAnchor)).disabled(!model.fullEdit).appNavigationTitle("projectEdit.nodeDetails")
            .navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("projectEdit.saveLocal") {
                    guard let lease, model.currentReviewLease() == lease, model.fullEdit,
                          targetChapter.wrappedValue.nodes.contains(where: { $0.id == nodeID }) else { return }
                    model.saveLocal()
                }.disabled(!model.fullEdit || !exists).accessibilityIdentifier("projectPrepared.saveNodeDraft")
            } }
    }
}

/// The existing node fields are shared by saved nodes and a temporary starter candidate.
@MainActor struct ProjectEditNodeFields: View {
    @Binding var node: ProjectEditNode
    var merchantDraftContext: ProjectMerchantDraftContext? = nil
    var descriptionContext: ProjectEditNodeDescriptionContext? = nil
    @Environment(\.locale) private var merchantDraftLocale
    func descriptionEditing(_ context: ProjectEditNodeDescriptionContext) -> Self {
        var result = self; result.descriptionContext = context; return result
    }
    func merchantDraftSelection(_ context: ProjectMerchantDraftContext) -> Self {
        var result = self; result.merchantDraftContext = context; return result
    }
    var body: some View {
        Group {
            Section("projectEdit.nodeDetails") {
                TextField("projectEdit.nodeName", text: $node.name).accessibilityIdentifier("projectEdit.nodeName").id("project-issue-anchor-nodeName")
                if let descriptionContext {
                    let descriptionSource = ProjectEditNodeDescriptionSource(node: $node, context: descriptionContext)
                    ProjectEditNodeDescriptionField(source: descriptionSource).id(descriptionSource.target)
                } else {
                    // Unscoped standalone forms keep their original Binding lifetime/semantics.
                    TextField("projectEdit.description", text: $node.description, axis: .vertical).lineLimit(3...8)
                        .accessibilityIdentifier("projectEdit.nodeDescription")
                }
                TextField("projectEdit.address", text: $node.address).accessibilityIdentifier("projectEdit.address")
                TextField("projectEdit.longitude", text: $node.longitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("projectEdit.longitude").id("project-issue-anchor-coordinates")
                TextField("projectEdit.latitude", text: $node.latitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("projectEdit.latitude")
                Text("projectEdit.coordinatesHint").font(.caption).foregroundStyle(.secondary)
                Stepper(value: $node.nodeTime, in: 0...Int.max) {
                    LabeledContent("projectEdit.nodeMinutes", value: String(node.nodeTime))
                }.id("project-issue-anchor-nodeTime")
                ProjectEditReferenceField(title: "projectEdit.nodeImages", value: $node.imgUrl, identifier: "projectEdit.nodeImages")
            }
            Section("projectEdit.gameplay") {
                if let id = node.templateID {
                    LabeledContent("projectEdit.templateID", value: String(id))
                }
                if let merchantDraftContext {
                    ProjectMerchantDraftField(context: merchantDraftContext).id(merchantDraftContext.id)
                    Text(ProjectMerchantDraftCopy.value(.otherGameplay, locale: merchantDraftLocale)).foregroundStyle(.secondary)
                } else { Text("projectEdit.gameplayDeferred").foregroundStyle(.secondary) }
            }.id("project-issue-anchor-gameplay")
        }
    }
}

@MainActor struct ProjectEditTicketView: View {
    @ObservedObject var model: ProjectEditModel
    let ticketID: String
    var initialIssueAnchor: String? = nil
    private var ticket: Binding<ProjectEditTicket> { model.ticket(ticketID) }
    var body: some View {
        Form {
            Section("projectEdit.ticketDetails") {
                TextField("projectEdit.ticketName", text: ticket.name).accessibilityIdentifier("projectEdit.ticketName").id("project-issue-anchor-ticketName")
                TextField("projectEdit.ticketPrice", text: ticket.price).keyboardType(.decimalPad).accessibilityIdentifier("projectEdit.ticketPrice").id("project-issue-anchor-price")
                Text("projectEdit.priceHint").font(.caption).foregroundStyle(.secondary)
                TextField("projectEdit.totalStock", text: ticket.totalStock).keyboardType(.numberPad).accessibilityIdentifier("projectEdit.totalStock").id("project-issue-anchor-stock")
                TextField("projectEdit.teamSize", text: ticket.teamSize).keyboardType(.numberPad).id("project-issue-anchor-team")
                TextField("projectEdit.description", text: ticket.description, axis: .vertical).lineLimit(3...8)
            }
            Section("projectEdit.saleSchedule") {
                ProjectEditDateField(title: "projectEdit.saleStart", value: ticket.saleStartTime, identifier: "projectEdit.saleStart").dateEditing(.init(model: model, field: .saleStart(ticketID)))
                    .disabled(!ticket.wrappedValue.canEditSaleTime(end: false))
                ProjectEditDateField(title: "projectEdit.saleEnd", value: ticket.saleEndTime, identifier: "projectEdit.saleEnd").dateEditing(.init(model: model, field: .saleEnd(ticketID)))
                    .disabled(!ticket.wrappedValue.canEditSaleTime(end: true))
                Text("projectEdit.saleStoredOnly").font(.caption).foregroundStyle(.secondary)
                if !ticket.wrappedValue.canEditSaleTime(end: false) || !ticket.wrappedValue.canEditSaleTime(end: true) {
                    Text("projectEdit.saleLegacy").font(.caption).foregroundStyle(.secondary)
                }
            }.id("project-issue-anchor-ticketSale")
            Section("projectEdit.ticketSchedule") {
                if model.draft.product == .freeExplore {
                    Toggle("projectEdit.syncThemeDates", isOn: model.ticketDateSync(ticketID))
                        .disabled(!ticket.wrappedValue.canEditThemeDateSync)
                        .accessibilityIdentifier("projectEdit.syncThemeDates")
                    Text("projectEdit.syncThemeDatesHint").font(.caption).foregroundStyle(.secondary)
                    if !ticket.wrappedValue.canEditThemeDateSync { Text("projectEdit.syncThemeDatesLegacy").font(.caption).foregroundStyle(.secondary) }
                }
                if model.draft.product == .freeExplore && ticket.wrappedValue.syncsWithThemeDates {
                    let schedule = ticket.wrappedValue.schedule(in: model.draft)
                    LabeledContent("projectEdit.ticketStart", value: schedule.start).accessibilityIdentifier("projectEdit.ticketStart")
                    LabeledContent("projectEdit.ticketEnd", value: schedule.end).accessibilityIdentifier("projectEdit.ticketEnd")
                } else {
                    ProjectEditDateField(title: "projectEdit.ticketStart", value: ticket.startTime, identifier: "projectEdit.ticketStart").dateEditing(.init(model: model, field: .ticketStart(ticketID)))
                    ProjectEditDateField(title: "projectEdit.ticketEnd", value: ticket.endTime, identifier: "projectEdit.ticketEnd").dateEditing(.init(model: model, field: .ticketEnd(ticketID)))
                }
                if model.draft.product == .city {
                    ProjectTicketMeetingPointFields(model: model, ticketID: ticketID)
                }
                Text("projectEdit.ticketScopeHint").foregroundStyle(.secondary)
            }.id("project-issue-anchor-ticketSchedule")
        }.modifier(ProjectEditIssueInitialScroll(anchor: initialIssueAnchor)).disabled(!model.fullEdit).appNavigationTitle("projectEdit.ticketDetails")
            .navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
    }
}

struct ProjectEditReviewView: View {
    let confirmation: ProjectEditConfirmation
    let canSimulate: Bool
    let canSubmit: Bool
    let busy: Bool
    let localSaveConfirmed: Bool
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("projectEdit.reviewHint", systemImage: "checklist")
                    Text(LocalizedStringKey(canSimulate ? "projectEdit.fixtureNotice" : (canSubmit ? "projectEdit.confirmLiveHint" : "projectEdit.unconfigured")))
                }
                if !localSaveConfirmed { Section { Text("projectPrepared.localSaveUnconfirmed").accessibilityIdentifier("projectPrepared.localSaveUnconfirmed") } }
                ProjectEditPreparedNodesView(value: .init(payload: confirmation.payload))
                ProjectStoryImagePreparedReferences(payload: confirmation.payload)
                ProjectStoryAudioPreparedReferences(payload: confirmation.payload)
                ProjectEditPreparedPayloadView(payload: confirmation.payload)
                Section { Text("projectPrepared.draftContext") }
                Section("projectEdit.basics") {
                    row("projectEdit.name", confirmation.draft.name)
                    row("projectEdit.subtitle", confirmation.draft.subtitle)
                    row("projectEdit.description", confirmation.draft.description)
                    row("projectEdit.cover", confirmation.draft.imgUrl)
                    row("projectEdit.gallery", confirmation.draft.imgArr)
                    row("projectEdit.categories", confirmation.draft.categoryIDs.map(String.init).joined(separator: ","))
                    row("projectEdit.startDate", confirmation.draft.startDate)
                    row("projectEdit.endDate", confirmation.draft.endDate)
                    if confirmation.draft.product == .freeExplore { row("projectEdit.deadline", confirmation.draft.recruitDeadline) }
                }
                if !(confirmation.draft.pendingMaterials ?? []).isEmpty { Section { Text("projectPending.reviewOmission") } }
                ProjectEditCompletionRulesSummary(draft: confirmation.draft)
                if confirmation.payload["openClubPool"] != nil {
                    Section("projectClubLead.title") { ProjectClubLeadSummary(draft: confirmation.draft) }
                }
                ForEach(confirmation.draft.chapters) { chapter in
                    Section {
                        row("projectEdit.chapterName", chapter.name); row("projectEdit.story", chapter.story)
                        if chapter.preserved["opening"] == .bool(true) { Text("projectEdit.rich.opening") }
                        if let ending = chapter.preserved["ending"]?.object {
                            Text("projectEdit.rich.ending")
                            if ending["fallback"] == .bool(true) { Text("projectEdit.rich.fallback") }
                            ForEach(Array((ending["when"]?.array ?? []).enumerated()), id: \.offset) { _, raw in
                                if let condition = raw.object {
                                    Text(verbatim: [condition["op"]?.text, condition["var"]?.text, condition["value"]?.text,
                                        condition["value"]?.integer.map(String.init), condition["nodeId"]?.integer.map(String.init)].compactMap { $0 }.joined(separator: " ")).font(.caption)
                                }
                            }
                        }
                        ForEach(chapter.blocks ?? []) { ProjectEditRichBlockSummary(block: $0, nodes: chapter.nodes) }

                    } header: { Text("projectEdit.chapterDetails") }
                }
                ForEach(confirmation.draft.tickets) { ticket in
                    Section("projectEdit.ticketDetails") {
                        row("projectEdit.ticketName", ticket.name); row("projectEdit.ticketPrice", ticket.price)
                        row("projectEdit.totalStock", ticket.totalStock); row("projectEdit.teamSize", ticket.teamSize)
                        let schedule = ticket.schedule(in: confirmation.draft)
                        row("projectEdit.ticketStart", schedule.start); row("projectEdit.ticketEnd", schedule.end)
                        if confirmation.draft.product == .freeExplore {
                            LabeledContent { Text(LocalizedStringKey(ticket.syncsWithThemeDates ? "projectEdit.yes" : "projectEdit.no")) } label: { Text("projectEdit.syncThemeDates") }
                            if !ticket.canEditThemeDateSync { Text("projectEdit.syncThemeDatesLegacy") }
                        }
                        ProjectTicketMeetingPointSummary(ticket: ticket)
                        let sale = (try? ticket.saleTimePayloads()) ?? [:]
                        row("projectEdit.saleStart", sale["saleStartTime"]?.text ?? ticket.saleStartTime)
                        row("projectEdit.saleEnd", sale["saleEndTime"]?.text ?? ticket.saleEndTime)
                        Text("projectEdit.saleStoredOnly").font(.caption).foregroundStyle(.secondary)
                        if !ticket.canEditSaleTime(end: false) || !ticket.canEditSaleTime(end: true) { Text("projectEdit.saleLegacy") }

                    }
                }
                Section("projectEdit.visibility") {
                    LabeledContent { Text(LocalizedStringKey(confirmation.draft.publishToCreative ? "projectEdit.yes" : "projectEdit.no")) } label: { Text("projectEdit.publishToCreative") }
                    Text("projectEdit.advancedPreserved")
                }
                if canSubmit {
                    Button(LocalizedStringKey(canSimulate ? "projectEdit.confirmSimulation" : "projectEdit.confirmLive"), action: confirm).disabled(busy)
                        .accessibilityIdentifier("projectEdit.confirmSimulation")
                }
                Button("action.cancel", role: .cancel, action: cancel).accessibilityIdentifier("projectEdit.cancelReview")
            }.appNavigationTitle("projectEdit.reviewTitle").navigationBarTitleDisplayMode(.inline)
                .interactiveDismissDisabled(busy)
        }
    }
    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent { Text(verbatim: value).multilineTextAlignment(.trailing).textSelection(.enabled) } label: { Text(title) }
    }
}
