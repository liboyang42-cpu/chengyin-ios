import SwiftUI

private struct SquareDeletionKey: EnvironmentKey { static let defaultValue: SquareDeletionCoordinator? = nil }
extension EnvironmentValues {
    /// Nil (the default) keeps delete visible but disabled; no host supplies an approved coordinator yet.
    var squareDeletion: SquareDeletionCoordinator? {
        get { self[SquareDeletionKey.self] }
        set { self[SquareDeletionKey.self] = newValue }
    }
}

/// Source danger-confirm sheets `club.post.delete` / `club.comment.delete`.
struct SquareDeletionConfirmView: View {
    let target: SquareDeletionTarget
    let excerpt: String?
    let coordinator: SquareDeletionCoordinator
    var body: some View {
        List {
            Section {
                switch target {
                case .post:
                    if let excerpt { Text("square.xcx.delete.postTitle \(excerpt)").font(.headline) }
                    else { Text("square.xcx.delete.postTitleImageOnly").font(.headline) }
                    Label("square.xcx.delete.postCascade", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                    Label("square.xcx.delete.postIrreversible", systemImage: "exclamationmark.triangle")
                case .comment:
                    Text("square.xcx.delete.commentTitle").font(.headline)
                    Label("square.xcx.delete.commentIrreversible", systemImage: "exclamationmark.triangle")
                }
            }
            Section {
                Button(role: .destructive) { Task { await coordinator.confirm() } } label: {
                    if case .post = target { Text("square.xcx.delete.postConfirm") } else { Text("square.xcx.delete.commentConfirm") }
                }.disabled(coordinator.isBusy).accessibilityIdentifier("square.delete.confirm")
                Button("action.cancel") { coordinator.cancel() }.disabled(coordinator.isBusy)
            }
        }.accessibilityIdentifier("square.delete.sheet")
    }
    /// Source excerpt: first 12 characters plus "…", or nil for an image-only post.
    static func excerpt(_ contents: String?) -> String? {
        let text = (contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.count > 12 ? String(text.prefix(12)) + "…" : text
    }
}

/// Inline status for terminal and unknown deletion results.
struct SquareDeletionStatusView: View {
    let coordinator: SquareDeletionCoordinator
    let verify: () -> Void
    var body: some View {
        switch coordinator.phase {
        case .done(let target):
            if case .post = target { Text("square.xcx.delete.postDone").accessibilityIdentifier("square.delete.done") }
            else { Text("square.xcx.delete.commentDone").accessibilityIdentifier("square.delete.done") }
        case .rejected(_, let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("square.xcx.delete.failed").accessibilityIdentifier("square.delete.failed")
                if let message, !message.isEmpty { Text(verbatim: message).font(.caption) }
            }
        case .unknown:
            VStack(alignment: .leading, spacing: 6) {
                Text("square.xcx.delete.unknown").accessibilityIdentifier("square.delete.unknown")
                Button("square.xcx.delete.verify", action: verify).accessibilityIdentifier("square.delete.verify")
            }
        case .disabled:
            Text("square.xcx.delete.unavailable").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("square.delete.unavailable")
        default: EmptyView()
        }
    }
}
