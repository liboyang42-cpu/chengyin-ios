import SwiftUI
struct AccountDeregistrationImpactSection: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.locale) private var displayLocale
    let impact: AccountDeregistrationImpact
    private let titles = ["BALANCE":"c08.display.1", "POINTS":"c08.display.2", "ACTIVE_ORDERS":"c08.display.3", "ACTIVE_REGISTRATIONS":"c08.display.4", "PENDING_REFUNDS":"c08.display.5", "CASH_WITHDRAWAL_PENDING":"c08.display.6", "BANK_WITHDRAWAL_PENDING":"c08.display.7", "OWNED_CLUBS":"c08.display.8", "COLLECTIBLES":"c08.display.9", "CASH_WITHDRAWAL_AMOUNT":"c08.display.10", "CREATOR_SETTLEMENT_STATES":"c08.display.11", "CREATOR_DEBTS":"c08.display.12", "CREATOR_RESERVATIONS":"c08.display.13", "CLUB_MEMBERSHIPS":"c08.display.14", "CITY_SEASON_PARTICIPATION":"c08.display.15", "CREATOR_LEDGER":"c08.display.16", "WITHDRAWAL_FROZEN":"c08.display.17", "CREATOR_INCOME_FACTS":"c08.display.18", "LEGACY_CREATOR_CASH_POLICY":"c08.display.19", "SEASON_PARTICIPATION":"c08.display.20", "SEASON_PROGRESS_EFFECT":"c08.display.21", "SEASON_REWARD_FACTS":"c08.display.22", "SEASON_REWARD_EFFECT":"c08.display.23"]
    private func unknownTitle(_ key: String) -> String {
        switch key {
        case "P_E01_E03_SEASON_MEMBER_ENTRY_PROGRESS_REWARD_SOURCE": return "c08.display.24"
        case "P_E02_SEASON_PROGRESS_DELETION_EFFECT": return "c08.display.25"
        case "P_E03_SEASON_ORIGINAL_REWARD_FACTS": return "c08.display.26"
        case "P_E03_SEASON_RANK_REWARD_DELETION_EFFECT": return "c08.display.27"
        default: return key
        }
    }
    var body: some View {
        Section {
            ForEach(impact.items) { item in
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    if let title = titles[item.key] { Text(LocalizedStringKey(title), tableName: "AccountDeregistrationPresentation").font(Theme.Font.sectionTitle) }
                    else { Text(verbatim: item.key).font(Theme.Font.sectionTitle) }
                    if item.key == "SEASON_REWARD_EFFECT" { Text("c08.display.29", tableName: "AccountDeregistrationPresentation") }
                    else if item.value == "true" { Text("c08.display.30", tableName: "AccountDeregistrationPresentation") }
                    else if item.value == "false" { Text("c08.display.31", tableName: "AccountDeregistrationPresentation") }
                    else { Text(verbatim: item.value) }
                    Text(item.effect).font(Theme.Font.label)
                }
            }
            if !impact.unknownCoverage.isEmpty {
                (Text("c08.display.32", tableName: "AccountDeregistrationPresentation") + Text(verbatim: impact.unknownCoverage.map {
                    let title = unknownTitle($0)
                    return title == $0 ? title : String(localized: String.LocalizationValue(stringLiteral: title), table: "AccountDeregistrationPresentation", locale: displayLocale)
                }.joined(separator: "、")))
                Text("c08.display.33", tableName: "AccountDeregistrationPresentation")
            }
            (Text("c08.display.34", tableName: "AccountDeregistrationPresentation") + Text(verbatim: impact.revision)).font(Theme.Font.caption).textSelection(.enabled)
        } header: { Text("c08.display.28", tableName: "AccountDeregistrationPresentation") }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.Color.textPrimary(in: domain))
        .themeDomain(domain)
        .tint(Theme.Color.accent(in: domain))
    }
}

struct AccountDeregistrationImpactConfirmation: View {
    @Environment(\.themeDomain) private var domain
    let revision: String
    let submit: () -> Void
    @State private var confirmation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            TextField(text: $confirmation) { Text("c08.display.35", tableName: "AccountDeregistrationPresentation") }
                .autocorrectionDisabled().accessibilityIdentifier("compliance.impactConfirmation")
            Button(role: .destructive) { confirmation = ""; submit() } label: { Text("compliance.submit", tableName: "AccountCompliance") }
                .frame(minHeight: 44)
                .disabled(confirmation != "注销").accessibilityIdentifier("compliance.submit")
        }.font(Theme.Font.body)
            .foregroundStyle(Theme.Color.textPrimary(in: domain))
            .onDisappear { confirmation = "" }
        .themeDomain(domain)
        .tint(Theme.Color.accent(in: domain))
    }
}
