import SwiftUI

/// S04 presentation only. All state, identity, journal and navigation ownership stays with callers.
private struct NativeChannelScreenPresentation: ViewModifier {
    @Environment(\.themeDomain) private var domain
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .environment(\.defaultMinListRowHeight, 44)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.bgPage(in: domain))
            .navigationBarTitleDisplayMode(.inline)
    }
}
private struct NativeChannelPrimaryAction: ViewModifier {
    @Environment(\.themeDomain) private var domain
    func body(content: Content) -> some View {
        content
            .buttonStyle(.questifyPrimary)
            .controlSize(.large)
            .tint(Theme.Color.actionPrimaryBackground(in: domain))
            .foregroundStyle(Theme.Color.actionPrimaryForeground(in: domain))
            .font(Theme.Font.button)
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
