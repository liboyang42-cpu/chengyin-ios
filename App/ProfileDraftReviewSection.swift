import SwiftUI

/// Comparison and discard confirmation share the immutable prepared review's lifetime.
struct ProfileDraftReviewSection: View {
    let summary: ProfileEditReviewSummary
    let canRestore: Bool
    let restore: () -> Void
    @State private var showsRestore = false
    var body: some View {
        Section {
            DisclosureGroup {
                if summary.changes.isEmpty { Text("profile.reviewRestore.noChanges") }
                ForEach(summary.changes) { change in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(title(change.field))).font(.headline)
                        LabeledContent { value(change.before) } label: { Text("profile.reviewRestore.before") }
                        LabeledContent { value(change.after) } label: { Text("profile.reviewRestore.after") }
                    }.accessibilityIdentifier("profile.reviewRestore.change.\(change.id)")
                }
                Text("profile.reviewRestore.exactTextHint").font(.footnote).foregroundStyle(.secondary)
            } label: { Text("profile.reviewRestore.compare") }
            .accessibilityIdentifier("profile.reviewRestore.compare")
            Button("profile.reviewRestore.open", role: .destructive) { showsRestore = true }
                .disabled(!canRestore).accessibilityIdentifier("profile.reviewRestore.open")
                .confirmationDialog("profile.reviewRestore.title", isPresented: $showsRestore, titleVisibility: .visible) {
                    Button("profile.reviewRestore.confirm", role: .destructive, action: restore)
                        .accessibilityIdentifier("profile.reviewRestore.confirm")
                    Button("action.cancel", role: .cancel) { }
                        .accessibilityIdentifier("profile.reviewRestore.cancel")
                } message: { Text("profile.reviewRestore.message") }
        }
    }
    @ViewBuilder private func value(_ value: ProfileEditReviewValue) -> some View {
        switch value {
        case .text(let text):
            if text.isEmpty { Text("profile.reviewRestore.empty") }
            else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text("profile.reviewRestore.whitespace") }
            else { Text(verbatim: text).textSelection(.enabled) }
        case .selection(let raw):
            if raw.isEmpty { Text("profile.preferenceRemoval.empty") }
            else { Text(verbatim: raw).textSelection(.enabled) }
        case .imageCount(let count): Text(verbatim: String(count))
        case .present(let present): Text(LocalizedStringKey(present ? "profile.reviewRestore.present" : "profile.reviewRestore.absent"))
        case .newAvatar: Text("profile.reviewRestore.newAvatar")
        }
    }
    private func title(_ field: ProfileEditReviewField) -> String {
        switch field {
        case .name: return "profile.edit.name"
        case .introduction: return "profile.edit.introduction"
        case .caseIntroduction: return "profile.case.description"
        case .preferences: return "context.preferences.title"
        case .avatar: return "profile.avatar.title"
        case .contactQR: return "profile.contactQR.title"
        case .casePictures: return "profile.case.images"
        }
    }
}
