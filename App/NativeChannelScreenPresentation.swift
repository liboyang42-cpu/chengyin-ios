import SwiftUI

/// S04 presentation only. All state, identity, journal and navigation ownership stays with callers.
private struct NativeChannelScreenPresentation: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.body)
            .environment(\.defaultMinListRowHeight, 44)
            .navigationBarTitleDisplayMode(.inline)
    }
}
/// The style itself supplies the primary colours and button font for the root's theme.
private struct NativeChannelPrimaryAction: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.questifyPrimary)
            .controlSize(.large)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44)
    }
}
private struct NativeChannelInlineNotice: ViewModifier {
    let systemImage: String
    @Environment(\.themeDomain) private var domain
    func body(content: Content) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s2) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.Color.textSecondary(in: domain))
                .accessibilityHidden(true)
            content.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(Theme.Font.body)
        .padding(Theme.Space.s3)
        .background(Theme.Color.bgSurface(in: domain), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .combine)
    }
}
extension View {
    func nativeChannelScreen() -> some View { modifier(NativeChannelScreenPresentation()) }
    func nativeChannelPrimaryAction() -> some View { modifier(NativeChannelPrimaryAction()) }
    func nativeChannelNotice(systemImage: String) -> some View { modifier(NativeChannelInlineNotice(systemImage: systemImage)) }
}
