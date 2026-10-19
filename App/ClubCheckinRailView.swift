import SwiftUI

struct ClubCheckinRailView: View {
    let rail: ClubCheckinRail
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
            if rail.refunded {
                Text("club.checkin.rail.refunded").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("club.checkin.rail.refundedNote")
            }
        }
    }
}
