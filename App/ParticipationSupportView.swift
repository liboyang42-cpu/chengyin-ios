import SwiftUI

struct ParticipationSupportView: View {
    var configuration: ParticipationSupportConfiguration? = nil
    var body: some View {
        Form {
            Section("participationSupport.title") {
                Text("participationSupport.purpose")
                if let configuration {
                    Link(destination: configuration.url) {
                        Label { Text(verbatim: configuration.name) } icon: { Image(systemName: "arrow.up.right.square") }
                    }.accessibilityIdentifier("participationSupport.open")
                    Text("participationSupport.privacy").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Label("participationSupport.notConfigured", systemImage: "message.badge.filled.fill")
                        .accessibilityIdentifier("participationSupport.notConfigured")
                    Text("participationSupport.configurationBoundary").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("participationSupport.title").navigationBarTitleDisplayMode(.inline)
    }
}
