import SwiftUI

@MainActor final class ClubProfileChoiceController: ObservableObject {
    struct Session: Identifiable, Equatable {
        let id = UUID()
        let context: ClubProfileChoiceContext
        let draft: ClubProfileChoiceDraft
    }
    @Published private(set) var session: Session?
    func open(kind: ClubProfileChoiceKind, source: ClubOperationsDraft,
              context: ClubProfileChoiceContext?, isCurrent: (ClubProfileChoiceContext) -> Bool) {
        guard session == nil, let context, isCurrent(context) else { return }
        session = .init(context: context, draft: .init(kind: kind, source: source))
    }
    func close() { session = nil }
    func apply(_ edited: ClubProfileChoiceDraft, session expected: Session, current: ClubOperationsDraft,
               isCurrent: (ClubProfileChoiceContext) -> Bool) -> ClubOperationsDraft? {
        guard session == expected, edited.kind == expected.draft.kind, edited.source == expected.draft.source,
              isCurrent(expected.context), let next = try? edited.applying(to: current) else { return nil }
        session = nil; return next
    }
}

/// Edit-only control; the source binding is unchanged until the explicit Apply callback.
@MainActor struct ClubProfileChoiceControl: View {
    let kind: ClubProfileChoiceKind
    @Binding var draft: ClubOperationsDraft
    let context: ClubProfileChoiceContext?
    let isCurrent: (ClubProfileChoiceContext) -> Bool
    @StateObject private var controller = ClubProfileChoiceController()
    @Environment(\.scenePhase) private var scenePhase
    private var available: Bool { scenePhase == .active && context.map(isCurrent) == true }
    var body: some View {
        Button {
            guard available else { return }
            controller.open(kind: kind, source: draft, context: context, isCurrent: isCurrent)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(kind == .type ? "club.profileChoice.type" : "club.profileChoice.directions"))
                if kind == .type {
                    if draft.clubType.isEmpty { Text("club.ops.chooseType").foregroundStyle(.secondary) }
                    else { choiceLabel(draft.clubType, catalog: ClubOperationsCatalog.types) }
                } else if draft.activityPrefs.isEmpty { Text("club.profileChoice.noDirections").foregroundStyle(.secondary) }
                else {
                    ForEach(draft.activityPrefs, id: \.self) { choiceLabel($0, catalog: ClubOperationsCatalog.directions) }
                }
            }
        }.disabled(!available).accessibilityIdentifier("club.profileChoice.open." + kind.rawValue)
        .sheet(item: Binding(get: { controller.session }, set: { if $0 == nil { controller.close() } })) { session in
            NavigationStack {
                ClubProfileChoiceEditor(session: session, isCurrent: { available && context == session.context && isCurrent(session.context) }, cancel: { controller.close() }) { edited in
                    guard available, context == session.context,
                          let next = controller.apply(edited, session: session, current: draft, isCurrent: isCurrent) else { return false }
                    draft = next; return true
                }
            }.presentationDetents([.medium, .large])
        }
        .onChange(of: context) { _, _ in controller.close() }
        .onChange(of: available) { _, ready in if !ready { controller.close() } }
        .onChange(of: draft) { _, _ in controller.close() }
        .onDisappear { controller.close() }
    }
    @ViewBuilder private func choiceLabel(_ value: String, catalog: [String]) -> some View {
        if catalog.contains(value) { Text(LocalizedStringKey("club.ops.value." + value)).font(.subheadline) }
        else { Text(verbatim: value).font(.subheadline) }
    }
}

@MainActor private struct ClubProfileChoiceEditor: View {
    let session: ClubProfileChoiceController.Session
    let isCurrent: () -> Bool
    let cancel: () -> Void
    let apply: (ClubProfileChoiceDraft) -> Bool
    @State private var draft: ClubProfileChoiceDraft
    @State private var failed = false
    init(session: ClubProfileChoiceController.Session, isCurrent: @escaping () -> Bool,
         cancel: @escaping () -> Void, apply: @escaping (ClubProfileChoiceDraft) -> Bool) {
        self.session = session; self.isCurrent = isCurrent; self.cancel = cancel; self.apply = apply
        _draft = State(initialValue: session.draft)
    }
    var body: some View {
        List {
            Text("club.profileChoice.applyHint").font(.footnote)
            if draft.kind == .type {
                ForEach(ClubOperationsCatalog.types, id: \.self) { value in
                    Button { guard isCurrent() else { return }; _ = draft.selectType(value); failed = false } label: {
                        HStack { Text(LocalizedStringKey("club.ops.value." + value)); Spacer(); if draft.type == value { Image(systemName: "checkmark") } }
                    }.accessibilityAddTraits(draft.type == value ? .isSelected : [])
                }
                if !draft.type.isEmpty, !ClubOperationsCatalog.types.contains(draft.type) { Text(verbatim: draft.type) }
            } else {
                Text("club.ops.directionsHint").font(.footnote)
                ForEach(ClubOperationsCatalog.directions, id: \.self) { value in
                    Toggle(LocalizedStringKey("club.ops.value." + value), isOn: Binding(get: { draft.directions.contains(value) }, set: { enabled in
                        guard isCurrent(), enabled != draft.directions.contains(value) else { return }
                        _ = draft.toggleDirection(value); failed = false
                    })).disabled(!draft.directions.contains(value) && draft.directions.count >= 3)
                }
                ForEach(draft.directions.filter { !ClubOperationsCatalog.directions.contains($0) }, id: \.self) { Text(verbatim: $0) }
            }
            if failed || !draft.isValid { Text("club.profileChoice.unavailable").accessibilityIdentifier("club.profileChoice.failure") }
        }
        .navigationTitle(LocalizedStringKey(draft.kind == .type ? "club.profileChoice.type" : "club.profileChoice.directions"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("action.cancel", action: cancel) }
            ToolbarItem(placement: .confirmationAction) {
                Button("club.profileChoice.apply") { guard isCurrent() else { cancel(); return }; failed = !apply(draft) }
                    .disabled(!draft.isValid || !isCurrent()).accessibilityIdentifier("club.profileChoice.apply")
            }
        }
        .onChange(of: isCurrent(), initial: true) { _, valid in if !valid { cancel() } }
    }
}
