import SwiftUI

@MainActor struct ProjectEditChapterView: View {
    @ObservedObject var model: ProjectEditModel
    let chapterID: String
    private var chapter: Binding<ProjectEditChapter> { model.chapter(chapterID) }
    private var exists: Bool { model.draft.chapters.contains { $0.id == chapterID } }
    var body: some View {
        Form {
            if exists {
                Section("projectEdit.chapterDetails") {
                    TextField("projectEdit.chapterName", text: chapter.name).accessibilityIdentifier("projectEdit.chapterName")
                    if chapter.wrappedValue.blocks == nil {
                        TextField("projectEdit.story", text: chapter.description, axis: .vertical).lineLimit(4...12)
                            .accessibilityIdentifier("projectEdit.story")
                        if model.draft.product == .city || ProjectEditStoryContract.usesV2(model.draft) {
                            Button("projectEdit.enableStoryFlow") {
                                var c = chapter.wrappedValue
                                c.blocks = [.init(kind: .text, content: c.description)] + c.nodes.map { .init(kind: .node, nodeID: $0.id) }
                                chapter.wrappedValue = c
                            }.accessibilityIdentifier("projectEdit.enableStoryFlow")
                        }
                    }
                }
                ProjectEditChapterStorySettings(chapter: chapter, isFirst: model.draft.chapters.first?.id == chapterID)
                if let blocks = chapter.wrappedValue.blocks {
                    Section("projectEdit.storyFlow") {
                        ForEach(blocks) { block in
                            switch block.kind {
                            case .text:
                                TextField("projectEdit.story", text: blockBinding(block.id).content, axis: .vertical).lineLimit(3...12)
                                    .accessibilityIdentifier("projectEdit.block." + block.id)
                                NavigationLink("projectEdit.rich.editDetails") { ProjectEditRichBlockEditor(model: model, block: blockBinding(block.id), chapterID: chapterID) }
                            case .node:
                                NavigationLink { ProjectEditRichBlockEditor(model: model, block: blockBinding(block.id), chapterID: chapterID) } label: {
                                    Label { Text(verbatim: chapter.wrappedValue.nodes.first { $0.id == block.nodeID }?.name ?? "") } icon: { Image(systemName: "mappin.circle") }
                                }
                            case .image, .audio:
                                ProjectEditReferenceField(title: LocalizedStringKey(block.kind == .image ? "projectEdit.imageReference" : "projectEdit.audioReference"), value: blockBinding(block.id).url, identifier: "projectEdit.block." + block.id)
                            case .dream, .mood, .thought, .voice, .odd, .reveal:
                                NavigationLink { ProjectEditRichBlockEditor(model: model, block: blockBinding(block.id), chapterID: chapterID) } label: { ProjectEditRichBlockSummary(block: block, nodes: chapter.wrappedValue.nodes) }
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
                        HStack {
                            Button("projectEdit.addText") { appendBlock(.text) }
                            Button("projectEdit.addImage") { appendBlock(.image) }
                            Button("projectEdit.addAudio") { appendBlock(.audio) }
                        }.buttonStyle(.bordered).disabled(blocks.count >= 200)
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
                    }
                }
                Section("projectEdit.nodes") {
                    ForEach(chapter.wrappedValue.nodes) { node in
                        NavigationLink { ProjectEditNodeView(model: model, chapterID: chapterID, nodeID: node.id) } label: {
                            Label { ProjectEditName(value: node.name, fallback: "projectEdit.untitledNode") } icon: { Image(systemName: "mappin.circle") }
                        }.accessibilityIdentifier("projectEdit.node." + node.id)
                    }.onDelete { offsets in
                        var c = chapter.wrappedValue; let ids = offsets.map { c.nodes[$0].id }
                        for id in ids { c.removeNode(id: id) }; chapter.wrappedValue = c
                    }.onMove { from, to in
                        guard chapter.wrappedValue.blocks == nil else { return }
                        var c = chapter.wrappedValue; c.nodes.move(fromOffsets: from, toOffset: to); chapter.wrappedValue = c
                    }
                    Button("projectEdit.addNode", systemImage: "plus") {
                        var c = chapter.wrappedValue
                        do { try c.addNode(product: model.draft.product); chapter.wrappedValue = c } catch { /* Inline explanation is already visible. */ }
                    }.disabled(chapter.wrappedValue.preserved["ending"]?.object != nil || (model.draft.product == .city && !chapter.wrappedValue.hasRealStory) || (chapter.wrappedValue.blocks?.count ?? 0) >= 200)
                        .accessibilityIdentifier("projectEdit.addNode")
                    if model.draft.product == .city && !chapter.wrappedValue.hasRealStory { Text("projectEdit.validation.story").foregroundStyle(.secondary) }
                }
                Section { Text("projectEdit.chapterCarryOver").foregroundStyle(.secondary) }
            } else { Text("projectEdit.signIn") }
        }.disabled(!model.fullEdit)
            .appNavigationTitle("projectEdit.chapterDetails").navigationBarTitleDisplayMode(.inline)
            .toolbar { EditButton().disabled(!model.fullEdit) }
            .scrollDismissesKeyboard(.interactively)
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
    private var node: Binding<ProjectEditNode> {
        Binding(get: { model.chapter(chapterID).wrappedValue.nodes.first { $0.id == nodeID } ?? .init() }, set: { value in
            var c = model.chapter(chapterID).wrappedValue
            guard let i = c.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            c.nodes[i] = value; model.chapter(chapterID).wrappedValue = c
        })
    }
    var body: some View {
        Form {
            Section("projectEdit.nodeDetails") {
                TextField("projectEdit.nodeName", text: node.name).accessibilityIdentifier("projectEdit.nodeName")
                TextField("projectEdit.description", text: node.description, axis: .vertical).lineLimit(3...8)
                TextField("projectEdit.address", text: node.address).accessibilityIdentifier("projectEdit.address")
                TextField("projectEdit.longitude", text: node.longitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("projectEdit.longitude")
                TextField("projectEdit.latitude", text: node.latitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("projectEdit.latitude")
                Text("projectEdit.coordinatesHint").font(.caption).foregroundStyle(.secondary)
                Stepper(value: node.nodeTime, in: 0...Int.max) {
                    LabeledContent("projectEdit.nodeMinutes", value: String(node.wrappedValue.nodeTime))
                }
                ProjectEditReferenceField(title: "projectEdit.nodeImages", value: node.imgUrl, identifier: "projectEdit.nodeImages")
            }
            Section("projectEdit.gameplay") {
                if let id = node.wrappedValue.templateID {
                    LabeledContent("projectEdit.templateID", value: String(id))
                }
                Text("projectEdit.gameplayDeferred").foregroundStyle(.secondary)
            }
        }.disabled(!model.fullEdit).appNavigationTitle("projectEdit.nodeDetails")
            .navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
    }
}

@MainActor struct ProjectEditTicketView: View {
    @ObservedObject var model: ProjectEditModel
    let ticketID: String
    private var ticket: Binding<ProjectEditTicket> { model.ticket(ticketID) }
    var body: some View {
        Form {
            Section("projectEdit.ticketDetails") {
                TextField("projectEdit.ticketName", text: ticket.name).accessibilityIdentifier("projectEdit.ticketName")
                TextField("projectEdit.ticketPrice", text: ticket.price).keyboardType(.decimalPad).accessibilityIdentifier("projectEdit.ticketPrice")
                Text("projectEdit.priceHint").font(.caption).foregroundStyle(.secondary)
                TextField("projectEdit.totalStock", text: ticket.totalStock).keyboardType(.numberPad).accessibilityIdentifier("projectEdit.totalStock")
                TextField("projectEdit.teamSize", text: ticket.teamSize).keyboardType(.numberPad)
                TextField("projectEdit.description", text: ticket.description, axis: .vertical).lineLimit(3...8)
            }
            Section("projectEdit.saleSchedule") {
                ProjectEditDateField(title: "projectEdit.saleStart", value: ticket.saleStartTime, identifier: "projectEdit.saleStart")
                    .disabled(!ticket.wrappedValue.canEditSaleTime(end: false))
                ProjectEditDateField(title: "projectEdit.saleEnd", value: ticket.saleEndTime, identifier: "projectEdit.saleEnd")
                    .disabled(!ticket.wrappedValue.canEditSaleTime(end: true))
                Text("projectEdit.saleStoredOnly").font(.caption).foregroundStyle(.secondary)
                if !ticket.wrappedValue.canEditSaleTime(end: false) || !ticket.wrappedValue.canEditSaleTime(end: true) {
                    Text("projectEdit.saleLegacy").font(.caption).foregroundStyle(.secondary)
                }
            }
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
                    ProjectEditDateField(title: "projectEdit.ticketStart", value: ticket.startTime, identifier: "projectEdit.ticketStart")
                    ProjectEditDateField(title: "projectEdit.ticketEnd", value: ticket.endTime, identifier: "projectEdit.ticketEnd")
                }
                if model.draft.product == .city {
                    TextField("projectEdit.meetingPoint", text: ticket.meetingPoint).accessibilityIdentifier("projectEdit.meetingPoint")
                }
                Text("projectEdit.ticketScopeHint").foregroundStyle(.secondary)
            }
        }.disabled(!model.fullEdit).appNavigationTitle("projectEdit.ticketDetails")
            .navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
    }
}

struct ProjectEditReviewView: View {
    let confirmation: ProjectEditConfirmation
    let canSimulate: Bool
    let canSubmit: Bool
    let busy: Bool
    let cancel: () -> Void
    let confirm: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("projectEdit.reviewHint", systemImage: "checklist")
                    Text(LocalizedStringKey(canSimulate ? "projectEdit.fixtureNotice" : (canSubmit ? "projectEdit.confirmLiveHint" : "projectEdit.unconfigured")))
                }
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
                ProjectEditCompletionRulesSummary(draft: confirmation.draft)
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
                        ForEach(chapter.nodes) { node in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: node.name).font(.headline)
                                Text(verbatim: node.address)
                                Text(verbatim: node.longitude + ", " + node.latitude).font(.caption)
                            }
                        }
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
                        row("projectEdit.meetingPoint", ticket.meetingPoint)
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
