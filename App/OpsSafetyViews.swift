import SwiftUI

// Reform plan v9 W09/W11 presentation components. They render fixed copy for decisions
// made elsewhere; none performs a request, opens a route or decides availability.

private func opsText(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "OpsSafety") }

/// W11.9 gate result. Preserved services always state that orders, refunds and
/// after-sales remain reachable; actions are callbacks to existing entries only.
struct OpsGateNoticeView: View {
    let decision: OpsGateDecision
    var perform: (OpsPreservedAction) -> Void = { _ in }
    var body: some View {
        switch decision {
        case .proceed, .preserved: EmptyView()
        case .unverified:
            Label { opsText("opsSafety.notice.unverified") } icon: { Image(systemName: "questionmark.circle") }
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine).accessibilityIdentifier("opsSafety.notice.unverified")
        case let .blocked(_, incident):
            VStack(alignment: .leading, spacing: 8) {
                Label { opsText("opsSafety.notice.title").font(.headline) } icon: { Image(systemName: "pause.circle") }
                opsText(incident.copyKey).accessibilityIdentifier("opsSafety.incident." + incident.rawValue)
                opsText("opsSafety.notice.preserved").font(.footnote).foregroundStyle(.secondary)
                ForEach(incident.preservedActions, id: \.self) { action in
                    if action == .doNotPayAgain {
                        opsText(action.copyKey).font(.subheadline.weight(.semibold))
                    } else {
                        Button { perform(action) } label: { opsText(action.copyKey) }
                            .buttonStyle(.bordered).frame(minHeight: 44)
                            .accessibilityIdentifier("opsSafety.action." + action.rawValue)
                    }
                }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain).accessibilityIdentifier("opsSafety.notice.blocked")
        }
    }
}

/// W09.5: shown wherever an AI reply or draft appears.
struct AIIdentityDisclosureView: View {
    let disclosure: AIIdentityDisclosure
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(disclosure.boundaryKeys, id: \.self) { key in opsText(key).font(.footnote) }
            }.padding(.top, 4)
        } label: {
            Label { opsText(disclosure.titleKey).font(.footnote.weight(.semibold)) } icon: { Image(systemName: "sparkles") }
        }
        .accessibilityIdentifier("opsSafety.ai.disclosure." + disclosure.surface.rawValue)
    }
}

/// W09.8: a stopped node cannot be started. Only a server-provided, no-purchase
/// alternative is offered; otherwise the support entry is the only action.
struct OfflineNodeSafetyView: View {
    let state: OfflineNodeSafetyState
    var openAlternative: (OfflineAlternative) -> Void = { _ in }
    var contactSupport: () -> Void = {}
    var body: some View {
        switch state {
        case .open: EmptyView()
        case .unknown:
            opsText("opsSafety.offline.unknown").font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("opsSafety.offline.unknown")
        case let .stopped(categories, _):
            VStack(alignment: .leading, spacing: 8) {
                Label { opsText("opsSafety.offline.title").font(.headline) } icon: { Image(systemName: "exclamationmark.triangle") }
                ForEach(Array(categories.enumerated()), id: \.offset) { _, category in opsText(category.copyKey) }
                if let alternative = state.noPurchaseAlternative {
                    Button { openAlternative(alternative) } label: {
                        VStack(alignment: .leading) {
                            opsText("opsSafety.action.viewAlternativeIfProvided")
                            Text(verbatim: alternative.title).font(.footnote)
                        }
                    }.buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("opsSafety.offline.alternative")
                } else {
                    opsText("opsSafety.offline.noAlternative").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("opsSafety.offline.noAlternative")
                }
                Button(action: contactSupport) { opsText("opsSafety.action.contactSupport") }
                    .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("opsSafety.action.contactSupport")
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain).accessibilityIdentifier("opsSafety.offline.stopped")
        }
    }
}

/// W09.6: asks before text that looks like personal data goes to an AI surface.
/// Sending stays the caller's decision; nothing is edited or stored here.
struct AIOutgoingSensitiveConfirmation: ViewModifier {
    @Binding var findings: Set<AIOutgoingSensitiveKind>
    let send: () -> Void
    func body(content: Content) -> some View {
        content.confirmationDialog(Text(LocalizedStringKey("opsSafety.ai.sensitive.title"), tableName: "OpsSafety"),
                                   isPresented: Binding(get: { !findings.isEmpty }, set: { if !$0 { findings = [] } }),
                                   titleVisibility: .visible) {
            Button(role: .destructive) { findings = []; send() } label: { opsText("opsSafety.ai.sensitive.send") }
            Button(role: .cancel) { findings = [] } label: { opsText("opsSafety.ai.sensitive.edit") }
        } message: {
            Text(findings.sorted { $0.rawValue < $1.rawValue }
                .map { String(localized: String.LocalizationValue(stringLiteral: $0.copyKey), table: "OpsSafety") }
                .joined(separator: "\n"))
        }
    }
}

#if DEBUG
/// Offline fixture only (`--ops-safety-fixture <scenario>`). No transport, session or
/// production approval is involved; readouts are constructed locally.
struct OpsSafetyFixtureHost: View {
    let scenario: String
    @State private var lastAction = "none"
    @State private var findings: Set<AIOutgoingSensitiveKind> = []
    private static let now = Date()
    private var decision: OpsGateDecision {
        let theme = OpsKillSwitchTarget(layer: .theme, identifier: "fixture-theme")!
        let readouts: [OpsKillSwitchReadout]
        switch scenario {
        case "payment": readouts = [.init(target: .global, state: .active(.init(blocksNewOperations: true, affectsExisting: false), incident: .paymentPendingEntitlement), observedAt: Self.now)]
        case "unverified": readouts = []
        default: readouts = [.init(target: .global, state: .inactive, observedAt: Self.now),
                             .init(target: theme, state: .active(.init(blocksNewOperations: true, affectsExisting: false), incident: .aiDisabled), observedAt: Self.now)]
        }
        return OpsKillSwitchResolver.decision(kind: .newOperation, chain: [theme], readouts: readouts, now: Self.now, maximumAge: 60)
    }
    private var node: OfflineNodeSafetyState {
        scenario == "stopped-no-alternative"
            ? .stopped(categories: [.night], alternative: nil)
            : .stopped(categories: [.businessHours, .roadTraffic], alternative: .init(nodeID: 2, title: "Fixture alternative", requiresPurchase: false))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    OpsGateNoticeView(decision: decision) { lastAction = $0.rawValue }
                    OpsGateNoticeView(decision: OpsKillSwitchResolver.decision(kind: .preservedService, chain: [], readouts: [], now: Self.now, maximumAge: 60))
                    AIIdentityDisclosureView(disclosure: .init(surface: .themeNPC))
                    OfflineNodeSafetyView(state: node, openAlternative: { lastAction = "alternative-\($0.nodeID)" }, contactSupport: { lastAction = "support" })
                    Button { findings = AIOutgoingTextScreen.findings(in: "13800138000") } label: { opsText("opsSafety.fixture.screen") }
                        .accessibilityIdentifier("opsSafety.fixture.screen")
                    Text(verbatim: lastAction).accessibilityIdentifier("opsSafety.fixture.lastAction")
                }.padding()
            }
            .modifier(AIOutgoingSensitiveConfirmation(findings: $findings, send: { lastAction = "sent" }))
            .navigationTitle(Text(LocalizedStringKey("opsSafety.fixture.title"), tableName: "OpsSafety"))
        }
    }
}
#endif
