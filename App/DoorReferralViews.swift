import SwiftUI

@MainActor struct DoorInviterSheet: View {
    let session: DoorReferralSession
    let queue: DoorReferralQueue
    let enabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var busy = false
    @State private var review = false
    @State private var errorKey: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("door.inviter.once")
                    TextField("door.inviter.placeholder", text: $input)
                        .keyboardType(.numberPad).accessibilityIdentifier("door.inviter.input")
                        .disabled(busy)
                    if let errorKey { Text(LocalizedStringKey(errorKey)).foregroundStyle(.red).accessibilityIdentifier("door.inviter.error") }
                    if !enabled { Text("door.disabled") }
                    Button("door.inviter.review") { review = true }
                        .disabled(!enabled || busy || !session.restored || session.accountID == nil || DoorParsing.inviter(input) == nil || DoorParsing.inviter(input) == session.accountID)
                        .accessibilityIdentifier("door.inviter.review")
                    if busy { ProgressView() }
                }
            }
            .navigationTitle("door.inviter.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("door.close") { task?.cancel(); dismiss() } } }
            .confirmationDialog("door.inviter.once", isPresented: $review, titleVisibility: .visible) {
                Button("door.inviter.confirm") {
                    let scope = session; busy = true; errorKey = nil
                    task = Task { @MainActor in
                        do { try await queue.manualBind(input)
                            guard !Task.isCancelled, scope == session else { return }; dismiss()
                        } catch DoorReferralFailure.rejected { errorKey = "door.inviter.remoteFailure" }
                        catch DoorReferralFailure.disabled { errorKey = "door.disabled" }
                        catch DoorReferralFailure.invalid { errorKey = "door.inviter.invalid" }
                        catch { errorKey = "door.inviter.unknown" }
                        busy = false
                    }
                }
                Button("door.cancel", role: .cancel) {}
            }
        }
        .onChange(of: session) { _, _ in task?.cancel(); review = false; input = ""; dismiss() }
        .onDisappear { task?.cancel() }
        .interactiveDismissDisabled(busy)
    }
}

/// Additive door landing shell. Host owns navigation and the current session snapshot.
@MainActor struct DoorEntrySheet: View {
    let intent: DoorIntent
    let session: DoorReferralSession
    let coordinator: DoorEntryCoordinator
    let onDestination: (DoorDestination, String?) -> Void
    @State private var received: DoorIntent?
    var body: some View {
        VStack(spacing: 16) { ProgressView(); Text("door.resolving") }
            .accessibilityIdentifier("door.entry.loading")
            .task(id: TaskIdentity(intent: intent, session: session)) {
                coordinator.updateSession(session)
                if received != intent { coordinator.receive(intent); received = intent }
                await coordinator.resolve()
                guard !Task.isCancelled, let destination = coordinator.destination else { return }
                onDestination(destination, coordinator.failure)
            }
            .onDisappear { coordinator.cancel() }
    }
    private struct TaskIdentity: Equatable, Hashable {
        let intent: DoorIntent
        let session: DoorReferralSession
        func hash(into hasher: inout Hasher) { hasher.combine(intent.scene); hasher.combine(intent.inviter); hasher.combine(session.epoch); hasher.combine(session.accountID); hasher.combine(session.restored) }
    }
}

#if DEBUG
@MainActor struct DoorReferralFixtureView: View {
    @State private var text = "ABCDEF0123456789ABCDEF0123456789"
    var body: some View {
        NavigationStack {
            Form {
                Text("door.fixture.offline")
                TextField("door.fixture.scene", text: $text).accessibilityIdentifier("door.fixture.scene")
                Text(DoorParsing.scene(text) ?? "invalid").accessibilityIdentifier("door.fixture.normalized")
                Text(String(describing: DoorScanResult(action: "play", topicID: 42).destination))
            }.navigationTitle("door.fixture.title")
        }
    }
}
#endif
