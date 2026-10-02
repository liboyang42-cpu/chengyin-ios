import Foundation

/// Known source permission reads. Missing capability evidence fails closed; no invented permission endpoint.
@MainActor public final class CoopFlowSourceEvidenceReader: CoopFlowEvidenceReading {
    private let reader: any CoopFlowReading
    /// For topic-owner creation and merchant offer contexts, the caller may supply an audited fresh reader.
    /// It must include current membership/role, source terms and selection in its baseline.
    private let additional: ((CoopFlowMutation, CoopFlowSession) async throws -> CoopFlowEvidence)?
    public init(reader: any CoopFlowReading, additional: ((CoopFlowMutation, CoopFlowSession) async throws -> CoopFlowEvidence)? = nil) {
        self.reader = reader; self.additional = additional
    }
    public func freshEvidence(for operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowEvidence {
        guard reader.session == session else { throw CoopFlowFailure.stale }
        let result = try await evidence(operation)
        guard reader.session == session else { throw CoopFlowFailure.stale }
        if let result { return result }
        if let additional {
            let value = try await additional(operation, session)
            guard reader.session == session else { throw CoopFlowFailure.stale }; return value
        }
        return CoopFlowEvidence(baseline: .null, permitted: false)
    }
    private func unique(_ rows: [CoopFlowJSON]?, key: String, id: Int) throws -> CoopFlowJSON {
        guard let rows else { throw CoopFlowFailure.malformed }
        let matches = rows.filter { $0[key].integer == id }
        guard !matches.isEmpty else { throw CoopFlowFailure.unavailable }
        guard matches.count == 1 else { throw CoopFlowFailure.conflict }; return matches[0]
    }
    private func evidence(_ op: CoopFlowMutation) async throws -> CoopFlowEvidence? {
        switch op {
        case .handle(let id, let action, _):
            let list = try await reader.read(.invitations)
            guard let sent = list["sent"].rows, let received = list["received"].rows else { throw CoopFlowFailure.malformed }
            let row = try unique(sent + received, key: "id", id: id)
            let from = sent.contains(row), to = received.contains(row)
            let allowed = CoopFlowContractState(invite: row).actions(isFrom: from, isTo: to).contains(action)
            return CoopFlowEvidence(baseline: .object(["invite": row, "slots": list["slots"]]), permitted: allowed)
        case .apply(let topic):
            let pool = try await reader.read(.pool)
            let row = try unique(pool["rows"].rows, key: "topicId", id: topic)
            return CoopFlowEvidence(baseline: .object(["pool": row, "hasClub": pool["hasClub"]]), permitted: pool["hasClub"].flag == true && ["open", "declined", "withdrawn"].contains(row["state"].text ?? ""))
        case .withdraw(let topic):
            let rows = try await reader.read(.applications)
            let row = try unique(rows.rows, key: "topicId", id: topic)
            return CoopFlowEvidence(baseline: row, permitted: row["status"].integer == 0)
        case .decline(let id, let scope):
            let rows = try await reader.read(.receivedApplications)
            let row = try unique(rows.rows, key: "applyId", id: id)
            return CoopFlowEvidence(baseline: row, permitted: row["status"].integer == 0 && row["scope"].text == scope)
        case .confirm(let id), .reject(let id):
            let value = try await reader.read(.registrations)
            let row = try unique(value["rows"].rows, key: "id", id: id)
            return CoopFlowEvidence(baseline: row, permitted: row["auditStatus"].integer == 0)
        case .createTemplate:
            let templates = try await reader.read(.templates)
            return CoopFlowEvidence(baseline: templates, permitted: true)
        case .attachPerks(let id, let ids):
            let list = try await reader.read(.invitations)
            let row = try unique((list["sent"].rows ?? []) + (list["received"].rows ?? []), key: "id", id: id)
            let templates = try await reader.read(.templates)
            var selected: [CoopFlowJSON] = []
            for id in ids {
                let template = try unique(templates.rows, key: "id", id: id)
                guard (CoopFlowMoney(template["retailValue"]).amount ?? 0) > 0, (template["quota"].integer ?? 0) > 0 else { return CoopFlowEvidence(baseline: template, permitted: false) }
                selected.append(template)
            }
            let existing = try await reader.read(.perks(inviteID: id))
            return CoopFlowEvidence(baseline: .object(["invite": row, "templates": .array(selected), "perks": existing]), permitted: row["status"].integer == 1 && row["inviteType"].integer != 2)
        case .contact(let id):
            let list = try await reader.read(.invitations)
            let row = try unique((list["sent"].rows ?? []) + (list["received"].rows ?? []), key: "id", id: id)
            return CoopFlowEvidence(baseline: row, permitted: row["status"].integer == 1 && row["inviteType"].integer != 2)
        case .review(let topic, let member, _, _):
            let list = try await reader.read(.invitations)
            let sent = (list["sent"].rows ?? []).filter { $0["topicId"].integer == topic && $0["toType"].text == "merchant" && $0["toId"].integer == member }
            let received = (list["received"].rows ?? []).filter { $0["topicId"].integer == topic && $0["fromId"].integer == member }
            let eligible = (sent + received).filter { $0["status"].integer == 1 && $0["inviteType"].integer != 2 }
            return CoopFlowEvidence(baseline: .array(eligible), permitted: !eligible.isEmpty)
        case .deleteTemplate(let id):
            let value = try await reader.read(.templates)
            return CoopFlowEvidence(baseline: try unique(value.rows, key: "id", id: id), permitted: true)
        case .complaint(let topic, _):
            let value = try await reader.read(.complaintTopics)
            // This source alone is the complaint selector; no participant/order age-window substitution.
            let row = try unique(value.rows, key: "topicId", id: topic)
            return CoopFlowEvidence(baseline: row, permitted: true)
        default: return nil
        }
    }
}
