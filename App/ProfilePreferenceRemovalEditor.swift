import SwiftUI

@MainActor struct ProfilePreferenceRemovalEditor: View {
    let edit: ProfileTextFieldEdit
    let cancel: () -> Void
    let confirm: ([Int]) -> Void
    private let original: [Int]?
    @State private var selection: [Int]
    init(edit: ProfileTextFieldEdit, cancel: @escaping () -> Void, confirm: @escaping ([Int]) -> Void) {
        self.edit = edit; self.cancel = cancel; self.confirm = confirm
        let values = ProfilePreferenceRemoval.selection(draft: edit.draft, snapshot: edit.snapshot)
        original = values; _selection = State(initialValue: values ?? [])
    }
    var body: some View {
        Form {
            if let original {
                if original.isEmpty {
                    Text("profile.preferenceRemoval.empty").accessibilityIdentifier("profile.preferenceRemoval.empty")
                } else {
                    Section {
                        ForEach(original, id: \.self) { id in
                            HStack {
                                VStack(alignment: .leading) {
                                    if let name = edit.snapshot.preferenceNames[id] { Text(verbatim: name) }
                                    else { Text("profile.preferenceRemoval.unknownName") }
                                    Text(verbatim: "#\(id)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selection.contains(id) {
                                    Button("profile.preferenceRemoval.remove", role: .destructive) { selection.removeAll { $0 == id } }
                                        .accessibilityIdentifier("profile.preferenceRemoval.remove.\(id)")
                                } else {
                                    Button("profile.preferenceRemoval.restore") {
                                        selection = original.filter { $0 == id || selection.contains($0) }
                                    }.accessibilityIdentifier("profile.preferenceRemoval.restore.\(id)")
                                }
                            }.buttonStyle(.borderless)
                        }
                    } footer: { Text("profile.preferenceRemoval.hint") }
                    Button("profile.preferenceRemoval.clear", role: .destructive) { selection = [] }
                        .disabled(selection.isEmpty).accessibilityIdentifier("profile.preferenceRemoval.clear")
                    if selection != original {
                        Button("profile.preferenceRemoval.undoAll") { selection = original }
                            .accessibilityIdentifier("profile.preferenceRemoval.undoAll")
                    }
                }
            } else {
                Text("profile.preferenceRemoval.unavailable").accessibilityIdentifier("profile.preferenceRemoval.unavailable")
            }
        }
        .appNavigationTitle("profile.preferenceRemoval.title")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel", role: .cancel, action: cancel).accessibilityIdentifier("profile.preferenceRemoval.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("profile.fieldEdit.apply") { confirm(selection) }
                    .disabled(original == nil).accessibilityIdentifier("profile.preferenceRemoval.apply")
            }
        }
    }
}

struct ProfilePreferenceRemovalReview: View {
    let ids: [Int]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("profile.preferenceRemoval.review")
            if ids.isEmpty { Text("profile.preferenceRemoval.empty") }
            else { Text(verbatim: ids.map { "#\($0)" }.joined(separator: ", ")) }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("profile.preferenceRemoval.review")
    }
}
