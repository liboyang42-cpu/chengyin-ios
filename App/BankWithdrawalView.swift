import SwiftUI

/// Reachable native form with an honest dormant state. The session host supplies a separately approved adapter when configured.
@MainActor struct BankWithdrawalView: View {
    let reader: WalletCommerceReader
    var adapter: BankWithdrawalAdapter? = nil
    var currentDocument: BankWithdrawalCurrentDocument? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = BankWithdrawalDraft()
    @State private var snapshot: BankWithdrawalDraft?
    @State private var review: BankWithdrawalReview?
    @State private var proof: BankWithdrawalProof?
    @State private var receipt: BankWithdrawalReceipt?
    @State private var issue: String?
    @State private var busy = false
    @State private var showReview = false
    @State private var confirmDiscard = false
    @State private var generation = UUID()
    @FocusState private var focused: Field?
    private enum Field: Hashable { case amount, name, bank, account, phone }
    private var available: Bool { adapter?.isAvailable == true }
    private var hasInput: Bool { draft != BankWithdrawalDraft() }
    var body: some View {
        Form {
            if let receipt {
                Section {
                    Label("bank.withdrawal.accepted", systemImage: "clock.badge.checkmark").accessibilityIdentifier("bank.withdrawal.receipt")
                    LabeledContent("bank.withdrawal.applicationID", value: String(receipt.applicationID))
                    Text("bank.withdrawal.notPaid")
                    NavigationLink("wallet.withdrawals") { WalletWithdrawalsView(reader: reader) }
                }
            } else {
                Section {
                    if reader.scope == nil { Text("wallet.login") }
                    else if !available { Label("bank.withdrawal.unavailable", systemImage: "lock") }
                    if adapter?.hasUnresolvedOutcome == true { Text("bank.withdrawal.unresolved") }
                    Text("bank.withdrawal.privacy")
                    if let currentDocument { Link("bank.withdrawal.currentDocument", destination: currentDocument.officialURL) }
                }
                Section("bank.withdrawal.destination") {
                    TextField("bank.withdrawal.name", text: $draft.realname).focused($focused, equals: .name)
                        .textContentType(.name).accessibilityIdentifier("bank.withdrawal.name").submitLabel(.next).onSubmit { focused = .bank }
                    TextField("bank.withdrawal.bank", text: $draft.bankName).focused($focused, equals: .bank)
                        .submitLabel(.next).onSubmit { focused = .account }.accessibilityIdentifier("bank.withdrawal.bank")
                    SecureField("bank.withdrawal.account", text: $draft.bankAccount).focused($focused, equals: .account)
                        .keyboardType(.numbersAndPunctuation).textContentType(.none).accessibilityIdentifier("bank.withdrawal.account")
                    SecureField("bank.withdrawal.phone", text: $draft.mobilephone).focused($focused, equals: .phone)
                        .keyboardType(.phonePad).textContentType(.none).accessibilityIdentifier("bank.withdrawal.phone")
                }.autocorrectionDisabled().textInputAutocapitalization(.never).privacySensitive()
                Section("bank.withdrawal.amount") {
                    TextField("bank.withdrawal.amountCNY", text: $draft.amount).focused($focused, equals: .amount)
                        .keyboardType(.decimalPad).accessibilityIdentifier("bank.withdrawal.amount")
                    Text("bank.withdrawal.feeArrivalUnknown")
                }
                if let issue { Text(LocalizedStringKey(issue)).foregroundStyle(.red).accessibilityIdentifier("bank.withdrawal.issue") }
                Section {
                    Button("bank.withdrawal.review") { localReview() }
                        .disabled(busy || reader.scope == nil || adapter?.hasUnresolvedOutcome == true)
                        .frame(minHeight: 44).accessibilityIdentifier("bank.withdrawal.review")
                    NavigationLink("wallet.withdrawals") { WalletWithdrawalsView(reader: reader) }
                }
            }
        }.navigationTitle("bank.withdrawal.title")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .keyboard) { Button("bank.withdrawal.keyboardDone") { focused = nil } }
                ToolbarItem(placement: .topBarTrailing) { Button("action.close") {
                    if hasInput || showReview { confirmDiscard = true } else { clear(); dismiss() }
                }.disabled(busy) }
            }
            .confirmationDialog("bank.withdrawal.discardQuestion", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("bank.withdrawal.discard", role: .destructive) { clear(); dismiss() }
                Button("action.cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showReview, onDismiss: { snapshot = nil; review = nil; proof = nil }) { reviewSheet }
            .onChange(of: reader.scope) { _, _ in clear() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { clear() } }
            .onDisappear { clear() }
    }
    private var reviewSheet: some View {
        NavigationStack {
            Form {
                if let snapshot {
                    Section("bank.withdrawal.checkDetails") {
                        LabeledContent("bank.withdrawal.amountCNY", value: NSDecimalNumber(decimal: (try? snapshot.validatedAmount()) ?? .nan).stringValue)
                        LabeledContent("bank.withdrawal.name", value: snapshot.realname)
                        LabeledContent("bank.withdrawal.bank", value: snapshot.bankName)
                        LabeledContent("bank.withdrawal.account", value: snapshot.accountMask)
                        LabeledContent("bank.withdrawal.phone", value: snapshot.phoneMask)
                    }.privacySensitive()
                }
                if let proof {
                    Section("bank.withdrawal.serverConfirmation") {
                        if proof.riskLevel == "WARNING" { Label("bank.withdrawal.serverWarning", systemImage: "exclamationmark.triangle") }
                        Text(verbatim: proof.question); Text(verbatim: proof.consequence)
                        ForEach(Array(proof.safetyMessages.enumerated()), id: \.offset) { _, text in Text(verbatim: text) }
                        Text("bank.withdrawal.feeArrivalUnknown")
                        Button("bank.withdrawal.confirmSubmit") { Task { await submit(proof) } }
                            .disabled(busy).frame(minHeight: 44).accessibilityIdentifier("bank.withdrawal.confirmSubmit")
                        Button("bank.withdrawal.reject", role: .destructive) { Task { await reject(proof) } }
                            .disabled(busy).frame(minHeight: 44)
                    }
                } else {
                    if adapter?.hasUnresolvedOutcome == true { Text("bank.withdrawal.unresolved") }
                    else { Text("bank.withdrawal.notSubmitted") }
                    if snapshot != nil { Text("bank.withdrawal.disclosure") }
                    if !available { Text("bank.withdrawal.unavailable") }
                    Button("bank.withdrawal.prepare") { Task { await prepare() } }
                        .disabled(!available || busy || review == nil)
                        .frame(minHeight: 44).accessibilityIdentifier("bank.withdrawal.prepare")
                }
                if busy { ProgressView("wallet.loading") }
                if let issue { Text(LocalizedStringKey(issue)).foregroundStyle(.red) }
            }.navigationTitle("bank.withdrawal.checkDetails")
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") {
                        if let proof { Task { await reject(proof) } } else { clear() }
                    }.disabled(busy)
                } }
        }.interactiveDismissDisabled(true)
            .presentationDetents([.large])
    }
    private func localReview() {
        focused = nil; issue = nil
        do {
            _ = try draft.validatedAmount()
            snapshot = draft
            if let adapter { review = try adapter.review(draft) }
            showReview = true
        } catch { issue = errorKey(error) }
    }
    private func prepare() async {
        guard let adapter, let review, !busy else { return }
        busy = true; issue = nil; let ticket = generation
        defer { if ticket == generation { busy = false } }
        do {
            let value = try await adapter.prepare(review)
            guard ticket == generation else { return }; proof = value
        } catch {
            guard ticket == generation else { return }; issue = errorKey(error)
        }
    }
    private func submit(_ value: BankWithdrawalProof) async {
        guard let adapter, !busy else { return }
        busy = true; issue = nil; let ticket = generation
        defer { if ticket == generation { busy = false } }
        do {
            let result = try await adapter.submit(value)
            guard ticket == generation else { return }
            clear(); receipt = result
        } catch {
            guard ticket == generation else { return }
            proof = nil; review = nil; snapshot = nil; draft = .init()
            issue = adapter.hasUnresolvedOutcome ? "bank.withdrawal.unresolved" : errorKey(error)
        }
    }
    private func reject(_ value: BankWithdrawalProof) async {
        guard let adapter, !busy else { return }
        busy = true; issue = nil; let ticket = generation
        defer { if ticket == generation { busy = false } }
        do { try await adapter.reject(value); guard ticket == generation else { return }; clear() }
        catch { guard ticket == generation else { return }; proof = nil; review = nil; issue = errorKey(error) }
    }
    private func clear() {
        generation = UUID(); focused = nil; draft = .init(); snapshot = nil; review = nil; proof = nil
        receipt = nil; issue = nil; busy = false; showReview = false; adapter?.discardLocalInput()
    }
    private func errorKey(_ error: Error) -> String {
        if adapter?.hasUnresolvedOutcome == true { return "bank.withdrawal.unresolved" }
        if (error as? APIError) == .unauthorized { return "wallet.login" }
        switch error as? BankWithdrawalFailure {
        case .invalidInput: return "bank.withdrawal.invalidInput"
        case .consentRequired: return "bank.withdrawal.consentRequired"
        case .expired: return "bank.withdrawal.expired"
        case .unavailable: return "bank.withdrawal.unavailable"
        case .staleSession: return "wallet.login"
        case .serverBlocked: return "bank.withdrawal.serverBlocked"
        default: return "wallet.failed"
        }
    }
}
