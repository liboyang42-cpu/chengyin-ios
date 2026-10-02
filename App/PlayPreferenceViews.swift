import SwiftUI

@MainActor struct PlayPreferenceView: View {
    @Bindable var model: PlayPreferenceCoordinator
    var onFinished: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var useExisting = true
    @State private var selectedTagID = 0
    @State private var review: PlayPreferenceReview?
    @State private var confirm = false
    @State private var tagConfirm = false
    @State private var correctedValue = ""
    @State private var error: PlayExperienceError?
    var body: some View {
        List {
            Section {
                PlayRuntimePhaseText(phase: model.phase)
                if let issue = model.issue ?? error { PlayExperienceIssueView(issue: issue) }
                if model.phase == "unknown" {
                    Text("playx.unknown.body")
                    Button("playx.reconcile") { Task { await model.load() } }
                    if model.canRetryExact { Button("playx.retryExact") { Task { await model.retryExact() } } }
                }
            }
            if let submission = model.submission, !submission.needsTiebreak {
                Section("playx.preference.result") {
                    if let title = submission.evaluation["title"].text { Text(verbatim: title).font(.headline) }
                    if let body = submission.evaluation["body"].text { Text(verbatim: body) }
                    if let next = submission.evaluation["nextStep"].text, !next.isEmpty { Text(verbatim: next) }
                    if let days = submission.evaluation["nextStepDays"].tolerantInteger { LabeledContent("playx.preference.days") { Text(verbatim: String(days)) } }
                }
                PlayRewardSection(reward: submission.progress)
                if let tag = model.pendingTag {
                    Section("playx.preference.tag") {
                        Text(verbatim: tag.code + " · " + tag.value)
                        if let purpose = submission.disclosure["purpose"].text { LabeledContent { Text(verbatim: purpose) } label: { Text("playx.preference.purpose") } }
                        if let recipient = submission.disclosure["recipientLabel"].text { LabeledContent { Text(verbatim: recipient) } label: { Text("playx.preference.recipient") } }
                        if tag.status == 1 { Label("playx.preference.confirmed", systemImage: "checkmark.seal") }
                        else { Button("playx.preference.confirmTag") { correctedValue = ""; tagConfirm = true }.disabled(model.phase != "completed" || !submission.canDiscloseTag) }
                        if submission.availableTagValues.count >= 2 {
                            Picker("playx.preference.correctValue", selection: $correctedValue) {
                                Text("playx.choose").tag("")
                                ForEach(submission.availableTagValues, id: \.self) { value in Text(verbatim: value).tag(value) }
                            }
                            Button("playx.preference.correctTag") { tagConfirm = true }
                                .disabled(correctedValue.isEmpty || correctedValue == tag.value || model.phase != "completed" || !submission.canDiscloseTag)
                        }
                    }
                }
            } else if model.phase == "completed" { Section { Text("playx.preference.completedNoResult") } }
            else if !model.steps.isEmpty || !model.inheritedTags.isEmpty {
                if !model.inheritedTags.isEmpty && useExisting {
                    Section("playx.preference.inherit") {
                        Text("playx.preference.inherit.detail")
                        Picker("playx.preference.tag", selection: $selectedTagID) {
                            Text("playx.choose").tag(0)
                            ForEach(model.inheritedTags) { tag in Text(verbatim: tag.code + " · " + tag.value).tag(tag.id) }
                        }
                        Button("playx.preference.reuse") { prepare(reuse: selectedTagID) }.disabled(selectedTagID <= 0 || model.phase != "ready")
                        Button("playx.preference.answerAgain") { useExisting = false }.disabled(model.phase != "ready" || model.steps.isEmpty)
                    }
                } else {
                    ForEach(model.steps) { step in
                        Section {
                            Text(verbatim: step.title).font(.headline)
                            Text(LocalizedStringKey(step.type == "discard" ? "playx.preference.discard" : "playx.choose"))
                            Picker("playx.choose", selection: Binding(get: { model.choices[step.id] ?? "" }, set: { model.select(stepID: step.id, optionID: $0) })) {
                                Text("playx.choose").tag("")
                                ForEach(step.options) { option in Text(verbatim: option.text).tag(option.id) }
                            }.disabled(model.phase != "ready").accessibilityIdentifier("playx.preference.step.\(step.id)")
                        }
                    }
                    Button("playx.review") { prepare(reuse: nil) }.disabled(model.phase != "ready").accessibilityIdentifier("playx.preference.review")
                }
            }
            if model.phase == "completed" { Button("playx.preference.done") { dismiss() } }
            if model.phase == "failed" || model.phase == "idle" { Button("playx.refresh") { Task { await model.load() } } }
        }.privacySensitive().navigationTitle("playx.preference.title").accessibilityIdentifier("playx.preference.view")
            .task { await model.load() }
            .confirmationDialog("playx.review", isPresented: $confirm, titleVisibility: .visible) {
                Button("playx.submit") { if let review { Task { await model.submit(review); self.review = nil; useExisting = false } } }
                Button("playx.cancel", role: .cancel) { model.cancelReview(); review = nil }
            } message: { Text(LocalizedStringKey(review?.reusedTagCode == nil ? "playx.preference.submitNotice" : "playx.preference.reuseNotice")) }
            .confirmationDialog("playx.preference.tag", isPresented: $tagConfirm, titleVisibility: .visible) {
                Button("playx.submit") { Task { await model.writeTag(correctedValue: correctedValue.isEmpty ? nil : correctedValue) } }
            } message: {
                if let disclosure = model.submission?.disclosure,
                   let recipient = disclosure["recipientLabel"].text, let purpose = disclosure["purpose"].text { Text(verbatim: recipient + "\n" + purpose) }
            }
            .onDisappear { model.cancelReview(); review = nil; onFinished() }
    }
    private func prepare(reuse: Int?) {
        do { review = try model.review(reuseTagID: reuse); confirm = true; error = nil }
        catch { self.error = .invalidAction }
    }
}

@MainActor struct PlayOperatingSummaryView: View {
    @Bindable var model: PlayOperatingSummaryCoordinator
    @State private var revokeID: Int?
    @State private var confirm = false
    var body: some View {
        List {
            Section {
                Text("playx.os.private").font(.footnote)
                PlayRuntimePhaseText(phase: model.phase)
                if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
                Button("playx.refresh") { Task { await model.load() } }.disabled(model.phase == "submitting")
                if !model.unresolvedTagIDs.isEmpty { Text("playx.unknown.body") }
            }
            if let summary = model.summary {
                if let edition = summary.edition { Section { Text(verbatim: edition) } }
                if summary.isEmpty { Text("playx.os.empty") }
                Section("playx.os.tags") {
                    ForEach(summary.tags) { tag in
                        VStack(alignment: .leading) {
                            Text(verbatim: tag.value)
                            if tag.revoked { Text("playx.os.revoked").font(.caption) }
                            else { Button("playx.os.revoke", role: .destructive) { revokeID = tag.id; confirm = true }.disabled(model.phase != "ready") }
                        }
                    }
                }
                ForEach(Array(summary.cards.enumerated()), id: \.offset) { _, card in
                    Section { if !card.title.isEmpty { Text(verbatim: card.title).font(.headline) }; if !card.body.isEmpty { Text(verbatim: card.body) } }
                }
                Section("playx.os.anchors") {
                    ForEach(summary.anchors) { anchor in Text(verbatim: anchor.name).accessibilityLabel(Text(verbatim: anchor.name)) }
                }
                Section("playx.os.week") { ForEach(Array(summary.actions7Days.enumerated()), id: \.offset) { _, action in Text(verbatim: action) } }
                Section("playx.os.month") { ForEach(Array(summary.actions30Days.enumerated()), id: \.offset) { _, action in Text(verbatim: action) } }
            }
        }.privacySensitive().navigationTitle("playx.os.title").accessibilityIdentifier("playx.os.view")
            .task { await model.load() }
            .confirmationDialog("playx.os.revoke", isPresented: $confirm, titleVisibility: .visible) {
                Button("playx.os.revoke", role: .destructive) { if let revokeID { Task { await model.revoke(tagID: revokeID) } } }
            } message: { Text("playx.os.revokeNotice") }
    }
}
