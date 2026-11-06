import SwiftUI

/// Source pages/merchant/aftercare/index.wxml list row: title, "HH:mm · status", takeover tag,
/// activity line and right-aligned amount (muted "amount to be confirmed" when unknown).
struct MerchantAftercareRowLabel: View {
    let row: MerchantAftercareParity.ListRow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var toneColor: Color {
        switch row.tone { case .warning: return .orange; case .success: return .green; case .danger: return .red; case .neutral: return .secondary }
    }
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        let metadataLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Space.s1))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: row.title).font(.headline)
                metadataLayout {
                    if let time = row.timeText { Text(verbatim: time + " ·").foregroundStyle(.secondary) }
                    Text(verbatim: MerchantOpsCopy.text(row.statusKey)).foregroundStyle(toneColor)
                    if row.isTakenOver { Text(verbatim: "· " + MerchantOpsCopy.text("merchantOps.aftercare.takenOver")).foregroundStyle(.secondary) }
                }.font(.subheadline)
                if let activity = row.activityTitle { Text(verbatim: activity).font(.footnote).foregroundStyle(.secondary) }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if let amount = row.amountDisplay { Text(verbatim: amount).font(Theme.Font.cardTitle).monospacedDigit() }
            else { Text(verbatim: MerchantOpsCopy.text("merchantOps.aftercare.amountPending")).font(.footnote).foregroundStyle(.secondary) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("merchantOps.aftercare.row.\(row.id)")
    }
}

/// Day header with an optional total, shown above the first row of each request day.
struct MerchantAftercareDayHeader: View {
    let group: MerchantAftercareParity.DayGroup
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            Text(verbatim: Self.label(group.label)).font(.footnote.bold())
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Space.s2) }
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

/// Source detail/index.js read-only line when the respond pills are hidden.
struct MerchantAftercareReadOnlyNote: View {
    let reason: MerchantAftercareParity.ReadOnlyReason
    var body: some View {
        Text(verbatim: MerchantOpsCopy.text(reason == .roleViewOnly ? "merchantOps.aftercare.readOnly.role" : "merchantOps.aftercare.readOnly.closed"))
            .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("merchantOps.aftercare.readOnly")
    }
}
