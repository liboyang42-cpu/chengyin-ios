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
/// The default quote gate is off, and production creation is unconditionally disabled.
@MainActor
struct RegistrationSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @StateObject private var model: RegistrationSheetModel
    @FocusState private var focusedField: Field?
    @State private var showingConfirmation = false
    private enum Field { case name, phone }

    init(activity: ActivityDetail, coordinator: RegistrationCoordinator,
         participantReader: (any ProfileReading)? = nil,
         currentIdentity: @escaping () -> ProfileReadIdentity?, quoteEnabled: Bool = false,
         creationPolicy: RegistrationUICreationPolicy = .disabled,
         onReadback: @escaping (RegistrationStatusSnapshot) -> Void = { _ in }) {
        _model = StateObject(wrappedValue: RegistrationSheetModel(flow: RegistrationUIFlow(
            activity: activity, coordinator: coordinator, participantReader: participantReader,
            currentIdentity: currentIdentity, quoteEnabled: quoteEnabled,
            creationPolicy: creationPolicy, onReadback: onReadback)))
    }
    private var flow: RegistrationUIFlow { model.flow }
    var body: some View {
        NavigationStack {
            Form {
                if flow.creationPolicy.permitsCreation {
                    Section { Label("registration.form.fixtureNotice", systemImage: "testtube.2").font(.callout) }
                }
                if !flow.hasCurrentSession {
                    Section { Label("registration.form.sessionChanged", systemImage: "person.crop.circle.badge.exclamationmark") }
                } else {
                    activitySection
                    if flow.hasRetainedIntent {
                        RegistrationOperationSections(flow: flow)
                    } else {
                        participantSection
                        ticketSection
                        quoteSection
                        confirmationSection
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("registration.form.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { flow.leave(); dismiss() }
                        .accessibilityIdentifier("registration.form.close")
                }
            }
            .alert("registration.form.confirmTitle", isPresented: $showingConfirmation) {
                Button("registration.form.confirmCreate") { Task { await flow.confirm() } }
                Button("action.cancel", role: .cancel) { flow.cancelConfirmation() }
            } message: {
                if let review = flow.confirmation {
                    Text("registration.form.confirmHint")
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
        } header: { Text("registration.form.contact") }
        footer: { Text("registration.form.contactHint") }
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
                        Text("registration.form.soldOutHint").foregroundStyle(.secondary)
                    } else if ticket.remainingInventory == nil {
                        Text("registration.form.inventoryUnknown").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private var quoteSection: some View {
        Section("registration.form.fees") {
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
                    LabeledContent("registration.form.pointsUsed", value: String(quote.pointsUsed))
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
        } footer: { Text("registration.form.currencyHint") }
    }
    private var confirmationSection: some View {
        Section {
            if flow.creationPolicy.permitsCreation {
                Toggle("registration.form.fixtureConsent", isOn: Binding(get: { flow.consented }, set: flow.setConsent))
                    .disabled(!flow.canEdit).accessibilityIdentifier("registration.form.consent")
            } else {
                Label("registration.form.creationDisabled", systemImage: "lock")
                    .accessibilityIdentifier("registration.form.creationDisabled")
                Text("registration.form.creationDisabledHint").font(.callout).foregroundStyle(.secondary)
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
                    if currencyCode == nil { Text("registration.form.currencyUnknown").font(.caption).foregroundStyle(.secondary) }
                }
            } else { Text("registration.form.unknownAmount") }
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
