import SwiftUI
import UIKit

/// Content stays on an opaque adaptive surface. System navigation owns translucent materials.
private struct QuestifyCardSurface: ViewModifier {
    @Environment(\.accessibilityContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.3 : 0.06), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func questifyCardSurface() -> some View { modifier(QuestifyCardSurface()) }
    func questifyCardListRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// Label remains available to VoiceOver even when the visual metadata is deliberately compact.
struct QuestifyMetadataLine: View {
    let label: LocalizedStringKey
    let value: String
    let systemImage: String
    var body: some View {
        Label {
            Text(verbatim: value).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).frame(width: 18).accessibilityHidden(true)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label) + Text(verbatim: ": " + value))
    }
}

/// The label and symbol carry status, not color alone. No badge implies an action is enabled.
struct QuestifyStatusBadge: View {
    let title: LocalizedStringKey
    let systemImage: String
    var emphasized = false
    /// Only the state key animates; parent lists and unrelated content never spring on refresh.
    var stateKey = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityContrast) private var contrast
    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(emphasized ? QuestifyPalette.accent : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(emphasized ? QuestifyPalette.accent.opacity(contrast == .increased ? 0.16 : 0.09) : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : QuestifyMotion.content, value: stateKey)
            .accessibilityElement(children: .combine)
    }
}

/// Real artwork only. URLs receive no account headers and unsafe or absent sources stay absent.
struct QuestifyCardArtwork: View {
    let url: URL
    var height: CGFloat = 164
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static func safeURL(_ source: String?) -> URL? {
        guard let source, let parts = URLComponents(string: source), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }
    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : QuestifyMotion.content)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill().transition(.opacity)
            } else {
                // A restrained placeholder while the supplied image is unavailable, never invented artwork.
                Color(uiColor: .tertiarySystemFill)
                    .overlay { Image(systemName: "photo").font(.title2).foregroundStyle(.secondary) }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct TicketWalletStatusBadge: View {
    let status: TicketWalletStatus
    private var symbol: String {
        switch status {
        case .ready: return "ticket"
        case .pending: return "clock"
        case .verified: return "checkmark.seal"
        case .cancelled: return "xmark.circle"
        case .expired: return "calendar.badge.exclamationmark"
        case .unknown: return "questionmark.circle"
        }
    }
    var body: some View {
        QuestifyStatusBadge(title: LocalizedStringKey("ticketWallet.status." + status.rawValue), systemImage: symbol, emphasized: status == .ready, stateKey: status.rawValue)
    }
}
