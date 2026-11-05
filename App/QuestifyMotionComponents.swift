import SwiftUI
import UIKit

/// Content stays on an opaque adaptive surface. System navigation owns translucent materials.
private struct QuestifyCardSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
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
    @QuestifyReduceMotion private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Label { Text(title).lineLimit(1).minimumScaleFactor(0.75) } icon: { Image(systemName: systemImage) }
            .font(.caption.weight(.semibold))
            .foregroundStyle(emphasized ? QuestifyPalette.accent : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(emphasized ? QuestifyPalette.accent.opacity(contrast == .increased ? 0.16 : 0.09) : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .contentTransition(.opacity)
            .animation(reduceMotion ? nil : QuestifyMotion.content, value: stateKey)
            .accessibilityElement(children: .combine)
    }
}

/// Real artwork only. URLs receive no account headers and unsafe or absent sources stay absent.
struct QuestifyCardArtwork: View {
    let url: URL
    var height: CGFloat = 164
    @QuestifyReduceMotion private var reduceMotion
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

// MARK: - Shared native layer

/// The one high-contrast primary action per screen: white on player, black on merchant.
struct QuestifyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuestifyPrimaryLabel(configuration: configuration)
    }
}

private struct QuestifyPrimaryLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.themeDomain) private var domain
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        configuration.label
            .font(Theme.Font.button)
            .foregroundStyle(Theme.Color.actionPrimaryForeground(in: domain))
            .padding(.vertical, controlSize == .large ? Theme.Space.s3_5 : Theme.Space.s2)
            .padding(.horizontal, controlSize == .large ? Theme.Space.s5 : Theme.Space.s3_5)
            .background(Theme.Color.actionPrimaryBackground(in: domain), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == QuestifyPrimaryButtonStyle {
    static var questifyPrimary: QuestifyPrimaryButtonStyle { QuestifyPrimaryButtonStyle() }
}

/// Large value at the top of a detail page.
struct QuestifyHeroValue: View {
    let value: Text
    var caption: Text? = nil

    var body: some View {
        VStack(spacing: Theme.Space.s1) {
            value.font(Theme.Font.dataXL).multilineTextAlignment(.center).minimumScaleFactor(0.6).lineLimit(2)
            if let caption { caption.font(Theme.Font.label).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.s6)
    }
}

/// Round icon with a short label. Use up to four in a row under a hero.
struct QuestifyRoundAction: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.s1_5) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(.quaternary, in: Circle())
                Text(title).font(Theme.Font.label).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Pins the screen's single primary action above the home indicator.
    func questifyBottomAction<Action: View>(@ViewBuilder _ action: () -> Action) -> some View {
        safeAreaInset(edge: .bottom) {
            action()
                .buttonStyle(.questifyPrimary)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Space.pageX)
                .padding(.vertical, Theme.Space.s2)
        }
    }
}

// MARK: - Shared notices and rows

/// One-line state message with a leading symbol.
private struct QuestifyNotice<Message: View>: View {
    let symbol: String
    var tint: Color = .secondary
    @ViewBuilder let message: Message

    var body: some View {
        Label { message.fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
            .font(Theme.Font.body)
    }
}

extension View {
    func clubStatus(_ symbol: String, emphasized: Bool = false) -> some View {
        QuestifyNotice(symbol: symbol, tint: emphasized ? .orange : .secondary) { self }
    }
    func clubPageSurface() -> some View { self }
    func merchantM02Page() -> some View { self }
}

struct ClubControlLabel: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }
    var body: some View { Text(title).frame(maxWidth: .infinity) }
}

struct MerchantM02Notice: View {
    let message: Text
    let symbol: String
    var isError = false
    var body: some View {
        QuestifyNotice(symbol: symbol, tint: isError ? .red : .secondary) { message.foregroundStyle(isError ? Color.red : Color.primary) }
    }
}

struct WorkshopLibraryNotice: View {
    let text: Text
    let systemImage: String
    var body: some View { QuestifyNotice(symbol: systemImage) { text } }
}

struct WorkshopLibraryState: View {
    let label: Text
    let raw: String
    var body: some View { label.font(Theme.Font.label).foregroundStyle(.secondary) }
}

struct SquareFlowNoticeStyle: ViewModifier {
    enum Tone { case neutral, attention, critical }
    var tone = Tone.neutral
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.label)
            .foregroundStyle(tone == .critical ? Color.red : tone == .attention ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SquareFlowSurfaceStyle: ViewModifier {
    func body(content: Content) -> some View { content }
}

struct MerchantJourneyFactRow<Value: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let value: Value
    init(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }
    var body: some View { LabeledContent { value } label: { Text(title) } }
}

struct MerchantJourneyFormAppearance: ViewModifier {
    func body(content: Content) -> some View { content }
}

