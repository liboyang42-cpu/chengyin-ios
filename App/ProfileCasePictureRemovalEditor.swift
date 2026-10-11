import SwiftUI

/// A clear-all decision remains usable without downloading or identifying individual images.
@MainActor struct ProfileCasePictureRemovalEditor: View {
    let edit: ProfileTextFieldEdit
    let cancel: () -> Void
    let confirm: (Bool) -> Void
    @State private var removes: Bool
    private var imageCount: Int { ProfileCasePortfolio(casePics: edit.snapshot.casePics).imageCount }
    init(edit: ProfileTextFieldEdit, cancel: @escaping () -> Void, confirm: @escaping (Bool) -> Void) {
        self.edit = edit; self.cancel = cancel; self.confirm = confirm
        _removes = State(initialValue: edit.draft.removesCasePictures)
    }
    var body: some View {
        Form {
            Section {
                LabeledContent("profile.caseRemoval.count", value: String(imageCount))
                    .accessibilityIdentifier("profile.caseRemoval.count")
                if imageCount == 0 {
                    Text("profile.caseRemoval.empty").accessibilityIdentifier("profile.caseRemoval.empty")
                } else if removes {
                    Label("profile.caseRemoval.staged", systemImage: "photo.stack")
                        .accessibilityIdentifier("profile.caseRemoval.staged")
                    Button("profile.caseRemoval.restore") { removes = false }
                        .accessibilityIdentifier("profile.caseRemoval.restore")
                } else {
                    Text("profile.caseRemoval.explanation")
                    Button("profile.caseRemoval.remove", role: .destructive) { removes = true }
                        .accessibilityIdentifier("profile.caseRemoval.remove")
                }
            } footer: { Text("profile.caseRemoval.hint") }
        }
        .appNavigationTitle("profile.caseRemoval.title")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel", role: .cancel, action: cancel).accessibilityIdentifier("profile.caseRemoval.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("profile.fieldEdit.apply") { confirm(removes) }.accessibilityIdentifier("profile.caseRemoval.apply")
            }
        }
    }
}
