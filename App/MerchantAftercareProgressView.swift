import SwiftUI

/// Rendered only inside the current authorized MerchantBusinessPage snapshot.
/// No separate fetch, cached destination, evidence download or mutation is introduced.
struct MerchantAftercareProgressView: View {
    let progress: MerchantAftercareProgress
    @State private var phoneTimeZone = TimeZone.current
    var body: some View {
        Section("merchant.aftercareProgress.summary") {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: progress.refundNumber ?? "#\(progress.refundID)").font(.headline)
                if progress.amount.raw != nil {
                    Text(verbatim: progress.amount.display).font(.title2).monospacedDigit()
                } else {
                    Text("merchant.aftercareProgress.amountUnknown").foregroundStyle(.secondary)
                }
                if let activity = progress.activityTitle { Text(verbatim: activity) }
            }.accessibilityIdentifier("merchant.business.row.refund.\(progress.refundID)")
            if let type = progress.sourceType { LabeledContent("merchant.business.field.sourceType", value: type) }
            if let id = progress.sourceID { LabeledContent("merchant.business.field.sourceId", value: String(id)) }
            if let name = progress.customerNickname { LabeledContent("merchant.business.field.customerNickname", value: name) }
            if let reason = progress.reason { LabeledContent("merchant.business.field.reason", value: reason) }
        }
        Section("merchant.aftercareProgress.current") {
            LabeledContent("merchant.aftercareProgress.platform") {
                Text(LocalizedStringKey("merchant.business.state." + progress.processing.rawValue))
            }.accessibilityIdentifier("merchant.aftercareProgress.platform")
            LabeledContent("merchant.aftercareProgress.opinion") {
                Text(LocalizedStringKey("merchant.aftercareProgress.opinion." + progress.opinion.rawValue))
            }.accessibilityIdentifier("merchant.aftercareProgress.opinion")
            LabeledContent("merchant.aftercareProgress.funds") {
                Text(LocalizedStringKey("merchant.aftercareProgress.funds." + progress.funds.rawValue))
            }.accessibilityIdentifier("merchant.aftercareProgress.funds")
            Text("merchant.business.opinionOnly").font(.footnote).foregroundStyle(.secondary)
        }
        Section("merchant.aftercareProgress.history") {
            Text("merchant.aftercareProgress.historyHint").font(.footnote).foregroundStyle(.secondary)
            ForEach(progress.events) { event in
                VStack(alignment: .leading, spacing: 6) {
                    switch event.kind {
                    case .requested:
                        Label("merchant.aftercareProgress.requested", systemImage: "doc.text")
                    case .platformTakeover:
                        Label("merchant.aftercareProgress.takeover", systemImage: "person.crop.circle.badge.clock")
                    case .response(let response):
                        Label(LocalizedStringKey("merchant.aftercareProgress.decision." + response.decision.rawValue), systemImage: "text.bubble")
                        Text(LocalizedStringKey(response.actorKey)).font(.subheadline)
                        if let content = response.content { Text(verbatim: content) }
                        if response.evidence != .none && response.evidence != .notProvided {
                            Text(LocalizedStringKey("merchant.aftercareProgress.evidence." + response.evidence.rawValue))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if let time = event.occurredAt { Text(verbatim: MerchantAftercareTime.event(time, phoneTimeZone: phoneTimeZone)).font(.caption).foregroundStyle(.secondary) }
                    else { Text("merchant.aftercareProgress.timeUnknown").font(.caption).foregroundStyle(.secondary) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("merchant.aftercareProgress.event." + event.id)
            }
        }
        .onAppear { phoneTimeZone = .current }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            phoneTimeZone = .current
        }
        if progress.policyCode != nil || progress.policyVersion != nil || progress.refundDeadline != nil {
            Section("merchant.aftercareProgress.policy") {
                if let code = progress.policyCode { LabeledContent("merchant.business.field.refundPolicyCode", value: code) }
                if let version = progress.policyVersion { LabeledContent("merchant.business.field.refundPolicyVersion", value: String(version)) }
                if let deadline = progress.refundDeadline { LabeledContent("merchant.aftercareProgress.deadlineBeijing", value: MerchantAftercareTime.deadline(deadline)) }
                Text("merchant.aftercareProgress.policyHint").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
