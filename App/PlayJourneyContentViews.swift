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
        .sheet(item: Binding(get: { model.review }, set: { if $0 == nil { model.cancelReview() } })) { review in
            NavigationStack {
                Form {
                    Section("journey.review") {
                        Text(LocalizedStringKey("journey." + review.action.rawValue))
                        if review.action == .reroll { Text("journey.reroll.cost") }
                        if review.action == .settle { Text("journey.settle.impact") }
                        Text(verbatim: "\(review.topicID) / \(review.nodeID) / \(review.checkID)")
                        Button("journey.confirm") { Task { await model.confirm(review) } }
                            .accessibilityIdentifier("journey.check.confirm")
                        Button("journey.cancel", role: .cancel) { model.cancelReview() }
                    }
                }.navigationTitle("journey.review").privacySensitive()
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
