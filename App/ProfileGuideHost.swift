import SwiftUI

/// One stable guide owner; pushing an article preserves its accepted-list receipt.
@MainActor struct ProfileGuideHost: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var reader: ProfileGuideListReader?
    let makeArticleReader: (ProfileGuideArticleSelection) -> ProfileGuideArticleReader
    var onOpenDestination: ((SocialGuideDestination) -> Void)? = nil
    var templateReader: (any DiscoveryReading)? = nil
    init(reader: ProfileGuideListReader?, makeArticleReader: @escaping (ProfileGuideArticleSelection) -> ProfileGuideArticleReader,
         onOpenDestination: ((SocialGuideDestination) -> Void)? = nil, templateReader: (any DiscoveryReading)? = nil) {
        _reader = State(initialValue: reader); self.makeArticleReader = makeArticleReader
        self.onOpenDestination = onOpenDestination; self.templateReader = templateReader
    }
    var body: some View {
        ZStack {
            if let reader {
                if reader.hasAppeared {
                    SocialPlayGuideView(reader: reader, onOpenDestination: onOpenDestination, templateReader: templateReader,
                        informationDestination: { row in AnyView(ProfileGuideArticleDestination(row: row, reader: reader, makeReader: makeArticleReader)) })
                } else { ProgressView() }
            } else { SocialIssueView(error: APIError.unauthorized) }
        }
        .onAppear { reader?.appear(foreground: scenePhase == .active) }
        .onDisappear { reader?.disappear() }
        .onChange(of: scenePhase) { _, phase in reader?.setForeground(phase == .active) }
        .refreshable { reader?.refresh() }
    }
}

@MainActor struct ProfileGuideArticleDestination: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var reader: ProfileGuideArticleReader?
    init(row: SocialInformation, reader: ProfileGuideListReader, makeReader: (ProfileGuideArticleSelection) -> ProfileGuideArticleReader) {
        _reader = State(initialValue: reader.select(row).map(makeReader))
    }
    var body: some View {
        ZStack {
            if let reader {
                if reader.hasAppeared { SocialInformationView(id: reader.selection.row.id, reader: reader) }
                else { ProgressView() }
            } else { SocialIssueView(error: SocialActionBlock.changed) }
        }
        .onAppear { reader?.appear(foreground: scenePhase == .active) }
        .onDisappear { reader?.disappear() }
        .onChange(of: scenePhase) { _, phase in reader?.setForeground(phase == .active) }
    }
}
