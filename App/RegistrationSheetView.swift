import SwiftUI

@MainActor
private final class RegistrationSheetModel: ObservableObject {
    let flow: RegistrationUIFlow
    @Published private(set) var revision: UInt64 = 0
    init(flow: RegistrationUIFlow) {
        self.flow = flow
        flow.onChange = { [weak self] in self?.revision &+= 1 }
    }
}

/// Inject the stable session-owned coordinator; never allocate one in a sheet builder.
/// Production needs an independent scoped grant; default creation and waitlist writes stay off.
@MainActor
struct RegistrationSheetView: View {
    @Environment(\.complianceSignupDestination) private var complianceSignupDestination
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @StateObject private var model: RegistrationSheetModel
    @FocusState private var focusedField: Field?
    @State private var showingConfirmation = false
    @State private var showingAddParticipant = false
    private let participantReader: (any ProfileReading)?
    private let participantCoordinator: ParticipantMutationCoordinator?
    private enum Field { case name, phone }

    init(activity: ActivityDetail, coordinator: RegistrationCoordinator,
         participantReader: (any ProfileReading)? = nil,
         participantCoordinator: ParticipantMutationCoordinator? = nil,
         currentIdentity: @escaping () -> ProfileReadIdentity?, quoteEnabled: Bool = false,
         creationPolicy: RegistrationUICreationPolicy = .disabled,
         waitlistService: (any RegistrationWaitlistServing)? = nil,
         onReadback: @escaping (RegistrationStatusSnapshot) -> Void = { _ in }) {
        self.participantReader = participantReader; self.participantCoordinator = participantCoordinator
        _model = StateObject(wrappedValue: RegistrationSheetModel(flow: RegistrationUIFlow(
            activity: activity, coordinator: coordinator, participantReader: participantReader,
            currentIdentity: currentIdentity, quoteEnabled: quoteEnabled,
            creationPolicy: creationPolicy, waitlistService: waitlistService, onReadback: onReadback)))
    }
    #if DEBUG
    /// Offline fixture-only injection keeps the real view/controller clock and guards intact.
    init(fixtureFlow: RegistrationUIFlow) {
        participantReader = nil; participantCoordinator = nil
        _model = StateObject(wrappedValue: RegistrationSheetModel(flow: fixtureFlow))
    }
    #endif
    private var flow: RegistrationUIFlow { model.flow }
    var body: some View {
        // Observe the controller notification even though its fields live in a reference type.
        let _ = model.revision
        NavigationStack {
            Form {
                if flow.creationPolicy.isOfflineFixture {
                    Section { Label("registration.form.fixtureNotice", systemImage: "testtube.2").font(.callout) }
                }
                if !flow.hasCurrentSession {
                    Section { Label("registration.form.sessionChanged", systemImage: "person.crop.circle.badge.exclamationmark") }
                } else {
                    activitySection
                    if flow.hasRetainedIntent {
                        RegistrationOperationSections(flow: flow,revision:model.revision)
                    } else if case .pending(let registrationID) = flow.durableCreation {
                        Section("registration.form.outcomeUnknown") {
                            Text("registration.waitlist.retainedOrder")
                            if registrationID != nil {
                                Button("registration.waitlist.readRetainedOrder") { Task { await flow.readDurableStatus() } }
                                    .disabled(flow.isReadingStatus)
                            }
                            if let snapshot = flow.durableStatus {
                                Text(LocalizedStringKey(RegistrationUIStatus.registrationKey(snapshot.registrationStatus)))
                                Text("registration.waitlist.orderReadback").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        participantSection
                        ticketSection
                        waitlistSection
                        quoteSection
                        confirmationSection
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .appNavigationTitle("registration.form.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { flow.leave(); dismiss() }
                        .accessibilityIdentifier("registration.form.close")
                }
            }
            .alert(LocalizedStringKey(flow.creationPolicy.isOfflineFixture ? "registration.form.confirmTitle" : "registration.waitlist.confirmTitle"), isPresented: $showingConfirmation) {
                Button(LocalizedStringKey(flow.creationPolicy.isOfflineFixture ? "registration.form.confirmCreate" : "registration.waitlist.confirmCreate")) { Task { await flow.confirm() } }
                Button("action.cancel", role: .cancel) { flow.cancelConfirmation() }
            } message: {
                if let review = flow.confirmation {
                    Text(LocalizedStringKey(flow.creationPolicy.isOfflineFixture ? "registration.form.confirmHint" : "registration.waitlist.confirmHint"))
                    + Text(verbatim: "\n\(flow.activity.summary.name)\n\(flow.selectedTicket?.name ?? "")\n\(review.draft.trimmedName)\n\(review.draft.trimmedPhone)\n")
                    + Text(verbatim: RegistrationUIMoney.display(review.quote.payAmount, locale: locale) ?? "—")
                }
            }
            .task(id: flow.identity) {
                flow.open()
                // Independent reads: a slow participant list must not hide the quote form.
                async let participants: Void = flow.loadParticipants()
                async let quote: Void = flow.requestQuote()
                _ = await (participants, quote)
            }
            .task(id: flow.waitlistReadKey) { await flow.loadWaitlist() }
            .task(id: flow.waitlistStatus?.expiresAt) {
                guard let deadline = flow.waitlistStatus?.expiresAt else { return }
                while deadline > Date() {
                    do { try await Task.sleep(for: .seconds(min(deadline.timeIntervalSinceNow, 86_400))) } catch { return }
                }
                flow.checkWaitlistDeadline()
            }
            .sheet(isPresented: $showingAddParticipant) {
                if let participantReader, let participantCoordinator {
                    NavigationStack {
                        ParticipantFormView(reader: participantReader, coordinator: participantCoordinator,
                            onSaved: { if participantCoordinator.savedParticipant == nil { Task { await flow.loadParticipants() } } },
                            onCreated: { row, identity in Task { await flow.selectCreatedParticipant(row, identity: identity) } })
                    }
                }
            }
            .onChange(of: flow.identity) { _, _ in showingAddParticipant = false }
            .onChange(of: flow.confirmation) { _, value in
                if value == nil { showingConfirmation = false }
            }
            .onDisappear { flow.leave() }
        }
        .accessibilityIdentifier("registration.form.sheet")
    }
    private var activitySection: some View {
        Section("registration.form.activity") {
            Text(verbatim: flow.activity.summary.name).font(.headline)
            if let date = flow.activity.summary.startDate, !date.isEmpty {
                LabeledContent("registration.form.startDate", value: date)
            }
            if let date = flow.activity.summary.endDate, !date.isEmpty {
                LabeledContent("registration.form.endDate", value: date)
            }
            if let address = flow.activity.summary.addressName ?? flow.activity.summary.address, !address.isEmpty {
                Label { Text(verbatim: address) } icon: { Image(systemName: "mappin.and.ellipse") }
            }
        }
    }
    private var participantSection: some View {
        Section {
            if flow.participantsState == .loading {
                ProgressView("registration.form.loadingParticipants")
            } else if flow.participantsState == .unavailable {
                Text("registration.form.participantReadFailed").foregroundStyle(.secondary)
                Button("registration.form.reloadParticipants") { Task { await flow.loadParticipants() } }
                    .accessibilityIdentifier("registration.form.reloadParticipants")
            } else if !flow.participants.isEmpty {
                Picker("registration.form.savedParticipant", selection: Binding<Int?>(
                    get: { flow.selectedParticipantID },
                    set: { if let id = $0 { flow.selectParticipant(id: id) } else { flow.useManualEntry() } }
                )) {
                    Text("registration.form.manualEntry").tag(Optional<Int>.none)
                    ForEach(flow.participants) { participant in
                        Text(verbatim: participant.fullName).tag(Optional(participant.id))
                    }
                }.accessibilityIdentifier("registration.form.participantPicker")
            }
            if participantReader != nil, participantCoordinator != nil {
                Button("participant.form.add") { focusedField = nil; showingAddParticipant = true }
                    .disabled(!flow.canEdit).accessibilityIdentifier("registration.form.addParticipant")
            }
            TextField("registration.form.name", text: Binding(get: { flow.draft.realName }, set: flow.setName))
                .textContentType(.name).textInputAutocapitalization(.words)
                .focused($focusedField, equals: .name).submitLabel(.next)
                .onSubmit { focusedField = .phone }
                .accessibilityIdentifier("registration.form.name")
            TextField("registration.form.phone", text: Binding(get: { flow.draft.phone }, set: flow.setPhone))
                .textContentType(.telephoneNumber).keyboardType(.phonePad)
                .focused($focusedField, equals: .phone)
                .accessibilityIdentifier("registration.form.phone")
            if !flow.draft.phone.isEmpty, flow.draft.validation == .invalidPhone {
                Text("registration.form.phoneHint").font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("registration.form.contact") } footer: { Text("registration.form.contactHint") }
        .disabled(!flow.canEdit)
    }
    private var ticketSection: some View {
        Section("registration.form.ticket") {
            if flow.activity.tickets.isEmpty {
                Text("registration.form.noTickets").foregroundStyle(.secondary)
            } else {
                Picker("registration.form.ticket", selection: Binding<Int?>(
                    get: { flow.selectedTicketID },
                    set: { if flow.selectTicket(id: $0) { Task { await flow.requestQuote() } } }
                )) {
                    ForEach(flow.activity.tickets) { ticket in
                        Text(verbatim: ticket.name).tag(Optional(ticket.id))
                    }
                }.disabled(!flow.canEdit).accessibilityIdentifier("registration.form.ticketPicker")
                if let ticket = flow.selectedTicket {
                    RegistrationAmountRow(key: "registration.form.ticketPrice", amount: ticket.price)
                    if let description = ticket.description, !description.isEmpty { Text(verbatim: description) }
                    if ticket.isSoldOut {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(LocalizedStringKey(RegistrationUIWaitlistGuidance.soldOutKey(
                                available: flow.waitlistAvailable, status: flow.waitlistStatus,
                                outcomeUnknown: flow.waitlistOutcomeUnknown, now: context.date)))
                                .foregroundStyle(.secondary).accessibilityIdentifier("registration.form.soldOutGuidance")
                        }
                    } else if ticket.remainingInventory == nil {
                        Text("registration.form.inventoryUnknown").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    @ViewBuilder private var waitlistSection: some View {
        if flow.selectedTicket?.isSoldOut == true || flow.waitlistStatus != nil {
            Section {
                if !flow.waitlistAvailable {
                    Text("registration.waitlist.disabled").foregroundStyle(.secondary)
                } else {
                    if flow.isReadingWaitlist || flow.isMutatingWaitlist { ProgressView("registration.waitlist.loading") }
                    if flow.waitlistOutcomeUnknown { Text("registration.waitlist.unknown").foregroundStyle(.secondary) }
                    if let status = flow.waitlistStatus {
                        Text(LocalizedStringKey("registration.waitlist.state." + status.state.rawValue))
                        if status.eligibility != .eligible {
                            Text(LocalizedStringKey("registration.waitlist.eligibility." + status.eligibility.rawValue)).foregroundStyle(.secondary)
                        }
                        if status.state == .offered, let deadline = status.expiresAt {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                if deadline > context.date {
                                    LabeledContent("registration.waitlist.remaining") {
                                        Text(timerInterval: context.date...deadline, countsDown: true).monospacedDigit()
                                    }
                                } else { Text("registration.waitlist.state.EXPIRED") }
                            }
                            Text("registration.waitlist.singleTicket").font(.caption).foregroundStyle(.secondary)
                            Button("registration.waitlist.reviewOffer") { Task { await flow.reviewWaitlistOffer() } }
                                .disabled(!flow.canEdit || flow.isReadingWaitlist)
                                .accessibilityIdentifier("registration.waitlist.reviewOffer")
                        }
                        if status.registrationID != nil {
                            Text("registration.waitlist.orderReadback").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if flow.block == .waitlistUnavailable { Text("registration.waitlist.unavailable") }
                    Button("registration.waitlist.refresh") { Task { await flow.loadWaitlist() } }
                        .disabled(!flow.canEdit || flow.isReadingWaitlist)
                        .accessibilityIdentifier("registration.waitlist.refresh")
                    if flow.canJoinWaitlist {
                        Button("registration.waitlist.join") { Task { await flow.joinWaitlist() } }
                            .accessibilityIdentifier("registration.waitlist.join")
                    }
                    if flow.canCancelWaitlist {
                        Button("registration.waitlist.cancel", role: .destructive) { Task { await flow.cancelWaitlist() } }
                            .accessibilityIdentifier("registration.waitlist.cancel")
                    }
                }
            } header: { Text("registration.waitlist.title") } footer: { Text("registration.waitlist.noAutoPayment") }
        }
    }
    private var quoteSection: some View {
        Section {
            if !flow.quoteEnabled {
                Text("registration.form.quoteDisabled").foregroundStyle(.secondary)
            } else if flow.isQuoting {
                ProgressView("registration.form.quoting").accessibilityIdentifier("registration.form.quoting")
            } else {
                switch flow.quoteState {
                case .received(let quote):
                    RegistrationAmountRow(key: "registration.form.memberDiscount", amount: quote.memberDiscountYuan, deduction: true, currencyCode: RegistrationUIMoney.yuanCurrencyCode)
                    RegistrationAmountRow(key: "registration.form.couponDiscount", amount: quote.couponDeductYuan, deduction: true, currencyCode: RegistrationUIMoney.yuanCurrencyCode)
                    RegistrationAmountRow(key: "registration.form.pointsDiscount", amount: quote.pointsDeductYuan, deduction: true, currencyCode: RegistrationUIMoney.yuanCurrencyCode)
                    LabeledContent("registration.form.pointsUsed") {
                        Text(verbatim: String(quote.pointsUsed)).foregroundStyle(Color.primary)
                    }
                    if quote.pointsUsable {
                        Toggle("registration.form.usePoints", isOn: Binding(
                            get: { flow.usePoints },
                            set: { if flow.setUsePoints($0) { Task { await flow.requestQuote() } } }
                        )).disabled(!flow.canEdit).accessibilityIdentifier("registration.form.usePoints")
                        if flow.usePoints, quote.pointsDeductYuan == .zero {
                            Text("registration.form.insufficientPoints").font(.caption).foregroundStyle(.secondary)
                        }
                    } else { Text("registration.form.pointsUnavailable").foregroundStyle(.secondary) }
                    RegistrationAmountRow(key: "registration.form.total", amount: quote.payAmount)
                        .font(.headline).accessibilityIdentifier("registration.form.total")
                    if !quote.isUsableForCreate { Text("registration.form.incompleteQuote").foregroundStyle(.secondary) }
                case .unavailable(let issue):
                    Text("registration.form.quoteFailed").foregroundStyle(.secondary)
                    RegistrationIssueText(issue: issue)
                case .idle, .loading:
                    Text("registration.form.quoteNeeded").foregroundStyle(.secondary)
                }
            }
            Button("registration.form.refreshQuote") { Task { await flow.requestQuote() } }
                .disabled(!flow.quoteEnabled || !flow.canEdit || flow.isQuoting)
                .accessibilityIdentifier("registration.form.refreshQuote")
        } header: { Text("registration.form.fees") } footer: { Text("registration.form.currencyHint") }
    }
    private var confirmationSection: some View {
        Section {
            if flow.creationPolicy.permitsCreation {
                if case .approved(let grant) = flow.creationPolicy {
                    Link("registration.waitlist.legalNotice", destination: grant.noticeURL)
                    if let complianceSignupDestination {
                        NavigationLink { complianceSignupDestination() } label: { Text("compliance.title") }
                    }
                }
                Toggle(LocalizedStringKey(flow.creationPolicy.isOfflineFixture ? "registration.form.fixtureConsent" : "registration.waitlist.reviewConsent"), isOn: Binding(get: { flow.consented }, set: flow.setConsent))
                    .disabled(!flow.canEdit).accessibilityIdentifier("registration.form.consent")
                if case .approved = flow.creationPolicy {
                    Button("registration.waitlist.recordConsent") { Task { await flow.recordSignupConsent() } }
                        .disabled(!flow.canEdit || !flow.consented)
                        .accessibilityIdentifier("registration.waitlist.recordConsent")
                    if flow.isRecordingConsent { ProgressView("registration.waitlist.recordingConsent") }
                    if flow.block == .missingConsent { Text("registration.waitlist.consentUnknown").foregroundStyle(.secondary) }
                }
            } else {
                Label("registration.form.creationDisabled", systemImage: "lock")
                    .accessibilityIdentifier("registration.form.creationDisabled")
                Text("registration.form.creationDisabledHint").font(.callout).foregroundStyle(.secondary)
                if let complianceSignupDestination {
                    NavigationLink { complianceSignupDestination() } label: { Text("compliance.title") }
                        .accessibilityIdentifier("compliance.signup.reviewSource")
                }
            }
            if flow.block == .confirmationChanged { Text("registration.form.confirmationChanged").foregroundStyle(.secondary) }
            Button {
                focusedField = nil
                if flow.prepareConfirmation() { showingConfirmation = true }
            } label: { Text("registration.form.review").frame(maxWidth: .infinity, minHeight: 44) }
            .buttonStyle(.borderedProminent).disabled(flow.confirmationBlock != nil)
            .accessibilityIdentifier("registration.form.review")
        } footer: { Text("registration.form.sharingPurpose") }
    }
}

private struct RegistrationAmountRow: View {
    @Environment(\.locale) private var locale
    let key: String
    let amount: Decimal?
    var deduction = false
    var currencyCode: String? = nil
    var body: some View {
        LabeledContent {
            if let text = RegistrationUIMoney.display(amount, locale: locale, currencyCode: currencyCode) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: deduction && amount != .zero ? "−\(text)" : text)
                        .foregroundStyle(Color.primary).accessibilityIdentifier(key + ".amount")
                    if currencyCode == nil { Text("registration.form.currencyUnknown").font(.caption).foregroundStyle(.primary) }
                }
            } else { Text("registration.form.unknownAmount").foregroundStyle(Color.primary) }
        } label: { Text(LocalizedStringKey(key)) }
    }
}

/// Do not display arbitrary Error descriptions, quote signatures, provider parameters,
/// credentials or contact fields. Verified structured server messages remain available.
private struct RegistrationIssueText: View {
    let issue: RegistrationCoordinatorIssue
    private var message: String? {
        switch issue {
        case .business(let failure): return failure.message
        case .http(let failure): return failure.response?.message
        default: return nil
        }
    }
    var body: some View {
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(verbatim: message).font(.callout).foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct RegistrationOperationSections: View {
    let flow: RegistrationUIFlow
    let revision:UInt64
    var body: some View {
        if flow.retainedForAnotherActivity {
            Section { Text("registration.form.otherActivityIntent").foregroundStyle(.secondary) }
        }
        switch flow.creationState {
        case .idle: EmptyView()
        case .submitting:
            Section { ProgressView("registration.form.creating") }
        case .outcomeUnknown:
            Section("registration.form.outcomeUnknown") {
                Text("registration.form.outcomeUnknownHint")
                    .accessibilityIdentifier("registration.form.outcomeUnknown")
                Text("registration.form.retainedIntentHint").font(.caption).foregroundStyle(.secondary)
            }
        case .responseReceived(_, let result):
            Section("registration.form.createdResponse") {
                LabeledContent("registration.form.registrationID", value: String(result.registrationID))
                if let number = result.registrationNo, !number.isEmpty {
                    LabeledContent("registration.form.registrationNumber", value: number)
                }
                RegistrationAmountRow(key: "registration.form.total", amount: result.payableAmount)
                Text(LocalizedStringKey(result.hasPaymentParameters ? "registration.form.paymentNotStarted" : "registration.form.noPaymentProof"))
                    .foregroundStyle(.secondary)
                Button("registration.form.readStatus") { Task { await flow.readKnownStatus() } }
                    .disabled(!flow.canReadStatus).accessibilityIdentifier("registration.form.readStatus")
                Text("registration.form.retainedIntentHint").font(.caption).foregroundStyle(.secondary)
            }
        }
        switch flow.readbackState {
        case .idle: EmptyView()
        case .loading: Section { ProgressView("registration.form.readingStatus") }
        case .unavailable(_, let issue):
            Section {
                Text("registration.form.statusUnavailable")
                RegistrationIssueText(issue: issue)
            }
        case .received(let snapshot):
            Section("registration.form.serverStatus") {
                LabeledContent("registration.form.registrationStatus") {
                    Text(LocalizedStringKey(RegistrationUIStatus.registrationKey(snapshot.registrationStatus)))
                }
                statusRow("registration.form.registrationCode", snapshot.registrationStatus)
                statusRow("registration.form.paymentCode", snapshot.paymentStatus)
                statusRow("registration.form.verificationCode", snapshot.verificationStatus)
                Text("registration.form.separateStatusHint").font(.caption).foregroundStyle(.secondary)
            }.accessibilityIdentifier("registration.form.statusSnapshot")
        }
    }
    private func statusRow(_ key: String, _ code: Int?) -> some View {
        LabeledContent {
            if let code { Text(verbatim: String(code)) }
            else { Text("registration.form.unknownStatus") }
        } label: { Text(LocalizedStringKey(key)) }
    }
}
