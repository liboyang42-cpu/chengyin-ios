import SwiftUI

/// Mini event-ops series copy around the existing draft bindings. It never submits or validates for the command.
@MainActor struct ClubOpsEventSeriesFields: View {
    let operation: ClubGovernanceMutation
    @Binding var capacity: String
    @Binding var waitlist: Bool
    var body: some View {
        if operation == .updateSeries {
            VStack(alignment: .leading, spacing: 6) {
                Text("clubOpsEvent.edit.locked", tableName: "ClubOpsEvent").font(.footnote)
                    .accessibilityIdentifier("clubOpsEvent.edit.locked")
                Text("clubOpsEvent.series.note", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
                Text("clubOpsEvent.refundAnchor", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
            }
        } else if operation == .createSeries {
            VStack(alignment: .leading, spacing: 6) {
                Text("clubOpsEvent.recurrence.note", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
                Text("clubOpsEvent.refundAnchor", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("clubOpsEvent.section.capacity", tableName: "ClubOpsEvent").font(.headline)
                Text("clubOpsEvent.capacity.note", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
                Text("club.gov.field.capacity")
                TextField(text: $capacity, prompt: Text("clubOpsEvent.capacity.placeholder", tableName: "ClubOpsEvent")) { Text("club.gov.field.capacity") }
                    .keyboardType(.numberPad).accessibilityIdentifier("club.gov.input.capacity")
                if ClubOpsEventInput.capacityInvalid(capacity) {
                    Text("clubOpsEvent.capacity.invalid", tableName: "ClubOpsEvent").font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("clubOpsEvent.capacity.invalid")
                }
                Text("clubOpsEvent.capacity.help", tableName: "ClubOpsEvent").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("club.gov.field.waitlistEnabled", isOn: $waitlist).accessibilityIdentifier("club.gov.input.waitlistEnabled")
        }
    }
}

/// Explains the existing offer field; the hidden value still goes through the command's 5...1440 check.
@MainActor struct ClubOpsEventOfferHelp: View {
    let minutes: String
    let visible: Bool
    var body: some View {
        if visible {
            Text("clubOpsEvent.offer.placeholder", tableName: "ClubOpsEvent").font(.caption).foregroundStyle(.secondary)
            Text("clubOpsEvent.offer.help", tableName: "ClubOpsEvent").font(.caption).foregroundStyle(.secondary)
        }
        if ClubOpsEventInput.offerInvalid(minutes) {
            Text("clubOpsEvent.offer.invalid", tableName: "ClubOpsEvent").font(.caption).foregroundStyle(.red)
                .accessibilityIdentifier("clubOpsEvent.offer.invalid")
        }
    }
}

/// Reason input for cancel/correct with the mini placeholder and inline range message.
@MainActor struct ClubOpsEventReasonField: View {
    let operation: ClubGovernanceMutation
    @Binding var reason: String
    var body: some View {
        let cancel = operation == .cancelOccurrence
        VStack(alignment: .leading, spacing: 4) {
            TextField(text: $reason, prompt: Text(cancel ? "clubOpsEvent.cancel.placeholder" : "clubOpsEvent.correct.placeholder", tableName: "ClubOpsEvent"),
                      axis: .vertical) { Text("club.gov.field.reason") }
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityIdentifier("club.gov.input.reason")
            if !reason.isEmpty, cancel ? ClubOpsEventInput.cancelReasonInvalid(reason) : ClubOpsEventInput.correctionReasonInvalid(reason) {
                Text(cancel ? "clubOpsEvent.cancel.reasonInvalid" : "clubOpsEvent.correct.reasonInvalid", tableName: "ClubOpsEvent")
                    .font(.caption).foregroundStyle(.red).accessibilityIdentifier("clubOpsEvent.reason.invalid")
            }
            if cancel {
                Text("clubOpsEvent.cancel.subtitle", tableName: "ClubOpsEvent").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct ClubOpsEventVisibility: ViewModifier {
    let visible: Bool
    @ViewBuilder func body(content: Content) -> some View { if visible { content } }
}
extension View {
    func clubOpsEventVisible(_ visible: Bool) -> some View { modifier(ClubOpsEventVisibility(visible: visible)) }
}

enum ClubOpsEventFormCopy {
    static func title(_ route: ClubGovernanceFormRoute) -> Text {
        if route.operation == .correctAttendance, let arrived = route.seed["arrived"]?.bool {
            return Text(arrived ? "clubOpsEvent.correct.toArrived" : "clubOpsEvent.correct.toAbsent", tableName: "ClubOpsEvent")
        }
        return Text(LocalizedStringKey("club.gov.action." + route.operation.rawValue))
    }
}
