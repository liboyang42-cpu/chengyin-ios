import SwiftUI

@MainActor struct PlayCompareView: View {
    let segment: PlayWireValue
    let revision: String
    let enabled: Bool
    let currentRevision: () -> String
    let onDirty: () -> Void
    let requestReview: PlayKitReviewRequest
    @State private var selection = PlayCompareSelection()
    @State private var resetSelection = false
    @State private var issue: PlayExperienceError?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var question: PlayCompareQuestion? { try? PlayCompareQuestion(segment) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let question {
                Text("playkit.compare.instructions").font(.subheadline)
                if let remaining = question.remainingAttempts {
                    LabeledContent("playkit.compare.remaining") { Text(verbatim: String(remaining)).monospacedDigit() }
                } else { Text("playkit.compare.unlimited").font(.footnote) }
                LabeledContent("playkit.compare.attempts") { Text(verbatim: String(question.attempts)).monospacedDigit() }
                if question.attempts > 0 {
                    Text(question.lastCorrect ? "playkit.compare.correct" : "playkit.compare.incorrect")
                        .accessibilityIdentifier("playkit.compare.receipt")
                }
                if !question.finished && selection.revision != revision {
                    Text("playkit.compare.changed").font(.footnote)
                    Button("playkit.compare.reload") { resetSelection = true }
                        .disabled(!enabled).accessibilityIdentifier("playkit.compare.reload")
                }
                if typeSize.isAccessibilitySize {
                    timelines(question, horizontal: false)
                } else {
                    ViewThatFits(in: .horizontal) {
                        timelines(question, horizontal: true).frame(minWidth: 600)
                        timelines(question, horizontal: false)
                    }
                }
                if !question.finished {
                    LabeledContent("playkit.compare.marked") { Text(verbatim: String(selection.marked.count)).monospacedDigit() }
                    Button("playkit.review") {
                        do {
                            let payload = try selection.payload(question, revision: currentRevision())
                            requestReview("SUBMIT_COMPARE", payload, {})
                            issue = nil
                        } catch { issue = error as? PlayExperienceError ?? .invalidAction }
                    }.buttonStyle(.borderedProminent)
                        .disabled(!enabled || selection.revision != revision)
                        .accessibilityIdentifier("playkit.submit.compare")
                }
                if let issue { PlayExperienceIssueView(issue: issue) }
            } else { Text("playkit.compare.invalid") }
        }
        .onAppear { if selection.revision == nil, let question { selection.restore(question, revision: revision) } }
        .confirmationDialog("playkit.compare.reloadQuestion", isPresented: $resetSelection, titleVisibility: .visible) {
            Button("playkit.compare.reload", role: .destructive) {
                if let question { selection.restore(question, revision: revision); issue = nil }
            }.accessibilityIdentifier("playkit.compare.reload.confirm")
            Button("playkit.cancel", role: .cancel) {}
        }
    }
    @ViewBuilder private func timelines(_ question: PlayCompareQuestion, horizontal: Bool) -> some View {
        if horizontal {
            HStack(alignment: .top, spacing: 20) { side(question.left, question: question); side(question.right, question: question) }
        } else {
            VStack(alignment: .leading, spacing: 24) { side(question.left, question: question); side(question.right, question: question) }
        }
    }
    private func side(_ side: PlayCompareQuestion.Side, question: PlayCompareQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: side.label).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            ForEach(side.items) { item in
                Button {
                    selection.toggle(item.id, question: question, revision: currentRevision()); onDirty()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selection.marked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: item.time).font(.caption.bold()).monospacedDigit()
                            Text(verbatim: item.text).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!enabled || selection.revision != revision || question.finished)
                    .accessibilityLabel(Text(verbatim: side.label + ", " + item.time + ", " + item.text))
                    .accessibilityValue(Text(selection.marked.contains(item.id) ? "playkit.compare.selected" : "playkit.compare.unselected"))
                    .accessibilityIdentifier("playkit.compare.item." + item.id)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Uses the exact immutable question captured with the action review, never a
/// later projection. IDs remain visible for reconciliation alongside readable text.
@MainActor struct PlayCompareReview: View {
    let question: PlayCompareQuestion
    let marked: [String]
    var body: some View {
        Text(verbatim: question.prompt).font(.headline)
        Text("playkit.compare.reviewBoundary").font(.footnote)
        if marked.isEmpty { Text("playkit.compare.none") }
        ForEach(Array([question.left, question.right].enumerated()), id: \.offset) { _, side in
            ForEach(side.items.filter { marked.contains($0.id) }) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: side.label + " · " + item.time).font(.subheadline.bold())
                    Text(verbatim: item.text)
                    Text(verbatim: item.id).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
