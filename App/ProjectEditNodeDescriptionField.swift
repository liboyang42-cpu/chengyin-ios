import SwiftUI

/// Text editing has its own lifetime, independent of the optional merchant chooser.
/// Scoped editor callers supply their existing live permission/destination check.
@MainActor struct ProjectEditNodeDescriptionContext {
    let model: ProjectEditModel
    let sourceID: String
    let isCurrent: () -> Bool
}

@MainActor struct ProjectEditNodeDescriptionSource {
    struct Target: Hashable {
        let nodeID: String
        let sourceID: String
        let lease: ProjectEditStarterController.Lease
        // Lease equality checks session, owner, identity and structure as well as incarnation.
        // Its hash need not repeat every equality component.
        func hash(into hasher: inout Hasher) {
            hasher.combine(nodeID); hasher.combine(sourceID); hasher.combine(lease.incarnation)
        }
    }
    struct Snapshot: Equatable { let target: Target?; let bytes: Data }
    let node: Binding<ProjectEditNode>
    let context: ProjectEditNodeDescriptionContext
    var target: Target? {
        guard context.isCurrent(), let lease = context.model.captureStarterLease() else { return nil }
        return .init(nodeID: node.wrappedValue.id, sourceID: context.sourceID, lease: lease)
    }
    var snapshot: Snapshot { .init(target: target, bytes: Data(node.wrappedValue.description.utf8)) }
}

/// Holds only the description, never a second node/draft. Parent echoes do not set text.
/// All editing, readback and invalidation are synchronous on the main actor.
@MainActor final class ProjectEditNodeDescriptionBuffer: ObservableObject {
    @Published private(set) var text: String
    @Published private(set) var active = false
    @Published private(set) var revision = 0
    private let source: ProjectEditNodeDescriptionSource
    private let target: ProjectEditNodeDescriptionSource.Target?
    private var acknowledgedBytes: Data

    init(source: ProjectEditNodeDescriptionSource) {
        self.source = source; target = source.target
        text = source.node.wrappedValue.description; acknowledgedBytes = Data(text.utf8)
    }
    func activate() {
        guard let target, source.target == target else { return }
        synchronize(); if !active { revision += 1; active = true }
    }
    func invalidate() {
        if active { active = false; revision += 1 }
    }
    func synchronize() {
        guard let target, source.target == target else { invalidate(); return }
        let current = source.node.wrappedValue.description, bytes = Data(current.utf8)
        guard bytes != acknowledgedBytes else { return }
        acknowledgedBytes = bytes; revision += 1
        if !text.utf8.elementsEqual(current.utf8) { text = current }
    }
    var binding: Binding<String> {
        let capturedRevision = revision
        return Binding(get: { self.text }, set: { self.edit($0, revision: capturedRevision) })
    }
    private func edit(_ value: String, revision capturedRevision: Int) {
        guard active, capturedRevision == revision, let target, source.target == target else { return }
        var current = source.node.wrappedValue
        // A restore/external replacement may arrive before SwiftUI's onChange callback.
        // Reject that queued edit rather than writing an old buffer into the new source.
        guard Data(current.description.utf8) == acknowledgedBytes else { synchronize(); return }
        let bytes = Data(value.utf8)
        guard bytes != acknowledgedBytes else { return }
        acknowledgedBytes = bytes
        text = value
        current.description = value
        source.node.wrappedValue = current // Preserve the existing permission guard and autosave path.
        synchronize() // Read back a rejected/adjusted setter, without reassigning an exact echo.
    }
}

@MainActor struct ProjectEditNodeDescriptionField: View {
    let source: ProjectEditNodeDescriptionSource
    @StateObject private var buffer: ProjectEditNodeDescriptionBuffer
    init(source: ProjectEditNodeDescriptionSource) {
        self.source = source; _buffer = StateObject(wrappedValue: .init(source: source))
    }
    var body: some View {
        TextField("projectEdit.description", text: buffer.binding, axis: .vertical).lineLimit(3...8)
            .accessibilityIdentifier("projectEdit.nodeDescription")
            .disabled(source.target == nil)
            .onAppear { buffer.activate() }
            .onChange(of: source.snapshot) { _, _ in buffer.synchronize() }
            .onDisappear { buffer.invalidate() }
    }
}
