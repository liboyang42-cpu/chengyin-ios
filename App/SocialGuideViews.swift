import SwiftUI

@MainActor struct SocialPlayGuideView: View {
    let reader: any SocialAccountReading
    var onOpenDestination: ((SocialGuideDestination) -> Void)? = nil
    var body: some View {
        List {
            Section("social.guide.modes") {
                ForEach(SocialGuideMode.allCases) { mode in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(mode.titleKey, systemImage: mode.icon).font(.headline)
                        Text(mode.detailKey).foregroundStyle(.secondary)
                        if let onOpenDestination { Button("social.guide.explore") { onOpenDestination(mode.destination) }.accessibilityIdentifier("social.guide.\(mode.rawValue)") }
                    }.padding(.vertical, 5)
                }
            }
            Section("social.guide.information") {
                SocialReadScreen(reader: reader, requestKey: "information-list", load: { try await reader.informationList() }) { rows in
                    if rows.isEmpty { Text("social.guide.empty") }
                    ForEach(rows) { row in
                        NavigationLink { SocialInformationView(id: row.id, reader: reader) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: row.title)
                                if let summary = row.summary { Text(verbatim: summary).font(.footnote).foregroundStyle(.secondary) }
                            }
                        }.accessibilityIdentifier("social.information.\(row.id)")
                    }
                }
            }
        }.appNavigationTitle("social.guide.title").accessibilityIdentifier("social.guide")
    }
}
@MainActor struct SocialInformationView: View {
    let id: Int
    let reader: any SocialAccountReading
    var body: some View {
        List {
            if id <= 0 { Text("social.incompleteLink") }
            else {
                SocialReadScreen(reader: reader, requestKey: "information-\(id)", load: { try await reader.information(id: id) }) { row in
                    if row.isRemoved { Text("social.guide.removed") }
                    else {
                        Text(verbatim: row.title).font(.title2.bold())
                        if let summary = row.summary { Text(verbatim: summary).foregroundStyle(.secondary) }
                        if let contents = row.contents { Text(verbatim: contents).textSelection(.enabled) }
                        else { Text("social.guide.noContent") }
                    }
                }
            }
        }.appNavigationTitle("social.guide.information").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("social.information.detail")
    }
}
