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
                    NavigationLink(value: CityFairnessOutingRoute()) {
                        Text("fairness.evidence", tableName: "CityFairness")
                    }
                    .accessibilityIdentifier("fairness.outing.own")
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
        .navigationDestination(for: CityFairnessOutingRoute.self) { _ in
            CityFairnessEvidenceView(reader: reader)
        }
        .task(id: readRequest) {
            guard visible, scenePhase == .active, !Task.isCancelled else { return }
            await reader.restoreSameQuery()
        }
        .onAppear { visible = true; reader.setForeground(scenePhase == .active); readRequest = UUID() }
        .onChange(of: scenePhase) { _, phase in
            reader.setForeground(phase == .active)
            if phase == .active { readRequest = UUID() }
        }
        .onDisappear { visible = false; reader.setForeground(false) }
    }

    @ViewBuilder private var screenBody: some View {
        switch reader.screen {
        case .blocked:
            Text("fairness.blocked", tableName: "CityFairness")
        case .loading:
            ProgressView { Text("fairness.loading", tableName: "CityFairness") }
        case .notComputable(let missing, let gaps):
            Text("fairness.notComputable", tableName: "CityFairness")
            if !missing.isEmpty { reasonLine(missing.joined(separator: "\n")) }
            cityFairnessFacts(gaps, [])
        case .noMatureSample(let gap):
            Text("fairness.noMatureSample", tableName: "CityFairness")
            stamp(gap.asOf, metricVersion: gap.metricVersion, formulaId: gap.formulaId, factRevision: gap.factRevision)
            if !gap.missing.isEmpty { reasonLine(gap.missing.joined(separator: "\n")) }
            cityFairnessFacts(gap.coverageGaps, gap.facts)
        case .unknown(let reason, let gaps):
            Text("fairness.unknown", tableName: "CityFairness")
            if let reason { reasonLine(reason) }
            cityFairnessFacts(gaps, [])
        case .failed(let failure):
            failureText(failure)
        case .mature(let page):
            if page.showsRatio {
                Text("fairness.ratio", tableName: "CityFairness")
                Text(verbatim: page.ratioText)
            } else {
                Text("fairness.unknown", tableName: "CityFairness")
            }
            stamp(page.asOf, metricVersion: page.metricVersion, formulaId: page.formulaId, factRevision: page.factRevision)
            if !page.missing.isEmpty { reasonLine(page.missing.joined(separator: "\n")) }
            cityFairnessFacts(page.coverageGaps, page.facts)
            Text("fairness.readOnly", tableName: "CityFairness")
            if page.members.isEmpty { Text("fairness.emptyEvidence", tableName: "CityFairness") }
            ForEach(page.members) { member in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: member.outingId)
                    if let t0 = member.t0 { Text(verbatim: String(t0)) }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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

struct CityFairnessOutingRoute: Hashable {}

struct CityFairnessEvidenceView: View {
    var reader: CityFairnessReader
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let page = reader.outingPage {
                    Text("fairness.readOnly", tableName: "CityFairness")
                    if page.maturity == "UNKNOWN" { Text("fairness.unknown", tableName: "CityFairness") }
                    if !page.missing.isEmpty { reasonLine(page.missing.joined(separator: "\n")) }
                    cityFairnessFacts(page.coverageGaps, page.facts)
                    if page.outings.isEmpty { Text("fairness.emptyEvidence", tableName: "CityFairness") }
                    ForEach(page.outings) { outing in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: outing.outingId)
                            Text("fairness.maturity", tableName: "CityFairness")
                            Text(verbatim: outing.maturity)
                            Text("fairness.reason", tableName: "CityFairness")
                            reasonText(outing.reason)
                            if let t0 = outing.t0 {
                                Text("fairness.t0", tableName: "CityFairness")
                                Text(verbatim: String(t0))
                            }
                        }
                        .accessibilityIdentifier("fairness.outing.\(outing.outingId)")
                    }
                    if let failure = reader.outingFailure { failureText(failure) }
                    if page.nextCursor != nil {
                        Button { Task { await reader.nextOutings() } } label: { Text("fairness.next", tableName: "CityFairness") }
                            .disabled(reader.outingRefreshing)
                    }
                    Button { Task { await reader.loadOutings() } } label: { Text("fairness.refresh", tableName: "CityFairness") }
                        .disabled(reader.outingRefreshing)
                } else if reader.outingBlocked {
                    Text("fairness.blocked", tableName: "CityFairness")
                } else if let failure = reader.outingFailure {
                    failureText(failure)
                } else {
                    ProgressView { Text("fairness.loading", tableName: "CityFairness") }
                }
                Button { dismiss() } label: { Text("fairness.back", tableName: "CityFairness") }
                    .accessibilityIdentifier("fairness.back")
            }.padding()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle(Text("fairness.evidence", tableName: "CityFairness"))
        .accessibilityIdentifier("fairness.evidence.screen")
        .task { await reader.loadOutings() }
    }

    @ViewBuilder private func reasonText(_ reason: CityFairnessOutingReason) -> some View {
        switch reason {
        case .firstOuting: Text(verbatim: "first-outing")
        case .secondOuting: Text(verbatim: "second-outing")
        case .insideDelta: Text(verbatim: "inside-delta")
        case .afterHorizon: Text(verbatim: "after-horizon")
        case .beforeT0: Text(verbatim: "before-t0")
        case .notEffective: Text(verbatim: "not-effective")
        case .unknown: Text("fairness.unknown", tableName: "CityFairness")
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

    private func reasonLine(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("fairness.missingReason", tableName: "CityFairness")
            Text(verbatim: reason)
        }
    }
}

@ViewBuilder func cityFairnessFacts(_ gaps: [String], _ facts: [CityFairnessFact]) -> some View {
    Text("fairness.coverage", tableName: "CityFairness")
    ForEach(Array(gaps.enumerated()), id: \.offset) { _, gap in
        Text(verbatim: gap)
        Text("fairness.unknown", tableName: "CityFairness")
    }
    ForEach(facts) { fact in
        Text(verbatim: fact.name)
        if fact.missing { Text("fairness.unknown", tableName: "CityFairness") }
        else if let count = fact.count { Text(verbatim: String(count)) }
        else if let text = fact.text { Text(verbatim: text) }
    }
}
