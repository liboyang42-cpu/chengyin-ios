import SwiftUI

/// Source pages/merchant/aftercare/index.wxml list row: title, "HH:mm · status", takeover tag,
/// activity line and right-aligned amount (muted "amount to be confirmed" when unknown).
struct MerchantAftercareRowLabel: View {
    let row: MerchantAftercareParity.ListRow
    private var toneColor: Color {
        switch row.tone { case .warning: return .orange; case .success: return .green; case .danger: return .red; case .neutral: return .secondary }
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: row.title).font(.headline)
                HStack(spacing: 4) {
                    if let time = row.timeText { Text(verbatim: time + " ·").foregroundStyle(.secondary) }
                    Text(verbatim: MerchantOpsCopy.text(row.statusKey)).foregroundStyle(toneColor)
                    if row.isTakenOver { Text(verbatim: "· " + MerchantOpsCopy.text("merchantOps.aftercare.takenOver")).foregroundStyle(.secondary) }
                }.font(.subheadline)
                if let activity = row.activityTitle { Text(verbatim: activity).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            if let amount = row.amountDisplay { Text(verbatim: amount).monospacedDigit() }
            else { Text(verbatim: MerchantOpsCopy.text("merchantOps.aftercare.amountPending")).font(.footnote).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("merchantOps.aftercare.row.\(row.id)")
    }
}

/// Day header with an optional total, shown above the first row of each request day.
struct MerchantAftercareDayHeader: View {
    let group: MerchantAftercareParity.DayGroup
    var body: some View {
        HStack {
            Text(verbatim: Self.label(group.label)).font(.footnote.bold())
            Spacer()
            if let total = group.total { Text(verbatim: total).font(.footnote).monospacedDigit() }
        }.foregroundStyle(.secondary).accessibilityIdentifier("merchantOps.aftercare.day.\(group.id)")
    }
    static func label(_ label: MerchantAftercareParity.DayLabel) -> String {
        switch label {
        case .today: return MerchantOpsCopy.text("merchantOps.aftercare.day.today")
        case .yesterday: return MerchantOpsCopy.text("merchantOps.aftercare.day.yesterday")
        case .sameYear(let month, let day): return MerchantOpsCopy.text("merchantOps.aftercare.day.monthDay %lld %lld", month, day)
        case .otherYear(let year, let month, let day): return MerchantOpsCopy.text("merchantOps.aftercare.day.yearMonthDay %lld %lld %lld", year, month, day)
        case .unknown: return MerchantOpsCopy.text("merchantOps.aftercare.day.unknown")
        }
    }
}

/// Source detail/view-model.js: hero subtitle, readable policy and the platform/funds steps that
/// follow recorded facts. Steps have no time and promise no arrival date.
struct MerchantAftercareDetailParitySections: View {
    let progress: MerchantAftercareProgress
    var body: some View {
        Section {
            let source = MerchantOpsCopy.text(MerchantAftercareParity.sourceKey(progress.sourceType))
            Text(verbatim: progress.activityTitle.map { source + " · " + $0 } ?? source).font(.subheadline)
                .accessibilityIdentifier("merchantOps.aftercare.heroSubtitle")
        }
        Section(MerchantOpsCopy.text("merchantOps.aftercare.platformSteps")) {
            ForEach(Array(MerchantAftercareParity.platformSteps(progress.processing).enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: MerchantOpsCopy.text(step.titleKey)).font(.subheadline.bold())
                    if let hint = step.hintKey { Text(verbatim: MerchantOpsCopy.text(hint)).font(.footnote).foregroundStyle(.secondary) }
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.aftercare.stepState." + step.state.rawValue)).font(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.aftercare.step.\(index)")
            }
        }
        if progress.policyCode != nil || progress.policyVersion != nil || progress.refundDeadline != nil {
            Section {
                Text(verbatim: MerchantOpsCopy.text(MerchantAftercareParity.policyKey(progress.policyCode)))
                    .accessibilityIdentifier("merchantOps.aftercare.policyText")
                if let version = progress.policyVersion {
                    Text(verbatim: MerchantOpsCopy.text("merchantOps.aftercare.policyVersion %lld", version)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Source detail/index.js read-only line when the respond pills are hidden.
struct MerchantAftercareReadOnlyNote: View {
    let reason: MerchantAftercareParity.ReadOnlyReason
    var body: some View {
        Text(verbatim: MerchantOpsCopy.text(reason == .roleViewOnly ? "merchantOps.aftercare.readOnly.role" : "merchantOps.aftercare.readOnly.closed"))
            .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("merchantOps.aftercare.readOnly")
    }
}
