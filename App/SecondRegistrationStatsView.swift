import SwiftUI

/// Read-only W10 report presentation. It has no reader: a reviewed report endpoint does
/// not exist yet, so only offline DEBUG fixtures supply a report.
struct SecondRegistrationStatsView: View {
    let report: SecondRegistrationReport?
    var offline = false
    var body: some View {
        List {
            if let report {
                Section("secondRegistration.windows") {
                    ForEach(SecondRegistrationWindow.allCases, id: \.rawValue) { window in
                        SecondRegistrationRateRow(window: window, display: .init(report.windows.first { $0.window == window }))
                    }
                    Text("secondRegistration.windowsNote").font(.footnote).foregroundStyle(.secondary)
                }
                if !report.transitions.isEmpty {
                    Section("secondRegistration.transitions") {
                        ForEach(Array(report.transitions.enumerated()), id: \.offset) { index, row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedStringKey(Self.transitionKey(row))).font(.headline)
                                SecondRegistrationRateRow(window: row.cell.window, display: .init(row.cell))
                            }.accessibilityElement(children: .combine)
                                .accessibilityIdentifier("secondRegistration.transition.\(index)")
                        }
                    }
                }
                Section("secondRegistration.refundSensitivity") {
                    if let cell = report.refundSensitivity {
                        SecondRegistrationRateRow(window: cell.window, display: .init(cell))
                    } else { Text("secondRegistration.notReported") }
                }
                Section("secondRegistration.exclusions") {
                    SecondRegistrationCountRow(label: "secondRegistration.exclusion.test", value: report.exclusions?.test)
                    SecondRegistrationCountRow(label: "secondRegistration.exclusion.fraud", value: report.exclusions?.fraud)
                    SecondRegistrationCountRow(label: "secondRegistration.exclusion.cancelled", value: report.exclusions?.cancelled)
                    SecondRegistrationCountRow(label: "secondRegistration.exclusion.fullRefund", value: report.exclusions?.fullRefund)
                    SecondRegistrationCountRow(label: "secondRegistration.supplyGap", value: report.supplyGapMembers)
                }
                Section {
                    LabeledContent("secondRegistration.asOf") { Text(verbatim: report.asOf) }
                    LabeledContent("secondRegistration.metricVersion") { Text(verbatim: report.metricVersion) }
                    if report.isTest { Label("secondRegistration.testData", systemImage: "testtube.2") }
                    Text("secondRegistration.exposureNote").font(.footnote).foregroundStyle(.secondary)
                    if offline { Label("secondRegistration.offlineExample", systemImage: "testtube.2").font(.footnote) }
                }.accessibilityIdentifier("secondRegistration.footer")
            } else {
                Text("secondRegistration.unavailable").accessibilityIdentifier("secondRegistration.unavailable")
            }
        }
        .accessibilityIdentifier("secondRegistration.content")
        .appNavigationTitle("secondRegistration.title")
    }
    static func transitionKey(_ row: SecondRegistrationTransition) -> String {
        "secondRegistration.transition.\(row.from.rawValue.lowercased()).\(row.to.rawValue.lowercased())"
    }
}
struct SecondRegistrationRateRow: View {
    let window: SecondRegistrationWindow
    let display: SecondRegistrationRateDisplay
    var body: some View {
        LabeledContent {
            switch display {
            case .rate(let numerator, let denominator, let percent):
                Text("secondRegistration.rate \(percent) \(numerator) \(denominator)")
            case .noMatureSample: Text("secondRegistration.noMatureSample")
            case .observedOnly(let count): Text("secondRegistration.observedOnly \(count)")
            case .unavailable: Text("secondRegistration.notReported")
            }
        } label: { Text("secondRegistration.window \(window.rawValue)") }
            .accessibilityIdentifier("secondRegistration.window.\(window.rawValue)")
    }
}
private struct SecondRegistrationCountRow: View {
    let label: LocalizedStringKey
    let value: Int?
    var body: some View {
        LabeledContent(label) {
            if let value, value >= 0 { Text(verbatim: String(value)) } else { Text("secondRegistration.notReported") }
        }
    }
}

#if DEBUG
/// Synthetic, marked-test report. Numbers are fixture data, not product facts.
enum SecondRegistrationFixtures {
    static let mature = #"""
    {"metricVersion":"w10-proposal-1","asOf":"2026-10-01T00:00:00+08:00","isTest":true,
     "windows":[{"days":7,"mature":true,"denominator":40,"numerator":3},
                {"days":28,"mature":true,"denominator":0,"numerator":0},
                {"days":56,"mature":false,"observedCumulative":5}],
     "transitions":[{"from":"FREE","to":"PAID","days":28,"mature":true,"denominator":12,"numerator":1}],
     "exclusions":{"test":2,"fraud":0,"cancelled":1},
     "refundSensitivity":{"days":28,"mature":true,"denominator":14,"numerator":2},
     "supplyGapMembers":4}
    """#
    static func report(_ scenario: String) -> SecondRegistrationReport? {
        guard scenario != "unavailable" else { return nil }
        return try? JSONDecoder().decode(SecondRegistrationReport.self, from: Data(mature.utf8))
    }
}
struct SecondRegistrationFixtureHost: View {
    let scenario: String
    var body: some View {
        NavigationStack { SecondRegistrationStatsView(report: SecondRegistrationFixtures.report(scenario), offline: true) }
    }
}
#endif
