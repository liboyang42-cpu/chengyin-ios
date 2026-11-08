import SwiftUI

/// Standalone candidate, unregistered and disconnected by default. Integrating
/// host must own prompt/media, hints, attempts, review, results and recovery.
@MainActor struct PlayWordFillView: View {
    var context: PlayWordFillContext? = nil
    var enabled = false
    var currentContext: () -> PlayWordFillContext? = { nil }
    var currentlyEnabled: () -> Bool = { false }
    var onDirty: () -> Void = {}
    var requestReview: ((PlayWordFillSubmission) -> Void)? = nil
    @State private var draft = PlayWordFillDraft()
    @State private var mounted = false
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .title2) private var slotWidth: CGFloat = 60

    private var visibleContext: PlayWordFillContext? {
        guard mounted, scenePhase == .active, let context, currentContext() == context,
              draft.isCurrent(context, mountID: draft.mountID) else { return nil }
        return context
    }
    private var canEdit: Bool {
        visibleContext != nil && enabled && currentlyEnabled() && requestReview != nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let context = visibleContext {
                Text("wordFill.instructions", tableName: "PlayWordFill").font(.footnote)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: max(60, slotWidth)), spacing: 12)], spacing: 12) {
                    ForEach(context.question.slots.indices, id: \.self) { index in
                        slot(context.question.slots[index], index: index)
                    }
                }
                TextField(text: blankInputBinding()) { Text("wordFill.input", tableName: "PlayWordFill") }
                    .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(!canEdit)
                    .accessibilityLabel(Text("wordFill.input", tableName: "PlayWordFill"))
                    .accessibilityIdentifier("playkit.wordFill.input")
                Button("playkit.review") {
                    guard canEdit, let submission = draft.submission(current: currentContext(), mountID: draft.mountID) else { return }
                    requestReview?(submission)
                }.buttonStyle(.borderedProminent)
                    .disabled(!canEdit || draft.submission(current: currentContext(), mountID: draft.mountID) == nil)
                    .accessibilityIdentifier("playkit.wordFill.review")
            } else {
                Text("playkit.unavailable").foregroundStyle(.secondary)
                    .accessibilityIdentifier("playkit.wordFill.unavailable")
            }
        }.privacySensitive()
            .onAppear { mountCurrent() }
            .onChange(of: context) { _, _ in mountCurrent() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { mountCurrent() }
                else { mounted = false; draft.clear() }
            }
            .onDisappear { mounted = false; draft.clear() }
    }
    @ViewBuilder private func slot(_ slot: PlayWordFillQuestion.Slot, index: Int) -> some View {
        VStack(spacing: 5) {
            Text(verbatim: String(index + 1)).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            switch slot {
            case .prefilled(let text):
                Text(verbatim: text).font(.title2).frame(maxWidth: .infinity, minHeight: 44)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(Text("wordFill.prefilled \(index + 1)", tableName: "PlayWordFill"))
                    .accessibilityValue(Text(verbatim: text))
                    .accessibilityIdentifier("playkit.wordFill.prefilled.\(index)")
            case .blank:
                let value = draft.input(at: index, current: visibleContext, mountID: draft.mountID)
                Text(verbatim: value.isEmpty ? "＿" : value).font(.title2)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary))
                    .accessibilityLabel(Text("wordFill.blank \(index + 1)", tableName: "PlayWordFill"))
                    .accessibilityValue(Text(verbatim: value))
                    .accessibilityIdentifier("playkit.wordFill.blank.\(index)")
            }
        }
    }
    private func blankInputBinding() -> Binding<String> {
        let mount = draft.mountID
        return .init(get: { draft.blankInput(current: visibleContext, mountID: mount) }, set: { value in
            guard canEdit else { return }
            if draft.replaceBlankInput(value, current: currentContext(), mountID: mount) { onDirty() }
        })
    }
    private func mountCurrent() {
        guard scenePhase == .active, let context, currentContext() == context else {
            mounted = false; draft.clear(); return
        }
        draft.mount(context); mounted = true
    }
}
