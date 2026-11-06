import SwiftUI

struct ClubCheckinRailView: View {
    let rail: ClubCheckinRail
    var stateKind: ClubCheckinRail.StateKind? = nil
    var body: some View {
        Section("club.checkin.rail.title") {
            HStack(spacing: 6) {
                ForEach(rail.stops) { stop in
                    VStack(spacing: 4) {
                        Image(systemName: stop.reached ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(stop.reached ? Color.accentColor : Color.secondary)
                        Text(LocalizedStringKey("club.checkin.rail." + stop.step.rawValue))
                            .font(.caption.weight(stop.current ? .semibold : .regular))
                            .foregroundStyle(stop.reached ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(stop.current ? .isSelected : [])
                    .accessibilityValue(Text(stop.reached ? "club.checkin.rail.reached" : "club.checkin.rail.notReached"))
                    .accessibilityIdentifier("club.checkin.rail." + stop.step.rawValue)
                }
            }
            if let stateKind {
                Text(verbatim: stateKind.title).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("club.checkin.rail.stateTitle")
            }
            if let sessionTime = rail.sessionTimeText {
                Text(verbatim: sessionTime).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("club.checkin.rail.sessionTime")
            }
            if let statusTime = rail.statusTimeText {
                Text(verbatim: statusTime).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("club.checkin.rail.statusTime")
            }
            if rail.refunded {
                Text("club.checkin.rail.refunded").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("club.checkin.rail.refundedNote")
            }
        }
    }
}

/// Mini-program club/checkin-detail (K3): customer + status head, ticket card, then the six right-aligned rows.
/// Values come straight from the server; a missing value shows —.
struct ClubCheckinDetailRows: View {
    let value: ClubGovernanceValue
    var body: some View {
        Section {
            HStack(alignment: .top, spacing: Theme.Space.s3) {
                if let avatar = text("avatar") {
                    SquareImage(source: avatar).frame(width: 48, height: 48).clipShape(Circle()).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: text("displayName") ?? "—").font(.title3.weight(.semibold))
                        .accessibilityIdentifier("club.gov.fact.displayName")
                    if let session = text("sessionTimeText") { Text(verbatim: session).font(.subheadline).foregroundStyle(.secondary) }
                    if let phone = text("phoneText") { Text(verbatim: phone).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer(minLength: Theme.Space.s2)
                VStack(alignment: .trailing, spacing: 4) {
                    if let status = text("statusText") {
                        Text(verbatim: status).font(.subheadline.weight(.semibold)).foregroundStyle(statusColor)
                    }
                    if let time = text("statusTimeText") { Text(verbatim: time).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: text("topicName") ?? "—").font(.headline)
                if let order = text("orderNo") { Text("club.checkin.orderNo \(order)").font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            row("club.gov.field.ticketText", "ticketText")
            row("club.gov.field.orderTimeText", "orderTimeText")
            row("club.gov.field.paidAmountText", "paidAmountText")
            row("club.gov.field.verifyTimeText", "verifyTimeText")
            row("club.gov.field.storeName", "storeName")
            row("club.gov.field.operatorName", "operatorName")
            ClubGovernanceFactRows(value: value, fields: ["registrationId"])
        }
    }
    private var statusColor: Color {
        switch value["statusCode"].string {
        case "VERIFIED": return .green
        case "REFUNDED", "CANCELLED": return .red
        default: return .orange
        }
    }
    private func text(_ key: String) -> String? {
        guard let raw = value[key].text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }
    private func row(_ title: LocalizedStringKey, _ key: String) -> some View {
        LabeledContent(title) { Text(verbatim: text(key) ?? "—").monospacedDigit() }
    }
}
