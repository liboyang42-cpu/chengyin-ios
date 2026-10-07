import SwiftUI

/// A read-only sheet of the current run. Its input is reprojected by the summary;
/// this view retains no snapshot, services, actions, answer state or destinations.
struct PlayBranchHistoryView: View {
    let history: PlayBranchHistoryPresentation?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(branchHistoryLocalized("branchHistory.detail", locale: locale))
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    if let history {
                        switch history.state {
                        case .unavailable: message("branchHistory.unavailable", id: "branchHistory.unavailable")
                        case .empty: message("branchHistory.empty", id: "branchHistory.empty")
                        case .recorded: EmptyView()
                        }
                        if history.containsInvalidEntries {
                            message("branchHistory.partial", id: "branchHistory.partial")
                        }
                    } else { message("branchHistory.expired", id: "branchHistory.expired") }
                }
                if let history {
                    ForEach(history.rows) { row in
                        Section {
                            PlayBranchHistoryRowView(row: row)
                        }
                    }
                }
            }
            .navigationTitle(branchHistoryLocalized("branchHistory.title", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(branchHistoryLocalized("branchHistory.close", locale: locale)) { dismiss() }
                        .accessibilityIdentifier("branchHistory.close")
                }
            }
        }.privacySensitive()
    }
    private func message(_ key: String, id: String) -> some View {
        Text(branchHistoryLocalized(key, locale: locale)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(id)
    }
}

struct PlayBranchHistoryRowView: View {
    let row: PlayBranchHistoryPresentation.Row
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: String(format: branchHistoryLocalized("branchHistory.step", locale: locale), locale: locale, row.id + 1))
                .font(.headline).accessibilityAddTraits(.isHeader)
            endpoint("branchHistory.from", name: row.fromName)
            endpoint("branchHistory.to", name: row.toName)
            Text(verbatim: row.time ?? branchHistoryLocalized("branchHistory.timeUnknown", locale: locale))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("branchHistory.row.\(row.id)")
    }
    private func endpoint(_ key: String, name: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(branchHistoryLocalized(key, locale: locale)).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: name ?? branchHistoryLocalized("branchHistory.nodeUnknown", locale: locale))
        }
    }
}

func branchHistoryLocalized(_ key: String, locale: Locale) -> String {
    String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "PlayBranchHistory", locale: locale))
}
