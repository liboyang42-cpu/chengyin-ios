import SwiftUI

/// Read-only local context. The saved source/draft revisions invalidate stale UI;
/// they do not prove which image the server's latest recorded submission identifies.
@MainActor enum ProfileCurrentReviewNoticeContext {
    static func key(model: ProfileEditModel, reader: ProfileCurrentReviewReader?, active: Bool) -> ProfileCurrentReviewReadKey? {
        guard active, !model.busy, !model.coordinator.isBusy, !model.avatarPresentationActive,
              model.draft.avatarReplacement == nil, model.confirmation == nil, model.coordinator.confirmation == nil,
              let snapshot = model.coordinator.currentAvatarReadSnapshot else { return nil }
        return reader?.key(snapshot: snapshot, editorID: model.avatarEditorID, lifetimeID: model.avatarLifetimeID,
                           draftRevision: model.avatarDraftRevision, readRevision: model.revision)
    }
}

@MainActor final class ProfileCurrentReviewNoticeOwner: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var revision: UInt64 = 0
    private let flow = ProfileCurrentReviewFlow()
    private var visible = false
    private var sceneActive = false
    func setVisible(_ value: Bool, sceneActive: Bool) {
        visible = value; self.sceneActive = sceneActive; updateActivity()
    }
    func setSceneActive(_ value: Bool) { sceneActive = value; updateActivity() }
    private func updateActivity() {
        let next = visible && sceneActive
        guard active != next else { return }
        active = next
        if !next { retire() }
    }
    func retire() { flow.invalidate(); revision &+= 1 }
    func fact(for key: ProfileCurrentReviewReadKey?) -> ProfileCurrentReviewRejectedFact? {
        guard active else { return nil }
        return flow.rejectedFact(for: key)
    }
    func load(reader: ProfileCurrentReviewReader, snapshot: ProfileEditSnapshot, key: ProfileCurrentReviewReadKey,
              currentKey: @escaping () -> ProfileCurrentReviewReadKey?) async {
        guard active else { return }
        // Clear old verdict synchronously before starting any new read.
        retire()
        await flow.load(reader: reader, snapshot: snapshot, key: key, currentKey: currentKey)
        revision &+= 1
    }
}

/// The stable editor owns the read even when there is no rejected row. Keeping
/// lifecycle on the editor avoids invisible Form rows and duplicate section tasks.
@MainActor struct ProfileCurrentReviewNoticeLifecycle: ViewModifier {
    @ObservedObject var model: ProfileEditModel
    let reader: ProfileCurrentReviewReader?
    @ObservedObject var owner: ProfileCurrentReviewNoticeOwner
    @Environment(\.scenePhase) private var scenePhase
    private var key: ProfileCurrentReviewReadKey? {
        ProfileCurrentReviewNoticeContext.key(model: model, reader: reader, active: owner.active && scenePhase == .active)
    }
    func body(content: Content) -> some View {
        content
            .onAppear { owner.setVisible(true, sceneActive: scenePhase == .active) }
            .onDisappear { owner.setVisible(false, sceneActive: scenePhase == .active); owner.retire() }
            .onChange(of: scenePhase) { _, phase in owner.setSceneActive(phase == .active) }
            .task(id: key) {
                owner.retire()
                guard let key, let reader, let snapshot = model.coordinator.currentAvatarReadSnapshot else { return }
                await owner.load(reader: reader, snapshot: snapshot, key: key, currentKey: {
                    ProfileCurrentReviewNoticeContext.key(model: model, reader: reader, active: owner.active)
                })
            }
    }
}

/// Normal mini requirement is one REJECTED notice, not a moderation page. No
/// pending/approved labels, unavailable verdict, image badge, or inferred removal.
@MainActor struct ProfileCurrentReviewNotice: View {
    @ObservedObject var model: ProfileEditModel
    let reader: ProfileCurrentReviewReader?
    @ObservedObject var owner: ProfileCurrentReviewNoticeOwner
    @Environment(\.scenePhase) private var scenePhase
    private var fact: ProfileCurrentReviewRejectedFact? {
        owner.fact(for: ProfileCurrentReviewNoticeContext.key(model: model, reader: reader,
            active: owner.active && scenePhase == .active))
    }
    var body: some View {
        if let fact {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label { Text("profile.currentReview.rejected", tableName: "ProfileCurrentReview") }
                        icon: { Image(systemName: "exclamationmark.circle").accessibilityHidden(true) }
                    Text(LocalizedStringKey(fact.liveWhenRead ? "profile.currentReview.liveWhenRead" : "profile.currentReview.notLiveWhenRead"), tableName: "ProfileCurrentReview")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("profile.currentReview.notImageBinding", tableName: "ProfileCurrentReview")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitive()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("profile.currentReview.rejected")
            }
        }
    }
}
