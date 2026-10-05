import SwiftUI
import UIKit

/// An explicit local clipboard action with visible, spoken feedback. It never opens
/// an external app or infers that the user has contacted the displayed recipient.
@MainActor struct NativeCopyTextButton: View {
    let text: String
    let title: LocalizedStringKey
    let identifier: String
    var copyText: (String) throws -> Void = { UIPasteboard.general.string = $0 }
    @Environment(\.locale) private var locale
    @State private var status: Status?
    private enum Status { case copied, failed }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                do { try copyText(text); status = .copied }
                catch { status = .failed }
                UIAccessibility.post(notification: .announcement,
                    argument: appLocalized(status == .copied ? "localCopy.copied" : "localCopy.failed", locale: locale))
            } label: { Label(title, systemImage: "doc.on.doc").frame(minHeight: 44) }
                .accessibilityIdentifier(identifier)
            if let status {
                Text(LocalizedStringKey(status == .copied ? "localCopy.copied" : "localCopy.failed"))
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier + (status == .copied ? ".copied" : ".failed"))
            }
        }
        .onChange(of: text) { _, _ in status = nil }
        .onDisappear { status = nil }
    }
}
