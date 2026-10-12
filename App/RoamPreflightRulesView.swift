import SwiftUI

/// Reuses the accepted native live rules. Mini-only radius, exchange and presence promises
/// are deliberately not inferred from merely opening the pre-roam guide.
enum RoamPreflightRule: String, CaseIterable, Identifiable {
    case explore, arrival, finish, privacy
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .explore: return "roam.live.ruleExploreTitle"
        case .arrival: return "roam.live.ruleArrivalTitle"
        case .finish: return "roam.live.ruleFinishTitle"
        case .privacy: return "roam.live.rulePrivacyTitle"
        }
    }
    var bodyKeys: [String] {
        switch self {
        case .explore: return ["roam.live.ruleExplore"]
        case .arrival: return ["roam.live.ruleArrival"]
        case .finish: return ["roam.live.ruleFinish"]
        case .privacy: return ["roam.live.presencePrivacy", "roam.live.leaveHint"]
        }
    }
}

/// Pure reading destination, reachable before entering live roaming. No service/device access,
/// permission request, location collection, consent mutation or start/finish action.
@MainActor struct RoamPreflightRulesView: View {
    var body: some View {
        List {
            Section {
                Label("roam.preflightRules.availability", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("roam.preflightRules.availability")
            }
            ForEach(RoamPreflightRule.allCases) { rule in
                Section {
                    ForEach(rule.bodyKeys, id: \.self) { key in
                        Text(LocalizedStringKey(key))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("roam.preflightRules.body." + key)
                    }
                } header: {
                    Text(LocalizedStringKey(rule.titleKey))
                        .accessibilityIdentifier("roam.preflightRules.section." + rule.id)
                }
            }
        }
        .navigationTitle("roam.live.rules")
        .accessibilityIdentifier("roam.preflightRules.screen")
    }
}
