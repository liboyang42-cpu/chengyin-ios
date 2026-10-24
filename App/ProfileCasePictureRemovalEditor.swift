import SwiftUI

/// All-image removal stays available; optional position selection only removes from the original snapshot.
@MainActor struct ProfileCasePictureRemovalEditor: View {
    let edit: ProfileTextFieldEdit
    let cancel: () -> Void
    let confirm: (Bool) -> Void
    let reader: (any RetainedPublicImageReading)?
    let confirmSubset: (([Int]) -> Void)?
    @State private var retainedIndices: [Int]
    private var originalIndices: [Int] { imageCount <= 100 ? Array(0..<imageCount) : [] }
    private var permitsSubset: Bool {
        confirmSubset != nil && imageCount <= 100 && (try? ProfileCasePictureSubset(source: edit.snapshot.casePics,
            retainedIndices: originalIndices)) != nil
    }
    @State private var removes: Bool
    private var imageCount: Int { ProfileCasePortfolio(casePics: edit.snapshot.casePics).imageCount }
    init(edit: ProfileTextFieldEdit, reader: (any RetainedPublicImageReading)? = nil, cancel: @escaping () -> Void, confirm: @escaping (Bool) -> Void, confirmSubset: (([Int]) -> Void)? = nil) {
        self.edit = edit; self.cancel = cancel; self.confirm = confirm
        self.reader = reader; self.confirmSubset = confirmSubset
        let count = ProfileCasePortfolio(casePics: edit.snapshot.casePics).imageCount
        _retainedIndices = State(initialValue: edit.draft.casePictureSubset?.retainedIndices
            ?? (count <= 100 ? Array(0..<count) : []))
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
                    Button("profile.caseRemoval.restore") { removes = false; retainedIndices = originalIndices }
                        .accessibilityIdentifier("profile.caseRemoval.restore")
                } else {
                    Text("profile.caseRemoval.explanation")
                    Button("profile.caseRemoval.remove", role: .destructive) { removes = true }
                        .accessibilityIdentifier("profile.caseRemoval.remove")
                }
            } footer: { Text("profile.caseRemoval.hint") }
            if !removes, imageCount > 0, permitsSubset {
                Section("profile.caseSubset.choose") {
                    LabeledContent("profile.caseSubset.remaining", value: String(retainedIndices.count))
                        .accessibilityIdentifier("profile.caseSubset.remaining")
                    ForEach(originalIndices, id: \.self) { index in
                        Toggle(isOn: Binding(get: { retainedIndices.contains(index) }, set: { keep in
                            if keep { retainedIndices = Array(Set(retainedIndices + [index])).sorted() }
                            else { retainedIndices.removeAll { $0 == index } }
                        })) {
                            LabeledContent("profile.caseSubset.originalImage", value: String(index + 1))
                        }.accessibilityIdentifier("profile.caseSubset.keep.\(index)")
                    }
                    Text("profile.caseSubset.positionHint").font(.footnote).foregroundStyle(.secondary)
                    if let reader {
                        NativeMediaGalleryEntry(sources: ProfileCasePortfolio(casePics: edit.snapshot.casePics).images,
                            scope: edit.id, titleKey: "profile.case.images", reader: reader)
                    }
                }
            }
        }
        .appNavigationTitle("profile.caseRemoval.title")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel", role: .cancel, action: cancel).accessibilityIdentifier("profile.caseRemoval.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("profile.fieldEdit.apply") {
                    if !removes, permitsSubset, let confirmSubset { confirmSubset(retainedIndices) }
                    else { confirm(removes) }
                }.accessibilityIdentifier("profile.caseRemoval.apply")
            }
        }
    }
}
