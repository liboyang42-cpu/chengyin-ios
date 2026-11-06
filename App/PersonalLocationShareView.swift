import SwiftUI

@MainActor struct PersonalLocationShareView: View {
    @Environment(\.locale) private var locale
    @Bindable var coordinator: PersonalLocationShareCoordinator
    let recipientId: Int64?
    @State private var confirmationTicket: PersonalLocationShareConfirmationTicket?
    @State private var presentationId = UUID()
    @State private var allowsFirstPermissionRequest = false
    private var presentsConfirmation: Binding<Bool> {
        Binding(get: { confirmationTicket != nil }, set: { presented in
            if !presented { cancelConfirmation() }
        })
    }
    private func cancelConfirmation() {
        if let ticket = confirmationTicket { coordinator.cancelConfirmationTicket(ticket) }
        confirmationTicket = nil
    }
    private var title: String { recipientId == nil ? "personalLocationShare.title.management" : "personalLocationShare.title.person" }
    var body: some View {
        Form {
            Section {
                Label(localized("personalLocationShare.overview"), systemImage: "location.circle")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                Text(statusMessage).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("personalLocationShare.status")
                journalRecoveryStatus
                Text("personalLocationShare.disclosure.summary", tableName: "PersonalLocationShare")
                    .font(.footnote).foregroundStyle(.secondary)
                if recipientId != nil && !coordinator.providerIsConnected { Text(localized("personalLocationShare.unconfigured")).foregroundStyle(.secondary) }
            }
            if let recipientId {
                Section(localized("personalLocationShare.recipient")) {
                    LabeledContent(localized("personalLocationShare.memberID"), value: String(recipientId))
                    if coordinator.isLoading { ProgressView(localized("personalLocationShare.loadingEligibility")) }
                    Text(localized("personalLocationShare.eligibilityNotice"))
                    Button(localized("personalLocationShare.recheck")) { Task { await coordinator.prepare(recipientId: recipientId) } }
                        .disabled(coordinator.isLoading)
                }
                if coordinator.recipientId == recipientId, let policy = coordinator.context?.policy {
                    Section(localized("personalLocationShare.choices")) {
                        Picker(localized("personalLocationShare.precision"), selection: Binding(get: { coordinator.selectedModeId }, set: { coordinator.chooseMode($0) })) {
                            Text(localized("personalLocationShare.choose")).tag(String?.none)
                            ForEach(policy.modeChoices) { choice in
                                Text(choice.mode == .exact ? localized("personalLocationShare.exact") : localized("personalLocationShare.coarse")).tag(Optional(choice.id))
                            }
                        }
                        Picker(localized("personalLocationShare.duration"), selection: Binding(get: { coordinator.selectedDurationId }, set: { coordinator.chooseDuration($0) })) {
                            Text(localized("personalLocationShare.choose")).tag(String?.none)
                            ForEach(policy.durationChoices) { choice in Text(localized("personalLocationShare.seconds", String(choice.seconds))).tag(Optional(choice.id)) }
                        }
                        Text(localized("personalLocationShare.precisionNotice"))
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(localized("personalLocationShare.policy", policy.policyId, String(policy.version))).font(.caption)
                    }.disabled(!coordinator.pending.isEmpty)
                    Section(localized("personalLocationShare.acknowledgements")) {
                        ForEach(PersonalLocationShareDisclosure.allCases, id: \.self) { disclosure in
                            Toggle(disclosureTitle(disclosure), isOn: Binding(
                                get: { coordinator.acknowledgements.contains(disclosure) },
                                set: { coordinator.acknowledge(disclosure, accepted: $0) }))
                        }
                        Toggle(localized("personalLocationShare.firstPermission"), isOn: Binding(get: { allowsFirstPermissionRequest }, set: { allowed in
                            cancelConfirmation(); allowsFirstPermissionRequest = allowed
                        }))
                        Button(localized("personalLocationShare.start")) {
                            confirmationTicket = coordinator.makeConfirmationTicket(displayedRecipientId: recipientId,
                                presentationId: presentationId, allowsFirstPermissionRequest: allowsFirstPermissionRequest)
                        }
                            .disabled(!coordinator.canConfirm || coordinator.recipientId != recipientId)
                            .accessibilityIdentifier("personalLocationShare.confirm")
                    }.disabled(!coordinator.pending.isEmpty)
                }
            }
            Section {
                if coordinator.originalRequestsAreVerifiedEmpty {
                    Text(localized("personalLocationShare.emptyRequests"))
                        .accessibilityIdentifier("personalLocationShare.verifiedEmptyRequests")
                }
                ForEach(coordinator.pending) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localized("personalLocationShare.recipientValue", String(record.request.recipientId))).font(.headline)
                        Label(stateTitle(coordinator.requests[record.id]), systemImage: record.stopRequested ? "stop.circle" : "clock")
                            .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Text(localized("personalLocationShare.requestValue", record.id)).font(.caption.monospaced())
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Button { Task { await coordinator.readback(requestKey: record.id) } } label: {
                                Text(localized("personalLocationShare.readRequest"))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                            }
                        if record.stopRequested {
                            Button(role: .destructive) { Task { await coordinator.retryStop(requestKey: record.id) } } label: {
                                Text(localized("personalLocationShare.retryStop"))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                            }
                        } else {
                            Button(role: .destructive) { Task { await coordinator.stop(requestKey: record.id) } } label: {
                                Text(localized("personalLocationShare.stop"))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                            }
                        }
                    }.accessibilityElement(children: .contain)
                }
                Button(localized("personalLocationShare.restore")) { Task { await coordinator.restoreOriginalRequests() } }
                    .disabled(coordinator.isRestoringOriginalRequests)
                    .accessibilityHint(localized("personalLocationShare.restoreHint"))
            } header: {
                Text(localized("personalLocationShare.requests"))
            } footer: {
                Text(localized("personalLocationShare.requestsFooter"))
            }
            Section {
                currentReadStatus(coordinator.ownedReadState)
                Button(localized("personalLocationShare.refreshManagement")) { Task { await coordinator.openManagement() } }
                    .disabled(coordinator.ownedReadState == .loading)
                if coordinator.ownedReadState == .loaded && coordinator.ownedGrants.isEmpty {
                    Text(localized("personalLocationShare.emptyGrants"))
                }
                ForEach(coordinator.ownedGrants) { grant in
                    VStack(alignment: .leading) {
                        Text(localized("personalLocationShare.recipientGrant", String(grant.recipientId))).font(.headline)
                        Text(localized("personalLocationShare.expires", date(grant.expiresAtMs))).font(.footnote)
                        Text(localized("personalLocationShare.grantStatus", grantStateTitle(grant.status.rawValue))).font(.footnote)
                        if grant.status == .active {
                            Button(role: .destructive) { Task { await coordinator.stop(requestKey: grant.requestKey) } } label: {
                                Text(localized("personalLocationShare.stopGrant"))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                            }
                        }
                    }
                }
            } header: {
                Text(localized("personalLocationShare.grants"))
            } footer: {
                Text(localized("personalLocationShare.currentFooter"))
            }
            Section(localized("personalLocationShare.received")) {
                currentReadStatus(coordinator.receivedReadState)
                Button(localized("personalLocationShare.refreshReceived")) { Task { await coordinator.refreshReceived() } }
                    .disabled(coordinator.receivedReadState == .loading)
                if coordinator.visibleLocations.isEmpty { Text(localized("personalLocationShare.emptyLocations")) }
                ForEach(coordinator.visibleLocations) { item in
                    VStack(alignment: .leading) {
                        Text(localized("personalLocationShare.owner", String(item.grant.ownerId))).font(.headline)
                        Text(item.observation.mode == .coarse ? localized("personalLocationShare.coarseObservation") : localized("personalLocationShare.exactObservation"))
                        Text(localized("personalLocationShare.coordinates", String(item.observation.latitude), String(item.observation.longitude)))
                        Text(localized("personalLocationShare.observed", date(item.observation.observedAtMs))).font(.footnote)
                        Text(item.isStale(at: coordinator.clockUptime) ? localized("personalLocationShare.stale") : localized("personalLocationShare.snapshot"))
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(localized("personalLocationShare.grantExpires", date(item.grant.expiresAtMs))).font(.footnote)
                    }
                }
            }
        }
        // Native Form/navigation preserve safe areas and Dynamic Type; no fixed-height content cards.
        .buttonStyle(.borderless)
        .navigationTitle(Text(LocalizedStringKey(title), tableName: "PersonalLocationShare"))
        .task(id: recipientId) {
            if let recipientId { await coordinator.prepare(recipientId: recipientId) }
            else { await coordinator.openManagement() }
        }
        .onChange(of: coordinator.confirmationRevision) { _, _ in
            if let ticket = confirmationTicket, !coordinator.confirmationIsCurrent(ticket) { cancelConfirmation() }
        }
        .onChange(of: ObjectIdentifier(coordinator)) { _, _ in cancelConfirmation() }
        .onChange(of: recipientId) { _, _ in cancelConfirmation(); allowsFirstPermissionRequest = false }
        .onDisappear {
            coordinator.confirmationEntryDisappeared(presentationId: presentationId)
            cancelConfirmation()
        }
        .confirmationDialog(localized("personalLocationShare.confirmTitle", confirmationTicket.map { String($0.recipientId) } ?? ""),
            isPresented: presentsConfirmation, titleVisibility: .visible) {
            if let ticket = confirmationTicket {
                Button(ticket.allowsFirstPermissionRequest ? localized("personalLocationShare.confirmFirstPermission") : localized("personalLocationShare.confirmExistingPermission")) {
                    guard ticket.recipientId == recipientId, ticket.presentationId == presentationId,
                          ticket.allowsFirstPermissionRequest == allowsFirstPermissionRequest else { cancelConfirmation(); return }
                    coordinator.confirmStart(ticket: ticket) // Synchronous consume before dialog dismissal.
                }
                Button(localized("personalLocationShare.cancel"), role: .cancel) { cancelConfirmation() }
            }
        } message: {
            if let ticket = confirmationTicket {
                Text(localized("personalLocationShare.confirmationSummary", String(ticket.recipientId), ticket.mode.mode == .exact ? localized("personalLocationShare.exact") : localized("personalLocationShare.coarse"), String(ticket.duration.seconds), ticket.policy.policyId, String(ticket.policy.version)))
            }
        }
    }

    @ViewBuilder private var journalRecoveryStatus: some View {
        if coordinator.isRestoringOriginalRequests {
            ProgressView(localized("personalLocationShare.journal.loading"))
                .accessibilityIdentifier("personalLocationShare.journalLoading")
        }
        if coordinator.journalReadState == .unavailable {
            Label(localized("personalLocationShare.journal.unavailable"), systemImage: "exclamationmark.triangle")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("personalLocationShare.journalUnavailable")
        } else if coordinator.journalReadState == .unread {
            Text(localized("personalLocationShare.journal.unread"))
        }
        if coordinator.hasUnpersistedStopIntent {
            Label(localized("personalLocationShare.journal.stopUnpersisted"), systemImage: "exclamationmark.shield")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("personalLocationShare.stopUnpersisted")
        }
    }
    @ViewBuilder private func currentReadStatus(_ state: PersonalLocationShareCoordinator.ReadState) -> some View {
        switch state {
        case .notRead: Text(localized("personalLocationShare.read.notRead")).foregroundStyle(.secondary)
        case .loading: ProgressView(localized("personalLocationShare.read.loading"))
        case .loaded: Text(localized("personalLocationShare.read.loaded")).font(.footnote).foregroundStyle(.secondary)
        case .unavailable: Label(localized("personalLocationShare.read.unavailable"), systemImage: "exclamationmark.circle")
        }
    }
    private func grantStateTitle(_ rawValue: String) -> String {
        switch rawValue {
        case "ACTIVE": return localized("personalLocationShare.grant.active")
        case "STOPPED": return localized("personalLocationShare.grant.stopped")
        case "REVOKED": return localized("personalLocationShare.grant.revoked")
        case "EXPIRED": return localized("personalLocationShare.grant.expired")
        case "NOT_FOUND": return localized("personalLocationShare.grant.notFound")
        default: return rawValue
        }
    }

    private var statusMessage: String {
        coordinator.messageParts.map { part in
            guard let key = part.key else { return part.fallback }
            let format = localized(key)
            return part.arguments.isEmpty ? format : String(format: format, locale: locale, arguments: part.arguments.map { $0 as CVarArg })
        }.joined(separator: " ")
    }

    private func localized(_ key: String, _ arguments: CVarArg...) -> String {
        let format = String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
            table: "PersonalLocationShare", locale: locale))
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }
    private func date(_ value: Int64) -> String {
        Date(timeIntervalSince1970: Double(value) / 1000).formatted(.dateTime.locale(locale))
    }
    private func stateTitle(_ state: PersonalLocationShareCoordinator.RequestState?) -> String {
        switch state {
        case .creating: return localized("personalLocationShare.state.creating")
        case .active: return localized("personalLocationShare.state.active")
        case .stopPending: return localized("personalLocationShare.state.stopPending")
        case .stopped: return localized("personalLocationShare.state.stopped")
        default: return localized("personalLocationShare.state.unknown")
        }
    }
    private func disclosureTitle(_ value: PersonalLocationShareDisclosure) -> String {
        switch value {
        case .audience: return localized("personalLocationShare.disclosure.audience")
        case .precision: return localized("personalLocationShare.disclosure.precision")
        case .duration: return localized("personalLocationShare.disclosure.duration")
        case .foregroundOnly: return localized("personalLocationShare.disclosure.foreground")
        case .stopAnytime: return localized("personalLocationShare.disclosure.stop")
        case .alreadySeenCannotBeRecalled: return localized("personalLocationShare.disclosure.recall")
        }
    }
}
