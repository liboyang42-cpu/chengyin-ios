import SwiftUI

/// Presentation only. IM, node NPC and merchant NPC keep their own models and authority.
/// The caller supplies sender truth and metadata; this view never infers delivery/read state.
struct ChatMessageBubble<Sender: View, Content: View>: View {
    let isOwn: Bool
    var timestamp: String? = nil
    @ViewBuilder let sender: () -> Sender
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.themeDomain) private var domain
    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: Theme.Space.s1) {
            sender().font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                // Own messages use the high-contrast primary pair; received ones sit on a raised fill.
                .foregroundStyle(isOwn ? Theme.Color.actionPrimaryForeground(in: domain) : Theme.Color.textPrimary(in: domain))
                .padding(.horizontal, Theme.Space.s3).padding(.vertical, Theme.Space.s2)
                .background(isOwn ? Theme.Color.actionPrimaryBackground(in: domain) : Theme.Color.bgRaised(in: domain),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if let timestamp, !timestamp.isEmpty {
                Text(verbatim: timestamp).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Leave an opposite-side gutter, but give accessibility text the full width.
        .padding(isOwn ? .leading : .trailing, typeSize.isAccessibilitySize ? 0 : 48)
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }
}
