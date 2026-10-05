import SwiftUI

@MainActor struct CooperationPoolView: View {
    let reader: any CooperationReading
    var body: some View {
        CooperationReadScreen(reader: reader, resource: "pool", operation: { try await reader.pool() }) { pool in
            if !pool.hasClub {
                Section {
                    Label("cooperation.pool.clubRequired", systemImage: "person.3")
                        .accessibilityIdentifier("cooperation.pool.clubRequired")
                    Text("cooperation.pool.clubHint").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    if pool.rows.isEmpty { Text("cooperation.pool.empty").foregroundStyle(.secondary) }
                    ForEach(Array(pool.rows.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 8) {
                            CooperationName(name: row.name, fallback: "cooperation.unnamedTopic").font(.headline)
                            CooperationStatus(key: row.stateKey)
                            CooperationField(key: "cooperation.about", value: row.subtitle)
                            CooperationTopicReference(id: row.topicId)
                            CooperationField(key: "cooperation.publisher", value: row.merchantNick)
                            CooperationTimeField(key: "cooperation.start", value: row.startDate)
                            CooperationTimeField(key: "cooperation.end", value: row.endDate)
                            CooperationTimeField(key: "cooperation.expires", value: row.recruitDeadline)
                        }.padding(.vertical, 4)
                    }
                }
                Section { CooperationReadOnlyNotice() }
            }
        }.appNavigationTitle("cooperation.pool.title").navigationBarTitleDisplayMode(.inline)
    }
}
@MainActor struct CooperationCandidatesView: View {
    let topicID: Int
    let reader: any CooperationReading
    var body: some View {
        CooperationReadScreen(reader: reader, resource: "candidates.\(topicID)", operation: {
            guard topicID > 0 else { throw CooperationReadFailure.unavailable }
            return try await reader.candidates(topicID: topicID)
        }) { directory in
            Section {
                CooperationTopicReference(id: topicID)
                Label("cooperation.candidates.ownerOnly", systemImage: "lock").font(.footnote).foregroundStyle(.secondary)
            }
            Section("cooperation.candidates.clubs") {
                if directory.clubApplies.isEmpty { Text("cooperation.applications.empty").foregroundStyle(.secondary) }
                ForEach(Array(directory.clubApplies.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 8) {
                        CooperationName(name: row.clubName, fallback: "cooperation.unnamedClub").font(.headline)
                        CooperationStatus(key: row.statusKey)
                        CooperationField(key: "cooperation.message", value: row.message)
                        CooperationField(key: "cooperation.inviteState", value: row.inviteStatus)
                        CooperationTimeField(key: "cooperation.created", value: row.createTime)
                    }.padding(.vertical, 4)
                }
            }
            Section("cooperation.candidates.merchants") {
                if directory.registrations.isEmpty { Text("cooperation.registrations.empty").foregroundStyle(.secondary) }
                ForEach(Array(directory.registrations.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 8) {
                        CooperationName(name: row.name, fallback: "cooperation.unnamedMerchant").font(.headline)
                        // CandidateRegistration.status has no audited presentation mapping; do not borrow auditStatus semantics.
                        if let status = row.status { CooperationField(key: "cooperation.sourceStatus", value: String(status)) }
                    }.padding(.vertical, 4)
                }
            }
            Section { CooperationReadOnlyNotice() }
        }.appNavigationTitle("cooperation.candidates.title").navigationBarTitleDisplayMode(.inline)
    }
}
