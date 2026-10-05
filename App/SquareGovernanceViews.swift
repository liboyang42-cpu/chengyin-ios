import SwiftUI

@MainActor struct SquareGovernanceContext {
    let coordinator: SquareGovernanceCoordinator
    let access: any SquareGovernanceAccess
    let communityPostRead: Bool
    let openPost: (Int) -> Void
    let openDrafts: () -> Void
    let signIn: () -> Void
}
/// Normal Square/profile host embeds this entry in its existing NavigationStack.
@MainActor struct SquareGovernanceEntryView: View {
    let context: SquareGovernanceContext
    var body: some View {
        NavigationLink { SquareGovernanceView(context: context) } label: {
            Label("square.gov.title", systemImage: "checkmark.shield")
        }.accessibilityIdentifier("square.gov.entry")
    }
}
@MainActor struct SquareGovernanceView: View {
    let context: SquareGovernanceContext
    @State private var snapshot: SquareGovernanceSnapshot?
    @State private var loading = false
    @State private var message: String?
    @State private var review: SquareGovernanceReview?
    @State private var appeal: SquareEnforcement?
    @State private var reason = ""
    @State private var pendingAppeal: SquareGovernanceAction?
    @State private var enforcementPages = 1
    @State private var notificationPages = 1
    @State private var generation = UUID()
    var body: some View {
        List {
            if context.access.identity == nil {
                Button("square.gov.signIn", action: context.signIn).accessibilityIdentifier("square.gov.signIn")
            } else {
                if loading { ProgressView().accessibilityIdentifier("square.gov.loading") }
                if let message { Text(LocalizedStringKey(message)).accessibilityIdentifier("square.gov.message") }
                Button("square.gov.refresh") { Task { await reload() } }.disabled(loading)
                if let snapshot {
                    Button("square.gov.drafts", action: context.openDrafts)
                    preferenceSection(snapshot)
                    notificationSection(snapshot)
                    enforcementSection(snapshot)
                    commentSection(snapshot)
                }
            }
        }
        .navigationTitle("square.gov.title")
        .task { await reload() }
        .onChange(of: context.access.identity) { _, _ in
            generation = UUID(); snapshot = nil; review = nil; appeal = nil; pendingAppeal = nil; reason = ""; message = nil
            enforcementPages = 1; notificationPages = 1
            Task { await reload() }
        }
        .onDisappear { generation = UUID(); review = nil; appeal = nil; pendingAppeal = nil; reason = "" }
        .sheet(item: $appeal, onDismiss: {
            if let action = pendingAppeal { pendingAppeal = nil; prepare(action) }
        }) { record in
            NavigationStack {
                Form {
                    Text("square.gov.appealFacts")
                    TextField("square.gov.reason", text: $reason, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("square.gov.reason")
                    Text("\(reason.count)/1000")
                    Button("square.gov.review") {
                        pendingAppeal = .appeal(enforcementID: record.id, reason: reason)
                        appeal = nil
                    }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reason.count > 1000)
                }
                .navigationTitle("square.gov.appeal")
                .toolbar { Button("square.gov.cancel") { appeal = nil; reason = "" } }
            }
        }
        .sheet(item: $review) { item in
            NavigationStack {
                Form {
                    Text("square.gov.reviewWarning")
                    reviewDetails(item)
                    if !context.coordinator.service.allows(item.action) { Text("square.gov.liveDisabled") }
                    Button("square.gov.confirm") { Task { await confirm(item) } }
                        .disabled(loading || !context.coordinator.service.allows(item.action))
                        .accessibilityIdentifier("square.gov.confirm")
                    Button("square.gov.cancel") { review = nil }.disabled(loading)
                }.navigationTitle("square.gov.review")
            }.interactiveDismissDisabled(loading)
        }
    }
    @ViewBuilder private func preferenceSection(_ snapshot: SquareGovernanceSnapshot) -> some View {
        Section("square.gov.preferences") {
            ForEach(SquarePreference.allCases, id: \.rawValue) { preference in
                if let value = snapshot.preferences[preference.rawValue].bool {
                    Toggle(LocalizedStringKey("square.gov." + preference.rawValue), isOn: Binding(get: { value }, set: { prepare(.preferences([preference: $0])) }))
                        .disabled(loading).accessibilityIdentifier("square.gov.preference." + preference.rawValue)
                } else { Text("square.gov.unknownLocked") }
            }
            Label("square.gov.governanceAlways", systemImage: "lock.shield")
        }
    }
    @ViewBuilder private func notificationSection(_ snapshot: SquareGovernanceSnapshot) -> some View {
        Section("square.gov.notifications") {
            if snapshot.notifications.isEmpty { Text("square.gov.emptyNotifications") }
            ForEach(snapshot.notifications) { notice in
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey(notificationKey(notice.action)))
                    if let note = notice.publicNote, !note.isEmpty { Text(note) }
                    Text(LocalizedStringKey(notice.unread ? "square.gov.unread" : "square.gov.read"))
                    if notice.unread { Button("square.gov.markRead") { prepare(.markRead(notificationID: notice.id)) }.disabled(loading) }
                    if let postID = notice.postID, postID > 0 {
                        Button("square.gov.openPost") { context.openPost(postID) }.disabled(!context.communityPostRead)
                    }
                }
            }
            if snapshot.notifications.count >= notificationPages * 50 {
                Button("square.gov.moreNotifications") { notificationPages += 1; Task { await reload() } }.disabled(loading)
            }
        }
    }
    @ViewBuilder private func enforcementSection(_ snapshot: SquareGovernanceSnapshot) -> some View {
        Section("square.gov.enforcements") {
            if snapshot.enforcements.isEmpty { Text("square.gov.emptyEnforcements") }
            ForEach(snapshot.enforcements) { record in
                VStack(alignment: .leading) {
                    Text(record.type); Text(record.rule); Text(record.status)
                    if let status = record.appealStatus { Text(status) }
                    else if record.canRequestReview {
                        Button("square.gov.appeal") { reason = ""; appeal = record }.disabled(loading).accessibilityIdentifier("square.gov.appeal.\(record.id)")
                    }
                }
            }
            if snapshot.enforcements.count >= enforcementPages * 30 {
                Button("square.gov.moreEnforcements") { enforcementPages += 1; Task { await reload() } }.disabled(loading)
            }
        }
    }
    @ViewBuilder private func commentSection(_ snapshot: SquareGovernanceSnapshot) -> some View {
        Section("square.gov.comments") {
            Text("square.gov.commentRoles")
            ForEach(snapshot.comments) { comment in
                VStack(alignment: .leading) {
                    Text("#\(comment.postID) / #\(comment.id)")
                    Text(comment.approvalState ?? "UNKNOWN")
                    if comment.canApprove(snapshot.identity) {
                        Button("square.gov.approveComment") { prepare(.approveComment(postID: comment.postID, commentID: comment.id)) }.disabled(loading).accessibilityIdentifier("square.gov.approve.\(comment.id)")
                    }
                    if comment.canDelete(snapshot.identity) {
                        Button("square.gov.deleteComment", role: .destructive) { prepare(.deleteOwnComment(commentID: comment.id)) }.disabled(loading).accessibilityIdentifier("square.gov.delete.\(comment.id)")
                    }
                    if !comment.canApprove(snapshot.identity) && !comment.canDelete(snapshot.identity) { Text("square.gov.unknownLocked") }
                }
            }
        }
    }
    @ViewBuilder private func reviewDetails(_ review: SquareGovernanceReview) -> some View {
        Text("square.gov.account"); Text("#\(review.snapshot.identity.accountID)")
        switch review.action {
        case .appeal(let id, let reason): Text("square.gov.appeal"); Text("#\(id)"); Text(reason)
        case .markRead(let id): Text("square.gov.markRead"); Text("#\(id)")
        case .preferences(let values):
            ForEach(SquarePreference.allCases, id: \.rawValue) { key in
                if let value = values[key] { Text(LocalizedStringKey("square.gov." + key.rawValue)); Text(LocalizedStringKey(value ? "square.gov.enabled" : "square.gov.disabled")) }
            }
        case .approveComment(let post, let comment):
            Text("square.gov.approveComment"); Text("#\(post) / #\(comment)")
            Text("square.gov.version"); Text(String(review.snapshot.comments.first(where: { $0.id == comment })?.version ?? -1))
        case .deleteOwnComment(let id): Text("square.gov.deleteComment"); Text("#\(id)"); Text("square.gov.deleteWarning")
        }
    }
    private func notificationKey(_ action: String) -> String {
        let known = ["LIKE", "BOOKMARK", "COMMENT", "REPLY", "COMMENT_LIKE", "POST_MENTION", "APPROVED", "REMOVED", "APPEAL_SUBMITTED", "APPEAL_UPHELD", "APPEAL_REVERSED", "FEATURED", "FOLLOW", "GUIDELINE_UPDATED", "REPORT_RECEIVED"]
        return "square.gov.notice." + (action.hasPrefix("REPORT_STAGE_") ? "REPORT_STAGE" : (known.contains(action) ? action : "UNKNOWN"))
    }
    private func prepare(_ action: SquareGovernanceAction) {
        guard let snapshot else { return }
        do { review = try context.coordinator.prepare(action, snapshot: snapshot, access: context.access); message = nil }
        catch { message = failureKey(error) }
    }
    private func reload() async {
        generation = UUID()
        let ticket = generation
        loading = true; defer { if ticket == generation { loading = false } }
        do {
            let value = try await context.coordinator.load(access: context.access, enforcementPages: enforcementPages, notificationPages: notificationPages)
            guard ticket == generation else { return }; snapshot = value; message = nil
        } catch { guard ticket == generation else { return }; snapshot = nil; message = failureKey(error) }
    }
    private func confirm(_ item: SquareGovernanceReview) async {
        let ticket = generation
        loading = true; defer { if ticket == generation { loading = false } }
        do {
            _ = try await context.coordinator.confirm(item, access: context.access)
            guard ticket == generation else { return }; review = nil; reason = ""; message = "square.gov.acknowledged"
        } catch { guard ticket == generation else { return }; review = nil; message = failureKey(error) }
    }
    private func failureKey(_ error: Error) -> String {
        switch error as? SquareGovernanceFailure {
        case .signedOut: return "square.gov.signIn"
        case .disabled: return "square.gov.liveDisabled"
        case .staleReview: return "square.gov.stale"
        case .unknown, .outcomeLocked: return "square.gov.unknownOutcome"
        case .forbidden: return "square.gov.forbidden"
        default: return "square.gov.error"
        }
    }
}
