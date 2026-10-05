import SwiftUI

/// Presentation only. IM, node NPC and merchant NPC keep their own models and authority.
/// The caller supplies sender truth and metadata; this view never infers delivery/read state.
struct ChatMessageBubble<Sender: View, Content: View>: View {
    let isOwn: Bool
    var timestamp: String? = nil
    @ViewBuilder let sender: () -> Sender
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 5) {
            sender().font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(isOwn ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            if let timestamp, !timestamp.isEmpty {
                Text(verbatim: timestamp).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Leave a modest opposite-side gutter, but give accessibility text the full width.
        .padding(isOwn ? .leading : .trailing, typeSize.isAccessibilitySize ? 0 : 28)
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }
}
