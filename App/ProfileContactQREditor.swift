import SwiftUI

@MainActor struct ProfileContactQRSection: View {
    let wechat: String
    let removes: Bool
    let open: () -> Void
    var body: some View {
        Section("profile.contactQR.title") {
            Button(action: open) {
                HStack {
                    Label("profile.contactQR.open", systemImage: "qrcode")
                    Spacer()
                    Text(LocalizedStringKey(removes ? "profile.contactQR.staged" : (wechat.isEmpty ? "profile.contactQR.empty" : "profile.contactQR.available")))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("profile.contactQR.open")
        }
    }
}

/// The only proposed change is clearing the existing QR reference. No URL entry or upload.
@MainActor struct ProfileContactQREditor: View {
    let edit: ProfileTextFieldEdit
    let reader: (any RetainedPublicImageReading)?
    let cancel: () -> Void
    let confirm: (Bool) -> Void
    @State private var removes: Bool
    init(edit: ProfileTextFieldEdit, reader: (any RetainedPublicImageReading)? = nil,
         cancel: @escaping () -> Void, confirm: @escaping (Bool) -> Void) {
        self.edit = edit; self.reader = reader; self.cancel = cancel; self.confirm = confirm
        _removes = State(initialValue: edit.draft.removesContactQR)
    }
    var body: some View {
        Form {
            Section {
                if edit.snapshot.wechat.isEmpty {
                    ContentUnavailableView("profile.contactQR.empty", systemImage: "qrcode")
                        .accessibilityIdentifier("profile.contactQR.empty")
                } else if removes {
                    Label("profile.contactQR.staged", systemImage: "qrcode")
                        .accessibilityIdentifier("profile.contactQR.staged")
                    Button("profile.contactQR.restore") { removes = false }
                        .accessibilityIdentifier("profile.contactQR.restore")
                } else {
                    NativeMediaGalleryEntry(sources: [edit.snapshot.wechat], scope: edit.id,
                        titleKey: "profile.contactQR.title", reader: reader)
                    Button("profile.contactQR.remove", role: .destructive) { removes = true }
                        .accessibilityIdentifier("profile.contactQR.remove")
                }
            } footer: { Text("profile.contactQR.hint") }
            Text("profile.contactQR.noUpload").font(.footnote).foregroundStyle(.secondary)
        }
        .appNavigationTitle("profile.contactQR.title")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel", role: .cancel, action: cancel)
                    .accessibilityIdentifier("profile.contactQR.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("profile.fieldEdit.apply") { confirm(removes) }
                    .accessibilityIdentifier("profile.contactQR.apply")
            }
        }
    }
}
