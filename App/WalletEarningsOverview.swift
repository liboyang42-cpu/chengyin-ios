import SwiftUI

/// Strings for this slice live in WalletEarningsOverview.xcstrings, not the main catalog.
enum WalletEarningsCopy {
    static let table = "WalletEarningsOverview"
    static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: table)
    }
    static func text(_ key: String, locale: Locale) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: table, locale: locale))
    }
}

struct WalletFundsStageInput: Equatable {
    var loading = false
    var failed = false
    var requiresLogin = false
    var unavailable = false
    var configured = false
    var hasScope = false
    var scopeMatches = false
    var stages: WalletFundsStages?
}

enum WalletFundsStagePhase: Equatable {
    case loading, empty, known, unknown, failed, unconfigured, signedOut
}

@MainActor enum WalletFundsStageClassifier {
    static func phase(_ input: WalletFundsStageInput) -> WalletFundsStagePhase {
        if !input.hasScope || input.requiresLogin { return .signedOut }
        // APIError.notConfigured is recorded as unavailable. No permission error exists on this read.
        if !input.configured || input.unavailable { return .unconfigured }
        if let stages = input.stages, input.scopeMatches, !input.loading {
            if !stages.amountsKnown { return .unknown }
            let moving = stages.pendingSettlement.value > 0 || stages.disputed.value > 0 || !stages.complaintPeriod.isEmpty
            return moving || stages.withdrawable.value > 0 ? .known : .empty
        }
        if input.loading { return .loading }
        if input.failed { return .failed }
        return .loading
    }
    static func showsAmounts(_ phase: WalletFundsStagePhase) -> Bool { phase == .known || phase == .empty }
    static func input(reader: WalletCommerceReader, funds: WalletScreen<WalletFundsStages>) -> WalletFundsStageInput {
        WalletFundsStageInput(loading: funds.loading, failed: funds.failed, requiresLogin: funds.requiresLogin,
            unavailable: funds.unavailable, configured: reader.isConfigured, hasScope: reader.scope != nil,
            scopeMatches: funds.loadedScope == reader.scope && reader.scope != nil, stages: funds.value)
    }
}

/// Inline stages. Amounts stay on this wallet's currency and are not added to balance or organizer share.
@MainActor struct WalletFundsStagesInline: View {
    @Environment(\.locale) private var locale
    private var format: WalletFormatting { .init(locale: locale) }
    let reader: WalletCommerceReader
    @ObservedObject var funds: WalletScreen<WalletFundsStages>
    let retry: () -> Void
    var body: some View {
        let phase = WalletFundsStageClassifier.phase(WalletFundsStageClassifier.input(reader: reader, funds: funds))
        VStack(alignment: .leading, spacing: 8) {
            switch phase {
            case .loading:
                ProgressView { Text("wallet.earnings.stages.loading", tableName: "WalletEarningsOverview") }
                    .accessibilityIdentifier("wallet.earnings.stages.loading")
            case .signedOut:
                Text("wallet.earnings.stages.signedOut", tableName: "WalletEarningsOverview")
                    .accessibilityIdentifier("wallet.earnings.stages.signedOut")
            case .unconfigured:
                Text("wallet.earnings.stages.unconfigured", tableName: "WalletEarningsOverview")
                    .accessibilityIdentifier("wallet.earnings.stages.unconfigured")
            case .failed:
                Text("wallet.earnings.stages.failed", tableName: "WalletEarningsOverview")
                    .accessibilityIdentifier("wallet.earnings.stages.failed")
                Button(action: retry) { Text("wallet.earnings.stages.retry", tableName: "WalletEarningsOverview") }
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("wallet.earnings.stages.retry")
            case .unknown:
                Text("wallet.earnings.stages.unknown", tableName: "WalletEarningsOverview")
                    .accessibilityIdentifier("wallet.earnings.stages.unknown")
                    .accessibilityLabel(Text("wallet.earnings.stages.unknown", tableName: "WalletEarningsOverview"))
                separate
            case .empty, .known:
                if let value = funds.value, WalletFundsStageClassifier.showsAmounts(phase) {
                    amounts(value, phase: phase)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet.earnings.stages")
    }
    @ViewBuilder private func amounts(_ value: WalletFundsStages, phase: WalletFundsStagePhase) -> some View {
        if phase == .empty {
            Text("wallet.earnings.stages.empty", tableName: "WalletEarningsOverview")
                .accessibilityIdentifier("wallet.earnings.stages.empty")
        }
        if phase == .known, value.pendingSettlement.value > 0 {
            LabeledContent("wallet.pendingSettlement", value: format.amount(value.pendingSettlement, currency: value.currency))
                .accessibilityIdentifier("wallet.earnings.stages.pending")
        }
        if phase == .known {
            ForEach(Array(value.complaintPeriod.enumerated()), id: \.offset) { index, item in
                LabeledContent { Text(format.amount(item.amount, currency: value.currency)) } label: {
                    Text("wallet.complaintPeriod"); Text(verbatim: WalletCivilDateLocalization.text(item.availableDate, locale: locale))
                }.accessibilityIdentifier("wallet.earnings.stages.complaint.\(index)")
            }
            if value.disputed.value > 0 {
                LabeledContent("wallet.disputed", value: format.amount(value.disputed, currency: value.currency))
                    .accessibilityIdentifier("wallet.earnings.stages.disputed")
            }
        }
        LabeledContent {
            Text(format.amount(value.withdrawable, currency: value.currency))
                .accessibilityIdentifier("wallet.earnings.stages.available")
                .privacySensitive()
        } label: {
            Text("wallet.available")
        }
        Text("wallet.notPayout")
        separate
    }
    private var separate: some View {
        Text("wallet.earnings.stages.separate", tableName: "WalletEarningsOverview")
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("wallet.earnings.stages.separate")
    }
}

struct WalletEarningsTabHold: Equatable {
    enum Tab: String, Equatable { case income, organizer }
    var tab: Tab = .income
    var mounted = false
    var active = true
    mutating func select(_ next: Tab) {
        tab = next
        if next == .organizer, active { mounted = true }
    }
    mutating func background() { active = false; mounted = false }
    mutating func foreground() {
        active = true
        if tab == .organizer { mounted = true }
    }
}

@MainActor struct WalletEarningsTabBar: View {
    let tab: WalletEarningsTabHold.Tab
    let select: (WalletEarningsTabHold.Tab) -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(alignment: .leading, spacing: 8) { buttons }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet.earnings.tabs")
    }
    private var buttons: some View {
        Group {
            button(.income, Text("wallet.earnings.tab.income", tableName: "WalletEarningsOverview"))
                .accessibilityIdentifier("wallet.earnings.tab.income")
            button(.organizer, Text("wallet.earnings.tab.organizer", tableName: "WalletEarningsOverview"))
                .accessibilityIdentifier("wallet.earnings.tab.organizer")
        }
    }
    private func button(_ which: WalletEarningsTabHold.Tab, _ label: Text) -> some View {
        Button { select(which) } label: {
            label.frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityAddTraits(tab == which ? .isSelected : AccessibilityTraits())
    }
}

enum WalletOrganizerFinanceAdmission {
    /// False skips the finance view, so `read(.finance)` is not started.
    static func showReader(allowsRead: Bool, hasSession: Bool, mounted: Bool) -> Bool {
        allowsRead && hasSession && mounted
    }
}

enum WalletOrganizerFinanceIdentity {
    static func key(accountID: Int?, epoch: UInt64?) -> String { "\(accountID ?? 0):\(epoch ?? 0)" }
}

@MainActor struct WalletOrganizerFinanceAccess {
    let reader: any CoopFlowReading
    var allowsRead: @MainActor () -> Bool
    var makeContent: @MainActor () -> AnyView
    init<Content: View>(reader: any CoopFlowReading, allowsRead: @escaping @MainActor () -> Bool, @ViewBuilder content: @escaping @MainActor () -> Content) {
        self.reader = reader
        self.allowsRead = allowsRead
        self.makeContent = { AnyView(content()) }
    }
}

/// Organizer share uses CoopFinanceSummarySection. Its ¥ figures stay in that section.
@MainActor struct WalletOrganizerFinancePane: View {
    let access: WalletOrganizerFinanceAccess
    var mounted: Bool
    private var identity: String {
        WalletOrganizerFinanceIdentity.key(accountID: access.reader.session?.accountID, epoch: access.reader.session?.epoch)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("wallet.earnings.finance.separate", tableName: "WalletEarningsOverview")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wallet.earnings.finance.separate")
            if WalletOrganizerFinanceAdmission.showReader(allowsRead: access.allowsRead(), hasSession: access.reader.session != nil, mounted: mounted) {
                // The existing finance view renders the summary and settlement rows from one payload.
                access.makeContent().id(identity)
            } else if !access.allowsRead() {
                Text("wallet.earnings.finance.unconfigured", tableName: "WalletEarningsOverview")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wallet.earnings.finance.unconfigured")
            } else {
                Text("wallet.earnings.finance.signedOut", tableName: "WalletEarningsOverview")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("wallet.earnings.finance.signedOut")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if DEBUG
@MainActor final class WalletEarningsSyntheticFinanceReader: CoopFlowReading {
    var session: CoopFlowSession? = try? CoopFlowSession(accountID: 101, epoch: 1, token: "synthetic-cooperation-only")
    var onFinanceRead: @MainActor () -> Void = {}
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        guard resource == .finance else { throw CoopFlowFailure.unavailable }
        onFinanceRead()
        return .object(["topics": .array([.object([
            "topicId": .id(8), "topicName": .string("Synthetic organizer route"),
            "myIncome": .number(Decimal(string: "12.50")!), "settled": .bool(true), "myIncomeArrived": .bool(false),
            "totalSales": .number(0), "verifiedSales": .number(0), "platformAmount": .number(0), "merchantTotal": .number(20)
        ])])])
    }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement {
        let value = try await read(source == .finance ? .finance : .myBusiness)
        let rows = value[source == .finance ? "topics" : "settlements"].rows ?? []
        guard let row = rows.first(where: { $0[source == .finance ? "topicId" : "id"].integer == id }) else { throw CoopFlowFailure.unavailable }
        return CoopFlowSettlement(source: source, record: row)
    }
}

@MainActor final class WalletEarningsDebugFinance: ObservableObject {
    @Published private(set) var financeReads = 0
    let reader: WalletEarningsSyntheticFinanceReader
    let blocksRead: Bool
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--wallet-earnings-overview-fixture") }
    init() {
        let reader = WalletEarningsSyntheticFinanceReader()
        self.reader = reader
        blocksRead = ProcessInfo.processInfo.arguments.contains("--wallet-earnings-finance-denied")
        reader.onFinanceRead = { [weak self] in self?.financeReads += 1 }
    }
    var access: WalletOrganizerFinanceAccess {
        let reader = reader, blocked = blocksRead
        return WalletOrganizerFinanceAccess(reader: reader, allowsRead: { !blocked }) {
            CoopFlowReadView(reader: reader, resource: .finance, title: "coopflow.finance")
        }
    }
}
#endif
