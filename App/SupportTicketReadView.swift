import SwiftUI

func supportTicketReadText(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "SupportTicketRead") }
/// r463's list and selected details remain in the same screen. No create, message composer or attachment action.
@MainActor struct SupportTicketReadView: View {
    @ObservedObject var session: AppSession
    @Environment(\.scenePhase) private var scene
    @State private var identity: AppSession.SupportTicketReadIdentity?
    @State private var flow: SupportTicketReadCoordinator?
    @State private var owner: SupportTicketReadVisit?
    @State private var visible = false
    @State private var resumeNumber: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        let rendered = readIntent()
        Form {
            Section { supportTicketReadText("boundary").font(.footnote) }
            if let flow, flow.isCurrent {
                if let ticket = flow.ticket {
                    Section {
                        Text(verbatim: ticket.subject).textSelection(.enabled)
                        Text(verbatim: ticket.ticket_no).font(.caption).textSelection(.enabled)
                        field("status", ticket.status); field("category", ticket.category)
                        field("timezone", ticket.timezone); field("created", ticket.create_time)
                        field("sla", ticket.sla_state); field("firstDue", ticket.sla_first_due_at); field("resolveDue", ticket.sla_resolve_due_at)
                        if let reference = ticket.related_reference {
                            supportTicketReadText("reference").font(.footnote)
                            Text(verbatim: reference.domain_type + " #" + reference.resource_id + " · MEMBER #" + reference.owner_member_id).font(.caption).textSelection(.enabled)
                        }
                    }
                    Section {
                        ForEach(flow.messages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: message.sender_type).font(.caption)
                                Text(verbatim: message.content).textSelection(.enabled)
                                Text(verbatim: message.create_time).font(.caption)
                                if !message.attachments.isEmpty { supportTicketReadText("attachmentsUnavailable").font(.footnote) }
                            }
                        }
                        if flow.loaded && flow.messages.isEmpty { supportTicketReadText("messagesEmpty") }
                        if flow.hasMoreMessages { Button { run(rendered) { await $0.reloadDetail($1, next: true) } } label: { supportTicketReadText("messagesMore") }.disabled(flow.busy) }
                        Button { run(rendered) { await $0.reloadDetail($1) } } label: { supportTicketReadText("reloadDetail") }.disabled(flow.busy)
                    } header: { supportTicketReadText("messages") }
                    Section {
                        supportTicketReadText("timelineBoundary").font(.footnote)
                        ForEach(flow.events) { event in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: event.event_type + " · " + event.actor_type)
                                Text(verbatim: event.result_state).font(.caption)
                                if let status = event.historical_status { Text(verbatim: status).font(.caption) }
                                if let reason = event.reason { Text(verbatim: reason).font(.caption) }
                                if let sla = event.historical_sla_state { Text(verbatim: sla).font(.caption) }
                                if let version = event.historical_version { Text(verbatim: "v" + String(version)).font(.caption) }
                                if let original = event.request_id { Text(verbatim: original).font(.caption).textSelection(.enabled) }
                                Text(verbatim: event.created_at).font(.caption)
                            }
                        }
                        if flow.timelineLoaded && flow.events.isEmpty { supportTicketReadText("eventsEmpty") }
                        Button { run(rendered) { await $0.loadTimeline($1) } } label: { supportTicketReadText("loadTimeline") }.disabled(flow.busy || !flow.reader.allows(.timeline))
                        if flow.hasMoreEvents { Button { run(rendered) { await $0.loadTimeline($1, next: true) } } label: { supportTicketReadText("eventsMore") }.disabled(flow.busy) }
                    } header: { supportTicketReadText("timeline") }
                } else {
                    Section {
                        ForEach(flow.tickets) { row in
                            Button { run(rendered) { await $0.open(row, intent: $1) } } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(verbatim: row.subject)
                                    Text(verbatim: row.ticket_no + " · " + row.status).font(.caption)
                                }
                            }.disabled(flow.busy || !flow.reader.allows(.detail))
                            .accessibilityIdentifier("support.read.row." + row.ticket_no)
                        }
                        if flow.loaded && flow.tickets.isEmpty { supportTicketReadText("empty") }
                        if flow.hasMoreTickets { Button { run(rendered) { await $0.loadHistory($1, next: true) } } label: { supportTicketReadText("listMore") }.disabled(flow.busy) }
                    } header: { supportTicketReadText("list") }
                }
                if flow.busy { ProgressView() }
                if let failure = flow.failure { supportTicketReadText("error.\(failure)").accessibilityIdentifier("support.read.error") }
                Button { resumeNumber = nil; run(rendered) { await $0.loadHistory($1) } } label: { supportTicketReadText("reloadList") }.disabled(flow.busy || !flow.reader.allows(.history))
            } else { supportTicketReadText("error.disabled") }
        }
        .navigationTitle(supportTicketReadText("title")).privacySensitive().accessibilityIdentifier("support.read.screen")
        .onAppear { visible = true; if identity == nil { identity = session.supportTicketReadIdentity }; start() }
        .onDisappear { visible = false; retire(preserveSelection: true) }
        .onChange(of: scene) { _, phase in retire(preserveSelection: true); if phase == .active { start() } }
        .onChange(of: session.supportTicketReadIdentity) { _, _ in retire(preserveSelection: false) }
    }
    @ViewBuilder private func field(_ key: String, _ value: String?) {
        if let value { LabeledContent { Text(verbatim: value).textSelection(.enabled) } label: { supportTicketReadText(key) } }
    }
    private func readIntent() -> (SupportTicketReadCoordinator, SupportTicketReadIntent)? {
        guard visible, scene == .active, identity == session.supportTicketReadIdentity,
              let flow, let owner, let intent = flow.capture(owner) else { return nil }; return (flow, intent)
    }
    private func start() {
        guard visible, scene == .active, identity == session.supportTicketReadIdentity else { return }
        retire(preserveSelection: true)
        guard let reader = session.makeSupportTicketReadReader() else { return }
        let value = reader.makeCoordinator(); flow = value; owner = value.begin()
        if let number = resumeNumber { run(readIntent()) { await $0.resumeDetail(number: number, intent: $1) } }
        else { run(readIntent()) { await $0.loadHistory($1) } }
    }
    private func run(_ captured: (SupportTicketReadCoordinator, SupportTicketReadIntent)?, action: @escaping @MainActor (SupportTicketReadCoordinator, SupportTicketReadIntent) async -> Void) {
        guard let (original, intent) = captured, original.accepts(intent) else { return }
        task?.cancel(); task = Task { guard original.accepts(intent) else { return }; await action(original, intent) }
    }
    private func retire(preserveSelection: Bool) {
        if preserveSelection, identity == session.supportTicketReadIdentity { resumeNumber = flow?.ticket?.ticket_no ?? resumeNumber }
        else { resumeNumber = nil }
        task?.cancel(); task = nil; if let owner { flow?.end(owner) }; flow = nil; owner = nil
    }
}
