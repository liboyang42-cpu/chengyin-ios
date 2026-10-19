import SwiftUI

@MainActor struct SocialPlayGuideView: View {
    let reader: any SocialAccountReading
    var onOpenDestination: ((SocialGuideDestination) -> Void)? = nil
    var templateReader: (any DiscoveryReading)? = nil
    var informationDestination: ((SocialInformation) -> AnyView)? = nil
    var body: some View {
        List {
            Section { SocialGuideXcxHero() }
            Section("social.guide.modes") {
                ForEach(SocialGuideMode.allCases) { mode in SocialGuideXcxModeRow(mode: mode, onOpen: onOpenDestination) }
            }
            SocialGuideTemplateSection(reader: templateReader)
            Section {
                SocialReadScreen(reader: reader, requestKey: "information-list", load: { try await reader.informationList() }) { rows in
                    if rows.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("social.guideXcx.docsEmpty").font(.headline)
                            Text("social.guideXcx.docsEmptyDetail").font(.footnote).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("social.guide.docsEmpty")
                    }
                    ForEach(rows) { row in
                        NavigationLink {
                            if let informationDestination { informationDestination(row) }
                            else { AnyView(SocialInformationView(id: row.id, reader: reader)) }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(verbatim: row.title)
                                if let summary = row.summary { Text(verbatim: summary).font(.footnote).foregroundStyle(.secondary) }
                            }
                        }.accessibilityIdentifier("social.information.\(row.id)")
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("social.guideXcx.docs")
                    Text("social.guideXcx.docsHint").font(.caption).textCase(nil)
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
                        if let created = SocialText.nonempty(row.createTime) { Text(verbatim: created).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("social.information.createTime") }
                        if let summary = row.summary { Text(verbatim: summary).foregroundStyle(.secondary) }
                        if let contents = row.contents { SocialArticleContentView(contents: contents) }
                        else { Text("social.guide.noContent") }
                    }
                }
            }
        }.appNavigationTitle("social.guideXcx.detailTitle").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("social.information.detail")
    }
}
