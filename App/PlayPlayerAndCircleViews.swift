import SwiftUI

@MainActor struct PlayPlayerSessionView: View {
    @Bindable var model: PlayPlayerGameCoordinator
    @State private var evidence: [Int: String] = [:]
    @State private var review: PlayPlayerCommand?
    @State private var showReview = false
    @State private var consequence = ""
    @State private var issue: PlayExperienceError?
    var body: some View {
        List {
            Section {
                LabeledContent("playx.state") { PlayRuntimePhaseText(phase: model.phase) }
                Button("playx.refresh") { Task { await model.load() } }.disabled(model.phase == "submitting")
                if let issue = model.issue ?? issue { PlayExperienceIssueView(issue: issue) }
                if model.phase == "unknown" {
                    Text("playx.unknown.body")
                    Button("playx.reconcile") { Task { await model.recover() } }.accessibilityIdentifier("playx.player.reconcile")
                    Button("playx.retryExact") { Task { await model.retryExact() } }
                }
            }
            if let projection = model.projection {
                Section("playx.player.role") {
                    if let name = projection.role["name"].text { Text(verbatim: name).font(.headline) }
                    if let brief = projection.role["publicBrief"].text { Text(verbatim: brief) }
                    if projection.roleConfirmed { Label("playx.player.role.confirmed", systemImage: "checkmark.seal") }
                    else { Button("playx.player.role.confirm") { prepare(.confirmRole, projection: projection) }.disabled(model.phase != "ready") }
                }
                ForEach(projection.nodes) { node in
                    Section {
                        Text(verbatim: node.name ?? "#\(node.id)").font(.headline)
                        if let state = node.state { Text(verbatim: state).font(.caption) }
                        if let clue = node.clue { Text(verbatim: clue) }
                        if node.state == "PAUSED" {
                            if let reason = node.pause["reason"].text { Text(verbatim: reason) }
                            if let eta = node.pause["resumeEta"].text { LabeledContent("playx.player.resumeETA") { Text(verbatim: eta) } }
                            if let fallback = node.fallback["playerMessage"].text { Text(verbatim: fallback) }
                        }
                        if let prompt = node.task["prompt"].text { Text(verbatim: prompt) }
                        if node.task["inputType"].text == "TEXT" {
                            TextField("playx.answer.placeholder", text: Binding(get: { evidence[node.id] ?? "" }, set: { evidence[node.id] = $0 }), axis: .vertical)
                                .accessibilityIdentifier("playx.player.text.\(node.id)")
                            Button("playx.review") {
                                do {
                                    let value = try PlayPlayerCommand.textEvidence(evidence[node.id] ?? "")
                                    prepare(.submit, projection: projection, nodeID: node.id, payload: ["taskCode": node.task["taskCode"], "evidenceUrls": .array([.string(value)])])
                                } catch { issue = .invalidAction }
                            }.disabled(model.phase != "ready")
                        } else if node.task["inputType"].text == "PHOTO" || node.task["inputType"].text == "SCAN" { Text("playx.device.disabled") }
                        ForEach(Array(node.choices.enumerated()), id: \.offset) { _, choice in
                            if let id = choice["id"].text, let label = choice["label"].text {
                                Button { prepare(.choice, projection: projection, nodeID: node.id, payload: ["choiceId": .string(id)]) } label: { Text(verbatim: label) }
                                    .disabled(model.phase != "ready")
                            }
                        }
                        ForEach(Array((node.hint["revealedTexts"].array ?? []).enumerated()), id: \.offset) { _, hint in
                            if let text = hint["text"].text { Text(verbatim: text) }
                        }
                        if let level = node.hint["nextLevel"].integer, let impact = node.hint["nextImpactLabel"].text, !impact.isEmpty {
                            Button("playx.hints.request") { prepare(.hint, projection: projection, nodeID: node.id, payload: ["level": .int(level)], consequence: impact) }
                                .disabled(model.phase != "ready")
                        }
                        if node.hint["revealAvailable"].bool == true, let impact = node.hint["revealImpactLabel"].text, !impact.isEmpty {
                            Button("playx.player.reveal") { prepare(.reveal, projection: projection, nodeID: node.id, consequence: impact) }
                                .disabled(model.phase != "ready")
                        }
                        if let completion = node.completionStatus { Text(verbatim: completion).font(.footnote) }
                    }
                }
                if let ending = projection.story["ending"].object {
                    Section("playx.ending") {
                        if let title = ending["title"]?.text { Text(verbatim: title).font(.headline) }
                        if let text = ending["summary"]?.text ?? ending["text"]?.text { Text(verbatim: text) }
                    }
                }
                if let receipt = model.receipt {
                    Section("playx.player.receipt") {
                        LabeledContent("playx.state") { Text(verbatim: receipt.outcome) }
                        if let answer = receipt.result["answerReveal"].text { Text(verbatim: answer) }
                        Text("playx.player.submissionNotice").font(.footnote)
                    }
                }
            }
        }.privacySensitive().navigationTitle("playx.player.title").accessibilityIdentifier("playx.player.view")
            .task { await model.load() }
            .confirmationDialog("playx.review", isPresented: $showReview, titleVisibility: .visible) {
                Button("playx.submit") { if let review { Task { await model.submit(review); self.review = nil } } }
                Button("playx.cancel", role: .cancel) { review = nil }
            } message: { if consequence.isEmpty { Text("playx.review.detail") } else { Text(verbatim: consequence) } }
    }
    private func prepare(_ action: PlayPlayerCommand.Action, projection: PlayPlayerGameProjection, nodeID: Int? = nil, payload: [String: PlayWireValue] = [:], consequence: String = "") {
        do {
            let command = try PlayPlayerCommand(activityID: projection.activityID, nodeID: nodeID, expectedRevision: projection.revision, action: action, payload: payload)
            guard projection.allows(command) else { throw PlayExperienceError.invalidAction }
            review = command; self.consequence = consequence; showReview = true; issue = nil
        } catch { issue = .invalidAction }
    }
}

@MainActor struct PlayCircleView: View {
    @Bindable var model: PlayCircleCoordinator
    @State private var invite = ""
    @State private var note = ""
    @State private var answers: [String: String] = [:]
    @State private var pending: PlayCircleIntent?
    @State private var review = false
    @State private var openReview = false
    var body: some View {
        List {
            Section {
                Text("playx.circle.notice").font(.footnote)
                if let issue = model.issue { PlayExperienceIssueView(issue: issue) }
                LabeledContent("playx.state") { PlayRuntimePhaseText(phase: model.phase) }
                if model.phase == "unknown" { Button("playx.reconcile") { Task { await model.recover() } }.accessibilityIdentifier("playx.circle.reconcile") }
                if model.phase == "unknownOpen" { Text("playx.circle.openUnknown") }
            }
            if model.card == nil {
                Section("playx.circle.open") {
                    TextField("playx.circle.invite", text: $invite).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    if model.offers.count < 3 { Text("playx.circle.closed") }
                    Button("playx.circle.open") { openReview = true }.disabled(model.phase != "ready" || model.offers.count < 3)
                }
            }
            if let card = model.card {
                Section("playx.circle.offers") {
                    TextField("playx.circle.note", text: $note, axis: .vertical)
                    ForEach(Array(model.offers.enumerated()), id: \.offset) { _, offer in
                        if let id = PlayCircleCard.identifier(offer["id"]) ?? PlayCircleCard.identifier(offer["offerId"]) {
                            Button {
                                pending = .record(offerID: id, note: note); review = true
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(verbatim: offer["candidateName"].text ?? offer["supplyName"].text ?? id).font(.headline)
                                    if let detail = offer["actionValue"].text, !detail.isEmpty { Text(verbatim: detail).font(.caption).foregroundStyle(.secondary) }
                                }
                            }.disabled(model.phase != "ready").accessibilityIdentifier("playx.circle.offer.\(id)")
                        }
                    }
                }
                ForEach(card.stages, id: \.self) { stage in
                    Section(LocalizedStringKey("playx.circle.stage." + stage)) {
                        if ["FITNESS", "FRIENDS"].contains(card.themeCode) {
                            Picker("playx.choose", selection: binding(stage)) {
                                Text("playx.choose").tag("")
                                ForEach(Array(model.offers.enumerated()), id: \.offset) { _, offer in
                                    if let code = offer["candidateCode"].text { Text(verbatim: offer["candidateName"].text ?? code).tag(code) }
                                }
                            }
                        } else if card.themeCode == "DATE" {
                            Picker("playx.choose", selection: binding(stage)) {
                                Text("playx.choose").tag("")
                                Text("playx.circle.date.q1").tag("Q1"); Text("playx.circle.date.q2").tag("Q2"); Text("playx.circle.date.q3").tag("Q3")
                            }
                        } else if card.themeCode == "SHANGHAI" { Text("playx.circle.shanghaiGate") }
                        else { TextField("playx.circle.answer", text: binding(stage), axis: .vertical) }
                        Button("playx.review") { pending = .answer(stage: stage, value: answers[stage] ?? ""); review = true }
                            .disabled(model.phase != "ready" || (answers[stage] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section("playx.circle.records") {
                    ForEach(Array(card.records.enumerated()), id: \.offset) { _, record in
                        VStack(alignment: .leading) {
                            Text(verbatim: record["candidateName"].text ?? record["supplyName"].text ?? "—")
                            if let note = record["note"].text { Text(verbatim: note).foregroundStyle(.secondary) }
                        }
                    }
                    ForEach(Array(card.memoryLines.enumerated()), id: \.offset) { _, line in Text(verbatim: line) }
                }
            }
        }.privacySensitive().navigationTitle("playx.circle.title").accessibilityIdentifier("playx.circle.view")
            .task { await model.loadOffers() }
            .confirmationDialog("playx.review", isPresented: $review, titleVisibility: .visible) {
                Button("playx.submit") { if let pending { Task { await model.submit(pending); self.pending = nil } } }
            } message: { Text("playx.circle.notice") }
            .confirmationDialog("playx.circle.open", isPresented: $openReview, titleVisibility: .visible) {
                Button("playx.submit") { Task { await model.open(inviteCode: invite.isEmpty ? nil : invite) } }
            }
    }
    private func binding(_ stage: String) -> Binding<String> { Binding(get: { answers[stage] ?? "" }, set: { answers[stage] = $0 }) }
}
