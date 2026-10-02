import SwiftUI

@MainActor struct RoamHistoryView: View {
    let reader: any RoamExperienceReading
    @State private var records: [RoamHistoryRecord] = []
    @State private var error: Error?
    @State private var loaded = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                if let error { RoamExperienceIssue(error: error, retry: load) }
                else if !loaded { ProgressView("roam.loading") }
                else if records.isEmpty {
                    ContentUnavailableView("roam.experience.historyEmpty", systemImage: "figure.walk", description: Text("roam.experience.historyEmptyHint"))
                        .accessibilityIdentifier("roam.experience.history.empty")
                } else {
                    let summary = RoamHistorySummary(records)
                    RoamExperienceCard {
                        LabeledContent("roam.experience.trips", value: String(summary.trips)).font(.headline)
                        if let distance = summary.knownKilometers, summary.tripsWithDistance > 0 {
                            LabeledContent("roam.experience.knownDistance") { Text(distance, format: .number.precision(.fractionLength(1))) + Text(verbatim: " km") }
                        }
                        Text("roam.experience.partialStats").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(records) { record in
                        NavigationLink { RoamHistoryDetailView(reader: reader, timestamp: record.ts) } label: {
                            RoamExperienceCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    if let zone = record.meaningfulZone { Text(verbatim: zone).font(.title3).bold() }
                                    else { Text("roam.experience.cityWalk").font(.title3).bold() }
                                    if let date = record.recordedAt { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
                                    RoamRouteSketchView(record: record)
                                    RoamRecordedStats(record: record)
                                }
                            }
                        }.buttonStyle(QuestifyCardButtonStyle())
                            .accessibilityIdentifier("roam.experience.history.record")
                    }
                }
            }.padding()
        }.navigationTitle("roam.experience.history")
            .task(id: reader.identity) { load() }
            .accessibilityIdentifier("roam.experience.history")
    }
    private func load() {
        records = []; error = nil; loaded = false
        do { records = try reader.history(); loaded = true } catch { self.error = error }
    }
}
@MainActor struct RoamHistoryDetailView: View {
    let reader: any RoamExperienceReading
    let timestamp: Int64
    @State private var record: RoamHistoryRecord?
    @State private var loaded = false
    @State private var error: Error?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                if let error { RoamExperienceIssue(error: error, retry: load) }
                else if let record {
                    RoamExperienceCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Label("roam.experience.savedRecord", systemImage: "book.closed").font(.caption).foregroundStyle(.secondary)
                            if let zone = record.meaningfulZone { Text(verbatim: zone).font(.title2).bold() }
                            else { Text("roam.experience.cityWalk").font(.title2).bold() }
                            if let date = record.recordedAt { Text(date, style: .date) }
                            RoamRouteSketchView(record: record)
                            RoamRecordedStats(record: record)
                        }
                    }
                    if !record.pois.isEmpty {
                        Text("roam.experience.recordedPlaces").font(.headline)
                        ForEach(Array(record.pois.enumerated()), id: \.offset) { _, place in
                            Label { RoamTitle(place.name) } icon: { Image(systemName: place.cat == "merchant" ? "storefront" : "mappin") }
                        }
                    }
                    if let medal = record.medal { Label { Text(verbatim: medal) } icon: { Image(systemName: "medal") } }
                    if let medal = record.shopMedalName { Label { Text(verbatim: medal) } icon: { Image(systemName: "medal") } }
                    if !record.photos.isEmpty { LabeledContent("roam.experience.savedPhotoReferences", value: String(record.photos.count)) }
                    Text("roam.experience.historyPrivacy").font(.caption).foregroundStyle(.secondary)
                } else if loaded {
                    ContentUnavailableView("roam.experience.recordMissing", systemImage: "questionmark.folder", description: Text("roam.experience.recordMissingHint"))
                        .accessibilityIdentifier("roam.experience.history.missing")
                } else { ProgressView("roam.loading") }
            }.padding()
        }.navigationTitle("roam.experience.session")
            .task(id: reader.identity) { load() }
            .accessibilityIdentifier("roam.experience.session")
    }
    private func load() {
        record = nil; error = nil; loaded = false
        do { record = try reader.history().first { $0.ts == timestamp }; loaded = true } catch { self.error = error }
    }
}
