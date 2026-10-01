import SwiftUI
import Observation

struct PlayLoadIssue {
    let titleKey: String
    let detailKey: String
    let message: String?
    let retryable: Bool
    init(_ error: Error) {
        message = (error as? PlayFailure)?.message
        if error as? APIError == .notConfigured {
            titleKey = "play.unconfigured"; detailKey = "play.unconfigured.detail"; retryable = false
        } else if error as? APIError == .unauthorized || (error as? PlayFailure)?.isUnauthorized == true {
            titleKey = "play.expired"; detailKey = "play.expired.detail"; retryable = false
        } else if (error as? PlayFailure)?.needsPass == true {
            titleKey = "play.passRequired"; detailKey = "play.passRequired.detail"; retryable = false
        } else if error as? APIError == .invalidRequest {
            titleKey = "play.missing"; detailKey = "play.missing.detail"; retryable = false
        } else {
            titleKey = "play.loadFailed"; detailKey = "play.loadFailed.detail"; retryable = true
        }
    }
}

struct PlayIssueView: View {
    let issue: PlayLoadIssue
    var retry: (() -> Void)? = nil
    var body: some View {
        ContentUnavailableView {
            Label(LocalizedStringKey(issue.titleKey), systemImage: "exclamationmark.circle")
        } description: {
            if let message = issue.message, !message.isEmpty { Text(verbatim: message) }
            else { Text(LocalizedStringKey(issue.detailKey)) }
        } actions: {
            if issue.retryable, let retry {
                Button("play.retry", action: retry).accessibilityIdentifier("play.retry")
            }
        }
    }
}

extension PlaySessionAvailability {
    var titleKey: String {
        switch self {
        case .registrationRequired: return "play.registrationRequired"
        case .empty: return "play.empty"
        case .completed: return "play.completed"
        case .unavailable: return "play.unavailable"
        case .unknown: return "play.unknown"
        case .active: return "play.active"
        }
    }
    var detailKey: String { titleKey + ".detail" }
}

extension PlayAnswerAvailability {
    var detailKey: String {
        switch self {
        case .text, .choice: return "play.answer.instructions"
        case .completed: return "play.node.completed"
        case .locked: return "play.node.locked"
        case .sessionUnavailable: return "play.unavailable.detail"
        case .arrivalRequired: return "play.answer.arrivalRequired"
        case .unsupported: return "play.answer.unsupported"
        case .advancedRequired: return "play.answer.advancedRequired"
        case .branchReadOnly: return "play.answer.branchReadOnly"
        case .missingQuestion: return "play.answer.missingQuestion"
        case .mediaUnavailable: return "play.answer.mediaUnavailable"
        }
    }
}

@Observable @MainActor
final class PlayViewModel {
    let reader: any PlayReading
    private(set) var snapshot: PlaySnapshot?
    private(set) var loadedIdentity: PlayReadIdentity?
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var issue: PlayLoadIssue?
    private(set) var actionIssue: PlayLoadIssue?
    private(set) var receipt: PlayAnswerReceipt?
    private(set) var needsProgressCheck = false
    private var generation: UInt64 = 0
    private var issueIdentity: PlayReadIdentity?
    private var receiptIdentity: PlayReadIdentity?
    var visibleIssue: PlayLoadIssue? { issueIdentity != nil && issueIdentity == reader.identity ? issue : nil }
    var visibleReceipt: PlayAnswerReceipt? { receiptIdentity != nil && receiptIdentity == reader.identity ? receipt : nil }
    init(reader: any PlayReading) { self.reader = reader }
    var visibleSnapshot: PlaySnapshot? {
        loadedIdentity != nil && loadedIdentity == reader.identity ? snapshot : nil
    }
    func invalidate() {
        generation &+= 1; snapshot = nil; loadedIdentity = nil
        issue = nil; actionIssue = nil; receipt = nil; needsProgressCheck = false
        isLoading = false; isSubmitting = false
    }
    func load(keepingReceipt: Bool = false) async {
        guard !isSubmitting else { return }
        generation &+= 1
        let request = generation, identity = reader.identity
        snapshot = nil; loadedIdentity = nil; issue = nil; isLoading = true
        if !keepingReceipt { receipt = nil; actionIssue = nil }
        defer { if generation == request { isLoading = false } }
        guard reader.isConfigured, identity != nil, reader.scope.isValid else { return }
        do {
            let result = try await reader.playSession()
            guard current(request, identity), result.scope == reader.scope else { return }
            snapshot = result; loadedIdentity = identity; actionIssue = nil
            needsProgressCheck = reader.supportsAnswerSubmission && !reader.canSubmitAnswer
        } catch is CancellationError {} catch {
            guard current(request, identity) else { return }
            issue = PlayLoadIssue(error); issueIdentity = identity
        }
    }
    func submit(nodeID: Int, answer: String) async {
        guard !isLoading, !isSubmitting, reader.canSubmitAnswer,
              let snapshot = visibleSnapshot else { return }
        do { try snapshot.validateAnswer(nodeID: nodeID, answer: answer) } catch { return }
        generation &+= 1
        let request = generation, identity = loadedIdentity
        isSubmitting = true; receipt = nil; actionIssue = nil; needsProgressCheck = true
        defer { if generation == request { isSubmitting = false } }
        do {
            let result = try await reader.submitAnswer(nodeID: nodeID, answer: answer)
            guard current(request, identity) else { return }
            receipt = result; receiptIdentity = identity; isSubmitting = false
            // Readback only; a successful answer never advances the UI speculatively.
            await load(keepingReceipt: true)
        } catch is CancellationError {
            if generation == request { isSubmitting = false }
        } catch {
            guard current(request, identity) else { return }
            actionIssue = PlayLoadIssue(error); isSubmitting = false
            // Preserve the server rejection; user may explicitly refresh. No auto-retry.
        }
    }
    private func current(_ request: UInt64, _ identity: PlayReadIdentity?) -> Bool {
        !Task.isCancelled && generation == request && identity != nil && reader.identity == identity
    }
}
