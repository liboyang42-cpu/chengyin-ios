import SwiftUI

@MainActor struct SessionHomeFeedView:View {
    @EnvironmentObject private var session:AppSession
    @State private var path:[HomeFeedDestination]=[]
    @State private var showsTemplates=false
    var body:some View {
        NavigationStack(path:$path) {
            HomeFeedView(reader:session.homeFeedReader,
                sourceTimeZone:session.operationalMarket == .china ? TimeZone(identifier:"Asia/Shanghai") : nil) { path.append($0) }
                .toolbar {
                    ToolbarItem(placement:.topBarTrailing) {
                        Button("discovery.browseTemplates",systemImage:"square.stack.3d.up") { showsTemplates=true }
                            .accessibilityIdentifier("homeFeed.openTemplates")
                    }
                }
                .navigationDestination(for:HomeFeedDestination.self) { destination in
                    switch destination {
                    case .activity(let id): ActivityDetailView(id:id,reader:session,playReaderForActivity:{ session.playReader(for:.activity($0)) },registrationEnabled:true)
                    case .topic(let id): TopicDetailView(id:id,reader:session.topicReader)
                    }
                }
        }
        .id(session.homeFeedReader.scope)
        .onChange(of:session.homeFeedReader.scope) { _,_ in path=[];showsTemplates=false }
        .sheet(isPresented:$showsTemplates) {
            NavigationStack {
                DiscoveryTemplateBrowserView(reader:session)
                    .toolbar { ToolbarItem(placement:.cancellationAction) { Button("action.close") { showsTemplates=false } } }
            }
        }
    }
}
