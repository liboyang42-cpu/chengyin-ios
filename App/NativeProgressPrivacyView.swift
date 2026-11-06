import SwiftUI

@MainActor struct NativeProgressPrivacyView: View {
    @State var flow: NativeProgressPrivacyFlow
    @Environment(\.locale) private var locale
    private var copy: NativeProgressPrivacyLocalization { .init(locale: locale) }
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Form {
            Section(copy.text("p31.overview")) {
                Text(copy.text("p31.explanation"))
                Text(copy.text("p31.unopened"))
            }
            if let result = flow.result { Section { Text(verbatim: copy.result(flow.resultPresentation, fallback: result)) } }
            if let request = flow.requestID {
                Section(copy.text("p31.recovery.title")) {
                    Text(verbatim: copy.pending(flow.pendingTarget, fallback: flow.pendingLabel))
                    Text(verbatim: request).textSelection(.enabled)
                    Text(copy.text("p31.recovery.unknown"))
                    Button(copy.text("p31.recovery.read")) { Task { await flow.recover() } }.disabled(!flow.canRecover)
                }
            }
            if let value = flow.snapshot {
                Section(copy.text(value.kind == .user ? "p31.current.user" : "p31.current.channel")) {
                    LabeledContent(copy.text("p31.scope"), value: copy.scope(value.aggregate))
                    if value.isDefault { Text(copy.text("p31.default")) }
                    if let updated = value.updatedAt { LabeledContent(copy.text("p31.updated"), value: updated) }
                    if let revision = value.revision { LabeledContent(copy.text("p31.revision"), value: String(revision)) }
                    switch value.aggregateReadState {
                    case .confirmedAbsentDefault:
                        Text(copy.text("p31.factor.default"))
                    case .configuredConsumerConfirmed:
                        Text(copy.text("p31.factor.confirmed"))
                    case .configuredConsumerUnconfirmed:
                        Text(copy.text("p31.factor.unconfirmed"))
                    }
                    Text(copy.text("p31.noGlobalEffective"))
                    Text(copy.text("p31.noExtraAccess"))
                    if flow.writeAuthorityPresentation?.isReadOnly == true { Text(copy.text("p31.noWrite")) }
                }
                Section(copy.text("p31.prepare")) {
                    ForEach(NativeProgressPrivacyScope.allCases) { scope in
                        Button(copy.scope(scope)) { flow.prepare(scope) }.disabled(!flow.canEdit || value.aggregate == scope)
                    }
                }
            }
            if let command = flow.reviewedCommand {
                Section(copy.text("p31.confirm.title")) {
                    Text(verbatim: copy.format("p31.confirm.scope", copy.scope(command.aggregate)))
                    Button(copy.text("p31.confirm.submit")) { Task { await flow.confirm(expected: command) } }.disabled(!flow.canConfirm)
                    Button(copy.text("p31.confirm.cancel")) { flow.cancelReview() }
                }
            }
            Section {
                if flow.phase == .loading || flow.phase == .saving { ProgressView() }
                if flow.phase == .closed { Text(copy.text("p31.closed")) }
                if flow.phase == .unknown { Text(copy.text("p31.unknown")) }
                if flow.phase == .unavailable { Text(copy.text("p31.unavailable")) }
                Button(copy.text("p31.refresh")) { Task { await flow.refresh() } }.disabled(!flow.canRefresh)
            }
        }
        .navigationTitle(copy.text("p31.title")).privacySensitive()
        .task { await flow.activate() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await flow.activate() } } else { flow.deactivate() } }
        .onDisappear { flow.deactivate() }
    }
}

/// Every opening comes from the original CLUB channel context; no caller-supplied numeric identity grants access.
@MainActor struct NativeChannelOverviewPrivacyEntry: View {
    @Environment(\.locale) private var locale
    private var copy: NativeProgressPrivacyLocalization { .init(locale: locale) }
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeProgressPrivacyFlow?
    @State private var flow: NativeProgressPrivacyFlow?
    @State private var generation: UInt64 = 0
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let flow { NativeProgressPrivacyView(flow: flow).id(ObjectIdentifier(flow)) }
            else { VStack { Text(copy.text("p31.channel.unavailable")); Button(copy.text("p31.channel.refresh")) { Task { await open() } } } }
        }
        .task { await open() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await open() } } else { close() } }
        .onDisappear { close() }.privacySensitive()
    }
    private func close() { generation &+= 1; flow?.deactivate(); flow = nil }
    private func open() async {
        close(); let stamp = generation
        do {
            let captured = try await channels.currentChannelContext(channelID: channelID)
            guard generation == stamp, scenePhase == .active, !Task.isCancelled, channels.contextIsCurrent(captured),
                  captured.ownerType == "CLUB", captured.serverPermissionNames.isSuperset(of: ["VIEW_CHANNEL", "MANAGE_PROGRESS"]) else { return }
            flow = makeFlow(captured)
        } catch { }
    }
}

/// UI-only catalog lookup. No journal access, permission inference, command or cached language.
@MainActor struct NativeProgressPrivacyLocalization {
    let locale: Locale
    func text(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
                                                 table: "NativeChannelProgress", locale: locale))
    }
    func format(_ key: String, _ values: String...) -> String {
        String(format: text(key), locale: locale, arguments: values.map { $0 as CVarArg })
    }
    func scope(_ value: NativeProgressPrivacyScope) -> String { text("p31.scope." + value.rawValue) }
    func number(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
    func pending(_ target: NativeProgressPrivacyTarget?, fallback: String?) -> String {
        guard let target else { return fallback ?? text("p31.pending.generic") }
        return target.kind == .user ? text("p31.pending.user") : format("p31.pending.channel", String(target.id))
    }
    func result(_ kind: NativeProgressPrivacyFlow.ResultPresentation?, fallback: String) -> String {
        guard let kind else { return fallback } // Unknown original prose remains original; never infer success.
        switch kind {
        case .notSent: return text("p31.result.notSent")
        case .applied: return text("p31.result.applied")
        case .conflict: return text("p31.result.conflict")
        }
    }
}
