import SwiftUI

/// Normal entry for the original admission routes. Appearance does not send.
/// The request id stays on the action that was sent, including when recovery is needed.
@MainActor struct ChannelAdmissionGovernanceView: View {
    let client: ChannelAdmissionGovernanceClient
    let kind: Int
    let spaceID: Int64
    @State private var reason = ""
    @State private var inviteID = ""
    @State private var pauseOnID: String?
    @State private var pauseOffID: String?
    @State private var lastPauseID: String?
    @State private var revokeID: String?
    @State private var sending = false
    @State private var message = ""

    var body: some View {
        Form {
            Section("admission.space") {
                Text(verbatim: String(spaceID))
                TextField("admission.reason", text: $reason)
                TextField("admission.invite", text: $inviteID)
            }
            Section {
                Button("admission.pause") { Task { await pause(true) } }
                Button("admission.unpause") { Task { await pause(false) } }
                Button("admission.revokeInvite") { Task { await revoke() } }
                Button("admission.recoverPause") { Task { await recover(lastPauseID) } }
                    .disabled(lastPauseID == nil)
                Button("admission.recoverInvite") { Task { await recover(revokeID) } }
                    .disabled(revokeID == nil)
            }
            .disabled(sending)
            if sending { ProgressView("admission.sending") }
            if !message.isEmpty { Text(verbatim: message).font(.footnote) }
            if let lastPauseID { Text(verbatim: lastPauseID).font(.footnote) }
            if let revokeID { Text(verbatim: revokeID).font(.footnote) }
        }
        .navigationTitle(Text("admission.title"))
        .privacySensitive()
    }

    private func pause(_ paused: Bool) async {
        let id = (paused ? pauseOnID : pauseOffID) ?? Self.freshRequestID()
        if paused { pauseOnID = id } else { pauseOffID = id }
        lastPauseID = id
        sending = true
        defer { sending = false }
        do {
            let sent = try await client.pause(kind: kind, spaceID: spaceID, paused: paused, until: nil, reason: reason, requestID: id)
            message = (sent["join_paused"] as? Bool) == paused ? "admission.paused" : "admission.unknown"
        } catch {
            message = "admission.unknown"
        }
    }

    private func revoke() async {
        guard let invite = Int64(inviteID), invite > 0 else { message = "admission.invalid"; return }
        let id = revokeID ?? Self.freshRequestID()
        revokeID = id
        sending = true
        defer { sending = false }
        do {
            _ = try await client.revokeInvite(inviteID: invite, reason: reason, requestID: id)
            message = "admission.revoked"
        } catch {
            message = "admission.unknown"
        }
    }

    private func recover(_ requestID: String?) async {
        guard let requestID else { return }
        sending = true
        defer { sending = false }
        do {
            let row = try await client.recover(requestID: requestID)
            message = row["state"] as? String ?? "admission.recovered"
        } catch {
            message = "admission.unknown"
        }
    }

    private static func freshRequestID() -> String {
        "adm-" + UUID().uuidString.lowercased()
    }
}
