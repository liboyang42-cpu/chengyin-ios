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

// MARK: - motion-1119 shared loading, remote image and numeric motion

/// Spinner-only loading → a redacted placeholder of the real layout that cross-fades to content
/// (App Store / Mail pattern). Error and empty states stay in `content`, unchanged.
/// The placeholder is one VoiceOver element carrying the screen's existing loading label and identifier.
struct QuestifyLoadingContainer<Placeholder: View, Content: View>: View {
    let isLoading: Bool
    let label: LocalizedStringKey
    var identifier: String? = nil
    private let placeholder: () -> Placeholder
    private let content: () -> Content
    @QuestifyReduceMotion private var reduceMotion

    init(isLoading: Bool, label: LocalizedStringKey, identifier: String? = nil,
         @ViewBuilder placeholder: @escaping () -> Placeholder, @ViewBuilder content: @escaping () -> Content) {
        self.isLoading = isLoading; self.label = label; self.identifier = identifier
        self.placeholder = placeholder; self.content = content
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isLoading {
                QuestifyRedactedPlaceholder(label: label, identifier: identifier, content: placeholder)
                    .transition(.opacity)
            } else {
                content().transition(.opacity)
            }
        }
        .animation(reduceMotion || isLoading ? nil : QuestifyMotion.content, value: isLoading)
    }
}

/// The placeholder half of QuestifyLoadingContainer, for List rows that cannot be wrapped in a ZStack.
/// Pair with `.questifyContentSwap(isLoading:)` on the List so rows cross-fade when loading ends.
struct QuestifyRedactedPlaceholder<Content: View>: View {
    let label: LocalizedStringKey
    var identifier: String? = nil
    private let content: () -> Content
    init(label: LocalizedStringKey, identifier: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label; self.identifier = identifier; self.content = content
    }
    var body: some View {
        content()
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier(identifier ?? "questify.loadingPlaceholder")
    }
}

/// Generic redacted card in the shape of QuestifyCardSurface rows: artwork tint, title, two metadata lines.
/// Used only where the screen has no sample-able real row.
struct QuestifyPlaceholderCard: View {
    var artworkHeight: CGFloat? = 164
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let artworkHeight {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: artworkHeight)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "Placeholder title").font(.title3.weight(.semibold))
                Text(verbatim: "Placeholder metadata line").font(.subheadline)
                Text(verbatim: "Placeholder detail").font(.subheadline)
            }
        }
        .questifyCardSurface()
    }
}

/// Plain grouped-list row placeholder: a headline and a secondary line.
struct QuestifyPlaceholderRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Placeholder row title").font(.headline)
            Text(verbatim: "Placeholder secondary").font(.subheadline)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

extension View {
    /// Cross-fade a List/stack when loading ends (placeholder → content), skipped under Reduce Motion.
    /// Only the arrival animates: going back to loading, sign-out or scope changes remove content at once,
    /// so stale (possibly private) rows never linger through a fade.
    func questifyContentSwap(isLoading: Bool) -> some View { modifier(QuestifyContentSwap(isLoading: isLoading)) }
    /// Numbers that update after load roll instead of jumping (contentTransition(.numericText())).
    func questifyNumericTransition(value: Double) -> some View { modifier(QuestifyNumericTransition(value: value)) }
}

private struct QuestifyContentSwap: ViewModifier {
    let isLoading: Bool
    @QuestifyReduceMotion private var reduceMotion
    func body(content: Content) -> some View {
        content.animation(reduceMotion || isLoading ? nil : QuestifyMotion.content, value: isLoading)
    }
}

private struct QuestifyNumericTransition: ViewModifier {
    let value: Double
    @QuestifyReduceMotion private var reduceMotion
    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText(value: value))
            .animation(reduceMotion ? nil : QuestifyMotion.release, value: value)
    }
}

/// Remote cover/card/thumbnail/avatar: placeholder tint at the final size or aspect ratio, image fades in on
/// load, failure keeps the placeholder. The frame never changes between phases, so nothing shifts.
struct QuestifyRemoteImage: View {
    let url: URL?
    /// Final width / height. Nil keeps the caller's frame (pass a fixed frame then).
    var aspectRatio: CGFloat? = nil
    var contentMode: ContentMode = .fill
    var cornerRadius: CGFloat = 0
    var placeholderSymbol: String? = nil
    @QuestifyReduceMotion private var reduceMotion

    var body: some View {
        Color(uiColor: .tertiarySystemFill)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : QuestifyMotion.content)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
                    } else if let placeholderSymbol {
                        Image(systemName: placeholderSymbol).font(.title3).foregroundStyle(.secondary)
                    } else { Color.clear }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Grouped-list rows for List screens: only the first row speaks the loading label to VoiceOver.
struct QuestifyPlaceholderRows: View {
    let label: LocalizedStringKey
    var identifier: String? = nil
    var count = 3
    var body: some View {
        ForEach(0..<count, id: \.self) { index in
            if index == 0 {
                QuestifyRedactedPlaceholder(label: label, identifier: identifier) { QuestifyPlaceholderRow() }
            } else {
                QuestifyPlaceholderRow().redacted(reason: .placeholder).accessibilityHidden(true)
            }
        }
    }
}

/// Detail-screen placeholder in the shape of the inset-grouped detail Lists (title block + rows).
struct QuestifyDetailListPlaceholder: View {
    let label: LocalizedStringKey
    var identifier: String? = nil
    var body: some View {
        QuestifyRedactedPlaceholder(label: label, identifier: identifier) {
            List {
                Section {
                    Text(verbatim: "Placeholder detail title").font(.title2.bold())
                    Text(verbatim: "Placeholder subtitle line")
                    Text(verbatim: "Placeholder introduction that wraps across two lines in the loaded layout.")
                }
                Section { ForEach(0..<4, id: \.self) { _ in QuestifyPlaceholderRow() } }
            }
            .listStyle(.insetGrouped)
            .scrollDisabled(true)
        }
    }
}

extension Transaction {
    /// AsyncImage phase change: fade the loaded image in over the placeholder (none under Reduce Motion).
    static func questifyImageFade(reduceMotion: Bool) -> Transaction {
        Transaction(animation: reduceMotion ? nil : QuestifyMotion.content)
    }
}

/// Tint reserved while a remote image of unknown size loads (4:3 by default), kept on failure.
struct QuestifyImageLoadingTint: View {
    var aspectRatio: CGFloat = 4.0 / 3.0
    var body: some View {
        Color(uiColor: .tertiarySystemFill)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
