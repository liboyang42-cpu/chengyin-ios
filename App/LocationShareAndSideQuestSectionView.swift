import SwiftUI

/// Reform plan v9 §21 / W13.5–W13.8 and §22 / W14.1–W14.4 offline SwiftUI section views
/// for voluntary location sharing and independent merchant side-quests.
/// Uses `Text(verbatim:)` throughout so zero new `.xcstrings` keys are required.
@MainActor public struct LocationShareHostSectionView: View {
    public let coordinator: LocationShareHostCoordinator
    public let now: Date
    public let onStopOwnerSharing: (() -> Void)?

    public init(
        coordinator: LocationShareHostCoordinator,
        now: Date = Date(),
        onStopOwnerSharing: (() -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.now = now
        self.onStopOwnerSharing = onStopOwnerSharing
    }

    public var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: ownerPhaseText)
            } label: {
                Text(verbatim: "Location Sharing Status")
            }
            .accessibilityIdentifier("mapCore.locationShare.ownerStatus")

            LabeledContent {
                Text(verbatim: coordinator.osLocationAuthorized ? "Authorized (Not Sharing)" : "Not Authorized")
            } label: {
                Text(verbatim: "OS Location Permission")
            }
            .accessibilityIdentifier("mapCore.locationShare.osPermission")

            Text(verbatim: "Granting OS location permission never turns on location sharing or roam presence.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("mapCore.locationShare.permissionNotice")

            LabeledContent {
                Text(verbatim: coordinator.isPreciseSharingFeatureEnabled ? "Enabled" : "Disabled (Default Off)")
            } label: {
                Text(verbatim: "Precise Grant Feature")
            }
            .accessibilityIdentifier("mapCore.locationShare.featureGate")

            ForEach(LocationShareDisclosure.allCases, id: \.self) { disclosure in
                Toggle(
                    isOn: Binding(
                        get: { coordinator.draft.acknowledged.contains(disclosure) },
                        set: { accepted in
                            if accepted {
                                coordinator.acknowledge(disclosure)
                            } else {
                                coordinator.withdraw(disclosure)
                            }
                        }
                    )
                ) {
                    Text(verbatim: disclosureLabel(disclosure))
                }
                .accessibilityIdentifier("mapCore.locationShare.disclosure.\(disclosure.rawValue)")
            }

            LabeledContent {
                Text(verbatim: "\(coordinator.missingDisclosures.count) remaining")
            } label: {
                Text(verbatim: "Pending Disclosures")
            }
            .accessibilityIdentifier("mapCore.locationShare.missingDisclosures")

            Button {} label: {
                Text(verbatim: "Start Precise Sharing")
            }
            .disabled(!coordinator.canStartPreciseSharing)
            .accessibilityIdentifier("mapCore.locationShare.startButton")

            if coordinator.ownerState.phase != .off {
                Button(role: .destructive) {
                    coordinator.stopOwnerSharing()
                    onStopOwnerSharing?()
                } label: {
                    Text(verbatim: "Stop Sharing Immediately")
                }
                .accessibilityIdentifier("mapCore.locationShare.stopButton")
            }

            Toggle(
                isOn: Binding(
                    get: { coordinator.roamPresence.consentAccepted },
                    set: { coordinator.setRoamPresenceConsent($0) }
                )
            ) {
                Text(verbatim: "Roam Session Approximate Presence Consent")
            }
            .accessibilityIdentifier("mapCore.locationShare.roamConsent")

            LabeledContent {
                Text(verbatim: roamPresenceText)
            } label: {
                Text(verbatim: "Roam Presence State")
            }
            .accessibilityIdentifier("mapCore.locationShare.roamState")

            LabeledContent {
                Text(verbatim: "\(coordinator.peerBoard.grants.count)")
            } label: {
                Text(verbatim: "Authorized Peer Grants")
            }
            .accessibilityIdentifier("mapCore.locationShare.peerGrantCount")

            ForEach(sortedPeerGrants, id: \.grantID) { grant in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Grant \(grant.grantID) • \(grant.precision.rawValue)")
                        .font(.subheadline)
                    Text(verbatim: peerPayloadSummary(for: grant.grantID))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("mapCore.locationShare.peerGrant.\(grant.grantID)")
            }
        } header: {
            Text(verbatim: "Voluntary Location Sharing (W13.5–W13.8)")
        } footer: {
            Text(verbatim: "Named audience only. Revoke or session change clears shared positions immediately.")
        }
    }

    private var sortedPeerGrants: [LocationShareGrant] {
        coordinator.peerBoard.grants.values.sorted { $0.grantID < $1.grantID }
    }

    private var ownerPhaseText: String {
        switch coordinator.ownerState.phase {
        case .off:
            return "Off"
        case .requesting:
            return "Requesting"
        case .active(let grant):
            return "Active (\(grant.precision.rawValue))"
        case .revoking:
            return "Stopping"
        case .unknown:
            return "Unknown (Readback Required)"
        }
    }

    private var roamPresenceText: String {
        switch coordinator.roamPresence.phase {
        case .off:
            return "Off"
        case .pendingEnable(let sessionID):
            return "Pending Confirm (Session #\(sessionID))"
        case .confirmedVisible(let sessionID):
            return "Visible (Session #\(sessionID))"
        case .unknown(let sessionID):
            return "Unknown (Session #\(sessionID))"
        }
    }

    private func disclosureLabel(_ disclosure: LocationShareDisclosure) -> String {
        switch disclosure {
        case .audience:
            return "Named recipient or team only"
        case .precision:
            return "Selected precision level understood"
        case .duration:
            return "Time-bounded sharing window understood"
        case .foregroundOnly:
            return "Foreground active session only"
        case .stopAnytime:
            return "Can stop sharing at any time"
        case .alreadySeenCannotBeRecalled:
            return "Positions already viewed cannot be recalled"
        }
    }

    private func peerPayloadSummary(for grantID: String) -> String {
        guard let latest = coordinator.peerBoard.latest[grantID] else {
            return "No location update received"
        }
        let staleSuffix = coordinator.isPeerLocationStale(grantID: grantID, now: now, maxAge: 300) ? " (Last seen / stale)" : ""
        switch latest.payload {
        case .band(let band):
            return "Distance band: \(band.rawValue)\(staleSuffix)"
        case .point(let observation):
            return "Datum: \(observation.datum.rawValue), rev \(latest.revision)\(staleSuffix)"
        }
    }
}

@MainActor public struct MerchantSideQuestHostSectionView: View {
    public let presentation: MerchantSideQuestHostPresentation
    public let now: Date
    public let onRequestAccept: ((SideQuestSpawnInstance) -> Void)?
    public let onSubmitPhotoEvidence: ((String) -> Void)?

    public init(
        presentation: MerchantSideQuestHostPresentation,
        now: Date = Date(),
        onRequestAccept: ((SideQuestSpawnInstance) -> Void)? = nil,
        onSubmitPhotoEvidence: ((String) -> Void)? = nil
    ) {
        self.presentation = presentation
        self.now = now
        self.onRequestAccept = onRequestAccept
        self.onSubmitPhotoEvidence = onSubmitPhotoEvidence
    }

    public var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: presentation.isAcceptFeatureEnabled ? "Enabled" : "Disabled (Default Off)")
            } label: {
                Text(verbatim: "Side-Quest Accept Gate")
            }
            .accessibilityIdentifier("mapCore.sideQuest.featureGate")

            if let unknownRequest = presentation.unknownPendingRequest {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Pending accept outcome unknown for \(unknownRequest.instanceID) (Attempt #\(unknownRequest.attemptNo))")
                        .font(.subheadline)
                    Text(verbatim: "New accepts stay locked until authoritative server readback resolves this request.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("mapCore.sideQuest.unknownLockBanner")
            }

            let cards = presentation.discoverableCards(now: now)
            if cards.isEmpty {
                Text(verbatim: "No discoverable merchant side-quests in the current window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mapCore.sideQuest.emptyCards")
            } else {
                ForEach(cards, id: \.instanceID) { card in
                    sideQuestCardRow(card)
                }
            }

            let attempts = presentation.attemptPresentations(now: now)
            if !attempts.isEmpty {
                ForEach(attempts, id: \.instanceID) { attempt in
                    attemptRow(attempt)
                }
            }
        } header: {
            Text(verbatim: "Independent Merchant Side-Quests (W14.1–W14.4)")
        } footer: {
            Text(verbatim: "Side-quests require no theme release. Photo evidence awaits server review and never auto-completes.")
        }
    }

    @ViewBuilder
    private func sideQuestCardRow(_ card: MerchantSideQuestCardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: card.markerState.symbolName)
                    .accessibilityHidden(true)
                Text(verbatim: card.title)
                    .font(.headline)
            }

            Text(verbatim: card.isIndependentOfTheme
                ? "Scope: Independent Merchant Side-Quest (No Theme Required)"
                : "Scope: Theme Release \(card.themeReleaseID ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: cardMetadataText(card))
                .font(.caption)
                .foregroundStyle(.secondary)

            if card.isCompletedByAuthority {
                Text(verbatim: "Completed by Server Authority")
                    .font(.caption)
                    .accessibilityIdentifier("mapCore.sideQuest.completed.\(card.instanceID)")
            } else if card.evidenceState == .submittedAwaitingReview {
                Text(verbatim: "Photo evidence submitted — awaiting review (not auto-completed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mapCore.sideQuest.awaitingReview.\(card.instanceID)")
            }

            HStack(spacing: 12) {
                Button {
                    if let instance = presentation.instances.first(where: { $0.instanceID == card.instanceID }) {
                        onRequestAccept?(instance)
                    }
                } label: {
                    Text(verbatim: "Accept Side-Quest")
                }
                .disabled(!card.canTriggerClientAccept)
                .accessibilityIdentifier("mapCore.sideQuest.accept.\(card.instanceID)")

                if card.attempt?.status == .active && card.evidenceState == .notSubmitted {
                    Button {
                        onSubmitPhotoEvidence?(card.instanceID)
                    } label: {
                        Text(verbatim: "Submit Photo Evidence")
                    }
                    .accessibilityIdentifier("mapCore.sideQuest.submitPhoto.\(card.instanceID)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("mapCore.sideQuest.card.\(card.instanceID)")
    }

    @ViewBuilder
    private func attemptRow(_ attempt: MerchantSideQuestAttemptPresentation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "Attempt #\(attempt.attemptNo) • \(attempt.instanceID) • \(attempt.status.rawValue)")
                .font(.subheadline)
            Text(verbatim: "Revision \(attempt.revision) • Evidence: \(attempt.evidenceState.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if attempt.survivedInstanceExpiryOrRemoval {
                Text(verbatim: "Preserved after spawn window expiry or viewport removal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mapCore.sideQuest.attempt.\(attempt.instanceID)")
    }

    private func cardMetadataText(_ card: MerchantSideQuestCardPresentation) -> String {
        let capacityText = card.remainingCapacity.map { "Capacity: \($0)" } ?? "Capacity: Undisclosed"
        return "Status: \(card.status.rawValue) • \(capacityText) • Marker: \(card.markerState.rawValue) • Evidence: \(card.evidenceState.rawValue)"
    }
}
