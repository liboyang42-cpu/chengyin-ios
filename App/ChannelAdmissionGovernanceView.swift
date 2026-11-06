import SwiftUI

/// Normal entry for the original admission routes. Appearance does not send.
/// Each action keeps its own request id, and recovery uses that same id.
@MainActor struct ChannelAdmissionGovernanceView: View {
    let client: ChannelAdmissionGovernanceClient
    let catalog: ChannelCatalogEntry?
    let kind: Int
    let spaceID: Int64
    @State private var reason = ""
    @State private var note = ""
    @State private var inviteID = ""
    @State private var applicationID = ""
    @State private var reasonCode = "1"
    @State private var submitID: String?
    @State private var cancelID: String?
    @State private var approveID: String?
    @State private var rejectID: String?
    @State private var leaveID: String?
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
                TextField("admission.note", text: $note)
                TextField("admission.invite", text: $inviteID)
                TextField("admission.application", text: $applicationID)
                TextField("admission.reasonCode", text: $reasonCode)
            }
            Section {
                Button("admission.submit") { Task { await submit() } }
                    .disabled(catalog == nil)
                Button("admission.cancel") { Task { await cancel() } }
                Button("admission.approve") { Task { await approve() } }
                Button("admission.reject") { Task { await reject() } }
                Button("admission.leave") { Task { await leave() } }
                Button("admission.pause") { Task { await pause(true) } }
                Button("admission.unpause") { Task { await pause(false) } }
                Button("admission.revokeInvite") { Task { await revoke() } }
            }
            .disabled(sending)
            Section {
                recoverButton("admission.recoverSubmit", submitID)
                recoverButton("admission.recoverCancel", cancelID)
                recoverButton("admission.recoverApprove", approveID)
                recoverButton("admission.recoverReject", rejectID)
                recoverButton("admission.recoverLeave", leaveID)
                recoverButton("admission.recoverPause", lastPauseID)
                recoverButton("admission.recoverInvite", revokeID)
            }
            .disabled(sending)
            if sending { ProgressView("admission.sending") }
            if !message.isEmpty { Text(verbatim: message).font(.footnote) }
            ForEach([submitID, cancelID, approveID, rejectID, leaveID, lastPauseID, revokeID].compactMap { $0 }, id: \.self) { id in
                Text(verbatim: id).font(.footnote)
            }
        }
        .navigationTitle(Text("admission.title"))
        .privacySensitive()
    }

    private func recoverButton(_ title: LocalizedStringKey, _ requestID: String?) -> some View {
        Button(title) { Task { await recover(requestID) } }
            .disabled(requestID == nil)
    }

    private func submit() async {
        guard let catalog else { message = "admission.invalid"; return }
        let id = remember(submitID) { submitID = $0 }
        await run(id) {
            _ = try await client.submit(catalog: catalog, kind: kind, spaceID: spaceID, inviteID: parsed(inviteID), message: note, requestID: id)
            message = "admission.submitted"
        }
    }

    private func cancel() async {
        guard let application = parsed(applicationID) else { message = "admission.invalid"; return }
        let id = remember(cancelID) { cancelID = $0 }
        await run(id) {
            _ = try await client.cancel(applicationID: application, requestID: id)
            message = "admission.cancelled"
        }
    }

    private func approve() async {
        guard let application = parsed(applicationID) else { message = "admission.invalid"; return }
        let id = remember(approveID) { approveID = $0 }
        await run(id) {
            _ = try await client.approve(applicationID: application, note: note, requestID: id)
            message = "admission.approved"
        }
    }

    private func reject() async {
        guard let application = parsed(applicationID), let code = Int(reasonCode), [1, 2, 3, 4, 5, 9].contains(code) else {
            message = "admission.invalid"
            return
        }
        let id = remember(rejectID) { rejectID = $0 }
        await run(id) {
            _ = try await client.reject(applicationID: application, reasonCode: code, note: note, requestID: id)
            message = "admission.rejected"
        }
    }

    private func leave() async {
        let id = remember(leaveID) { leaveID = $0 }
        await run(id) {
            _ = try await client.leave(kind: kind, spaceID: spaceID, requestID: id)
            message = "admission.left"
        }
    }

    private func pause(_ paused: Bool) async {
        let id = (paused ? pauseOnID : pauseOffID) ?? Self.freshRequestID()
        if paused { pauseOnID = id } else { pauseOffID = id }
        lastPauseID = id
        await run(id) {
            let sent = try await client.pause(kind: kind, spaceID: spaceID, paused: paused, until: nil, reason: reason, requestID: id)
            message = (sent["join_paused"] as? Bool) == paused ? "admission.paused" : "admission.unknown"
        }
    }

    private func revoke() async {
        guard let invite = parsed(inviteID) else { message = "admission.invalid"; return }
        let id = remember(revokeID) { revokeID = $0 }
        await run(id) {
            _ = try await client.revokeInvite(inviteID: invite, reason: reason, requestID: id)
            message = "admission.revoked"
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

    private func remember(_ current: String?, store: (String) -> Void) -> String {
        let id = current ?? Self.freshRequestID()
        store(id)
        return id
    }

    private func run(_ requestID: String, _ body: () async throws -> Void) async {
        _ = requestID
        sending = true
        defer { sending = false }
        do { try await body() } catch { message = "admission.unknown" }
    }

    private func parsed(_ raw: String) -> Int64? {
        guard let value = Int64(raw), value > 0 else { return nil }
        return value
    }

    private static func freshRequestID() -> String {
        "adm-" + UUID().uuidString.lowercased()
    }
}
