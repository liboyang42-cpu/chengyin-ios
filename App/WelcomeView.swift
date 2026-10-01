import SwiftUI

struct WelcomeView: View {
    private enum Destination: Identifiable {
        case settings, login(RegistrationIntent)
        var id: String {
            switch self {
            case .settings: return "settings"
            case .login(let intent): return "login-" + intent.rawValue
            }
        }
    }
    @State private var destination: Destination?

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
                    Button("settings.title", systemImage: "gearshape") { destination = .settings }
                        .accessibilityIdentifier("welcome.settings")
                }
            }
            .sheet(item: $destination) { destination in
                switch destination {
                case .settings: SettingsView()
                case .login(let intent): LoginView(intent: intent)
                }
            }
        }
    }

    private func roleButton(_ role: RegistrationIntent, title: LocalizedStringKey,
                            detail: LocalizedStringKey, symbol: String) -> some View {
        Button { destination = .login(role) } label: {
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

#Preview("English") { WelcomeView().environmentObject(AppSession()).environment(\.locale, Locale(identifier: "en")) }
#Preview("简体中文 · Large type") {
    WelcomeView().environmentObject(AppSession()).environment(\.locale, Locale(identifier: "zh-Hans"))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Dark") { WelcomeView().environmentObject(AppSession()).preferredColorScheme(.dark) }
