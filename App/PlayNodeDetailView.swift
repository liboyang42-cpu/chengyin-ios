import SwiftUI

@MainActor
struct PlayNodeDetailView: View {
    let nodeID: Int
    let model: PlayViewModel
    @State private var answer = ""
    var body: some View {
        Group {
            if model.reader.identity == nil {
                PlayIssueView(issue: .init(APIError.unauthorized))
            } else if model.isLoading {
                ProgressView("play.loading")
            } else if let issue = model.visibleIssue {
                VStack {
                    if let receipt = model.visibleReceipt { PlayReceiptView(receipt: receipt).padding() }
                    PlayIssueView(issue: issue) { Task { await model.load(keepingReceipt: true) } }
                }
            } else if let snapshot = model.visibleSnapshot,
                      snapshot.availability != .registrationRequired,
                      let node = snapshot.visibleNodes.first(where: { $0.id == nodeID }) {
                detail(node, snapshot: snapshot)
            } else {
                ContentUnavailableView("play.node.unavailable", systemImage: "lock", description: Text("play.node.unavailable.detail"))
            }
        }
        .privacySensitive()
        .appNavigationTitle("play.node.title")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.reader.identity) { _, _ in answer = "" }
        .onChange(of: model.visibleSnapshot) { _, _ in answer = "" }
    }
    private func detail(_ node: PlayNode, snapshot: PlaySnapshot) -> some View {
        let availability = snapshot.answerAvailability(for: node)
        return Form {
            Section {
                if let name = node.name, !name.isEmpty { Text(verbatim: name).font(.title2.bold()) }
                else { Text("play.node.untitled").font(.title2.bold()) }
                if let address = node.address, !address.isEmpty {
                    Label { Text(verbatim: address) } icon: { Image(systemName: "mappin.and.ellipse") }
                }
                Text(LocalizedStringKey(snapshot.isDone(node) ? "play.node.completed" : snapshot.isLocked(node) ? "play.node.locked" : "play.node.open"))
                    .font(.headline).accessibilityIdentifier("play.node.status")
                if let reason = snapshot.lockReason(node), !reason.isEmpty { Text(verbatim: reason) }
                if let note = snapshot.result.timeNote, snapshot.availability != .active, !note.isEmpty { Text(verbatim: note) }
                if let hours = node.businessTime, !hours.isEmpty { LabeledContent("play.businessTime") { Text(verbatim: hours) } }
                if let open = node.openStatus, !open.isEmpty { LabeledContent("play.openStatus") { Text(verbatim: open) } }
            }
            if !snapshot.isLocked(node) {
                if let story = node.storyText, !story.isEmpty { Section("play.story") { Text(verbatim: story) } }
                if let description = node.description, !description.isEmpty { Section("play.description") { Text(verbatim: description) } }
                if let title = node.gameTitle, !title.isEmpty {
                    Section("play.task") {
                        Text(verbatim: title).font(.headline)
                        if let rules = node.ruleInstructions, !rules.isEmpty { Text(verbatim: rules) }
                        if let materials = node.requiredMaterials, !materials.isEmpty { LabeledContent("play.materials") { Text(verbatim: materials) } }
                        if let duration = node.durationMinutes { LabeledContent("play.duration") { Text(verbatim: String(duration)) } }
                        if let players = node.players, !players.isEmpty { LabeledContent("play.players") { Text(verbatim: players) } }
                        if let difficulty = node.difficulty, !difficulty.isEmpty { LabeledContent("play.difficulty") { Text(verbatim: difficulty) } }
                    }
                }
                if let question = node.question, !question.isEmpty {
                    Section("play.question") {
                        Text(verbatim: question).accessibilityIdentifier("play.question")
                        if node.validationMethod == 3, let options = node.options {
                            ForEach(options.keys.sorted(), id: \.self) { key in
                                Button {
                                    guard availability.canAnswer, !model.isSubmitting, !model.needsProgressCheck else { return }
                                    answer = key
                                } label: {
                                    HStack(alignment: .top) {
                                        Image(systemName: answer == key ? "largecircle.fill.circle" : "circle")
                                        Text(verbatim: key + ". " + (options[key] ?? ""))
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .disabled(!availability.canAnswer || model.isSubmitting || model.needsProgressCheck)
                                .accessibilityAddTraits(answer == key ? .isSelected : [])
                                .accessibilityIdentifier("play.option.\(key)")
                            }
                        } else if availability == .text {
                            TextField("play.answer.placeholder", text: $answer, axis: .vertical)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .disabled(model.isSubmitting || model.needsProgressCheck)
                                .accessibilityIdentifier("play.answer.input")
                        }
                    }
                }
            }
            if let receipt = model.visibleReceipt, receipt.nodeID == nodeID { Section { PlayReceiptView(receipt: receipt) } }
            Section {
                if let issue = model.actionIssue {
                    if let message = issue.message, !message.isEmpty { Text(verbatim: message) }
                    else { Text("play.answer.failed") }
                }
                if model.isSubmitting {
                    ProgressView("play.answer.submitting").accessibilityIdentifier("play.answer.submitting")
                } else if model.needsProgressCheck {
                    Text("play.answer.checkProgress").foregroundStyle(.secondary)
                    Button("play.answer.refreshProgress") { Task { await model.load(keepingReceipt: true) } }
                        .disabled(model.isLoading || model.isSubmitting)
                        .accessibilityIdentifier("play.answer.refreshProgress")
                } else if availability.canAnswer {
                    if model.reader.supportsAnswerSubmission {
                        Text("play.answer.instructions").font(.footnote).foregroundStyle(.secondary)
                        Button {
                            Task { await model.submit(nodeID: nodeID, answer: answer) }
                        } label: {
                            if model.isSubmitting { ProgressView("play.answer.submitting") }
                            else { Text("play.answer.submit") }
                        }
                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSubmitting || !model.reader.canSubmitAnswer)
                        .accessibilityIdentifier("play.answer.submit")
                    } else { Text("play.answer.readOnly").foregroundStyle(.secondary) }
                } else {
                    Text(LocalizedStringKey(availability.detailKey)).foregroundStyle(.secondary)
                }
            }
            if snapshot.isDone(node) {
                Section("play.result") {
                    if let xp = node.xp { LabeledContent("play.xp") { Text(verbatim: String(xp)) } }
                    else { Text("play.xp.unknown") }
                    if let score = node.puzzleScore { LabeledContent("play.puzzleScore") { Text(verbatim: String(score)) } }
                    if let mode = node.completionMode, !mode.isEmpty { LabeledContent("play.completionMode") { Text(verbatim: mode) } }
                }
            }
        }
        .accessibilityIdentifier("play.nodeDetail")
    }
}
