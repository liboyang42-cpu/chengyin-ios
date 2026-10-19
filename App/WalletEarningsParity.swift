import SwiftUI

/// 今天 / 昨天 / M月D日 for income rows (mini-program income-detail).
struct WalletIncomeDayText: View {
    let day: WalletIncomeDay
    @Environment(\.locale) private var locale
    var body: some View {
        switch day {
        case .today: Text("member.wallet.today", tableName: "MemberProfile")
        case .yesterday: Text("member.wallet.yesterday", tableName: "MemberProfile")
        case .monthDay(let month, let day):
            if locale.language.languageCode?.identifier == "zh" { Text(verbatim: "\(month)月\(day)日") }
            else { Text(verbatim: "\(month)/\(day)") }
        }
    }
}

/// Zero balance on 账户收益 (还没有收益). The source CTA 去发布路线 is not offered here
/// because this screen has no route to the publish tab.
struct WalletEarningsEmptyNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("member.wallet.noEarnings", tableName: "MemberProfile").font(.headline)
            Text("member.wallet.noEarningsHint", tableName: "MemberProfile").font(.footnote).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("wallet.earnings.empty")
    }
}
