import SwiftUI

@MainActor struct NativeChannelAppealEntry: View {
    @Bindable var flow: NativeChannelAppealFlow
    @State private var explanation = ""
    @State private var retryConfirmation = false
    @Environment(\.scenePhase) private var scenePhase
    private var explanationCount: Int { explanation.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count }
    private var validExplanation: Bool { explanationCount > 0 && explanationCount <= 500 }
    private var reading: Bool { flow.state == .loading || flow.state == .submitting || flow.readingCurrent }
    private var hasAvailableOperation: Bool { flow.canSubmit || flow.canSupplement || flow.canWithdraw }
    var body: some View {
        Form {
            if flow.isCurrent {
                progressSection
                if flow.journalUnavailable {
                    Section {
                        Label { Text("recovery.journalUnavailable", tableName: "NativeChannelAppealDetails") } icon: { Image(systemName: "externaldrive.badge.exclamationmark") }
                            .accessibilityIdentifier("channel.appeal.journalUnavailable")
                    }
                }
                if flow.hasPending {
                    Section {
                        Label { Text("recovery.pending", tableName: "NativeChannelAppealDetails") } icon: { Image(systemName: "clock.arrow.circlepath") }
                        if let id = flow.requestID {
                            Text(verbatim: id).font(.callout).textSelection(.enabled)
                                .accessibilityLabel(Text("recovery.requestID", tableName: "NativeChannelAppealDetails"))
                                .accessibilityValue(id)
                        }
                        Text("recovery.explanation", tableName: "NativeChannelAppealDetails")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button { Task { await flow.refresh() } } label: { Text("recovery.readOriginal", tableName: "NativeChannelAppealDetails") }.disabled(!flow.canRecover)
                        Button { retryConfirmation = true } label: { Text("recovery.reviewRetry", tableName: "NativeChannelAppealDetails") }.disabled(!flow.canRetry)
                    } header: { Text("recovery.title", tableName: "NativeChannelAppealDetails") }
                } else if flow.state == .reviewing {
                    Section {
                        Text(LocalizedStringKey(NativeChannelAppealPresentation.operationTitleKey(flow.reviewedOperation)), tableName: "NativeChannelAppealDetails").font(.headline)
                        Text(verbatim: flow.reviewedText).textSelection(.enabled)
                        Button { Task { await flow.confirm() } } label: { Text("review.confirm", tableName: "NativeChannelAppealDetails") }
                        Button(role: .cancel) { flow.cancelReview() } label: { Text("action.cancel", tableName: "NativeChannelAppealDetails") }
                    } header: { Text("review.title", tableName: "NativeChannelAppealDetails") }
                } else if hasAvailableOperation {
                    Section {
                        TextField(text: $explanation, axis: .vertical) { Text("input.placeholder", tableName: "NativeChannelAppealDetails") }
                            .accessibilityIdentifier("channel.appeal.explanation")
                        HStack(alignment: .firstTextBaseline) {
                            Text("input.limit", tableName: "NativeChannelAppealDetails")
                            Spacer(minLength: 8)
                            Text(verbatim: "\(explanationCount)/500").monospacedDigit()
                        }.font(.footnote).foregroundStyle(.secondary)
                        if !validExplanation {
                            Text(explanationCount > 500 ? "input.tooLong" : "input.required", tableName: "NativeChannelAppealDetails")
                                .font(.footnote)
                        }
                        Text("input.explanation", tableName: "NativeChannelAppealDetails")
                            .font(.footnote).foregroundStyle(.secondary)
                        if flow.canSubmit {
                            Button { _ = flow.prepare(.submit, text: explanation) } label: { Text("action.submit", tableName: "NativeChannelAppealDetails") }.disabled(!validExplanation)
                        }
                        if flow.canSupplement {
                            Button { _ = flow.prepare(.evidence, text: explanation) } label: { Text("action.evidence", tableName: "NativeChannelAppealDetails") }.disabled(!validExplanation)
                        }
                        if flow.canWithdraw {
                            Button { _ = flow.prepare(.withdraw, text: explanation) } label: { Text("action.withdraw", tableName: "NativeChannelAppealDetails") }.disabled(!validExplanation)
                        }
                    } header: { Text("input.title", tableName: "NativeChannelAppealDetails") }
                }
                actionFactsSection
                appealDetailsSection
                Section {
                    Button { Task { await flow.refresh() } } label: {
                        Label { Text("refresh.action", tableName: "NativeChannelAppealDetails") } icon: { Image(systemName: "arrow.clockwise") }
                    }.disabled(reading)
                    Text("refresh.readOnly", tableName: "NativeChannelAppealDetails")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if flow.state == .idle {
                ProgressView { Text("progress.reading", tableName: "NativeChannelAppealDetails") }
            } else {
                Section {
                    Label { Text("session.unavailable", tableName: "NativeChannelAppealDetails") } icon: { Image(systemName: "lock.shield") }
                }
            }
        }
        .formStyle(.grouped)
        .font(.body)
        .foregroundStyle(.primary)
        .navigationTitle(Text("entry.title", tableName: "NativeChannelAppealDetails"))
        .task { await flow.activate() }
        .onDisappear { retryConfirmation = false; flow.deactivate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await flow.activate() } }
            else { retryConfirmation = false; flow.deactivate() }
        }
        .confirmationDialog(Text("retry.confirmation", tableName: "NativeChannelAppealDetails"), isPresented: $retryConfirmation, titleVisibility: .visible) {
            Button { Task { await flow.retryOriginal() } } label: { Text("retry.confirm", tableName: "NativeChannelAppealDetails") }
            Button(role: .cancel) { } label: { Text("action.cancel", tableName: "NativeChannelAppealDetails") }
        }
        .privacySensitive()
    }
    private var progressSection: some View {
        Section {
            if !flow.appealStatus.isEmpty {
                Text(LocalizedStringKey(NativeChannelAppealPresentation.statusTitleKey(flow.appealStatus)), tableName: "NativeChannelAppealDetails")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("channel.appeal.currentStatus")
                LabeledContent { Text(verbatim: flow.appealStatus) } label: { Text("progress.serverStatus", tableName: "NativeChannelAppealDetails") }.font(.footnote).foregroundStyle(.secondary)
            }
            if reading {
                HStack(alignment: .top, spacing: 12) {
                    ProgressView()
                    Text(flow.state == .submitting ? "progress.submitting" : "progress.reading", tableName: "NativeChannelAppealDetails")
                }.accessibilityElement(children: .combine)
            }
            LabeledContent { Text(verbatim: flow.notice.actionID) } label: { Text("progress.actionID", tableName: "NativeChannelAppealDetails") }.font(.callout).textSelection(.enabled)
            if !flow.actionReason.isEmpty { Text(verbatim: flow.actionReason) }
            if !flow.deadline.isEmpty { LabeledContent { Text(verbatim: flow.deadline) } label: { Text("progress.deadline", tableName: "NativeChannelAppealDetails") } }
            if !flow.decisionReason.isEmpty { Text(verbatim: flow.decisionReason).textSelection(.enabled) }
            if flow.state == .applied {
                Label { Text("result.confirmed", tableName: "NativeChannelAppealDetails") } icon: { Image(systemName: "checkmark.circle") }
                Text("result.currentSeparate", tableName: "NativeChannelAppealDetails")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if flow.currentReadFailed {
                Text("progress.currentReadFailed", tableName: "NativeChannelAppealDetails")
            }
            if flow.state == .unavailable {
                Text("source.unavailable", tableName: "NativeChannelAppealDetails")
            }
            if flow.locatorUnavailable {
                Text("locator.unavailable", tableName: "NativeChannelAppealDetails")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if ["UPHELD", "REVERSED", "WITHDRAWN"].contains(flow.appealStatus) {
                Text("status.closed", tableName: "NativeChannelAppealDetails").font(.footnote)
            }
            Text("result.acceptedNotReversed", tableName: "NativeChannelAppealDetails")
                .font(.footnote).foregroundStyle(.secondary)
        } header: { Text("progress.title", tableName: "NativeChannelAppealDetails") }
    }
    @ViewBuilder private var appealDetailsSection: some View {
        if let details = flow.appealDetails {
            Section {
                originalFact("reason", details.reason)
                originalFact("submittedAt", details.submittedAt)
                originalFact("decidedAt", details.decidedAt)
                originalFact("withdrawnAt", details.withdrawnAt)
                originalFact("dueAt", details.dueAt)
                originalFact("slaDueAt", details.slaDueAt)
            } header: { Text("facts", tableName: "NativeChannelAppealDetails") }
            Section {
                if let count = details.evidenceCount {
                    LabeledContent { Text(verbatim: String(count)) } label: { Text("evidenceCount", tableName: "NativeChannelAppealDetails") }
                }
                ForEach(details.evidence) { item in
                    VStack(alignment: .leading) {
                        Text(item.supplement ? "supplement" : "originalEvidence", tableName: "NativeChannelAppealDetails").font(.subheadline)
                        if let text = item.text { Text(verbatim: text).textSelection(.enabled) }
                        if !item.messageIDs.isEmpty {
                            LabeledContent { Text(verbatim: item.messageIDs.joined(separator: ", ")) } label: { Text("messageReferences", tableName: "NativeChannelAppealDetails") }
                        }
                        if let count = item.attachmentCount {
                            LabeledContent { Text(verbatim: String(count)) } label: { Text("attachmentReferences", tableName: "NativeChannelAppealDetails") }
                            Text("attachmentsNotOpened", tableName: "NativeChannelAppealDetails").font(.subheadline)
                        }
                        if item.text == nil && item.messageIDs.isEmpty && item.attachmentCount == nil { Text("unsupportedEvidence", tableName: "NativeChannelAppealDetails") }
                    }
                }
                if details.evidenceUnavailable { Text("evidenceUnavailable", tableName: "NativeChannelAppealDetails") }
                if details.evidence.isEmpty && !details.evidenceUnavailable { Text("noTextEvidence", tableName: "NativeChannelAppealDetails") }
            } header: { Text("materials", tableName: "NativeChannelAppealDetails") }
            Section {
                ForEach(details.timeline) { item in
                    VStack(alignment: .leading) {
                        if let event = item.event { Text(verbatim: event).font(.subheadline) }
                        originalFact("eventAt", item.at)
                        if let reason = item.reason { Text(verbatim: reason) }
                    }
                }
                if details.timelineUnavailable { Text("timelineUnavailable", tableName: "NativeChannelAppealDetails") }
                else if details.timeline.isEmpty { Text("noTimeline", tableName: "NativeChannelAppealDetails") }
            } header: { Text("timeline", tableName: "NativeChannelAppealDetails") }
        }
    }
    private func originalFact(_ key: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(key), tableName: "NativeChannelAppealDetails")
                .font(.subheadline).foregroundStyle(.secondary)
            if let value { Text(verbatim: value).textSelection(.enabled) }
            else { Text("unknown", tableName: "NativeChannelAppealDetails") }
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private var actionFactsSection: some View {
        Section {
            if let facts = flow.actionFacts {
                fact("channel.actionFacts.type", facts.type)
                fact("channel.actionFacts.status", facts.status)
                fact("channel.actionFacts.reasonCode", facts.reasonCode)
                fact("channel.actionFacts.scopeType", facts.scopeType)
                fact("channel.actionFacts.scopeID", facts.scopeID)
                fact("channel.actionFacts.startsAt", facts.startsAt)
                fact("channel.actionFacts.expiresAt", facts.expiresAt)
                fact("channel.actionFacts.durationSeconds", facts.durationSeconds.map { String($0) })
                Text("channel.actionFacts.noTrustedCountdown", tableName: "NativeChannelAppealDetails")
                    .font(.footnote)
            } else if flow.actionFactsUnavailable {
                Text("channel.actionFacts.unavailable", tableName: "NativeChannelAppealDetails")
            }
        } header: {
            Text("channel.actionFacts.title", tableName: "NativeChannelAppealDetails")
        }
    }
    private func fact(_ key: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(key), tableName: "NativeChannelAppealDetails").font(.subheadline)
            if let value { Text(verbatim: value).textSelection(.enabled) }
            else { Text("channel.actionFacts.unknown", tableName: "NativeChannelAppealDetails") }
        }
    }
}

// Presentation keys only. Server values and request identity are never translated.
@MainActor enum NativeChannelAppealPresentation {
    static func operationTitleKey(_ operation: NativeChannelAppealFlow.Operation?) -> String {
        switch operation {
        case .submit: "operation.submit"
        case .evidence: "operation.evidence"
        case .withdraw: "operation.withdraw"
        case nil: "operation.original"
        }
    }
    static func statusTitleKey(_ status: String) -> String {
        switch status {
        case "PENDING": "status.PENDING"
        case "REVIEWING": "status.REVIEWING"
        case "UPHELD": "status.UPHELD"
        case "REVERSED": "status.REVERSED"
        case "WITHDRAWN": "status.WITHDRAWN"
        default: "status.unknown"
        }
    }
}
