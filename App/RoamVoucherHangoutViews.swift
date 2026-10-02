import SwiftUI

struct RoamVoucherEntryView: View {
    @State private var poiID = ""
    private var phase: RoamVoucherPhase { (Int(poiID) ?? 0) > 0 ? .unavailable : .missing }
    var body: some View {
        List {
            Section {
                TextField("roam.experience.poiID", text: $poiID).keyboardType(.numberPad)
                    .accessibilityIdentifier("roam.experience.voucher.poiID")
                if phase == .missing {
                    Label("roam.experience.voucherMissing", systemImage: "questionmark.circle")
                    Text("roam.experience.voucherMissingHint").font(.caption)
                } else {
                    Label("roam.experience.voucherUnavailable", systemImage: "lock.shield")
                    Text("roam.experience.voucherHint").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("roam.experience.voucher")
            .accessibilityIdentifier("roam.experience.voucher")
    }
}
struct RoamHangoutUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("roam.experience.hangoutUnavailable", systemImage: "person.3")
        } description: {
            Text("roam.experience.hangoutHint")
        }.navigationTitle("roam.experience.hangout")
            .accessibilityIdentifier("roam.experience.hangout.unavailable")
    }
}
