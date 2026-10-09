import SwiftUI

@MainActor final class ComplianceViewModel: ObservableObject {
    @Published var state: ComplianceState
    let coordinator: AccountComplianceCoordinator
    init(_ coordinator: AccountComplianceCoordinator) {
        self.coordinator = coordinator; state = coordinator.state
        coordinator.onChange = { [weak self] in self?.state = $0 }
    }
}
/// Add to Settings Form with an injected coordinator; sheet dismissal never retries a write.
@MainActor struct AccountComplianceSettingsSection: View {
    let makeCoordinator: () -> AccountComplianceCoordinator
    let market: RegionalMarket?
    let legalReader: any SettingsLegalReading
    @State private var selected: ComplianceDestination?
    @State private var npcChatData: NPCChatDataPresentation?
    var body: some View {
        Section("compliance.title") {
            ForEach(ComplianceDestination.allCases) { destination in
                Button(LocalizedStringKey(destination.title)) { selected = destination }
                    .accessibilityIdentifier("compliance.open.\(destination.rawValue)")
            }
            Button("npcData.title") { npcChatData = .init(coordinator: makeCoordinator().makeNPCChatDataCoordinator()) }
                .accessibilityIdentifier("npcData.open")
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
    @Environment(\.locale) private var locale
    @StateObject private var model: ComplianceViewModel
    let destination: ComplianceDestination
    let market: RegionalMarket?
    let legalReader: any SettingsLegalReading
    @Environment(\.dismiss) private var dismiss
    @State private var agreement = false
    @State private var document: SettingsLegalDocument?
    @State private var phone = ""
    @State private var code = ""
    @State private var cancelReview = false
    init(coordinator: AccountComplianceCoordinator, destination: ComplianceDestination, market: RegionalMarket?, legalReader: any SettingsLegalReading) {
        _model = StateObject(wrappedValue: ComplianceViewModel(coordinator)); self.destination = destination; self.market = market; self.legalReader = legalReader
    }
    var body: some View {
        Form {
            if model.state.busy { ProgressView("compliance.loading").accessibilityIdentifier("compliance.loading") }
            if let error = model.state.error { Text(LocalizedStringKey(error)).foregroundStyle(.red).accessibilityIdentifier("compliance.error") }
            switch destination {
            case .cancellation: cancellation
            case .roam: roam
            case .marketing: marketing
            }
        }
        .navigationTitle(Text(LocalizedStringKey(destination.title)))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("compliance.close") { code = ""; phone = ""; dismiss() } } }
        .disabled(model.state.busy)
        .interactiveDismissDisabled(model.state.busy)
        .task {
            if destination == .marketing { await model.coordinator.loadMarketing() }
            if destination == .cancellation {
                if let availability = try? await legalReader.document(type: .cancellationNotice, market: market), case .sourceDocument(let value) = availability { document = value }
                await model.coordinator.load()
            }
        }
        .onDisappear { code = ""; phone = ""; model.coordinator.invalidate() }
        .confirmationDialog("compliance.cancelReview", isPresented: $cancelReview) {
            Button("compliance.cancelApplication", role: .destructive) { Task { await model.coordinator.cancel(explicitlyConfirmed: true) } }
        }
    }
    @ViewBuilder private var cancellation: some View {
        if let status = model.state.status {
            Section("compliance.serverStatus") {
                Text(status.status).accessibilityIdentifier("compliance.serverStatus")
                ForEach(Array(status.blockers.enumerated()), id: \.offset) { _, blocker in Text(blocker) }
                if let time = status.executeAfter { LabeledContent("compliance.executeAfter", value: time) }
            }
        }
        switch model.state.step {
        case .idle: EmptyView()
        case .notice, .blocked:
            Section {
                if let document {
                    Text(document.title).font(.headline)
                    Text(document.intro)
                    ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                        Text(section.heading).font(.headline); Text(section.body)
                    }
                    // Source content stays exact; availability is not release approval.
                    Toggle("compliance.agreeNotice", isOn: $agreement).accessibilityIdentifier("compliance.agreeNotice")
                } else { Text("compliance.legalMissing") }
                Button("compliance.precheck") { Task { await model.coordinator.precheckAndAgree(documentRead: document != nil, explicitAgreement: agreement) } }
                    .disabled(document == nil || !agreement).accessibilityIdentifier("compliance.precheck")
            }
        case .verify:
            Section {
                TextField("compliance.phone", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad).accessibilityIdentifier("compliance.phone")
                Button("compliance.sendSMS") { Task { await model.coordinator.sendSMS(phone: phone, explicitlyRequested: true) } }.accessibilityIdentifier("compliance.sendSMS")
                if model.state.smsSent { Text("compliance.smsSent") }
                TextField("compliance.code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad).accessibilityIdentifier("compliance.code")
                Button("compliance.review") { model.coordinator.prepareReview(code: code); code = "" }.disabled(!model.state.smsSent).accessibilityIdentifier("compliance.review")
            }
        case .review:
            Section {
                Text("compliance.reviewWarning")
                Button("compliance.submit", role: .destructive) { Task { await model.coordinator.apply(explicitlyConfirmed: true); code = ""; phone = "" } }.accessibilityIdentifier("compliance.submit")
                Button("compliance.back") { model.coordinator.backToVerification() }
            }
        case .pending:
            Text("compliance.pending")
            Button("compliance.cancelApplication", role: .destructive) { cancelReview = true }.accessibilityIdentifier("compliance.cancelApplication")
        case .freshLogin: Text("compliance.freshLogin").accessibilityIdentifier("compliance.freshLogin")
        case .unknown: Text("compliance.unknown").accessibilityIdentifier("compliance.unknown")
        }
        Button("compliance.refresh") { Task { await model.coordinator.load() } }
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
            ForEach(model.state.marketing) { row in
                VStack(alignment: .leading) {
                    Text(row.merchantName ?? appLocalized("compliance.merchant", locale: locale))
                    ForEach(ComplianceMarketingChannel.allCases, id: \.rawValue) { channel in
                        Toggle(LocalizedStringKey("compliance.channel." + channel.rawValue), isOn: Binding(get: { row.value(channel) }, set: { value in Task { await model.coordinator.setMarketing(row, channel: channel, optedIn: value) } }))
                            .accessibilityIdentifier("compliance.marketing.\(row.id).\(channel.rawValue)")
                    }
                }
            }
            Button("compliance.refresh") { Task { await model.coordinator.loadMarketing() } }
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
