import SwiftUI

// Native SwiftUI renderers for the new gameplay types (UG-01/02/03/04/10) and the arrival /
// compatibility notices (U05-01, §23.2, U04-03). Layout follows the mini-program structure; the
// look is Apple's: system fonts, materials, continuous corners, 44pt targets, Reduce Motion.
// None of these views judges an answer or counts chances; they submit and render receipts.

// MARK: - UG-01 Hangman

@MainActor struct PlayHangmanView: View {
    let projection: PlayHangmanProjection
    let submitting: Bool
    /// Submission error text from the server (缺槽/越界/冲突), mirrored verbatim. Input is kept.
    let errorMessage: String?
    let onSubmitSlots: ([Int: String]) -> Void
    let onSubmitInput: (String) -> Void
    @State private var cells: [Int: String] = [:]
    @State private var whole = ""
    @FocusState private var focused: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(projection.slots) { slot in cell(slot) }
                }
                .padding(.vertical, 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: projection.display))

            if projection.solved {
                if let answer = projection.answerText {
                    Label { Text(verbatim: answer).font(.title3.weight(.semibold)) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            } else {
                TextField(text: $whole) { questoText("hangman.wholeWord") }
                    .textInputAutocapitalization(projection.caseSensitive ? .never : .characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44)
                if let errorMessage {
                    Text(verbatim: errorMessage).font(.footnote).foregroundStyle(.red)
                }
                if projection.verdict == .wrong { questoText("hangman.wrong").font(.footnote).foregroundStyle(.secondary) }
                Button {
                    let word = whole.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !word.isEmpty { onSubmitInput(word) } else { onSubmitSlots(cells.filter { !$0.value.isEmpty }) }
                } label: {
                    if submitting { ProgressView() } else { questoText("common.submit").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(submitting || (whole.trimmingCharacters(in: .whitespaces).isEmpty && cells.values.allSatisfy(\.isEmpty)))
            }
        }
        .accessibilityIdentifier("playQuesto.hangman")
    }

    @ViewBuilder private func cell(_ slot: PlayHangmanProjection.Slot) -> some View {
        let box = RoundedRectangle(cornerRadius: 8, style: .continuous)
        switch slot.kind {
        case .separator:
            Text(verbatim: slot.character ?? " ").font(.title3.monospaced()).frame(width: 18, height: 44)
        case .prefilled:
            Text(verbatim: slot.character ?? "").font(.title3.monospaced().weight(.semibold))
                .frame(width: 36, height: 44).background(.thinMaterial, in: box)
        case .filled, .blank:
            if projection.solved {
                Text(verbatim: slot.character ?? "").font(.title3.monospaced().weight(.semibold))
                    .frame(width: 36, height: 44).background(.thinMaterial, in: box)
            } else {
                TextField(text: Binding(
                    get: { cells[slot.index] ?? slot.character ?? "" },
                    // One character per cell; extra characters keep only the last typed one.
                    set: { cells[slot.index] = $0.last.map { String($0) } ?? "" }
                )) { Text(verbatim: "_") }
                .font(.title3.monospaced().weight(.semibold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(projection.caseSensitive ? .never : .characters)
                .autocorrectionDisabled()
                .focused($focused, equals: slot.index)
                .frame(width: 36, height: 44)
                .overlay(box.strokeBorder(focused == slot.index ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1.5))
                .accessibilityLabel(Text("playQuesto.hangman.cell \(slot.index + 1)", tableName: "PlayQuesto"))
            }
        }
    }
}

// MARK: - UG-02 Image options

@MainActor struct PlayImageOptionList: View {
    let options: [PlayChoiceOption]
    @Binding var selection: Set<String>
    let multiple: Bool
    let disabled: Bool

    var body: some View {
        let anyImage = options.contains { $0.imageURL != nil }
        LazyVGrid(columns: anyImage ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)] : [GridItem(.flexible())], spacing: 12) {
            ForEach(options) { option in
                let selected = selection.contains(option.id)
                Button {
                    if multiple { if selected { selection.remove(option.id) } else { selection.insert(option.id) } }
                    else { selection = [option.id] }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        if let url = option.imageURL {
                            // Fixed aspect ratio so selection never shifts the layout.
                            Color.clear.aspectRatio(4.0 / 3.0, contentMode: .fit)
                                .overlay {
                                    AsyncImage(url: url) { phase in
                                        if let image = phase.image { image.resizable().scaledToFill() }
                                        else if phase.error != nil { Image(systemName: "photo").foregroundStyle(.secondary) }
                                        else { ProgressView() }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .accessibilityHidden(true)
                        }
                        Text(verbatim: option.label).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                        if let alt = option.alt, option.imageURL != nil { Text(verbatim: alt).font(.footnote).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityLabel(Text(verbatim: option.accessibilityLabel))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("playQuesto.option." + option.id)
            }
        }
    }
}

// MARK: - UG-03 / UG-04 Accusation

@MainActor struct PlayAccusationPage: View {
    let view: PlayAccusationView
    let outcome: PlayAccusationOutcome?
    let submitting: Bool
    /// Submits SUBMIT_QA with the chosen suspect id. Choosing and re-choosing never submits.
    let onConfirm: (String) -> Void
    let onRecheck: () -> Void
    @State private var chosen: String?
    @State private var dossier: PlayAccusationView.Suspect?
    @State private var confirming = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let outcome, outcome.ending != .keepInvestigating { ending(outcome) } else { picker }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            if outcome == nil || outcome?.ending == .keepInvestigating { bottomBar }
        }
        .sheet(item: $dossier) { suspect in dossierSheet(suspect) }
        .confirmationDialog(Text(LocalizedStringKey("playQuesto.accuse.confirmTitle"), tableName: "PlayQuesto"), isPresented: $confirming, titleVisibility: .visible) {
            Button(role: .destructive) { if let chosen { onConfirm(chosen) } } label: { questoText("accuse.confirm") }
            Button(role: .cancel) {} label: { questoText("accuse.rethink") }
        } message: { questoText("accuse.finalWarning") }
    }

    @ViewBuilder private var picker: some View {
        if let url = view.corkboardURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFit() } else { Color.secondary.opacity(0.1).frame(height: 160) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel(Text(verbatim: view.corkboardAlt ?? ""))
        }
        ForEach(Array(view.introTexts.enumerated()), id: \.offset) { _, text in Text(verbatim: text).font(.body) }
        if outcome?.ending == .keepInvestigating {
            questoText("accuse.keepInvestigating").font(.callout).foregroundStyle(.secondary)
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(view.suspects) { suspect in card(suspect) }
            }
        }
    }

    private func card(_ suspect: PlayAccusationView.Suspect) -> some View {
        let selected = chosen == suspect.id
        return VStack(alignment: .leading, spacing: 8) {
            avatar(suspect).frame(width: 140, height: 140)
            Text(verbatim: suspect.name).font(.headline)
            if let identity = suspect.identity { Text(verbatim: identity).font(.footnote).foregroundStyle(.secondary) }
            HStack {
                Button { chosen = suspect.id } label: { questoText(selected ? "accuse.chosen" : "accuse.choose") }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                if !suspect.testimony.isEmpty {
                    Button { dossier = suspect } label: { questoText("accuse.dossier") }.buttonStyle(.borderless).frame(minHeight: 44)
                }
            }
        }
        .padding(12)
        .frame(width: 164, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: selected)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playQuesto.suspect." + suspect.id)
    }

    @ViewBuilder private func avatar(_ suspect: PlayAccusationView.Suspect) -> some View {
        if let url = suspect.avatarURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() } else { Image(systemName: "person.crop.square").resizable().scaledToFit().foregroundStyle(.secondary) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
        } else {
            Image(systemName: "person.crop.square").resizable().scaledToFit().foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { chosen = nil } label: { questoText("accuse.rethink").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
            Button { confirming = true } label: {
                if submitting { ProgressView().frame(maxWidth: .infinity) } else { questoText("accuse.confirm").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(chosen == nil || submitting)
            .accessibilityIdentifier("playQuesto.accuse.confirm")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder private func ending(_ outcome: PlayAccusationOutcome) -> some View {
        switch outcome.ending {
        case .confirming:
            VStack(alignment: .leading, spacing: 12) {
                questoText("accuse.confirming").font(.headline)
                Button { onRecheck() } label: { questoText("unknown.check") }.buttonStyle(.bordered)
            }
        case .refused(let message):
            if let message, !message.isEmpty { Text(verbatim: message).foregroundStyle(.red) } else { questoText("accuse.refused").foregroundStyle(.red) }
        case .solved, .closedEarly, .failed:
            // Neutral status tag; colour and icon only from system styles. No internal codes shown.
            Label { questoText(outcome.ending == .solved ? "ending.solved" : outcome.ending == .closedEarly ? "ending.closedEarly" : "ending.failed") }
                icon: { Image(systemName: outcome.ending == .solved ? "checkmark.seal" : outcome.ending == .closedEarly ? "flag" : "xmark.seal") }
                .font(.headline)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .accessibilityIdentifier("playQuesto.ending")
            if let text = outcome.screenText { Text(verbatim: text).font(.body) }
        case .keepInvestigating:
            EmptyView()
        }
    }

    private func dossierSheet(_ suspect: PlayAccusationView.Suspect) -> some View {
        NavigationStack {
            List {
                Section { ForEach(suspect.testimony) { Text(verbatim: $0.text) } }
            }
            .navigationTitle(Text(verbatim: suspect.name))
            .navigationBarTitleDisplayMode(.inline)
        }
        .questoSheet([.half, .full])
    }
}

// MARK: - UG-10 Clue transform

/// Only the question text layer is mirrored. Inputs, options and buttons are never flipped.
struct PlayClueText: View {
    let text: String
    let transform: PlayClueTransform
    var body: some View {
        Text(verbatim: text)
            .font(.title3)
            .scaleEffect(x: transform.mirrorsText ? -1 : 1, y: 1)
    }
}

// MARK: - Arrival and compatibility notices

/// A refused arrival: reason, then only the actions the server's flags allow.
struct PlayArrivalRefusalNotice: View {
    let refusal: PlayArrivalRefusal
    let onRelocate: () -> Void
    let onRefresh: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let key = refusal.reason.key { questoText("arrive.reason." + key).font(.headline) }
            if let message = refusal.message, !message.isEmpty { Text(verbatim: message).font(.callout).foregroundStyle(.secondary) }
            if refusal.refreshRequired {
                Button { onRefresh() } label: { questoText("arrive.refresh") }.buttonStyle(.bordered)
            } else if refusal.canRetry {
                // Re-locate retries the original intent; accuracy never widens the fence.
                Button { onRelocate() } label: { questoText("arrive.relocate") }.buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("playQuesto.arrive.refusal")
    }
}

/// Played once per arrival receipt, after a real arrival only.
struct PlayArrivalReadingCard: View {
    let reading: PlayArrivalReading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    var body: some View {
        Text(verbatim: reading.log)
            .font(.body)
            .italic(reading.level >= 2)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { shown = true } }
            .accessibilityIdentifier("playQuesto.arrive.reading")
    }
}

/// Before payment or start: names missing capabilities only on an explicit server "unsupported".
struct PlayCompatibilityNotice: View {
    let compatibility: PlayContentCompatibility
    var body: some View {
        switch compatibility.verdict {
        case .supported:
            EmptyView()
        case .unconfirmed:
            Label { questoText("compat.unconfirmed") } icon: { Image(systemName: "questionmark.circle") }
                .font(.footnote).foregroundStyle(.secondary)
        case .unsupported:
            VStack(alignment: .leading, spacing: 6) {
                Label { questoText("compat.unsupported") } icon: { Image(systemName: "exclamationmark.triangle") }.font(.headline)
                ForEach(compatibility.missing) { Text(verbatim: $0.key).font(.footnote.monospaced()).foregroundStyle(.secondary) }
            }
            .accessibilityIdentifier("playQuesto.compat.unsupported")
        }
    }
}
