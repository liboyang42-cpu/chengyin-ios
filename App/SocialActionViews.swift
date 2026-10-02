import SwiftUI

public enum SocialEditorPurpose: String, Identifiable {
    case createPost, editPost, comment, like, bookmark, commentLike, report, toggleFollow, startChat
    public var id: String { rawValue }
}
@MainActor struct SocialActionEditorView: View {
    let purpose: SocialEditorPurpose
    let target: SocialActionTarget
    let coordinator: SocialActionCoordinator
    var initialText = ""
    var contentGeneration: SquareContentGeneration = .legacySquare
    var initialEnabled = true
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var enabled = true
    @State private var legacyReportReason: String?
    private let legacyReasons = ["含有违法违规内容", "色情低俗", "人身攻击或骚扰", "虚假信息或欺诈", "侵犯他人权益", "其他"]
    private var needsLegacyReason: Bool { purpose == .report && target.commentID == nil && contentGeneration == .legacySquare }
    @State private var ownerID = UUID()
    @State private var sessionIdentity: SocialAccountIdentity?
    @State private var review: SocialActionReview?
    @State private var heldReview: SocialActionReview?
    @State private var issue: Error?
    @State private var preparing = false
    @State private var revision = 0
    @State private var initialized = false
    @State private var confirmsDiscard = false
    @FocusState private var textFocused: Bool
    private var hasDraft: Bool { hasText && text != initialText }
    private var hasText: Bool { [.createPost, .editPost, .comment].contains(purpose) }
    private var state: SocialActionState { _ = revision; return coordinator.state(target: target, generation: contentGeneration) }
    private var title: String { "social.editor.\(purpose.rawValue)" }
    var body: some View {
        Form {
            Section {
                if coordinator.availability == .syntheticOnly { Text("social.offline").font(.footnote) }
                else if coordinator.availability(for: command(), target: target) == .disabled { Text("social.writesDisabled").font(.footnote) }
                if coordinator.identity.accountID == nil { SocialIssueView(error: SocialActionBlock.signIn) }
                if let memberID = target.memberID { LabeledContent("social.targetMember", value: String(memberID)) }
                if let postID = target.postID { LabeledContent("social.targetPost", value: String(postID)) }
                if let commentID = target.commentID { LabeledContent("social.targetComment", value: String(commentID)) }
            }
            if hasText {
                Section("social.text") {
                    TextEditor(text: $text).frame(minHeight: 160).accessibilityLabel("social.text")
                        .accessibilityIdentifier("social.editor.text").focused($textFocused).disabled(state.locksForm)
                    if purpose == .editPost { Text("social.editPreservesMedia").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            if (purpose == .like && contentGeneration == .communityV1) || purpose == .bookmark || (purpose == .commentLike && contentGeneration == .communityV1) {
                Section {
                    Toggle("social.actionEnabled", isOn: $enabled).disabled(state.locksForm)
                    Text("social.explicitActionHint").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if purpose == .like && contentGeneration == .legacySquare { Section { Text("squareReport.legacyLikeHint").font(.footnote) } }
            if purpose == .toggleFollow { Section { Text("social.followToggleHint").font(.footnote) } }
            if purpose == .startChat { Section { Text("social.startChatHint").font(.footnote) } }
            if purpose == .commentLike && contentGeneration != .communityV1 { Section { Text("social.toggleHint").font(.footnote) } }
            if purpose == .report {
                Section {
                    if needsLegacyReason {
                        Picker("squareReport.reason", selection: $legacyReportReason) {
                            Text("squareReport.chooseReason").tag(String?.none)
                            ForEach(Array(legacyReasons.enumerated()), id: \.offset) { index, label in
                                Text(LocalizedStringKey("squareReport.legacyReason." + String(index))).tag(Optional(label))
                            }
                        }.accessibilityIdentifier("social.editor.legacyReportReason")
                        Text("squareReport.legacyHint").font(.footnote)
                    } else { Text("social.reportHint").font(.footnote) }
                }
            }
            if let issue { SocialIssueView(error: issue) }
            SocialActionStateView(state: state)
            Section {
                Button("social.review") { textFocused = false; Task { await prepare() } }
                    .disabled(preparing || state.locksForm || coordinator.identity.accountID == nil || (hasText && SocialText.nonempty(text) == nil) || (needsLegacyReason && legacyReportReason == nil))
                    .accessibilityIdentifier("social.editor.review")
            }
        }
        .appNavigationTitle(key: title).privacySensitive()
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.close") {
                    textFocused = false
                    if hasDraft { confirmsDiscard = true } else { dismiss() }
                }.accessibilityIdentifier("social.editor.close")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("action.done") { textFocused = false }.accessibilityIdentifier("social.editor.keyboardDone")
            }
        }
        .interactiveDismissDisabled(hasDraft || preparing)
        .confirmationDialog("social.editor.discardTitle", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("social.editor.discard", role: .destructive) { text = ""; dismiss() }
                .accessibilityIdentifier("social.editor.discard")
            Button("social.editor.keepEditing", role: .cancel) {}
                .accessibilityIdentifier("social.editor.keepEditing")
        } message: { Text("social.editor.discardMessage") }
        .onAppear {
            sessionIdentity = coordinator.identity
            if !initialized { text = initialText; enabled = initialEnabled; initialized = true }
        }
        .onChange(of: coordinator.identity) { _, _ in clearForSessionChange() }
        .onDisappear {
            // A nested review is still this editor's presentation, not an abandoned draft.
            guard review == nil else { return }
            textFocused = false; confirmsDiscard = false
            if let identity = sessionIdentity { coordinator.leaveScreen(target: target, expectedIdentity: identity, ownerID: ownerID, generation: contentGeneration) }
            text = ""; review = nil; heldReview = nil; preparing = false
        }
        .sheet(item: $review, onDismiss: {
            if let heldReview { coordinator.cancel(heldReview) }; heldReview = nil; revision += 1
        }) { item in
            NavigationStack {
                SocialActionReviewView(review: item, coordinator: coordinator, onClose: { review = nil; revision += 1 })
            }
        }
        .accessibilityIdentifier("social.editor")
    }
    private func command() -> SocialActionCommand {
        switch purpose {
        case .createPost: return .newPost(text: text)
        case .editPost: return .editPost(text: text)
        case .comment: return contentGeneration == .communityV1 ? .communityComment(text: text, requestID: UUID().uuidString) : .comment(text: text)
        case .like: return contentGeneration == .legacySquare ? .legacyPostLike : .action(.like, enabled: enabled)
        case .bookmark: return .action(.bookmark, enabled: enabled)
        case .commentLike: return contentGeneration == .communityV1 ? .communityCommentLike(enabled: enabled, requestID: UUID().uuidString) : .toggleCommentLike
        case .report: return needsLegacyReason ? .legacyPostReport(reason: legacyReportReason ?? "") : .report
        case .toggleFollow: return .toggleFollow
        case .startChat: return .startChat
        }
    }
    private func prepare() async {
        guard !preparing else { return }
        let identity = coordinator.identity; preparing = true; issue = nil
        defer { preparing = false; revision += 1 }
        do {
            let value = try await coordinator.prepare(command(), target: target, ownerID: ownerID, expectedIdentity: identity)
            guard !Task.isCancelled, coordinator.identity == identity, sessionIdentity == identity else { coordinator.cancel(value); return }
            heldReview = value; review = value
        } catch { if coordinator.identity == identity, sessionIdentity == identity { issue = error } }
    }
    private func clearForSessionChange() {
        if let heldReview { coordinator.cancel(heldReview) }
        coordinator.synchronizeSession(); textFocused = false; confirmsDiscard = false
        text = ""; legacyReportReason = nil; review = nil; heldReview = nil; issue = nil
        sessionIdentity = coordinator.identity; revision += 1
    }
}
@MainActor private struct SocialActionReviewView: View {
    let review: SocialActionReview
    let coordinator: SocialActionCoordinator
    let onClose: () -> Void
    @State private var busy = false
    @State private var revision = 0
    private var current: Bool { coordinator.identity == review.identity }
    private var state: SocialActionState { _ = revision; return coordinator.state(target: review.target, generation: review.command.requiredGeneration) }
    var body: some View {
        List {
            if !current { SocialIssueView(error: SocialActionBlock.changed) }
            else {
                Section("social.reviewTarget") {
                    if let account = review.identity.accountID { LabeledContent("social.currentAccount", value: String(account)) }
                    if let profile = review.snapshot.profile { LabeledContent("social.targetMember", value: String(profile.id)); if let name = profile.nickname { Text(verbatim: name) } }
                    if let post = review.snapshot.post { LabeledContent("social.targetPost", value: String(post.id)) }
                    if let comment = review.snapshot.comment {
                        LabeledContent("social.targetComment", value: String(comment.id))
                        if let body = comment.contents { Text(verbatim: body) }
                    }
                }
                if let text = review.command.text { Section("social.text") { Text(verbatim: text).textSelection(.enabled) } }
                Section {
                    switch review.command {
                    case .postAction(let action, let enabled, _):
                        Text(LocalizedStringKey(action == .like ? "social.editor.like" : "social.editor.bookmark"))
                        Text(LocalizedStringKey(enabled ? "social.willEnable" : "social.willDisable"))
                    case .communityCommentLike(let enabled, _):
                        Text(LocalizedStringKey(enabled ? "social.willEnable" : "social.willDisable"))
                    case .toggleCommentLike: Text("social.toggleHint")
                    case .report: Text("social.reportHint")
                    case .legacyPostLike: Text("squareReport.legacyLikeHint")
                    case .legacyPostReport(let reason): Text("squareReport.legacyHint"); Text(verbatim: reason)
                    case .toggleFollow:
                        Text("social.followToggleHint")
                        if let followed = review.snapshot.profile?.isFollowed { Text(LocalizedStringKey(followed ? "social.willDisable" : "social.willEnable")) }
                    case .startChat: Text("social.startChatHint")
                    default: Text("social.moderationHint")
                    }
                    if coordinator.availability(for: review.command, target: review.target) == .disabled { Text("social.writesDisabled") }
                }
                SocialActionStateView(state: state)
                if coordinator.availability == .syntheticOnly {
                    Button("social.simulate") {
                        busy = true
                        Task { await coordinator.confirm(review); busy = false; revision += 1 }
                    }.disabled(busy || state != .reviewing).accessibilityIdentifier("social.review.confirm")
                } else if coordinator.availability(for: review.command, target: review.target) == .approved {
                    Button("social.submit") {
                        busy = true
                        Task { await coordinator.confirm(review); busy = false; revision += 1 }
                    }.disabled(busy || state != .reviewing).accessibilityIdentifier("social.review.confirm")
                } else {
                    Button("social.submit") {}.disabled(true).accessibilityIdentifier("social.review.disabled")
                }
            }
        }.appNavigationTitle("social.review")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close", action: onClose).disabled(busy).accessibilityIdentifier("social.review.close") } }
            .interactiveDismissDisabled(busy)
            .onChange(of: coordinator.identity) { _, _ in coordinator.synchronizeSession(); revision += 1 }
            .privacySensitive().accessibilityIdentifier("social.review")
    }
}
private struct SocialActionStateView: View {
    let state: SocialActionState
    var body: some View {
        Group {
            switch state {
            case .idle, .reviewing: EmptyView()
            case .preparing, .preflighting, .submitting: ProgressView("social.loading")
            case .notSent: Text("social.notSent").accessibilityIdentifier("social.state.notSent")
            case .rejected: Text("social.rejected").accessibilityIdentifier("social.state.rejected")
            case .outcomeUnknown: Text("social.unknown").accessibilityIdentifier("social.state.unknown")
            case .acknowledged(let receipt):
                Text(LocalizedStringKey(receipt.synthetic ? "social.simulated" : "social.acknowledged")).accessibilityIdentifier("social.state.acknowledged")
            }
        }.font(.footnote).accessibilityElement(children: .combine)
    }
}
