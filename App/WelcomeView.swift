import SwiftUI

struct WelcomeView: View {
    @State private var intent: RegistrationIntent?
    @State private var showsSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("welcome.title")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("welcome.subtitle").foregroundStyle(.secondary)
                    roleButton(.player, title: "role.player", detail: "role.player.detail", symbol: "figure.walk")
                    roleButton(.merchant, title: "role.merchant", detail: "role.merchant.detail", symbol: "storefront")
                    Text("welcome.intentNotice").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Questify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("settings.title", systemImage: "gearshape") { showsSettings = true }
                        .accessibilityIdentifier("welcome.settings")
                }
            }
            .sheet(isPresented: $showsSettings) { SettingsView() }
            .sheet(item: $intent) { RegistrationHandoffView(intent: $0) }
        }
    }

    private func roleButton(_ role: RegistrationIntent, title: LocalizedStringKey,
                            detail: LocalizedStringKey, symbol: String) -> some View {
        Button { intent = role } label: {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol).font(.title2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(8)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("welcome.\(role.rawValue)")
    }
}

/// A visible development boundary: selecting an intent does not create a user/session.
private struct RegistrationHandoffView: View {
    let intent: RegistrationIntent
    @Environment(\.dismiss) private var dismiss
    private var title: LocalizedStringKey {
        intent == .player ? "registration.player" : "registration.merchant"
    }

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text("registration.pending")
            } actions: {
                Button("action.back") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { dismiss() }
                }
            }
        }
    }
}

#Preview("English") { WelcomeView().environment(\.locale, Locale(identifier: "en")) }
#Preview("简体中文 · Large type") {
    WelcomeView().environment(\.locale, Locale(identifier: "zh-Hans"))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Dark") { WelcomeView().preferredColorScheme(.dark) }
