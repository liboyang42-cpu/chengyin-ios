import SwiftUI

@MainActor struct SquareReportContext {
    let coordinator: SquareReportCoordinator
    let access: any SquareReportAccess
}
private struct SquareReportContextKey: EnvironmentKey { static let defaultValue: SquareReportContext? = nil }
extension EnvironmentValues {
    var squareReportContext: SquareReportContext? {
        get { self[SquareReportContextKey.self] }
        set { self[SquareReportContextKey.self] = newValue }
    }
}

@MainActor struct SquareReportView: View {
    let target: SquareReportTarget
    let context: SquareReportContext?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var snapshot: SquareReportSnapshot?
    @State private var reasonCode: String?
    @State private var description = ""
    @State private var showsReasons = false
    @State private var confirmsDiscard = false
    @State private var review: SquareReportReview?
    @State private var receipt: SquareReportReceipt?
    @State private var busy = false
    @State private var locked = false
    @State private var message: String?
    @State private var generation = 0
    @State private var actionTask: Task<Void, Never>?
    @FocusState private var descriptionFocused: Bool
    private var selectedReason: SquareReportReason? { snapshot?.policy.reasons.first { $0.id == reasonCode } }
    private var hasDraft: Bool { !locked && (reasonCode != nil || !description.isEmpty) }
    private var validDescription: Bool {
        let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.utf16.count <= 2000
    }
    var body: some View {
        Form {
            Section {
                Text(LocalizedStringKey(context?.coordinator.service.synthetic == true ? "squareReport.synthetic" : "squareReport.boundary"))
                    .font(.footnote).accessibilityIdentifier("squareReport.boundary")
                LabeledContent(target.type == "CONTENT" ? "social.targetPost" : "social.targetComment", value: String(target.id))
                Text("squareReport.noRemoval").font(.footnote)
            }
            if busy { ProgressView("social.loading").accessibilityIdentifier("squareReport.loading") }
            if let message { Text(LocalizedStringKey(message)).accessibilityIdentifier("squareReport.message") }
            if let receipt { receiptSection(receipt) }
            else if locked { Text("squareReport.locked").accessibilityIdentifier("squareReport.locked") }
            else if let snapshot {
                if let contents = snapshot.subject.comment?.contents ?? snapshot.subject.post?.contents {
                    Section(target.type == "CONTENT" ? "social.targetPost" : "social.targetComment") {
                        Text(verbatim: contents).accessibilityIdentifier("squareReport.subject")
                    }
                }
                Section("squareReport.reason") {
                    Button { descriptionFocused = false; showsReasons = true } label: {
                        HStack {
                            if let selectedReason { reasonLabel(selectedReason) } else { Text("squareReport.chooseReason") }
                            Spacer(); Image(systemName: "chevron.up.chevron.down").accessibilityHidden(true)
                        }.frame(minHeight: 44)
                    }.disabled(busy).accessibilityIdentifier("squareReport.chooseReason")
                    LabeledContent("squareReport.policyVersion", value: snapshot.policy.version)
                    Text("squareReport.sourceLabels").font(.footnote).foregroundStyle(.secondary)
                    if selectedReason?.emergency == true, snapshot.policy.emergencyGuidanceCode == "CONTACT_LOCAL_EMERGENCY_SERVICES" {
                        Text("squareReport.emergency").foregroundStyle(.secondary)
                    }
                }
                Section("squareReport.description") {
                    TextEditor(text: $description).frame(minHeight: 140).focused($descriptionFocused)
                        .accessibilityLabel("squareReport.description").accessibilityIdentifier("squareReport.description")
                    Text("\(description.utf16.count)/2000").foregroundStyle(description.utf16.count > 2000 ? Color.red : Color.secondary)
                    Text("squareReport.noAttachments").font(.footnote)
                }
                Section {
                    Button("social.review") { prepare(snapshot) }
                        .disabled(busy || selectedReason == nil || !validDescription)
                        .accessibilityIdentifier("squareReport.review")
                }
            } else if !busy {
                Button("action.retry") { actionTask = Task { await load() } }
                    .disabled(context?.coordinator.service.readsEnabled != true)
                    .accessibilityIdentifier("squareReport.retry")
            }
        }
        .navigationTitle("squareReport.title").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively).privacySensitive()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.close") {
                    descriptionFocused = false
                    if hasDraft { confirmsDiscard = true } else { dismiss() }
                }.disabled(busy).accessibilityIdentifier("squareReport.close")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button("action.done") { descriptionFocused = false }.accessibilityIdentifier("squareReport.keyboardDone")
            }
        }
        .interactiveDismissDisabled(hasDraft || busy)
        .confirmationDialog("social.editor.discardTitle", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("social.editor.discard", role: .destructive) { dismiss() }.accessibilityIdentifier("squareReport.discard")
            Button("social.editor.keepEditing", role: .cancel) {}.accessibilityIdentifier("squareReport.keepEditing")
        } message: { Text("social.editor.discardMessage") }
        .sheet(isPresented: $showsReasons) {
            if let snapshot {
                NavigationStack {
                    List {
                        ForEach(snapshot.policy.reasons) { reason in
                            Button {
                                guard snapshot.identity == context?.access.identity else { showsReasons = false; return }
                                reasonCode = reason.id; showsReasons = false
                            } label: {
                                HStack {
                                    reasonLabel(reason).fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    if reasonCode == reason.id { Image(systemName: "checkmark").accessibilityHidden(true) }
                                }.frame(minHeight: 44)
                            }.accessibilityAddTraits(reasonCode == reason.id ? .isSelected : [])
                                .accessibilityIdentifier("squareReport.reason." + reason.id)
                        }
                    }.navigationTitle("squareReport.reason").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) {
                            Button("action.cancel") { showsReasons = false }.accessibilityIdentifier("squareReport.reasonCancel")
                        } }
                }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $review) { item in
            NavigationStack {
                Form {
                    Text("squareReport.reviewWarning")
                    LabeledContent(item.snapshot.target.type == "CONTENT" ? "social.targetPost" : "social.targetComment", value: String(item.snapshot.target.id))
                    if let contents = item.snapshot.subject.comment?.contents ?? item.snapshot.subject.post?.contents { Text(verbatim: contents) }
                    Section("squareReport.reason") { reasonLabel(item.reason) }
                    LabeledContent("squareReport.policyVersion", value: item.snapshot.policy.version)
                    Section("squareReport.description") { Text(verbatim: item.description).textSelection(.enabled) }
                    if context?.coordinator.service.writesEnabled != true { Text("squareReport.boundary") }
                    Button(context?.coordinator.service.synthetic == true ? "social.simulate" : "social.submit") {
                        actionTask = Task { await submit(item) }
                    }.disabled(busy || context?.coordinator.service.writesEnabled != true)
                        .accessibilityIdentifier("squareReport.confirm")
                }.navigationTitle("social.review").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("action.back") { review = nil }.disabled(busy).accessibilityIdentifier("squareReport.reviewBack")
                    } }
            }.interactiveDismissDisabled(busy).presentationDetents([.large])
        }
        .task(id: context?.access.identity) {
            generation += 1; actionTask?.cancel(); snapshot = nil; reasonCode = nil; description = ""
            review = nil; receipt = nil; locked = false; showsReasons = false; confirmsDiscard = false
            await load()
        }
        .onChange(of: scenePhase) { _, next in
            if next != .active { descriptionFocused = false; showsReasons = false; review = nil; actionTask?.cancel() }
        }
        .onDisappear {
            guard !showsReasons, review == nil else { return }
            generation += 1; actionTask?.cancel(); descriptionFocused = false
        }
        .accessibilityIdentifier("squareReport.editor")
    }
    @ViewBuilder private func reasonLabel(_ reason: SquareReportReason) -> some View {
        // The policy's exact source label remains visible; no guessed translated
        // labels can silently replace a changed server policy.
        let known = ["DANGEROUS", "MINOR_SAFETY", "SELF_HARM", "SEXUAL_CONTENT", "HARASSMENT", "HATE", "FRAUD", "IMPERSONATION", "FALSE_INFORMATION", "SPAM", "PRIVACY", "INTELLECTUAL_PROPERTY", "OTHER"]
        VStack(alignment: .leading, spacing: 4) {
            if locale.language.languageCode?.identifier != "zh", known.contains(reason.id) {
                Text(LocalizedStringKey("squareReport.reasonLabel." + reason.id))
                Text(verbatim: reason.label).font(.caption).foregroundStyle(.secondary)
            } else { Text(verbatim: reason.label) }
        }
    }
    @ViewBuilder private func receiptSection(_ value: SquareReportReceipt) -> some View {
        Section("squareReport.receipt") {
            Text(LocalizedStringKey(context?.coordinator.service.synthetic == true ? "squareReport.syntheticReceipt" : "squareReport.acknowledged"))
                .accessibilityIdentifier("squareReport.acknowledged")
            LabeledContent("squareReport.caseID", value: String(value.id))
            LabeledContent("squareReport.stage", value: value.publicStage ?? value.stage)
                .accessibilityIdentifier("squareReport.stage")
            if let summary = value.decisionSummary { Text(verbatim: summary) }
            Text("squareReport.noRemoval")
            Button("squareReport.refresh") { actionTask = Task { await refresh(value) } }
                .disabled(busy).accessibilityIdentifier("squareReport.refresh")
        }
    }
    private func prepare(_ snapshot: SquareReportSnapshot) {
        descriptionFocused = false
        guard let context, let reasonCode else { return }
        do { review = try context.coordinator.prepare(snapshot: snapshot, reasonCode: reasonCode, description: description, access: context.access); message = nil }
        catch {
            message = failureKey(error)
            if error as? SquareReportFailure == .stale {
                review = nil; self.reasonCode = nil; self.snapshot = nil
                let identity = context.access.identity
                actionTask = Task {
                    await load()
                    guard !Task.isCancelled, identity == context.access.identity else { return }
                    message = "squareReport.stale"
                }
            }
        }
    }
    private func load() async {
        generation += 1; let ticket = generation
        busy = true; message = nil
        defer { if generation == ticket { busy = false } }
        guard let context else { message = "squareReport.boundary"; return }
        if let identity = context.access.identity {
            locked = context.coordinator.isLocked(target: target, identity: identity)
            receipt = context.coordinator.receipt(target: target, identity: identity)
            if locked {
                if receipt == nil {
                    do {
                        let value = try await context.coordinator.recover(target: target, expectedIdentity: identity, access: context.access)
                        guard ticket == generation, !Task.isCancelled else { return }; receipt = value
                    } catch { if ticket == generation, !Task.isCancelled { message = failureKey(error) } }
                }
                return
            }
        }
        do {
            let value = try await context.coordinator.reload(target: target, access: context.access)
            guard ticket == generation, !Task.isCancelled else { return }; snapshot = value
        } catch { if ticket == generation, !Task.isCancelled { snapshot = nil; message = failureKey(error) } }
    }
    private func submit(_ item: SquareReportReview) async {
        guard !busy, let context else { return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            let value = try await context.coordinator.confirm(item, access: context.access)
            guard ticket == generation, context.access.identity == item.snapshot.identity else { return }
            receipt = value; locked = true; review = nil; message = nil
        } catch {
            guard ticket == generation, context.access.identity == item.snapshot.identity else { return }
            review = nil; locked = context.coordinator.isLocked(target: target, identity: item.snapshot.identity)
            message = failureKey(error)
            if error as? SquareReportFailure == .stale {
                reasonCode = nil; snapshot = nil; await load()
                guard !Task.isCancelled, context.access.identity == item.snapshot.identity else { return }
                message = "squareReport.stale"
            }
        }
    }
    private func refresh(_ value: SquareReportReceipt) async {
        guard !busy, let context, let identity = context.access.identity else { return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            let updated = try await context.coordinator.refresh(value, target: target, expectedIdentity: identity, access: context.access)
            guard ticket == generation else { return }; receipt = updated; message = nil
        } catch { if ticket == generation { message = failureKey(error) } }
    }
    private func failureKey(_ error: Error) -> String {
        switch error as? SquareReportFailure {
        case .disabled: return "squareReport.boundary"
        case .signedOut: return "social.signIn"
        case .stale: return "squareReport.stale"
        case .locked, .unknown: return "squareReport.locked"
        case .invalid: return "squareReport.invalid"
        case .rejected: return "squareReport.rejected"
        default: return "squareReport.failed"
        }
    }
}
