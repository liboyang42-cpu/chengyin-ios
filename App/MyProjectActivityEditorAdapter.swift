import SwiftUI

/// Host for one existing activity. The approved factory is `AppSession.activityEditingController(id:)`.
/// Inputs: the server activity id, the current publishing session, and fresh `ActivityEditingGrants`
/// from `activityEditingApproval`. Output: `ActivityEditingController`, or nil when that session
/// cannot build one. `ActivityEditingService.canRead` / `canUpdate` still decide load and write.
/// Source: `Core/ActivityEditing.swift`, `App/AppSession.swift`.
/// A nil factory shows unavailable copy. It does not open the activity detail screen or a local form.
@MainActor struct MyProjectActivityEditorDestination: View {
    let request: MyProjectActivityEditorRequest
    let authenticated: Bool
    let currentScope: UUID
    let publishingEpoch: UUID?
    let browseOnly: Bool
    let grants: ActivityEditingGrants
    var makeEditor: ((Int) -> ActivityEditingController?)?
    var makeCover: (() -> ActivityCoverService?)?
    let onAcknowledged: (MyProjectActivityEditorReturnToken) -> Void
    let onRevoke: () -> Void
    @State private var controller: ActivityEditingController?
    @State private var resolved = false
    @State private var revoked = false
    @State private var deliveredReceipt = false
    @State private var openedEpoch: UUID?
    @State private var openedGrants: ActivityEditingGrants?

    var body: some View {
        Group {
            if revoked || epochLost {
                Text("revoked \(request.activityID)", tableName: "MyProjectActivityEditor")
                    .accessibilityIdentifier("myProject.state.activityEditorRevoked")
            } else if let controller {
                ActivityEditingView(owner: controller, makeActivityCover: makeCover)
                    .id(editorIdentity)
                    .background {
                        MyProjectActivitySaveReceiptObserver(controller: controller, onReceipt: deliverReceipt)
                    }
                    .accessibilityIdentifier("myProject.state.activityEditor")
            } else if resolved {
                Text("unavailable \(request.activityID)", tableName: "MyProjectActivityEditor")
                    .accessibilityIdentifier("myProject.state.activityEditorUnavailable")
            } else {
                ProgressView().accessibilityIdentifier("myProject.state.activityEditorLoading")
            }
        }
        .onAppear(perform: resolve)
        .onChange(of: currentScope) { _, _ in revokeIfNeeded() }
        .onChange(of: authenticated) { _, _ in revokeIfNeeded() }
        .onChange(of: publishingEpoch) { _, _ in revokeIfNeeded() }
        .onChange(of: browseOnly) { _, _ in revokeIfNeeded() }
        .onChange(of: grants) { _, _ in revokeIfNeeded() }
    }

    private var editorIdentity: String { "\(request.activityID):\(openedEpoch?.uuidString ?? "")" }
    private var epochLost: Bool { openedEpoch != nil && openedEpoch != publishingEpoch }
    private var grantsLost: Bool { openedGrants != nil && openedGrants != grants }
    private var sameAccount: Bool {
        MyProjectActivityEditorPolicy.mayResolveFactory(requestScope: request.readerScope, currentScope: currentScope, authenticated: authenticated)
    }

    private func resolve() {
        guard !resolved, !revoked else { return }
        resolved = true
        openedEpoch = publishingEpoch
        openedGrants = grants
        guard sameAccount, publishingEpoch != nil, !browseOnly else { return }
        controller = makeEditor?(request.activityID)
    }

    /// Account change or a new publishing epoch drops the controller that was built for the old session.
    /// The next open calls the factory again, so a persisted draft can return without the old grants.
    private func revokeIfNeeded() {
        guard !revoked, controller != nil, epochLost || !sameAccount || browseOnly || grantsLost else { return }
        revoked = true
        controller = nil
        onRevoke()
    }

    private func deliverReceipt() {
        guard !deliveredReceipt, !revoked, sameAccount, !epochLost,
              let controller, MyProjectActivityEditorPolicy.isServerSaveReceipt(controller.status) else { return }
        deliveredReceipt = true
        onAcknowledged(.init(readerScope: request.readerScope, activityID: request.activityID))
    }
}

@MainActor private struct MyProjectActivitySaveReceiptObserver: View {
    @ObservedObject var controller: ActivityEditingController
    let onReceipt: () -> Void
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: controller.status) { _, status in
                if MyProjectActivityEditorPolicy.isServerSaveReceipt(status) { onReceipt() }
            }
    }
}

/// Activity detail write entry. Browse-only merchant scope hides it; topic routes are unchanged.
@MainActor struct MyProjectActivityDetailWriteToolbar: View {
    @ObservedObject var session: AppSession
    let activityID: Int
    @Environment(\.myProjectMerchantScopeAccess) private var merchantScopeAccess
    var body: some View {
        if !merchantScopeAccess.isBrowseOnly,
           let resource = try? PublishedResource(kind: .activity, value: activityID) {
            PublisherLifecycleNavigationLink(session: session, resource: resource)
        }
    }
}
