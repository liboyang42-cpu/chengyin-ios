import SwiftUI

/// Optional node augmentation: probe errors render nothing and never replace task controls.
@MainActor struct PlayJourneyCheckView: View {
    @Bindable var model: JourneyCheckCoordinator
    let nodeDone: Bool
    var body: some View {
        Group {
            JourneyRoleViewSection(model: model.roleContent)
            if model.visible, let problem = model.problem {
                Section("journey.check.title") {
                    Text(verbatim: problem.skill).font(.headline).accessibilityIdentifier("journey.check.stage")
                    Text(verbatim: problem.tier)
                    if problem.advantage { Label("journey.advantage", systemImage: "plus.circle") }
                    if problem.disadvantage { Label("journey.disadvantage", systemImage: "minus.circle") }
                    modifiers(problem.mods)
                    if let receipt = model.receipt {
                        if let success = receipt.success { Text(success ? "journey.success" : "journey.failure").font(.headline) }
                        LabeledContent("journey.dice") { Text(verbatim: receipt.dice.map(String.init).joined(separator: ", ")) }
                        number("journey.kept", receipt.kept); number("journey.total", receipt.total); number("journey.dc", receipt.dc)
                        if !receipt.nat.isEmpty { Text(verbatim: receipt.nat) }
                        number("journey.hp", receipt.hp); number("journey.luck", receipt.luck)
                        modifiers(receipt.mods)
                        if receipt.exhausted { Text("journey.exhausted") }
                        if receipt.settled {
                            if !receipt.text.isEmpty { Text(verbatim: receipt.text) }
                            if !receipt.failCostLabel.isEmpty { LabeledContent("journey.cost") { Text(verbatim: receipt.failCostLabel) } }
                        }
                    }
                    if let issue = model.issue { Text(verbatim: issue).foregroundStyle(.red).accessibilityIdentifier("journey.check.error") }
                    if model.unknown {
                        Text("journey.unknown")
                        Button("journey.recover") { try? model.prepare(.settle, recoverUnknown: true) }
                            .disabled(!model.canRecover).accessibilityIdentifier("journey.check.recover")
                    } else if model.receipt == nil { action(.roll) }
                    else if model.receipt?.settled == false {
                        if model.receipt?.canReroll == true { action(.reroll) }
                        action(.settle)
                    }
                    if model.acting { ProgressView("journey.working") }
                    if !model.available { Text("journey.disabled") }
                    Button("journey.close") { model.close() }.accessibilityIdentifier("journey.check.close")
                }
            } else if model.problem != nil && !model.nodeDone {
                Button("journey.check.title") { model.reopen() }.accessibilityIdentifier("journey.check.reopen")
            }
        }
    }
    private func action(_ action: JourneyCheckAction) -> some View {
        Button(LocalizedStringKey("journey." + action.rawValue)) { try? model.prepare(action) }
            .disabled(model.acting || !model.available).accessibilityIdentifier("journey.check." + action.rawValue)
    }
    @ViewBuilder private func number(_ key: LocalizedStringKey, _ value: Int?) -> some View {
        if let value { LabeledContent(key) { Text(verbatim: String(value)).monospacedDigit() } }
    }
    private func modifiers(_ mods: [JourneyCheckMod]) -> some View {
        ForEach(Array(mods.enumerated()), id: \.offset) { _, mod in
            HStack { Text(verbatim: mod.label); Spacer(); if let value = mod.value { Text(verbatim: String(value)) }; Text(mod.active ? "journey.active" : "journey.inactive") }
                .accessibilityElement(children: .combine)
        }
    }
}
/// A List row is recycled while scrolling. Present reviews from the owning screen instead
/// of distributing one sheet modifier across the optional Group's lazy Section children.
@MainActor struct JourneyCheckReviewPresentation: ViewModifier {
    let model: JourneyCheckCoordinator?
    @ViewBuilder func body(content: Content) -> some View {
        if let model { content.modifier(JourneyCheckReviewPresenter(model: model)) }
        else { content }
    }
}
@MainActor private struct JourneyCheckReviewPresenter: ViewModifier {
    @Bindable var model: JourneyCheckCoordinator
    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { model.review }, set: { if $0 == nil { model.cancelReview() } })) { review in
            NavigationStack {
                Form {
                    Section("journey.review") {
                        Text(LocalizedStringKey("journey." + review.action.rawValue))
                        if review.action == .reroll { Text("journey.reroll.cost") }
                        if review.action == .settle { Text("journey.settle.impact") }
                        Text(verbatim: "\(review.topicID) / \(review.nodeID) / \(review.checkID)")
                        Button("journey.confirm") { Task { await model.confirm(review) } }
                            .accessibilityIdentifier("journey.check.confirm")
                    }
                }.navigationTitle("journey.review").privacySensitive()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("journey.cancel", role: .cancel) { model.cancelReview() }
                                .accessibilityIdentifier("journey.check.cancelReview")
                        }
                    }
            }
        }
    }
}
@MainActor struct PlayAmbientView: View {
    @Bindable var model: JourneyAmbientCoordinator
    var locationSource: (any JourneyAmbientLocationSource)? = nil
    var body: some View {
        Group {
            if let line = model.line { Section("journey.companion") { Text(verbatim: line).accessibilityIdentifier("journey.companion.line") } }
            if let egg = model.eggBubble {
                Section("journey.egg") {
                    Text(verbatim: egg.text).accessibilityIdentifier("journey.egg.text")
                    if model.collected.contains(egg.id) { Text("journey.egg.collected") }
                    Button("journey.close") { model.dismissBubble() }
                }.accessibilityIdentifier("journey.egg.bubble")
            }
        }
        .task {
            if let locationSource { await model.track(source: locationSource) }
        }
        .task {
            while !Task.isCancelled {
                model.tick(now: Date())
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
/// F08 per-station 「我已到达」 and FE-STORY 「我已到达」 visit control. Every state is text plus
/// icon; the one success haptic follows a server-confirmed arrival, never a page load.
@MainActor struct PlayArrivalControl: View {
    @Bindable var arrival: PlayArrivalService
    let nodeID: Int
    let context: PlayInteractionContext?
    let canSubmit: Bool
    var visitRadius: Int? = nil
    private var isCurrent: Bool { arrival.nodeID == nodeID }
    var body: some View {
        Group {
            if let kind = arrival.offer(for: nodeID) {
                Section("playArrival.title") {
                    hint(kind)
                    Button { Task { await arrival.arrive(nodeID: nodeID, context: context) } } label: {
                        Label("playArrival.action", systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).disabled(arrival.isBusy || !canSubmit)
                        .accessibilityIdentifier("playArrival.action.\(nodeID)")
                    if !canSubmit { Text("playArrival.disabled").font(.footnote).foregroundStyle(.secondary) }
                    if isCurrent { status }
                }
            } else if isCurrent, arrival.phase != .idle {
                Section("playArrival.title") { status }
            }
        }
        .sensoryFeedback(.success, trigger: isCurrent && arrival.phase == .succeeded) { _, new in new }
    }
    @ViewBuilder private func hint(_ kind: PlayArrivalService.Kind) -> some View {
        switch kind {
        case .stationTap: Text("playArrival.station.hint").font(.subheadline)
        case .start: Text("playArrival.start.hint").font(.subheadline)
        case .freeVisit: Text("playArrival.visit.hint \(PlayArrivalPolicy.visitRadiusMeters(configured: visitRadius))").font(.subheadline)
        }
    }
    @ViewBuilder private var status: some View {
        switch arrival.phase {
        case .idle: EmptyView()
        case .locating: ProgressView("playArrival.locating")
        case .submitting: ProgressView("playArrival.submitting")
        case .succeeded:
            Label("playArrival.succeeded", systemImage: "checkmark.circle.fill").accessibilityIdentifier("playArrival.succeeded")
        case .rejected(let rejection):
            VStack(alignment: .leading, spacing: 6) {
                Label(LocalizedStringKey("playArrival.rejected." + rejection.reason.rawValue), systemImage: "exclamationmark.triangle")
                if let distance = rejection.distanceMeters { Text("playArrival.distance \(distance)") }
                Text("playArrival.retryHint").font(.footnote).foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("playArrival.rejected")
        case .unknown:
            Label("playArrival.unknown", systemImage: "questionmark.circle").accessibilityIdentifier("playArrival.unknown")
            Button("playArrival.reread", systemImage: "arrow.clockwise") { Task { await arrival.reread() } }
                .accessibilityIdentifier("playArrival.reread")
        case .unavailable: Label("playArrival.unavailable", systemImage: "nosign")
        case .locationUnavailable: Label("playArrival.location.unavailable", systemImage: "location.slash")
        }
    }
}
