import SwiftUI

struct ClubOperationsReviewView: View {
    let review: ClubOperationsReview
    let canSubmit: Bool
    let isExample: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @State private var submitted = false
    var body: some View {
        Form {
            Section {
                Text("club.ops.reviewTarget").font(.headline).accessibilityIdentifier("club.ops.reviewSheet")
                if let club = review.snapshot.profile?.club {
                    LabeledContent("club.ops.club") { Text(verbatim: "\(club.name) (#\(club.id))") }
                } else { Text("club.ops.newClub") }
                if let account = review.identity.accountID {
                    LabeledContent("club.ops.account") { Text(verbatim: "#\(account)") }
                }
            }
            details
            Section {
                Text(LocalizedStringKey(canSubmit ? (isExample ? "club.ops.fixtureOnly" : "club.ops.confirmLiveHint") : "club.ops.writeGated"))
                if canSubmit {
                    Button(LocalizedStringKey(isExample ? "club.ops.confirmFixture" : "club.ops.confirmLive")) { submitted = true; onConfirm() }
                        .disabled(submitted).accessibilityIdentifier("club.ops.confirm")
                }
            }
        }
        .navigationTitle("club.ops.review")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("club.ops.cancel", action: onCancel).disabled(submitted).accessibilityIdentifier("club.ops.cancelReview")
            }
        }
    }
    @ViewBuilder private var details: some View {
        switch review.command {
        case .create(let draft): profile(draft, original: nil)
        case .update(let draft, let original): profile(draft, original: original)
        case .openSetting(let setting, let enabled, let previous):
            Section(LocalizedStringKey("club.ops." + setting.rawValue)) {
                LabeledContent("club.ops.current") { Text(previous ? "club.ops.enabled" : "club.ops.disabled") }
                LabeledContent("club.ops.requested") { Text(enabled ? "club.ops.enabled" : "club.ops.disabled") }
                Text(LocalizedStringKey("club.ops.settingConsequences." + setting.rawValue))
            }
        case .memberRole(let id, let admin, _):
            Section("club.ops.memberRoles") {
                let name = review.snapshot.members.first { $0.id == id }?.trimmedNickname ?? "#\(id)"
                LabeledContent("club.ops.member") { Text(verbatim: "\(name) (#\(id))") }
                Text(admin ? "club.ops.makeAdmin" : "club.ops.removeAdmin")
                Text("club.ops.roleConsequences")
            }
        }
    }
    private func profile(_ draft: ClubOperationsDraft, original: ClubOperationsProfile?) -> some View {
        Section("club.ops.profile") {
            row("name", draft.name); row("city", draft.city)
            LabeledContent("club.ops.clubType") { canonical(draft.clubType) }
            row("description", draft.description); row("keywords", draft.keywords); row("style", draft.style)
            ForEach(draft.activityPrefs, id: \.self) { canonical($0) }
            if let original {
                LabeledContent("club.ops.prioritySignup") { Text(draft.prioritySignupEnabled ? "club.ops.enabled" : "club.ops.disabled") }
                row("quota", draft.memberReservedQuota.isEmpty ? "0" : draft.memberReservedQuota)
                if original.club.joinPolicySupported {
                    LabeledContent("club.ops.joinPolicy") { Text(draft.joinPolicy == 1 ? "club.ops.joinReview" : "club.ops.joinDirect") }
                }
            }
            Text("club.ops.mediaPreserved").font(.footnote)
        }
    }
    @ViewBuilder private func canonical(_ value: String) -> some View {
        if ClubOperationsCatalog.types.contains(value) || ClubOperationsCatalog.directions.contains(value) { Text(LocalizedStringKey("club.ops.value." + value)) }
        else { Text(verbatim: value) }
    }
    private func row(_ key: String, _ value: String) -> some View {
        LabeledContent(LocalizedStringKey("club.ops." + key)) { Text(verbatim: value.trimmingCharacters(in: .whitespacesAndNewlines)).textSelection(.enabled) }
    }
}
