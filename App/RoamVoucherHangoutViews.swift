import SwiftUI

@MainActor struct RoamVoucherEntryView: View {
    @State private var poiID = ""
    @Environment(\.verificationCodeFactory) private var codeFactory
    private var target: VerificationCodeTarget? {
        guard let id = Int(poiID), id > 0 else { return nil }
        return .init(kind: .cityVoucher, id: id)
    }
    var body: some View {
        List {
            Section {
                TextField("roam.experience.poiID", text: $poiID).keyboardType(.numberPad)
                    .accessibilityIdentifier("roam.experience.voucher.poiID")
                if let target {
                    if let codeFactory {
                        NavigationLink("verificationCode.city.open") { VerificationCodeView(model: codeFactory(target)) }
                            .accessibilityIdentifier("verificationCode.city.open")
                    } else { Text("verificationCode.phase.disabled") }
                } else {
                    Label("roam.experience.voucherMissing", systemImage: "questionmark.circle")
                    Text("roam.experience.voucherMissingHint").font(.caption)
                }
                Text("verificationCode.city.authority").font(.footnote).foregroundStyle(.secondary)
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
