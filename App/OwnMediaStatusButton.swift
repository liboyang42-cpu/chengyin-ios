import SwiftUI

/// Explicit status read only; a confirmed response refreshes the existing list.
@MainActor struct OwnMediaStatusButton: View {
    let reader: any OwnMediaStatusReading
    let assetID: Int64
    let onRead: () -> Void
    private let capturedScope: UUID
    @Environment(\.scenePhase) private var scenePhase
    @State private var active = false
    @State private var retired = false
    @State private var busy = false
    @State private var failed = false
    @State private var generation = UUID()
    @State private var task: Task<Void, Never>?

    init(reader: any OwnMediaStatusReading, assetID: Int64, onRead: @escaping () -> Void) {
        self.reader = reader; self.assetID = assetID; self.onRead = onRead
        capturedScope = reader.scope
    }
    private var available: Bool {
        !retired && active && scenePhase == .active && reader.scope == capturedScope &&
            reader.isSignedIn && reader.isStatusAvailable
    }
    var body: some View {
        VStack(alignment: .leading) {
            Button { read() } label: {
                Text("check", tableName: "OwnMediaStatus")
            }
            .disabled(!available || busy)
            .accessibilityIdentifier("member.media.status.\(assetID)")
            if busy { ProgressView().accessibilityIdentifier("member.media.status.loading.\(assetID)") }
            if failed && available {
                Text("failed", tableName: "OwnMediaStatus").foregroundStyle(.secondary)
                    .accessibilityIdentifier("member.media.status.failed.\(assetID)")
            }
        }
        .onAppear { active = true }
        .onDisappear { active = false; cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancel() } }
        .onChange(of: reader.scope) { _, scope in
            if scope != capturedScope { retired = true; cancel() }
        }
        .onChange(of: reader.isStatusAvailable) { _, allowed in if !allowed { cancel() } }
    }
    private func cancel() {
        generation = UUID(); task?.cancel(); task = nil; busy = false; failed = false
    }
    private func read() {
        guard available, !busy else { return }
        let run = UUID(); generation = run; busy = true; failed = false
        task = Task { @MainActor in
            defer { if generation == run { busy = false; task = nil } }
            do {
                try Task.checkCancellation()
                let result = try await reader.status(id: assetID)
                try Task.checkCancellation()
                guard generation == run, available else { return }
                guard result.asset.id == assetID else { throw APIError.malformedResponse }
                // Keep the list producer authoritative; never splice a status response into a page.
                onRead()
            } catch {
                guard !Task.isCancelled, generation == run, available else { return }
                failed = true
            }
        }
    }
}
