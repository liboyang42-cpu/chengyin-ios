import SwiftUI

@MainActor struct JourneyNarrativeView: View {
    @Bindable var model: JourneyNarrativeCoordinator
    var imageReader: (any RetainedPublicImageReading)? = nil
    var makeAudio: (@MainActor () -> PlatformAudioPlayback)? = nil
    var mediaScope = UUID()
    var onChanged: (() async -> Void)? = nil
    var body: some View {
        List {
            if model.busy { ProgressView("journey.working") }
            if let issue = model.issue { Text(LocalizedStringKey(issue)).accessibilityIdentifier("journey.record.error") }
            if !model.pending.isEmpty { Text("journey.record.unknown").accessibilityIdentifier("journey.record.pending") }
            if let receipt = model.receipt {
                Section("journey.record.answer") { Text(verbatim: receipt.question); Text(verbatim: receipt.answer) }
            }
            if let document = model.document { content(document) }
            Button("journey.record.refresh") { Task { await model.load() } }.disabled(model.busy || !model.available)
                .accessibilityIdentifier("journey.record.refresh")
        }
        .navigationTitle(LocalizedStringKey(model.query.titleKey)).privacySensitive()
        .accessibilityIdentifier("journey.record." + model.query.key)
        .task(id: model.identity) { await model.load() }
        .refreshable { await model.load() }
        .onDisappear { model.dismiss() }
        .onChange(of: model.acknowledgedRevision) { _, _ in Task { await onChanged?() } }
        .sheet(item: Binding(get: { model.review }, set: { if $0 == nil && model.review != nil { model.cancelReview() } })) { review in
            NavigationStack {
                Form {
                    Text(verbatim: review.question.question)
                    Text("journey.record.askImpact")
                    Button("journey.confirm") { Task { await model.confirm(review) } }.disabled(model.busy)
                        .accessibilityIdentifier("journey.record.confirm")
                }.navigationTitle("journey.record.questions")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("journey.cancel") { model.cancelReview() }.disabled(model.busy) } }
            }.interactiveDismissDisabled(model.busy)
        }
    }
    @ViewBuilder private func content(_ document: JourneyNarrativeDocument) -> some View {
        switch document {
        case .casebook(let value):
            progress(found: value.found, total: value.total)
            lines("journey.record.facts", value.facts)
            relations(value.relations)
            lines("journey.record.costs", value.costs)
            Section("journey.record.log") {
                if value.log.isEmpty { Text("journey.record.empty") }
                ForEach(Array(value.log.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: item.text)
                        if let at = item.at { Text(Date(timeIntervalSince1970: Double(at) / 1000), style: .date).font(.caption) }
                        LabeledContent("journey.hp", value: String(item.hpDelta)); LabeledContent("journey.luck", value: String(item.luckDelta))
                    }
                }
            }
        case .backpack(let items):
            Text("journey.record.rewardAuthority").font(.footnote)
            if items.isEmpty { Text("journey.record.empty") }
            ForEach(items) { item in
                Section {
                    LabeledContent("journey.record.node", value: String(item.id))
                    if let reward = item.reward { Text(verbatim: reward) }
                    Text(LocalizedStringKey("journey.record.reward." + item.status))
                    if let at = item.claimableAt { Text(Date(timeIntervalSince1970: Double(at) / 1000), style: .date) }
                }.accessibilityIdentifier("journey.record.reward.\(item.id)")
            }
        case .stage(let value):
            lines("journey.record.changed", value.changed)
            if let open = value.open { Section("journey.record.next") { Text(verbatim: open) } }
            lines("journey.record.costs", value.costs)
            Section { if let hp = value.hp { LabeledContent("journey.hp", value: String(hp)) }; if let luck = value.luck { LabeledContent("journey.luck", value: String(luck)) } }
        case .ending(let value): ending(value)
        case .questions(let value):
            if let opener = value.opener { Text(verbatim: opener) }
            if let aside = value.aside { Text(verbatim: aside).foregroundStyle(.secondary) }
            if value.questions.isEmpty { Text("journey.record.empty") }
            ForEach(value.questions) { question in
                Section {
                    Text(verbatim: question.question).font(.headline)
                    if question.asked {
                        if let answer = question.answer { Text(verbatim: answer) }
                    } else {
                        Button("journey.record.ask") { model.prepare(question.id) }
                            .disabled(!model.canAsk || model.pending.contains(question.id)).accessibilityIdentifier("journey.record.ask." + question.id)
                    }
                }
            }
            if !model.canAsk { Text("journey.record.actionGate").font(.footnote) }
        }
    }
    private func progress(found: Int, total: Int) -> some View {
        LabeledContent("journey.record.discoveries", value: "\(found) / \(total)")
    }
    private func lines(_ key: LocalizedStringKey, _ values: [String]) -> some View {
        Section(key) { if values.isEmpty { Text("journey.record.empty") }; ForEach(Array(values.enumerated()), id: \.offset) { _, text in Text(verbatim: text) } }
    }
    private func relations(_ values: [JourneyRecordRelation]) -> some View {
        Section("journey.record.relations") {
            if values.isEmpty { Text("journey.record.empty") }
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading) {
                    if let name = item.name { Text(verbatim: name).font(.headline) }
                    Text(LocalizedStringKey("journey.record.relation." + item.state))
                    if let line = item.line { Text(verbatim: line) }
                }
            }
        }
    }
    @ViewBuilder private func ending(_ value: JourneyEndingDocument) -> some View {
        if let title = value.title { Text(verbatim: title).font(.title2.bold()) }
        if let summary = value.summary { Text(verbatim: summary) }
        if let badge = value.badgeTitle { Section("journey.record.badge") { Text(verbatim: badge) } }
        progress(found: value.found, total: value.total)
        relations(value.epilogues); lines("journey.record.exhibits", value.exhibits); lines("journey.record.costs", value.costs)
        Section("journey.record.archive") {
            ForEach(Array(value.identity.enumerated()), id: \.offset) { _, item in LabeledContent { Text(verbatim: item.text ?? "") } label: { Text(verbatim: item.title) } }
            ForEach(Array(value.notes.enumerated()), id: \.offset) { _, item in VStack(alignment: .leading) { Text(verbatim: item.title).font(.headline); Text(verbatim: item.text ?? "") } }
            ForEach(Array(value.photos.enumerated()), id: \.offset) { _, item in
                if let url = item.text { photo(url, title: item.title) }
            }
        }
        if value.chapter.object != nil { JourneyEndingChapterView(raw: value.chapter, imageReader: imageReader, makeAudio: makeAudio, mediaScope: mediaScope) }
    }
    @ViewBuilder private func photo(_ url: String, title: String) -> some View {
        if !title.isEmpty { Text(verbatim: title) }
        if let imageReader { RetainedPublicReviewImages(urls: [url], reader: imageReader) }
        else { Label("journey.record.mediaGate", systemImage: "photo") }
    }
}

/// Only server-projected ending blocks are accepted here. Never evaluate creator
/// conditions or expose internal variables/tags in a player ending.
@MainActor private struct JourneyEndingChapterView: View {
    let raw: PlayWireValue
    let imageReader: (any RetainedPublicImageReading)?
    let makeAudio: (@MainActor () -> PlatformAudioPlayback)?
    let mediaScope: UUID
    @State private var audioURL: String?
    var body: some View {
        Section("journey.record.endingChapter") {
            if let title = raw["name"].text { Text(verbatim: title).font(.headline) }
            ForEach(Array((raw["blocks"].array ?? []).enumerated()), id: \.offset) { _, block in
                switch block["type"].text {
                case "text", "voice", "reveal":
                    if let who = block["who"].text { Text(verbatim: who).font(.caption) }
                    if let content = block["content"].text { Text(verbatim: content) }
                case "image": if let url = block["url"].text { image(url) }
                case "audio": if let url = block["url"].text { Button("chapterStory.listen") { audioURL = url } }
                case "dream":
                    if let title = block["title"].text { Text(verbatim: title).font(.headline) }
                    ForEach(Array((block["images"].array ?? []).enumerated()), id: \.offset) { _, item in
                        if let url = item["url"].text { image(url) }; if let line = item["line"].text { Text(verbatim: line) }
                    }
                default: EmptyView()
                }
            }
            if audioURL != nil { PlatformAudioHost(rawURL: audioURL, scope: mediaScope, makeModel: makeAudio) }
        }.onDisappear { audioURL = nil }
    }
    @ViewBuilder private func image(_ url: String) -> some View {
        if let imageReader { RetainedPublicReviewImages(urls: [url], reader: imageReader) }
        else { Label("journey.record.mediaGate", systemImage: "photo") }
    }
}
