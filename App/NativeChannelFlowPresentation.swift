import SwiftUI

/// S03 presentation only. These views do not hold access, requests or recovery state.
private struct NativeChannelFlowPageStyle: ViewModifier {
    @Environment(\.themeDomain) private var domain
    func body(content: Content) -> some View {
        content
            .font(Theme.Font.body)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.bgPage(in: domain))
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .tint(Theme.Color.accent(in: domain))
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func nativeChannelFlowPage() -> some View { modifier(NativeChannelFlowPageStyle()) }
    func nativeChannelFlowAction() -> some View {
        buttonStyle(.borderedProminent).controlSize(.large)
    }
}

/// Existing state text with a semantic icon and room for accessibility-size text.
struct NativeChannelFlowNotice: View {
    let title: Text
    var message: Text? = nil
    var symbol: String = "info.circle"
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s3) {
            Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                title.font(Theme.Font.sectionTitle)
                if let message { message.font(.subheadline).foregroundStyle(.secondary) }
            }.fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
