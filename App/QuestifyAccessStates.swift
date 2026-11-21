import SwiftUI

/// The one missing-parameter state (hengyin #888 `cy-empty kind="missing-param"`): an info
/// symbol, 「链接已失效」 and a single way back. Every screen opened from an incomplete,
/// unsupported or expired link uses this, so a broken link always reads the same.
@MainActor struct QuestifyInvalidLinkView: View {
    var identifier = "access.linkInvalid"
    let back: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("access.linkInvalid", systemImage: "info.circle")
                .accessibilityIdentifier(identifier + ".title")
        } actions: {
            Button("action.back", action: back)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(identifier + ".back")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// The one no-permission state for merchant and club screens (hengyin #890 `cy-empty
/// kind="no-permission" fill size="lg"`): a lock, 「当前身份不能查看XX」 and exactly one
/// action. Same component and size wherever access is refused, in a list or full screen.
@MainActor struct QuestifyNoPermissionView: View {
    let titleKey: LocalizedStringKey
    var actionKey: LocalizedStringKey = "access.recheck"
    let identifier: String
    let action: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label { Text(titleKey).accessibilityIdentifier(identifier + ".error") } icon: { Image(systemName: "lock") }
        } actions: {
            Button(actionKey, action: action)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(identifier + ".access")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier + ".noPermission")
    }
}

/// A disabled control that says why when tapped (hengyin #890 `bind:disabledtap`). The control
/// stays disabled for input; a tap on it shows the reason in a small popover, and VoiceOver
/// hears the same reason as the hint. No reason means the control behaves as before.
struct QuestifyDisabledReason: ViewModifier {
    let reason: LocalizedStringKey?
    /// Other conditions (loading, a stale screen) that disable the control without a reason to tell.
    var disabled = false
    var identifier: String? = nil
    @State private var showsReason = false
    func body(content: Content) -> some View {
        content
            .disabled(reason != nil || disabled)
            .overlay {
                if reason != nil && !disabled {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { showsReason = true }
                        .accessibilityHidden(true)
                }
            }
            .popover(isPresented: $showsReason) {
                if let reason {
                    Text(reason).font(.callout).padding()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 320)
                        .presentationCompactAdaptation(.popover)
                        .accessibilityIdentifier((identifier ?? "control") + ".disabledReason")
                }
            }
            .accessibilityHint(reason.map { Text($0) } ?? Text(verbatim: ""))
            .onChange(of: reason == nil) { _, cleared in if cleared { showsReason = false } }
    }
}

extension View {
    /// Disables the control while `reason` is non-nil (or `otherwise` holds) and explains the reason on tap.
    func disabledExplained(_ reason: LocalizedStringKey?, otherwise: Bool = false, identifier: String? = nil) -> some View {
        modifier(QuestifyDisabledReason(reason: reason, disabled: otherwise, identifier: identifier))
    }
}
