import SwiftUI

/// S02 presentation only. The original owners retain every state and request boundary.
private struct IMFlowFormPresentation: ViewModifier {
    @Environment(\.themeDomain) private var domain
    func body(content: Content) -> some View {
        content
            .formStyle(.grouped)
            .font(Theme.Font.body)
            .environment(\.defaultMinListRowHeight, 44)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct IMFlowPrimaryActionPresentation: ViewModifier {
    @Environment(\.themeDomain) private var domain
    func body(content: Content) -> some View {
        content.font(Theme.Font.button)
            .buttonStyle(.questifyPrimary)
            .controlSize(.large)
            .tint(Theme.Color.actionPrimaryBackground(in: domain))
            .foregroundStyle(Theme.Color.actionPrimaryForeground(in: domain))
            .frame(minHeight: 44)
    }
}

extension View {
    func imFlowForm() -> some View { modifier(IMFlowFormPresentation()) }
    func imFlowPrimaryAction() -> some View { modifier(IMFlowPrimaryActionPresentation()) }
}

/// One existing state, readable independently of color; never infers an operation result.
struct IMFlowStateMessage: View {
    enum Tone { case neutral, attention, success }
    let text: Text
    var symbol = "info.circle"
    var tone: Tone = .neutral
    @Environment(\.themeDomain) private var domain
    private var color: Color {
        switch tone {
        case .neutral: return Theme.Color.textSecondary(in: domain)
        case .attention: return Theme.Color.danger(in: domain)
        case .success: return Theme.Color.success(in: domain)
        }
    }
    var body: some View {
        Label { text.fixedSize(horizontal: false, vertical: true) } icon: {
            Image(systemName: symbol).accessibilityHidden(true)
        }
        .font(Theme.Font.body)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, Theme.Space.s1)
        .accessibilityElement(children: .combine)
    }
}
