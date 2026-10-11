import SwiftUI

/// Mini parity: nickname openPop4/cancel4/confirm4; introduction openPop/cancel/confirm.
enum ProfileTextField: String, CaseIterable {
    case name, introduction
    var titleKey: String { "profile.edit.\(rawValue)" }
    func value(in draft: ProfileEditDraft) -> String {
        switch self { case .name: return draft.name; case .introduction: return draft.introduction }
    }
}

/// Captures the current editor, complete page draft and replacement snapshot.
/// It grants only a single local field-stage operation, never a network write.
struct ProfileTextFieldEdit: Identifiable {
    let id = UUID()
    let field: ProfileTextField
    let identity: ProfileReadIdentity
    let viewerRevision: UInt64?
    let generation: Int
    let modelRevision: Int
    let draftRevision: UInt64
    let snapshot: ProfileEditSnapshot
    let draft: ProfileEditDraft
    var originalText: String { field.value(in: draft) }
}

struct ProfileTextFieldEditor: View {
    let edit: ProfileTextFieldEdit
    let cancel: () -> Void
    let confirm: (String) -> Void
    @State private var text: String
    @FocusState private var focused: Bool
    init(edit: ProfileTextFieldEdit, cancel: @escaping () -> Void, confirm: @escaping (String) -> Void) {
        self.edit = edit; self.cancel = cancel; self.confirm = confirm
        _text = State(initialValue: edit.originalText)
    }
    var body: some View {
        Form {
            Section {
                if edit.field == .name {
                    TextField(LocalizedStringKey(edit.field.titleKey), text: $text)
                        .textContentType(.nickname).focused($focused)
                        .accessibilityIdentifier("profile.edit.name")
                } else {
                    TextField(LocalizedStringKey(edit.field.titleKey), text: $text, axis: .vertical)
                        .lineLimit(3...8).focused($focused)
                        .accessibilityIdentifier("profile.edit.introduction")
                }
            } footer: { Text("profile.fieldEdit.hint") }
        }
        .appNavigationTitle(key: edit.field.titleKey)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel", role: .cancel) { focused = false; cancel() }
                    .accessibilityIdentifier("profile.fieldEdit.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("profile.fieldEdit.apply") { focused = false; confirm(text) }
                    .accessibilityIdentifier("profile.fieldEdit.apply")
            }
        }
    }
}
