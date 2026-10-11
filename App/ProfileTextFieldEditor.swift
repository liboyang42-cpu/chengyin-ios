import SwiftUI

/// Mini parity: nickname openPop4/cancel4/confirm4; introduction openPop/cancel/confirm.
enum ProfileTextField: String, CaseIterable {
    case name, introduction, caseIntroduction, contactQR
    var titleKey: String {
        switch self {
        case .caseIntroduction: return "profile.case.description"
        case .contactQR: return "profile.contactQR.title"
        default: return "profile.edit.\(rawValue)"
        }
    }
    func value(in draft: ProfileEditDraft) -> String {
        switch self {
        case .name: return draft.name
        case .introduction: return draft.introduction
        case .caseIntroduction: return draft.caseIntroduction ?? ""
        case .contactQR: return "" // Contact QR uses the action-only editor; never expose a raw URL input.
        }
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
    var originalText: String {
        field == .caseIntroduction ? (draft.caseIntroduction ?? snapshot.caseIntroduction ?? "") : field.value(in: draft)
    }
}

struct ProfileTextFieldEditor: View {
    let edit: ProfileTextFieldEdit
    let caseImageReader: (any RetainedPublicImageReading)?
    let cancel: () -> Void
    let confirm: (String) -> Void
    @State private var text: String
    @FocusState private var focused: Bool
    init(edit: ProfileTextFieldEdit, caseImageReader: (any RetainedPublicImageReading)? = nil, cancel: @escaping () -> Void, confirm: @escaping (String) -> Void) {
        self.edit = edit; self.caseImageReader = caseImageReader; self.cancel = cancel; self.confirm = confirm
        _text = State(initialValue: edit.originalText)
    }
    var body: some View {
        Form {
            Section {
                if edit.field == .contactQR {
                    Text("profile.contactQR.noUpload")
                } else if edit.field == .name {
                    TextField(LocalizedStringKey(edit.field.titleKey), text: $text)
                        .textContentType(.nickname).focused($focused)
                        .accessibilityIdentifier("profile.edit.name")
                } else if edit.field == .caseIntroduction, edit.snapshot.caseIntroduction == nil {
                    Text("profile.case.descriptionUnavailable")
                        .accessibilityIdentifier("profile.case.descriptionUnavailable")
                } else {
                    TextField(LocalizedStringKey(edit.field.titleKey), text: $text, axis: .vertical)
                        .lineLimit(3...8).focused($focused)
                        .accessibilityIdentifier("profile.edit.\(edit.field.rawValue)")
                }
            } footer: { Text("profile.fieldEdit.hint") }
            if edit.field == .caseIntroduction {
                ProfileCasePortfolioSection(casePics: edit.snapshot.casePics, scope: edit.id, reader: caseImageReader)
            }
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
                    .disabled(edit.field == .contactQR || (edit.field == .caseIntroduction && edit.snapshot.caseIntroduction == nil))
            }
        }
    }
}
