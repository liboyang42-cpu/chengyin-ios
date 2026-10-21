import SwiftUI

/// Read-only CITY fairness. The host supplies the reader; this screen does not grant a write.
struct CityFairnessView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State var reader: CityFairnessReader
    @State private var visible = false
    @State private var readRequest = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                screenBody
                if let failure = reader.refreshFailure { failureText(failure) }
                if reader.isConfigured {
                    Button { readRequest = UUID() } label: { Text("fairness.refresh", tableName: "CityFairness") }
                        .disabled(!visible || scenePhase != .active)
                    if case .mature(let page) = reader.screen, page.nextCursor != nil {
                        Button { Task { await reader.nextPage() } } label: { Text("fairness.next", tableName: "CityFairness") }
                            .disabled(reader.refreshing || !visible || scenePhase != .active)
                    }
                }
            }.padding()
        }
        .navigationTitle(Text("fairness.title", tableName: "CityFairness"))
        .accessibilityIdentifier("fairness.screen")
        .navigationDestination(for: CityFairnessOutingRoute.self) { route in
            CityFairnessEvidenceView(reader: reader, outingID: route.outingID)
        }
        .task(id: readRequest) {
            guard visible, scenePhase == .active, !Task.isCancelled else { return }
            await reader.restoreSameQuery()
        }
        .onAppear { visible = true; readRequest = UUID() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { readRequest = UUID() }
        }
        .onDisappear { visible = false }
    }

    @ViewBuilder private var screenBody: some View {
        switch reader.screen {
        case .blocked:
            Text("fairness.blocked", tableName: "CityFairness")
        case .loading:
            ProgressView { Text("fairness.loading", tableName: "CityFairness") }
        case .notComputable(let missing):
            Text("fairness.notComputable", tableName: "CityFairness")
            if !missing.isEmpty { reasonLine(missing.joined(separator: "\n")) }
        case .noMatureSample(let gap):
            Text("fairness.noMatureSample", tableName: "CityFairness")
            stamp(gap.asOf, metricVersion: gap.metricVersion, formulaId: gap.formulaId, factRevision: gap.factRevision)
        case .unknown(let reason):
            Text("fairness.unknown", tableName: "CityFairness")
            if let reason { reasonLine(reason) }
        case .failed(let failure):
            failureText(failure)
        case .mature(let page):
            Text("fairness.ratio", tableName: "CityFairness")
            Text(verbatim: page.ratioText)
            stamp(page.asOf, metricVersion: page.metricVersion, formulaId: page.formulaId, factRevision: page.factRevision)
            Text("fairness.readOnly", tableName: "CityFairness")
            if page.members.isEmpty { Text("fairness.emptyEvidence", tableName: "CityFairness") }
            ForEach(page.members) { member in
                NavigationLink(value: CityFairnessOutingRoute(outingID: member.outingId)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("fairness.evidence", tableName: "CityFairness")
                        Text(verbatim: member.outingId)
                        if let t0 = member.t0 { Text(verbatim: String(t0)) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityIdentifier("fairness.outing.\(member.outingId)")
            }
        }
    }

    private func reasonLine(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("fairness.missingReason", tableName: "CityFairness")
            Text(verbatim: reason)
        }
    }

    private func stamp(_ asOf: Int64, metricVersion: String?, formulaId: String, factRevision: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("fairness.asOf", tableName: "CityFairness")
            Text(verbatim: String(asOf))
            if let metricVersion {
                Text("fairness.metricVersion", tableName: "CityFairness")
                Text(verbatim: metricVersion)
            }
            Text("fairness.formulaId", tableName: "CityFairness")
            Text(verbatim: formulaId)
            if let factRevision {
                Text("fairness.factRevision", tableName: "CityFairness")
                Text(verbatim: String(factRevision))
            }
        }
    }

    private func failureText(_ failure: CityFairnessFailure) -> some View {
        switch failure {
        case .unauthorized: Text("fairness.unauthorized", tableName: "CityFairness")
        case .forbidden: Text("fairness.forbidden", tableName: "CityFairness")
        case .notComputable: Text("fairness.notComputable", tableName: "CityFairness")
        case .unavailable: Text("fairness.unavailable", tableName: "CityFairness")
        case .malformed: Text("fairness.malformed", tableName: "CityFairness")
        case .unknown: Text("fairness.unknown", tableName: "CityFairness")
        }
    }
}

struct CityFairnessOutingRoute: Hashable { let outingID: String }

struct CityFairnessEvidenceView: View {
    var reader: CityFairnessReader
    let outingID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let evidence = reader.evidence {
                Text(verbatim: evidence.outingId)
                Text("fairness.maturity", tableName: "CityFairness")
                Text(verbatim: evidence.maturity)
                Text("fairness.reason", tableName: "CityFairness")
                Text(verbatim: evidence.reason)
                if let t0 = evidence.t0 {
                    Text("fairness.t0", tableName: "CityFairness")
                    Text(verbatim: String(t0))
                }
                Text("fairness.readOnly", tableName: "CityFairness")
            } else if let failure = reader.evidenceFailure {
                switch failure {
                case .unauthorized: Text("fairness.unauthorized", tableName: "CityFairness")
                case .forbidden: Text("fairness.forbidden", tableName: "CityFairness")
                case .notComputable: Text("fairness.notComputable", tableName: "CityFairness")
                case .unavailable: Text("fairness.unavailable", tableName: "CityFairness")
                case .malformed: Text("fairness.malformed", tableName: "CityFairness")
                case .unknown: Text("fairness.unknown", tableName: "CityFairness")
                }
            } else {
                ProgressView { Text("fairness.loading", tableName: "CityFairness") }
            }
            Button { dismiss() } label: { Text("fairness.back", tableName: "CityFairness") }
                .accessibilityIdentifier("fairness.back")
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle(Text("fairness.evidence", tableName: "CityFairness"))
        .accessibilityIdentifier("fairness.evidence.screen")
        .task { await reader.loadEvidence(outingID) }
        .onDisappear { reader.clearEvidence() }
    }
}
