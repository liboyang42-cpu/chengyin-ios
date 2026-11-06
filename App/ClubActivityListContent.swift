import SwiftUI

@MainActor struct ClubActivityListContent: View {
    let rows: [ClubActivityRow]
    let canOpen: Bool
    let open: (ClubActivityRow) -> Void
    var report: ((ClubActivityRow) -> AnyView)? = nil
    init(overview: ClubActivityOverview, canOpen: Bool, open: @escaping (ClubActivityRow) -> Void,
         report: ((ClubActivityRow) -> AnyView)? = nil) {
        self.init(rows: overview.rows, canOpen: canOpen, open: open, report: report)
    }
    /// Display rows do not imply a governance snapshot or any mutation authority.
    init(rows: [ClubActivityRow], canOpen: Bool, open: @escaping (ClubActivityRow) -> Void,
         report: ((ClubActivityRow) -> AnyView)? = nil) {
        self.rows = rows; self.canOpen = canOpen; self.open = open; self.report = report
    }
    private var currentRows: [ClubActivityRow] { rows.filter { $0.status != .ended } }
    private var endedRows: [ClubActivityRow] { rows.filter { $0.status == .ended } }
    var body: some View {
        Section("club.activityList.current") {
            Text("club.activityList.timeZone").font(.caption).foregroundStyle(.secondary)
            if rows.isEmpty { Text("club.calendar.noEvents").accessibilityIdentifier("club.calendar.empty") }
            else if currentRows.isEmpty { Text("club.activityList.noCurrent").accessibilityIdentifier("club.activityList.current.empty") }
            ForEach(currentRows) { row in item(row) }
        }
        if !endedRows.isEmpty {
            Section("club.activityList.ended") { ForEach(endedRows) { row in item(row) } }
        }
    }
    @ViewBuilder private func item(_ row: ClubActivityRow) -> some View {
        if canOpen {
            Button { open(row) } label: { ClubActivityCard(row: row) }
                .buttonStyle(.plain).accessibilityHint("roamEvent.openTopic")
                .accessibilityIdentifier("club.calendar.topic.\(row.id)")
        } else { ClubActivityCard(row: row) }
        if let report { report(row) }
    }
}

private struct ClubActivityCard: View {
    let row: ClubActivityRow
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cover = row.cover {
                SquareImage(source: cover).frame(maxWidth: .infinity).frame(height: 140).clipped().accessibilityHidden(true)
            }
            HStack(alignment: .top) {
                if let name = row.name { Text(verbatim: name).font(.headline) }
                else { Text("club.calendar.untitled").font(.headline) }
                Spacer(minLength: 8)
                Text(LocalizedStringKey("club.activityList.status." + row.status.rawValue)).font(.caption.bold())
                    .foregroundStyle(row.status == .live ? Color.green : row.status == .ended ? Color.secondary : Color.primary)
                    .accessibilityIdentifier("club.activityList.status.\(row.id)")
            }
            if let value = timeText { Text(verbatim: value).font(.subheadline) }
            else { Text("club.calendar.dateUnknown").font(.subheadline) }
            if let address = row.address { Label { Text(verbatim: address) } icon: { Image(systemName: "mappin") }.font(.caption) }
            Text(LocalizedStringKey("club.activityList.category." + row.category.rawValue)).font(.caption).foregroundStyle(.secondary)
            if row.signups != nil || row.stations != nil || row.mileageKM != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) { stats }
                    VStack(alignment: .leading, spacing: 8) { stats }
                }
            }
        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var stats: some View {
        if let count = row.signups { stat(count, title: "club.activityList.signups") }
        if let count = row.stations { stat(count, title: "club.activityList.stations") }
        if let distance = row.mileageKM { stat(distance, title: "club.activityList.kilometers") }
    }
    private func stat(_ value: Double, title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private var timeText: String? {
        guard let date = row.start else { return row.sourceStart.map { String($0.prefix(16)).replacingOccurrences(of: "T", with: " ") } }
        let formatter = DateFormatter(); formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.setLocalizedDateFormatFromTemplate(row.dateOnly ? "EEE MMMd" : "EEE MMMd HHmm")
        return formatter.string(from: date)
    }
}
