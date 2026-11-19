import SwiftUI

/// F03 hangman. Keyboard mode keeps typed input distributed over the server's open
/// slots; pool mode only arranges the server's visible candidates. Both submit
/// SUBMIT_HANGMAN through the shared review sheet. The verdict is server-owned.
@MainActor struct PlayKitHangmanView: View {
    let segment: PlayWireValue
    let revision: String
    let enabled: Bool
    let onDirty: () -> Void
    let requestReview: PlayKitReviewRequest
    @State private var pool: LetterPoolState?
    @State private var typed = ""
    @State private var loadedRevision: String?
    @State private var awaitingVerdict = false
    @State private var issue: PlayExperienceError?
    @State private var showHowTo = false
    private var projection: PlayHangmanProjection? { try? PlayHangmanProjection(segment) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let projection {
                if projection.solved {
                    Label("playkit.hangman.solved", systemImage: "checkmark.seal")
                        .accessibilityIdentifier("playkit.hangman.solved")
                } else if awaitingVerdict {
                    Label("playkit.hangman.notYet", systemImage: "arrow.uturn.backward.circle")
                        .accessibilityIdentifier("playkit.hangman.notYet")
                }
                if projection.inputMode == .pool { poolInput(projection) } else { keyboardInput(projection) }
                if let howTo = projection.howTo, !projection.solved {
                    Button { showHowTo = true } label: { Label("playkit.hangman.howTo", systemImage: "questionmark.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("playkit.hangman.howTo")
                        .sheet(isPresented: $showHowTo) { PlayKitHangmanHowToSheet(text: howTo) }
                }
                if let issue { PlayExperienceIssueView(issue: issue) }
            } else {
                Text("playkit.configurationInvalid").accessibilityIdentifier("playkit.hangman.invalid")
            }
        }
        .onAppear { synchronize() }
        .onChange(of: revision) { _, _ in synchronize() }
    }
    @ViewBuilder private func poolInput(_ projection: PlayHangmanProjection) -> some View {
        if projection.poolRemoved > 0 {
            Text("playkit.letterPool.removed \(projection.poolRemoved)").font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("playkit.hangman.poolRemoved")
        }
        if let binding = Binding($pool) {
            PlayKitLetterPoolInput(state: binding, enabled: enabled && !projection.solved, identifierPrefix: "playkit.hangman",
                                   onEdit: { awaitingVerdict = false; issue = nil; onDirty() })
            if !projection.solved {
                PlayKitLetterPoolActions(enabled: enabled, canClear: binding.wrappedValue.hasPlacedCandidates,
                    canSubmit: binding.wrappedValue.isComplete && binding.wrappedValue.hasPlacedCandidates,
                    identifierPrefix: "playkit.hangman", submitIdentifier: "playkit.submit.hangman",
                    clear: { pool?.clearAll(); awaitingVerdict = false; onDirty() },
                    submit: { if let state = pool { review(state.hangmanPayload, projection: projection) } })
            }
        }
    }
    @ViewBuilder private func keyboardInput(_ projection: PlayHangmanProjection) -> some View {
        PlayKitHangmanKeyboardSlots(projection: projection, typed: typed)
        if !projection.solved {
            TextField("playkit.hangman.answer", text: Binding(get: { typed }, set: { next in
                typed = PlayKitInputContract.limitText(next, toUTF16: max(1, projection.fillableSlots.count * 2))
                awaitingVerdict = false; issue = nil; onDirty()
            }))
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .disabled(!enabled)
            .accessibilityIdentifier("playkit.hangman.keyboard")
            Text("playkit.hangman.keyboardHint \(projection.fillableSlots.count)").font(.footnote).foregroundStyle(.secondary)
            Button("playkit.letterPool.submit") {
                if let payload = projection.keyboardPayload(typed) { review(payload, projection: projection) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!enabled || projection.keyboardPayload(typed) == nil)
            .accessibilityIdentifier("playkit.submit.hangman")
        }
    }
    private func review(_ payload: [String: PlayWireValue], projection: PlayHangmanProjection) {
        do {
            try projection.validate(payload)
            issue = nil
            requestReview("SUBMIT_HANGMAN", payload, { awaitingVerdict = true })
        } catch { issue = error as? PlayExperienceError ?? .invalidAction }
    }
    /// A new server projection (refresh, wrong answer, POOL_TRIM) keeps the player's
    /// placed characters where their candidate is still visible.
    private func synchronize() {
        guard loadedRevision != revision else { return }
        loadedRevision = revision
        guard let projection else { pool = nil; return }
        if projection.inputMode == .pool, let fresh = LetterPoolState(hangman: projection) {
            pool = pool.map { fresh.rebased(keeping: $0) } ?? fresh
        } else {
            pool = nil
            if typed.isEmpty { typed = projection.keyboardDraft }
        }
    }
}

/// CG-01-P2-5: the author's fill instructions, reopenable at any time.
@MainActor private struct PlayKitHangmanHowToSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: text).frame(maxWidth: .infinity, alignment: .leading).padding()
                    .accessibilityIdentifier("playkit.hangman.howTo.text")
            }
            .navigationTitle(Text("playkit.hangman.howTo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("playhelp.close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Read-only slot row for keyboard mode: typed characters fill open slots in order.
@MainActor private struct PlayKitHangmanKeyboardSlots: View {
    let projection: PlayHangmanProjection
    let typed: String
    @ScaledMetric(relativeTo: .title2) private var cell: CGFloat = 44
    var body: some View {
        let characters = typed.filter { !$0.isWhitespace }.map(String.init)
        let open = projection.fillableSlots.map(\.index)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(projection.slots) { slot in
                let position = open.firstIndex(of: slot.index)
                let value: String? = slot.isFillable ? position.flatMap { characters.indices.contains($0) ? characters[$0] : nil } : slot.character
                PlayKitLetterSlotFace(text: value, fixed: !slot.isFillable, cell: cell)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(value.map { Text(verbatim: $0) } ?? Text("playkit.letterPool.emptySlot"))
                    .accessibilityIdentifier("playkit.hangman.slot." + String(slot.index))
            }
        }
    }
}

/// Shared letter-pool input for hangman pool mode and TYPE question letter pools:
/// answer slots on top, candidate grid below. Tapping a candidate fills the first
/// empty slot; tapping a filled slot returns its character. Fixed slots are inert.
@MainActor struct PlayKitLetterPoolInput: View {
    @Binding var state: LetterPoolState
    let enabled: Bool
    let identifierPrefix: String
    let onEdit: () -> Void
    @ScaledMetric(relativeTo: .title2) private var cell: CGFloat = 44
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("playkit.letterPool.instructions").font(.subheadline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(state.slots) { slot in
                    let value = state.text(of: slot)
                    if slot.isFillable {
                        Button {
                            if state.clear(slotID: slot.id) { onEdit() }
                        } label: { PlayKitLetterSlotFace(text: value, fixed: false, cell: cell) }
                        .buttonStyle(.plain)
                        .disabled(!enabled || slot.poolIndex == nil)
                        .accessibilityLabel(value.map { Text(verbatim: $0) } ?? Text("playkit.letterPool.emptySlot"))
                        .accessibilityHint(slot.poolIndex == nil ? Text(verbatim: "") : Text("playkit.letterPool.returnHint"))
                        .accessibilityIdentifier(identifierPrefix + ".slot." + String(slot.id))
                    } else {
                        PlayKitLetterSlotFace(text: value, fixed: true, cell: cell)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: value ?? ""))
                            .accessibilityIdentifier(identifierPrefix + ".fixed." + String(slot.id))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("playkit.letterPool.answerRow"))
            Divider()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cell), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(state.pool.enumerated()), id: \.offset) { index, character in
                    let used = state.isUsed(index)
                    Button {
                        if state.pick(index) { onEdit() }
                    } label: {
                        Text(verbatim: character).font(.title2.weight(.semibold))
                            .frame(minWidth: cell, minHeight: cell)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .opacity(used ? 0.35 : 1)
                    .disabled(!enabled || used || state.isComplete)
                    .accessibilityLabel(Text("playkit.letterPool.candidate \(character)"))
                    .accessibilityValue(used ? Text("playkit.letterPool.used") : Text(verbatim: ""))
                    .accessibilityIdentifier(identifierPrefix + ".candidate." + String(index))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("playkit.letterPool.candidates"))
        }
    }
}

/// 「清空」/「提交」 controls. Submit opens the shared action review, like every kit.
@MainActor struct PlayKitLetterPoolActions: View {
    let enabled: Bool
    let canClear: Bool
    let canSubmit: Bool
    let identifierPrefix: String
    let submitIdentifier: String
    let clear: () -> Void
    let submit: () -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { clearButton; submitButton }
            VStack(alignment: .leading, spacing: 12) { clearButton; submitButton }
        }
    }
    private var clearButton: some View {
        Button("playkit.letterPool.clear", systemImage: "delete.left", action: clear)
            .buttonStyle(.bordered).disabled(!enabled || !canClear)
            .accessibilityIdentifier(identifierPrefix + ".clear")
    }
    private var submitButton: some View {
        Button("playkit.letterPool.submit", action: submit)
            .buttonStyle(.borderedProminent).disabled(!enabled || !canSubmit)
            .accessibilityIdentifier(submitIdentifier)
    }
}

@MainActor struct PlayKitLetterSlotFace: View {
    let text: String?
    let fixed: Bool
    let cell: CGFloat
    var body: some View {
        Text(verbatim: text ?? " ")
            .font(.title2.weight(fixed ? .regular : .semibold))
            .foregroundStyle(fixed ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
            .frame(minWidth: cell, minHeight: cell)
            .background {
                if !fixed {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(text == nil ? Color.secondary : Color.accentColor, lineWidth: text == nil ? 1 : 2)
                }
            }
    }
}

/// TYPE question with `letterPool`: pick `answerLength` characters, submit SUBMIT_QA
/// `{input}` with the picked characters joined in slot order. A wrong answer keeps
/// the picked characters; a trimmed pool keeps those still visible.
@MainActor struct PlayKitQuestionLetterPoolView: View {
    let segment: PlayWireValue
    let revision: String
    let enabled: Bool
    let onDirty: () -> Void
    let requestReview: PlayKitReviewRequest
    @State private var pool: LetterPoolState?
    @State private var loadedRevision: String?
    private var letterPool: PlayQuestionLetterPool? { try? PlayQuestionLetterPool(question: segment) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let letterPool, let binding = Binding($pool) {
                if letterPool.removed > 0 {
                    Text("playkit.letterPool.removed \(letterPool.removed)").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("playkit.letterPool.removed")
                }
                PlayKitLetterPoolInput(state: binding, enabled: enabled, identifierPrefix: "playkit.letterPool", onEdit: onDirty)
                PlayKitLetterPoolActions(enabled: enabled, canClear: binding.wrappedValue.hasPlacedCandidates,
                    canSubmit: binding.wrappedValue.isComplete,
                    identifierPrefix: "playkit.letterPool", submitIdentifier: "playkit.submit.qa",
                    clear: { pool?.clearAll(); onDirty() },
                    submit: { if let state = pool { requestReview("SUBMIT_QA", state.questionPayload, {}) } })
            } else if letterPool == nil {
                Text("playkit.configurationInvalid").accessibilityIdentifier("playkit.letterPool.invalid")
            }
        }
        .onAppear { synchronize() }
        .onChange(of: revision) { _, _ in synchronize() }
    }
    private func synchronize() {
        guard loadedRevision != revision else { return }
        loadedRevision = revision
        guard let letterPool, let fresh = LetterPoolState(question: letterPool) else { pool = nil; return }
        pool = pool.map { fresh.rebased(keeping: $0) } ?? fresh
    }
}
