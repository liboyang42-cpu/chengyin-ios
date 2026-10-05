import SwiftUI

@MainActor struct SessionHomeFeedView:View {
    @EnvironmentObject private var session:AppSession
    var onSignIn:(()->Void)? = nil
    @State private var path:[HomeFeedDestination]=[]
    @State private var showsGlobalSearch=false
    @State private var showsTemplates=false
    @State private var showsSquare=false
    @State private var showsOfficialEvents=false
    @State private var showsProjectEditor=false
    var body:some View {
        NavigationStack(path:$path) {
            // Unzoned content needs a separately verified event/backend timezone.
            // Market and interface language alone do not establish one.
            HomeFeedView(reader:session.homeFeedReader, unavailableMessageKey: session.homeReadAvailability.messageKey) { path.append($0) }
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        Button("square.title",systemImage:"square.grid.2x2") { showsSquare=true }
                            .accessibilityIdentifier("homeFeed.openSquare")
                    }
                    ToolbarItemGroup(placement:.topBarTrailing) {
                        Button("searchMap.title",systemImage:"magnifyingglass") { showsGlobalSearch=true }
                            .labelStyle(.iconOnly).frame(minWidth:44,minHeight:44)
                            .accessibilityIdentifier("homeFeed.openGlobalSearch")
                        Button("projectEdit.title", systemImage:"square.and.pencil") { showsProjectEditor=true }
                            .labelStyle(.iconOnly).frame(minWidth:44,minHeight:44)
                            .accessibilityIdentifier("homeFeed.openProjectEditor")
                        Button("official.title",systemImage:"sparkles") { showsOfficialEvents=true }
                            .labelStyle(.iconOnly).frame(minWidth:44,minHeight:44)
                            .accessibilityIdentifier("homeFeed.openOfficialEvents")
                        Button("discovery.browseTemplates",systemImage:"square.stack.3d.up") { showsTemplates=true }
                            .accessibilityIdentifier("homeFeed.openTemplates")
                    }
                }
                .navigationDestination(for:HomeFeedDestination.self) { destination in
                    switch destination {
                    case .activity(let id): ActivityDetailView(id:id,reader:session,playReaderForActivity:{ session.playReader(for:.activity($0)) },registrationEnabled:true)
                    case .topic(let id): SessionTopicDetailView(id: id, session: session)
                    }
                }
        }
        .id(session.homeFeedReader.scope)
        .onChange(of:session.homeFeedReader.scope) { _,_ in path=[];showsGlobalSearch=false;showsTemplates=false;showsSquare=false;showsOfficialEvents=false;showsProjectEditor=false }
        .onChange(of:session.officialEventReader.scope) { _,_ in showsOfficialEvents=false }
        .onChange(of:session.sessionRevision) { _,_ in showsProjectEditor=false }
        .sheet(isPresented:$showsGlobalSearch) {
            NavigationStack {
                SessionGlobalSearchView(onSignIn:{ showsGlobalSearch=false;onSignIn?() })
                    .toolbar { ToolbarItem(placement:.cancellationAction) { Button("action.close") { showsGlobalSearch=false } } }
            }.id(session.searchMapReader.scope)
        }
        .sheet(isPresented:$showsProjectEditor) {
            NavigationStack {
                ProjectEditLaunchView().toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("action.close") { showsProjectEditor=false } }
                }
            }.id(session.sessionRevision)
        }
        .sheet(isPresented:$showsOfficialEvents) {
            OfficialEventsBrowserView(reader:session.officialEventReader,actions:session.officialActionCoordinator,onClose:{ showsOfficialEvents=false },onLogin:{
                showsOfficialEvents=false
                onSignIn?()
            }).id(session.officialEventReader.scope)
        }
        .sheet(isPresented:$showsSquare) { SessionSquareBrowserView(session: session, onClose: { showsSquare = false }, onSignIn: { showsSquare = false; onSignIn?() }).id(session.squareReader.scope) }
        .sheet(isPresented:$showsTemplates) {
            NavigationStack {
                DiscoveryTemplateBrowserView(reader: session, authoringFactory: { session.templateAuthoringEditor(adopting: $0) }, authoringRevision: session.sessionRevision).id(session.templateAuthoringViewIdentity)
                    .toolbar {
                        ToolbarItem(placement:.cancellationAction) {
                            Button("action.close") { showsTemplates=false }
                        }
                    }
            }
        }
    }
}
