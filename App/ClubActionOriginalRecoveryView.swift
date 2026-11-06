import SwiftUI

/// Same-account immutable receipt only. Does not need current detail or authorize joining.
@MainActor struct ClubActionOriginalRecoveryView: View {
    let clubID: Int
    let identity: ClubReadIdentity
    let coordinator: ClubActionCoordinator
    @State private var revision: UInt64 = 0
    @State private var working = false
    @State private var checked = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        let _ = revision
        let state = coordinator.state(clubID: clubID)
        if coordinator.identity == identity, identity.isSignedIn {
            VStack(alignment: .leading, spacing: 8) {
                if case .outcomeUnknown = state {
                    Text("club.action.unknown")
                    Button { recover() } label: {
                        Text("club.admission.original.read", tableName: "ClubAdmissionRecovery")
                    }
                    .disabled(working || !coordinator.canRecoverOriginal(clubID: clubID))
                    .accessibilityIdentifier("club.admission.original.read")
                    if !coordinator.canRecoverOriginal(clubID: clubID) {
                        Text("club.action.unavailable").foregroundStyle(.secondary)
                    }
                } else if checked, case .acknowledged = state {
                    Text("club.admission.original.applied", tableName: "ClubAdmissionRecovery")
                        .accessibilityIdentifier("club.admission.original.applied")
                }
                if working { ProgressView() }
            }
            .padding(.horizontal)
            .background(.regularMaterial)
            .onDisappear { revision &+= 1; task?.cancel(); task = nil; working = false }
        }
    }
    private func recover() {
        guard !working, coordinator.identity == identity,
              coordinator.canRecoverOriginal(clubID: clubID) else { return }
        revision &+= 1
        let generation = revision, snapshot = identity
        working = true
        task = Task {
            _ = await coordinator.recoverOriginal(clubID: clubID, expectedIdentity: snapshot)
            guard !Task.isCancelled, revision == generation, coordinator.identity == snapshot else { return }
            working = false; checked = true; revision &+= 1
        }
    }
}
