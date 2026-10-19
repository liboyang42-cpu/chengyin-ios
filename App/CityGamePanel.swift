import SwiftUI

/// W20 resident CITY business section on the official CITY read surface. Production has
/// no factory (no reviewed endpoint, `cityActions` OFF), so the section states that
/// business actions are not enabled. DEBUG fixtures inject a coordinator.
struct CityGameSlot: View {
    let snapshot: CityReadSnapshot
    let factory: (@MainActor (CityReadSnapshot) -> CityGameCoordinator?)?
    @State private var model: CityGameCoordinator?
    @State private var resolved = false
    var body: some View {
        Group {
            if let model { CityGamePanel(model: model, read: snapshot) }
            else if resolved {
                VStack(alignment: .leading, spacing: 4) {
                    Text("cityGame.title", tableName: "CityGame").font(.headline)
                    Text("cityGame.notEnabled", tableName: "CityGame").font(.footnote).fixedSize(horizontal: false, vertical: true)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("cityGame.notEnabled")
            }
        }
        .task {
            guard !resolved else { return }
            model = factory?(snapshot); resolved = true
            await model?.load()
        }
        .onDisappear { model?.invalidate() }
    }
}

struct CityGamePanel: View {
    let model: CityGameCoordinator
    let read: CityReadSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("cityGame.title", tableName: "CityGame").font(.headline)
            phaseText.font(.footnote).accessibilityIdentifier("cityGame.phase")
            if model.phase == .loading || model.phase == .quoting || model.phase == .sending { ProgressView() }
            if let notice = model.notice { noticeText(notice).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("cityGame.notice") }
            if let outcome = model.lastOutcome { outcomeText(outcome).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("cityGame.outcome") }
            if model.phase == .unknown { unknownSection }
            if let review = model.review, model.phase == .review { reviewCard(review) }
            if let snapshot = model.snapshot { boardContent(snapshot) }
            if model.phase == .unavailable || model.phase == .ready {
                Button { Task { if model.phase == .ready { await model.refresh() } else { await model.load() } } } label: {
                    Text("cityGame.refresh", tableName: "CityGame")
                }.frame(minHeight: 44).accessibilityIdentifier("cityGame.refresh")
            }
            Text("cityGame.privacy", tableName: "CityGame").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cityGame.panel")
    }

    @ViewBuilder private func boardContent(_ snapshot: CityGameSnapshot) -> some View {
        if let notice = model.boardNotice {
            Group {
                if notice == .notJoined { Text("cityGame.board.notJoined", tableName: "CityGame") }
                else { lifecycleText(snapshot.lifecycle) }
            }.fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("cityGame.boardNotice")
        }
        LabeledContent { Text(verbatim: snapshot.rules.ruleVersion) } label: { Text("cityGame.rules.version", tableName: "CityGame") }
        LabeledContent {
            if let remaining = snapshot.rules.actionsRemaining, let total = snapshot.rules.actionsPerRound { Text(verbatim: "\(remaining) / \(total)") }
            else { Text("cityGame.value.unavailable", tableName: "CityGame") }
        } label: { Text("cityGame.rules.actions", tableName: "CityGame") }.accessibilityIdentifier("cityGame.actions")
        LabeledContent {
            if let limit = snapshot.rules.holdingLimit { Text(verbatim: "\(snapshot.heldCount) / \(limit)") }
            else { Text("cityGame.value.unavailable", tableName: "CityGame") }
        } label: { Text("cityGame.rules.holdings", tableName: "CityGame") }
        LabeledContent {
            if let points = snapshot.memberPoints { Text(verbatim: String(points)) }
            else { Text("cityGame.value.unavailable", tableName: "CityGame") }
        } label: { Text("cityGame.points.balance", tableName: "CityGame") }.accessibilityIdentifier("cityGame.points")
        Text("cityGame.points.existing", tableName: "CityGame").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if snapshot.memberPoints == 0, snapshot.neutralTasksAvailable {
            Text("cityGame.points.zero", tableName: "CityGame").font(.footnote).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("cityGame.zeroPoints")
        }
        if model.canRoll {
            Button { model.prepareRoll() } label: { Text("cityGame.roll", tableName: "CityGame") }
                .frame(minHeight: 44).accessibilityIdentifier("cityGame.roll")
        }
        if snapshot.properties.isEmpty { Text("cityGame.properties.empty", tableName: "CityGame") }
        ForEach(snapshot.properties) { property in propertyRow(property) }
    }

    @ViewBuilder private func propertyRow(_ property: CityPropertyState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title(for: property)).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) { roleText(property.role); statusText(property.status) }.font(.footnote)
            if property.heldByMyTeam { Text("cityGame.property.mine", tableName: "CityGame").font(.footnote) }
            if let until = property.protectedUntilMillis {
                LabeledContent { Text(Date(timeIntervalSince1970: Double(until) / 1000), format: .dateTime.month().day().hour().minute()) } label: { Text("cityGame.property.protectedUntil", tableName: "CityGame") }.font(.footnote)
            }
            if let challenge = property.challenge { challengeText(challenge).font(.footnote) }
            if property.taskAttemptKept { Text("cityGame.property.taskKept", tableName: "CityGame").font(.footnote).fixedSize(horizontal: false, vertical: true) }
            ForEach(property.services) { offer in
                HStack {
                    VStack(alignment: .leading) {
                        Text(verbatim: offer.title).font(.footnote)
                        if let fee = offer.memberPointsFee {
                            if fee == 0 { Text("cityGame.service.free", tableName: "CityGame").font(.caption) }
                            else { LabeledContent { Text(verbatim: String(fee)) } label: { Text("cityGame.service.fee", tableName: "CityGame") }.font(.caption) }
                        } else { Text("cityGame.service.feeUnpublished", tableName: "CityGame").font(.caption) }
                    }
                    Spacer(minLength: 0)
                    if model.canAcceptService(offer, on: property) {
                        Button { Task { await model.prepare(.acceptServiceVisit, property: property, service: offer) } } label: {
                            Text("cityGame.service.accept", tableName: "CityGame")
                        }.frame(minHeight: 44).accessibilityIdentifier("cityGame.service.\(offer.serviceId)")
                    }
                }
            }
            ForEach(model.actions(for: property), id: \.rawValue) { kind in
                Button { Task { await model.prepare(kind, property: property) } } label: { actionText(kind) }
                    .frame(minHeight: 44).accessibilityIdentifier("cityGame.action.\(kind.rawValue).\(property.propertyId)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cityGame.property.\(property.propertyId)")
    }

    @ViewBuilder private func reviewCard(_ review: CityGameReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("cityGame.review.title", tableName: "CityGame").font(.headline)
            actionText(review.kind)
            if let propertyId = review.propertyId, let property = model.snapshot?.properties.first(where: { $0.propertyId == propertyId }) {
                Text(verbatim: title(for: property))
            }
            if let service = review.serviceTitle { Text(verbatim: service) }
            if let quote = review.quote {
                LabeledContent { Text(verbatim: String(quote.memberPointsCost)) } label: { Text("cityGame.review.cost", tableName: "CityGame") }
                    .accessibilityIdentifier("cityGame.review.cost")
                LabeledContent { Text(verbatim: String(quote.actionCost)) } label: { Text("cityGame.review.actionCost", tableName: "CityGame") }
                LabeledContent { Text("cityGame.review.payerYou", tableName: "CityGame") } label: { Text("cityGame.review.payer", tableName: "CityGame") }
                LabeledContent { Text(verbatim: String(quote.beneficiaryMemberIds.count)) } label: { Text("cityGame.review.beneficiaries", tableName: "CityGame") }
                LabeledContent { Text(verbatim: quote.ruleVersion) } label: { Text("cityGame.rules.version", tableName: "CityGame") }
                LabeledContent { Text(Date(timeIntervalSince1970: Double(quote.expiresAtMillis) / 1000), format: .dateTime.hour().minute().second()) } label: { Text("cityGame.review.expires", tableName: "CityGame") }
                Text("cityGame.review.noTeammate", tableName: "CityGame").font(.footnote).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("cityGame.review.free", tableName: "CityGame").font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
            if !model.reviewAffordable {
                Text("cityGame.review.insufficient", tableName: "CityGame").font(.footnote).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cityGame.review.insufficient")
            }
            Button { Task { await model.confirm() } } label: { Text("cityGame.review.confirm", tableName: "CityGame") }
                .frame(minHeight: 44).disabled(!model.reviewAffordable).accessibilityIdentifier("cityGame.confirm")
            Button(role: .cancel) { model.cancelReview() } label: { Text("cityGame.review.cancel", tableName: "CityGame") }
                .frame(minHeight: 44).accessibilityIdentifier("cityGame.cancel")
        }
        .padding().background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain).accessibilityIdentifier("cityGame.review")
    }

    @ViewBuilder private var unknownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("cityGame.unknown.explain", tableName: "CityGame").font(.footnote).fixedSize(horizontal: false, vertical: true)
            Button { Task { await model.readBack() } } label: { Text("cityGame.unknown.readBack", tableName: "CityGame") }
                .frame(minHeight: 44).accessibilityIdentifier("cityGame.readBack")
            if model.canRetryExact {
                Button { Task { await model.retryExact() } } label: { Text("cityGame.unknown.retry", tableName: "CityGame") }
                    .frame(minHeight: 44).accessibilityIdentifier("cityGame.retry")
            }
        }
    }

    private func title(for property: CityPropertyState) -> String {
        read.points?.first(where: { $0.pointId == property.pointId })?.title ?? property.propertyId
    }

    private var phaseText: Text {
        switch model.phase {
        case .disabled: return Text("cityGame.phase.disabled", tableName: "CityGame")
        case .idle, .ready: return Text("cityGame.phase.ready", tableName: "CityGame")
        case .loading: return Text("cityGame.phase.loading", tableName: "CityGame")
        case .unavailable: return Text("cityGame.phase.unavailable", tableName: "CityGame")
        case .quoting: return Text("cityGame.phase.quoting", tableName: "CityGame")
        case .review: return Text("cityGame.phase.review", tableName: "CityGame")
        case .sending: return Text("cityGame.phase.sending", tableName: "CityGame")
        case .unknown: return Text("cityGame.phase.unknown", tableName: "CityGame")
        case .invalidated: return Text("cityGame.phase.invalidated", tableName: "CityGame")
        }
    }

    private func noticeText(_ notice: CityGameCoordinator.Notice) -> Text {
        switch notice {
        case .unavailable: return Text("cityGame.notice.unavailable", tableName: "CityGame")
        case .invalidQuote: return Text("cityGame.notice.invalidQuote", tableName: "CityGame")
        case .payerMismatch: return Text("cityGame.notice.payerMismatch", tableName: "CityGame")
        case .quoteExpired: return Text("cityGame.notice.quoteExpired", tableName: "CityGame")
        case .insufficientPoints: return Text("cityGame.review.insufficient", tableName: "CityGame")
        case .busy: return Text("cityGame.notice.busy", tableName: "CityGame")
        case .noReceiptYet: return Text("cityGame.notice.noReceiptYet", tableName: "CityGame")
        case .unknownOutcome: return Text("cityGame.notice.unknownOutcome", tableName: "CityGame")
        case .boardNotOpen: return Text("cityGame.notice.boardNotOpen", tableName: "CityGame")
        case .notJoined: return Text("cityGame.board.notJoined", tableName: "CityGame")
        case .refreshed: return Text("cityGame.notice.refreshed", tableName: "CityGame")
        }
    }

    private func outcomeText(_ outcome: CityPendingAction.Outcome) -> Text {
        switch outcome {
        case .applied: return Text("cityGame.outcome.applied", tableName: "CityGame")
        case .alreadyApplied: return Text("cityGame.outcome.alreadyApplied", tableName: "CityGame")
        case .refresh(let kept):
            return kept ? Text("cityGame.outcome.conflictKept", tableName: "CityGame") : Text("cityGame.outcome.conflict", tableName: "CityGame")
        case .requote: return Text("cityGame.outcome.requote", tableName: "CityGame")
        case .rejected: return Text("cityGame.outcome.rejected", tableName: "CityGame")
        case .blocked: return Text("cityGame.outcome.blocked", tableName: "CityGame")
        case .unknown: return Text("cityGame.notice.unknownOutcome", tableName: "CityGame")
        }
    }

    private func actionText(_ kind: CityActionKind) -> Text {
        switch kind {
        case .roll: return Text("cityGame.roll", tableName: "CityGame")
        case .acceptTask: return Text("cityGame.action.acceptTask", tableName: "CityGame")
        case .submitEvidence: return Text("cityGame.action.submitEvidence", tableName: "CityGame")
        case .acquireProperty: return Text("cityGame.action.acquire", tableName: "CityGame")
        case .acceptServiceVisit: return Text("cityGame.service.accept", tableName: "CityGame")
        case .completeServiceVisit: return Text("cityGame.action.completeService", tableName: "CityGame")
        case .startChallenge: return Text("cityGame.action.challenge", tableName: "CityGame")
        }
    }

    private func roleText(_ role: CityPropertyRole) -> Text {
        role == .neutral ? Text("cityGame.role.neutral", tableName: "CityGame") : Text("cityGame.role.operable", tableName: "CityGame")
    }

    private func statusText(_ status: CityPropertyStatus) -> Text {
        switch status {
        case .available: return Text("cityGame.status.available", tableName: "CityGame")
        case .held: return Text("cityGame.status.held", tableName: "CityGame")
        case .protected: return Text("cityGame.status.protected", tableName: "CityGame")
        case .paused: return Text("cityGame.status.paused", tableName: "CityGame")
        case .safetyBlocked: return Text("cityGame.status.safetyBlocked", tableName: "CityGame")
        }
    }

    private func challengeText(_ state: CityChallengeState) -> Text {
        switch state {
        case .offered: return Text("cityGame.challenge.offered", tableName: "CityGame")
        case .accepted: return Text("cityGame.challenge.accepted", tableName: "CityGame")
        case .evidenceReady: return Text("cityGame.challenge.evidenceReady", tableName: "CityGame")
        case .resolved: return Text("cityGame.challenge.resolved", tableName: "CityGame")
        case .cancelled: return Text("cityGame.challenge.cancelled", tableName: "CityGame")
        case .expired: return Text("cityGame.challenge.expired", tableName: "CityGame")
        case .suspended: return Text("cityGame.challenge.suspended", tableName: "CityGame")
        }
    }

    private func lifecycleText(_ lifecycle: CityBoardLifecycle) -> Text {
        switch lifecycle {
        case .frozen: return Text("cityGame.lifecycle.frozen", tableName: "CityGame")
        case .closing: return Text("cityGame.lifecycle.closing", tableName: "CityGame")
        case .closed, .archived: return Text("cityGame.lifecycle.closed", tableName: "CityGame")
        case .draft, .review, .ready: return Text("cityGame.lifecycle.notOpen", tableName: "CityGame")
        case .open: return Text("cityGame.notice.boardNotOpen", tableName: "CityGame")
        }
    }
}
