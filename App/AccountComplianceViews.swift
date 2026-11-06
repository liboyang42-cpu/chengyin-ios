import SwiftUI

@MainActor final class ComplianceViewModel: ObservableObject {
    @Published var state: ComplianceState
    let coordinator: AccountComplianceCoordinator
    private let cancellationPresentation: AccountDeregistrationPresentation?
    private let marketingPresentation: AccountMarketingPresentation?
    private var ended = false
    init(_ coordinator: AccountComplianceCoordinator, isDeregistration: Bool = false, isMarketing: Bool = false) {
        self.coordinator = coordinator
        cancellationPresentation = isDeregistration ? coordinator.beginDeregistrationPresentation() : nil
        marketingPresentation = !isDeregistration && isMarketing ? coordinator.beginMarketingPresentation() : nil
        state = coordinator.state
        coordinator.onChange = { [weak self] value in
            guard let self else { return }
            if let lease = self.cancellationPresentation, !self.coordinator.ownsDeregistrationPresentation(lease) {
                self.state = .init()
            } else if let lease = self.marketingPresentation, !self.coordinator.ownsMarketingPresentation(lease) {
                self.state = .init()
            } else { self.state = value }
        }
    }
    func cancellationIntent(resume: Bool = false) -> AccountDeregistrationIntent? {
        guard !ended, !Task.isCancelled, let lease = cancellationPresentation else { return nil }
        if resume, !coordinator.resumeDeregistrationPresentation(lease) { state = .init(); state.error = "compliance.unavailable"; return nil }
        return coordinator.captureDeregistrationIntent(lease)
    }
    func pauseCancellation() {
        guard let lease = cancellationPresentation else { return }
        coordinator.pauseDeregistrationPresentation(lease); state = .init()
    }
    func marketingRead(resume: Bool = false) -> AccountMarketingReadIntent? {
        guard !ended, !Task.isCancelled, let lease = marketingPresentation else { return nil }
        if resume, !coordinator.resumeMarketingPresentation(lease) { state = .init(); state.error = "compliance.unavailable"; return nil }
        return coordinator.captureMarketingRead(lease)
    }
    func pauseMarketing() {
        guard let lease = marketingPresentation else { return }
        coordinator.pauseMarketingPresentation(lease); state = .init()
    }
    func endPresentation() {
        ended = true
        if cancellationPresentation != nil { pauseCancellation() }
        else if marketingPresentation != nil { pauseMarketing() }
        else { coordinator.invalidate() }
    }
}
/// Add to Settings Form with an injected coordinator; sheet dismissal never retries a write.
@MainActor struct AccountComplianceSettingsSection: View {
    let makeCoordinator: () -> AccountComplianceCoordinator
    let market: RegionalMarket?
    let legalReader: any SettingsLegalReading
    var showsNPCChatDataEntry = true
    @State private var selected: ComplianceDestination?
    @State private var npcChatData: NPCChatDataPresentation?
    var body: some View {
        Section("compliance.title") {
            ForEach(ComplianceDestination.allCases) { destination in
                if destination == .marketing {
                    NavigationLink {
                        AccountComplianceSheet(coordinator: makeCoordinator(), destination: destination,
                            market: market, legalReader: legalReader, showsCloseButton: false)
                    } label: { Text(LocalizedStringKey(destination.title)) }
                    .accessibilityIdentifier("compliance.open.\(destination.rawValue)")
                } else {
                    Button(LocalizedStringKey(destination.title)) { selected = destination }
                        .accessibilityIdentifier("compliance.open.\(destination.rawValue)")
                }
            }
            if showsNPCChatDataEntry {
            Button("npcData.title") { npcChatData = .init(coordinator: makeCoordinator().makeNPCChatDataCoordinator()) }
                .accessibilityIdentifier("npcData.open")
            }
        }
        .sheet(item: $selected) { destination in
            NavigationStack {
                AccountComplianceSheet(coordinator: makeCoordinator(), destination: destination, market: market, legalReader: legalReader)
            }
        }
        .sheet(item: $npcChatData) { presentation in NPCChatDataView(coordinator: presentation.coordinator) }
    }
}
enum ComplianceDestination: String, CaseIterable, Identifiable {
    case roam, marketing, cancellation
    var id: String { rawValue }
    var title: String { "compliance.\(rawValue)" }
}
@MainActor struct AccountComplianceSheet: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @StateObject private var model: ComplianceViewModel
    let destination: ComplianceDestination
    let market: RegionalMarket?
    let legalReader: any SettingsLegalReading
    let showsCloseButton: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var agreement = false
    @State private var document: SettingsLegalDocument?
    @State private var phone = ""
    @State private var code = ""
    @State private var cancelReview = false
    @State private var cancelIntent: AccountDeregistrationIntent?
    @State private var marketingChange: ComplianceMarketingReview?
    init(coordinator: AccountComplianceCoordinator, destination: ComplianceDestination, market: RegionalMarket?, legalReader: any SettingsLegalReading, showsCloseButton: Bool = true) {
        _model = StateObject(wrappedValue: ComplianceViewModel(coordinator, isDeregistration: destination == .cancellation, isMarketing: destination == .marketing)); self.destination = destination; self.market = market; self.legalReader = legalReader
        self.showsCloseButton = showsCloseButton
    }
    var body: some View {
        Form {
            if model.state.busy { ProgressView("compliance.loading").accessibilityIdentifier("compliance.loading") }
            if let error = model.state.error {
                Text(LocalizedStringKey(error), tableName: error == "compliance.impactChanged" ? "AccountDeregistrationPresentation" : nil)
                    .foregroundStyle(.red).accessibilityIdentifier("compliance.error")
            }
            switch destination {
            case .cancellation: cancellation
            case .roam: roam
            case .marketing: marketing
            }
        }
        .navigationTitle(Text(LocalizedStringKey(destination.title)))
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("compliance.close") { code = ""; phone = ""; dismiss() }
                }
            }
        }
        .disabled(model.state.busy)
        .interactiveDismissDisabled(model.state.busy)
        .task {
            if destination == .marketing, scenePhase == .active,
               let intent = model.marketingRead(resume: true) { await model.coordinator.loadMarketing(intent: intent) }
            if destination == .cancellation, scenePhase == .active,
               let intent = model.cancellationIntent(resume: true) { await loadCancellation(intent) }
        }
        .onDisappear {
            code = ""; phone = ""; agreement = false; cancelReview = false; cancelIntent = nil
            marketingChange = nil
            model.endPresentation()
        }
        .onChange(of: model.coordinator.deregistrationOriginalRevision) { _, _ in
            guard destination == .cancellation else { return }
            code = ""; phone = ""; agreement = false; cancelReview = false; cancelIntent = nil
            model.pauseCancellation()
        }
        .onChange(of: model.coordinator.marketingOriginalRevision) { _, _ in
            guard destination == .marketing else { return }
            marketingChange = nil; model.pauseMarketing()
        }
        .onChange(of: scenePhase) { _, phase in
            if destination == .marketing {
                marketingChange = nil
                if phase != .active { model.pauseMarketing() }
                else if let intent = model.marketingRead(resume: true) { Task { await model.coordinator.loadMarketing(intent: intent) } }
                return
            }
            guard destination == .cancellation else { return }
            code = ""; phone = ""; agreement = false; cancelReview = false; cancelIntent = nil
            if phase != .active { model.pauseCancellation() }
            else if let intent = model.cancellationIntent(resume: true) { Task { await loadCancellation(intent) } }
        }
        .confirmationDialog("compliance.cancelReview", isPresented: $cancelReview) {
            Button("compliance.cancelApplication", role: .destructive) {
                guard let intent = cancelIntent else { return }; cancelIntent = nil
                Task { await model.coordinator.cancel(explicitlyConfirmed: true, intent: intent) }
            }
        }
    }
    private func loadCancellation(_ intent: AccountDeregistrationIntent) async {
        guard model.coordinator.isCurrentDeregistrationIntent(intent) else { return }
        let availability = try? await legalReader.document(type: .cancellationNotice, market: market)
        guard model.coordinator.isCurrentDeregistrationIntent(intent), scenePhase == .active else { return }
        if case .sourceDocument(let value)? = availability { document = value } else { document = nil }
        await model.coordinator.load(intent: intent)
    }
    private func requestCancellationRead() {
        guard scenePhase == .active, let intent = model.cancellationIntent() else { return }
        cancelReview = false; cancelIntent = nil
        Task { await loadCancellation(intent) }
    }
    @ViewBuilder private var cancellation: some View {
        Section {
            Text(LocalizedStringKey(model.state.localCancellationConsent.messageKey), tableName: "AccountDeregistrationConsent")
                .accessibilityIdentifier("cancellationConsent.state")
            if let request = model.state.localCancellationConsent.requestID {
                Text("cancellationConsent.request", tableName: "AccountDeregistrationConsent").font(.caption)
                Text(verbatim: request).font(.caption).textSelection(.enabled)
            }
            Text("cancellationConsent.scope", tableName: "AccountDeregistrationConsent").font(.footnote)
        } header: {
            Text("cancellationConsent.title", tableName: "AccountDeregistrationConsent")
        }
        .accessibilityElement(children: .combine)
        if let request = model.state.originalApplicationRequestID {
            Section {
                (Text("c08.display.43", tableName: "AccountDeregistrationPresentation") + Text(verbatim: request)).font(.caption).textSelection(.enabled)
                if let receipt = model.state.originalApplication {
                    Text(receipt.outcome)
                    if receipt.reason == "ACCOUNT_IMPACT_CHANGED_REFRESH_AND_CONFIRM" { Text("c08.display.37", tableName: "AccountDeregistrationPresentation") }
                    if let impact = receipt.impactAtConfirmation { AccountDeregistrationImpactSection(impact: impact) }
                    if receipt.accepted {
                        Text("c08.display.44", tableName: "AccountDeregistrationPresentation")
                        if let applicationID = receipt.applicationId {
                            Text("c08.display.45", tableName: "AccountDeregistrationPresentation") + Text(verbatim: String(applicationID))
                        }
                    } else if receipt.settled {
                        Text("c08.display.38", tableName: "AccountDeregistrationPresentation")
                    } else { Text("c08.display.39", tableName: "AccountDeregistrationPresentation") }
                } else { Text("c08.display.40", tableName: "AccountDeregistrationPresentation") }
            } header: { Text("c08.display.36", tableName: "AccountDeregistrationPresentation") }
        }
        if let status = model.state.status {
            if let impact = status.impact { AccountDeregistrationImpactSection(impact: impact) }
            else { Text("c08.display.41", tableName: "AccountDeregistrationPresentation") }
            Section("compliance.serverStatus") {
                statusText(status.status).accessibilityIdentifier("compliance.serverStatus")
                ForEach(Array(status.blockers.enumerated()), id: \.offset) { _, blocker in Text(blocker) }
                if status.executeAfter != nil || status.pending { DeregistrationExecuteAfterRow(raw: status.executeAfter) }
            }
        }
        switch model.state.step {
        case .idle: EmptyView()
        case .notice, .blocked:
            if model.state.status?.cancellationConfirmed == true {
                Text("compliance.cancellationConfirmed", tableName: "AccountDeregistrationPresentation").accessibilityIdentifier("compliance.cancellationConfirmed")
            }
            Section {
                if let document {
                    Text(document.title).font(.headline)
                    Text(document.intro)
                    ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                        Text(section.heading).font(.headline); Text(section.body)
                    }
                    // Source content stays exact; availability is not release approval.
                    Toggle("compliance.agreeNotice", isOn: $agreement)
                        .disabled(!model.state.localCancellationConsent.allowsNewConsent)
                        .accessibilityIdentifier("compliance.agreeNotice")
                } else { Text("compliance.legalMissing") }
                Button("compliance.precheck") {
                    guard let intent = model.cancellationIntent() else { return }
                    let displayedVersion = document?.version
                    let documentWasRead = document != nil
                    let explicitlyAgreed = agreement
                    Task { await model.coordinator.precheckAndAgree(documentRead: documentWasRead,
                        explicitAgreement: explicitlyAgreed, expectedConsentVersion: displayedVersion, intent: intent) }
                }
                    .disabled(document?.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                        || !agreement || !model.state.localCancellationConsent.allowsNewConsent)
                    .accessibilityIdentifier("compliance.precheck")
            }
        case .verify:
            Section {
                TextField("compliance.phone", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad).accessibilityIdentifier("compliance.phone")
                Button("compliance.sendSMS") {
                    guard let intent = model.cancellationIntent() else { return }; let number = phone
                    Task { await model.coordinator.sendSMS(phone: number, explicitlyRequested: true, intent: intent) }
                }
                    .disabled(!model.state.localCancellationConsent.allowsNewConsent).accessibilityIdentifier("compliance.sendSMS")
                if model.state.smsSent { Text("compliance.smsSent") }
                TextField("compliance.code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad).accessibilityIdentifier("compliance.code")
                Button("compliance.review") {
                    guard model.cancellationIntent() != nil else { return }
                    model.coordinator.prepareReview(code: code); code = ""
                }.disabled(!model.state.smsSent || !model.state.localCancellationConsent.allowsNewConsent).accessibilityIdentifier("compliance.review")
            }
        case .verificationUnavailable:
            DeregistrationVerificationUnavailableSection(method: model.state.status?.verificationMethod) { requestCancellationRead() }
        case .review:
            Section {
                Text("compliance.reviewWarning")
                Text("c08.display.42", tableName: "AccountDeregistrationPresentation")
                if let impact = model.state.status?.impact, impact.confirmable {
                    AccountDeregistrationImpactConfirmation(revision: impact.revision) {
                        guard let intent = model.cancellationIntent() else { return }; code = ""; phone = ""
                        Task { await model.coordinator.apply(explicitlyConfirmed: true, intent: intent) }
                    }.id(impact.revision).disabled(!model.state.localCancellationConsent.allowsNewConsent)
                }
                Button("compliance.back") {
                    guard model.cancellationIntent() != nil else { return }
                    model.coordinator.backToVerification()
                }
            }
        case .pending:
            Text("compliance.pending")
            Button("compliance.cancelApplication", role: .destructive) { cancelIntent = model.cancellationIntent(); cancelReview = cancelIntent != nil }.accessibilityIdentifier("compliance.cancelApplication")
        case .completed: Text("compliance.completed", tableName: "AccountDeregistrationPresentation").accessibilityIdentifier("compliance.completed")
        case .freshLogin: Text("compliance.freshLogin").accessibilityIdentifier("compliance.freshLogin")
        case .unknown: Text("compliance.unknown").accessibilityIdentifier("compliance.unknown")
        }
        Button("compliance.refresh") { requestCancellationRead() }
    }
    /// Server status codes (PENDING / ELIGIBLE / BLOCKED) read as plain words, as the mini-program titles them.
    private func statusText(_ raw: String) -> Text {
        switch raw.uppercased() {
        case "PENDING": return Text("compliance.status.pending")
        case "ELIGIBLE": return Text("compliance.status.eligible")
        case "BLOCKED": return Text("compliance.status.blocked")
        default: return Text(verbatim: raw)
        }
    }
    private var roam: some View {
        Section {
            NavigationLink { SettingsLegalDocumentView(type: .privacyPolicy, market: market, reader: legalReader) } label: { Text("compliance.readPrivacy") }
            Text("compliance.roamExplanation")
            Text(LocalizedStringKey("compliance.cleanup." + String(describing: model.state.roamCleanup)))
            Button("compliance.revoke", role: .destructive) { Task { await model.coordinator.revokeRoam(explicitlyConfirmed: true) } }
                .disabled(model.state.roamCleanup == .complete).accessibilityIdentifier("compliance.revoke")
        }
    }
    private var marketing: some View {
        Section {
            Text("compliance.marketingExplanation")
            if model.state.marketingLoaded && model.state.marketing.isEmpty {
                Text("compliance.marketing.empty", tableName: "MarketingConsentOriginalPresentation").accessibilityIdentifier("compliance.marketing.empty")
            }
            Text("marketingOriginal.scope", tableName: "MarketingConsentOriginalPresentation")
            ForEach(model.state.marketingOriginalResults) { receipt in
                MarketingConsentOriginalReceiptView(receipt: receipt)
            }
            if !model.state.marketingLoaded {
                Text("marketingOriginal.current.unconfirmed", tableName: "MarketingConsentOriginalPresentation")
            }

            if !model.state.marketingUnresolved.isEmpty {
                Text("compliance.marketing.unknown", tableName: "MarketingConsentOriginalPresentation").accessibilityIdentifier("compliance.marketing.unknown")
            }
            if !model.state.marketing.isEmpty {
                Text("marketingOriginal.current.title", tableName: "MarketingConsentOriginalPresentation")
                    .font(.headline).accessibilityAddTraits(.isHeader)
            }
            ForEach(model.state.marketing) { row in
                VStack(alignment: .leading) {
                    Text(row.merchantName ?? appLocalized("compliance.merchant", locale: locale))
                    ForEach(ComplianceMarketingChannel.allCases, id: \.rawValue) { channel in
                        Toggle(LocalizedStringKey("compliance.channel." + channel.rawValue), isOn: Binding(get: { row.value(channel) }, set: { value in
                            guard scenePhase == .active, model.marketingRead() != nil else { return }
                            marketingChange = model.coordinator.reviewMarketing(row, channel: channel, optedIn: value)
                        }))
                            .disabled(model.coordinator.reviewMarketing(row, channel: channel, optedIn: !row.value(channel)) == nil)
                            .accessibilityIdentifier("compliance.marketing.\(row.id).\(channel.rawValue)")
                    }
                }
            }
            Button("compliance.refresh") {
                guard scenePhase == .active, let intent = model.marketingRead() else { return }
                marketingChange = nil
                Task { await model.coordinator.loadMarketing(intent: intent) }
            }.accessibilityIdentifier("compliance.marketing.refresh")
        }
        .confirmationDialog(Text("compliance.marketing.review", tableName: "MarketingConsentOriginalPresentation"), isPresented: Binding(
            get: { marketingChange != nil }, set: { if !$0 { marketingChange = nil } }), titleVisibility: .visible) {
            if let change = marketingChange {
                Button {
                    guard scenePhase == .active, model.marketingRead() != nil else { marketingChange = nil; return }
                    marketingChange = nil
                    Task { await model.coordinator.setMarketing(change, explicitlyConfirmed: true) }
                } label: { Text(change.optedIn ? "compliance.marketing.confirmOptIn" : "compliance.marketing.confirmOptOut", tableName: "MarketingConsentOriginalPresentation") }
                    .accessibilityIdentifier("compliance.marketing.confirm")
                Button("compliance.close", role: .cancel) { marketingChange = nil }
            }
        } message: {
            if let change = marketingChange {
                Text(verbatim: change.row.merchantName ?? appLocalized("compliance.merchant", locale: locale))
                Text(LocalizedStringKey("compliance.channel." + change.channel.rawValue))
            }
        }
    }
}

/// Bridge for Registration/Play merchant-on-site consent. Content must be source-backed and
/// approved independently; missing content never becomes a guessed legal statement.
@MainActor struct ComplianceConsentReviewSheet: View {
    let subject: ComplianceSubject
    let sourceText: String?
    let service: AccountComplianceService
    let session: ComplianceSession
    let onConfirmed: (ComplianceConsent) -> Void
    @State private var agreed = false
    @State private var busy = false
    @State private var errorKey: String?
    @State private var requestID = UUID().uuidString
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            if let sourceText, !sourceText.isEmpty {
                Text(sourceText).accessibilityIdentifier("compliance.scope.document")
                Toggle("compliance.scope.agree", isOn: $agreed)
                Button("compliance.scope.confirm") {
                    Task {
                        guard !busy, agreed else { return }; busy = true; defer { busy = false }
                        do {
                            let record = try await service.consent(subject, event: .agree, requestID: requestID, session: session)
                            try service.check(session); onConfirmed(record); dismiss()
                        } catch { errorKey = "compliance.unknown" }
                    }
                }.disabled(!agreed || busy).accessibilityIdentifier("compliance.scope.confirm")
            } else { Text("compliance.legalMissing") }
            if busy { ProgressView("compliance.loading") }
            if let errorKey { Text(LocalizedStringKey(errorKey)) }
        }
        .interactiveDismissDisabled(busy)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("compliance.close") { dismiss() }.disabled(busy) } }
    }
}

/// The registration host can inspect the missing/legal-gated source without granting creation.
private struct ComplianceSignupDestinationKey: EnvironmentKey {
    static let defaultValue: (() -> AnyView)? = nil
}
extension EnvironmentValues {
    var complianceSignupDestination: (() -> AnyView)? {
        get { self[ComplianceSignupDestinationKey.self] }
        set { self[ComplianceSignupDestinationKey.self] = newValue }
    }
}
@MainActor struct SessionComplianceSignupView: View {
    @ObservedObject var session: AppSession
    var body: some View {
        Group {
            if let context = session.complianceSignupContext() {
                ComplianceConsentReviewSheet(subject: .signup, sourceText: nil, service: context.0,
                    session: context.1, onConfirmed: { _ in })
            } else { Text("compliance.legalMissing") }
        }.id(session.sessionRevision)
    }
}
