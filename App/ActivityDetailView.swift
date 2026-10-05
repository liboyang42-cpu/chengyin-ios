import SwiftUI
import MapKit

@MainActor
struct ActivityDetailView: View {
    let id: Int
    let reader: any ActivityReading
    var playReaderForActivity: ((Int)->PlaySessionReader)? = nil
    var registrationEnabled = false
    var peopleProfile: ActivityPeopleProfileContext? = nil
    var body: some View {
        if let session = reader as? AppSession {
            SessionActivityDetailView(id: id, session: session,
                playReaderForActivity: playReaderForActivity, registrationEnabled: registrationEnabled)
        } else {
            ActivityDetailContentView(id: id, reader: reader,
                playReaderForActivity: playReaderForActivity, registrationEnabled: registrationEnabled,
                peopleProfile: peopleProfile)
        }
    }
}

@MainActor private struct SessionActivityDetailView: View {
    let id: Int
    @ObservedObject var session: AppSession
    var playReaderForActivity: ((Int)->PlaySessionReader)?
    var registrationEnabled: Bool
    var body: some View {
        Group {
            if session.account == nil {
                ContentUnavailableView("activity.signInRequired", systemImage: "person.crop.circle.badge.exclamationmark")
                    .accessibilityIdentifier("activity.detail.signIn")
            } else {
                ActivityDetailContentView(id: id, reader: session,
                    playReaderForActivity: playReaderForActivity,
                    topicDestination: { AnyView(SessionTopicDetailView(id: $0, session: session)) },
                    registrationEnabled: registrationEnabled,
                    peopleProfile: .init(reader: session.socialAccountReader, squareReader: session.squareReader, actions: session.socialActionCoordinator))
                    .id(session.contentDetailRevision)
            }
        }.appNavigationTitle("activity.details")
    }
}

@MainActor private struct ActivityDetailContentView: View {
    let id: Int
    let reader: any ActivityReading
    var playReaderForActivity: ((Int)->PlaySessionReader)? = nil
    var topicDestination: ((Int) -> AnyView)? = nil
    var registrationEnabled=false
    var peopleProfile: ActivityPeopleProfileContext? = nil
    @State private var loadedPeopleSnapshotID: UUID?
    @State private var loadedProfileIdentity: SocialAccountIdentity?
    @State private var profileSelection: ActivityPersonProfileSelection?
    @State private var showsReview = false
    @State private var showsRegistration=false
    @State private var access: ActivityDetailAccess?
    @State private var loading=false
    @State private var failed=false
    @State private var generation=0
    @State private var loads = SignedInContentDetailLoadOwner()
    var body: some View {
        // Group with nil access produces EmptyView, which cannot host the initial task.
        // Keep one concrete root for the task and navigation title through every state.
        ZStack {
            if loading { ProgressView("activity.loading") }
            else if failed {
                ContentUnavailableView {
                    Label {
                        Text("activity.loadFailed").accessibilityIdentifier("activity.detail.error")
                    } icon: { Image(systemName:"wifi.exclamationmark") }
                } actions: {
                    Button("action.retry") { loads.start { await load() } }
                        .accessibilityIdentifier("activity.detail.retry")
                }
            } else if let access {
                switch access {
                case .clubRequired(_,let message):
                    ContentUnavailableView {
                        Label {
                            Text("activity.clubRequired").accessibilityIdentifier("activity.detail.clubGate")
                        } icon: { Image(systemName:"lock") }
                    } description: {
                        if let message, !message.isEmpty { Text(message) }
                        else { Text("activity.clubRequiredHint") }
                    }
                case .allowed(let detail):
                    detailContent(detail)
                }
            } else { ProgressView("activity.loading") }
        }
        .appNavigationTitle("activity.details")
        .navigationBarTitleDisplayMode(.inline)
        .task(id:id) { await loads.run { await load() } }
        .onDisappear { loads.cancel(); generation += 1; loading = false }
        .onChange(of: peopleProfile?.reader.identity) { _, _ in
            profileSelection = nil; loadedProfileIdentity = nil
            loads.start { await load() }
        }
        .navigationDestination(item: $profileSelection) { selection in
            if let peopleProfile, let loadedPeopleSnapshotID, let access, case .allowed(let detail) = access,
               loadedProfileIdentity == peopleProfile.reader.identity,
               selection.matches(activityID: id, people: detail.people, identity: peopleProfile.reader.identity, snapshotID: loadedPeopleSnapshotID) {
                SocialPublicProfileView(memberID: selection.memberID, reader: peopleProfile.reader,
                                        squareReader: peopleProfile.squareReader, actions: peopleProfile.actions)
                    .id(selection)
            } else {
                ContentUnavailableView("social.changed", systemImage: "person.crop.circle.badge.exclamationmark")
            }
        }
        .sheet(isPresented: $showsReview) {
            NavigationStack { ContextualReviewComposer(target: .activity(id), owner: (reader as? AppSession)?.contextualReviews?.coordinator(.activity(id))) { loads.start { await load() } } }
        }
        .sheet(isPresented:$showsRegistration) {
            if let access,case .allowed(let detail)=access { SessionRegistrationSheet(activity:detail) }
        }
    }
    private func detailContent(_ detail:ActivityDetail) -> some View {
        List {
            Section {
                ActivityDetailHeader(summary:detail.summary)
                    .questifyCardListRow()
            }
            if let topicID = detail.summary.linkedTopicID, let topicDestination {
                Section {
                    NavigationLink { topicDestination(topicID) } label: {
                        Label("activity.viewTopic", systemImage: "map")
                    }.accessibilityIdentifier("activity.openTopic")
                }
            }
            if let text=ActivityPresentation.nonempty(detail.summary.description) {
                Section("activity.about") {
                    Text(verbatim:text)
                        .font(.body)
                        .fixedSize(horizontal:false,vertical:true)
                        .textSelection(.enabled)
                        .questifyCardSurface()
                        .questifyCardListRow()
                }
            }
            ActivityPeopleSection(people: detail.people, onOpenProfile: profileAction(detail))
            if detail.summary.hasValidCoordinates,
               let latitude=detail.summary.latitude, let longitude=detail.summary.longitude {
                Section("activity.location") {
                    let coordinate=CLLocationCoordinate2D(latitude:latitude,longitude:longitude)
                    Map(initialPosition:.region(MKCoordinateRegion(center:coordinate,span:MKCoordinateSpan(latitudeDelta:0.01,longitudeDelta:0.01)))) {
                        Marker(detail.summary.name,coordinate:coordinate)
                    }.frame(height:220)
                        .clipShape(RoundedRectangle(cornerRadius:14,style:.continuous))
                        .accessibilityLabel(Text("activity.location"))
                        .questifyCardSurface()
                        .questifyCardListRow()
                }
            }
            Section("activity.tickets") {
                if detail.tickets.isEmpty {
                    Text("activity.noTickets")
                        .foregroundStyle(.secondary)
                        .questifyCardSurface()
                        .questifyCardListRow()
                }
                ForEach(detail.tickets) { ticket in
                    ActivityTicketCard(ticket:ticket)
                        .questifyCardListRow()
                }
            }
            ActivityReviewsSection(reviews: detail.reviews)
            Section { Button("context.review.title") { showsReview = true }.accessibilityIdentifier("activity.openReview") }
            if let playReaderForActivity {
                Section {
                    NavigationLink { PlaySessionView(reader:playReaderForActivity(id)) } label: {
                        Label("play.openSession",systemImage:"figure.walk")
                    }.accessibilityIdentifier("activity.openPlay")
                }
            }
            if let session = reader as? AppSession, session.playExperience(for: .activity(id)) != nil {
                Section {
                    NavigationLink { SessionPlayRuntimeView(session: session, destination: .journey(.activity(id))) } label: {
                        Label("playx.title", systemImage: "figure.walk.circle")
                    }.accessibilityIdentifier("activity.openPlayExperience")
                    NavigationLink { SessionPlayRuntimeView(session: session, destination: .director(id)) } label: {
                        Label("playx.director.title", systemImage: "person.3.sequence")
                    }.accessibilityIdentifier("activity.openPlayDirector")
                }
            }
            Section {
                Label {
                    Text("activity.registrationPending")
                        .accessibilityIdentifier("activity.detail.readOnly")
                } icon: { Image(systemName:"info.circle").accessibilityHidden(true) }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal:false,vertical:true)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(20)
        .accessibilityIdentifier("activity.detail.content")
        .safeAreaInset(edge:.bottom,spacing:0) {
            // This view exists only for .allowed details. Preserve the caller's
            // existing gate; the unchanged registration sheet owns further checks.
            if registrationEnabled { registrationAction }
        }
    }
    private func profileAction(_ detail: ActivityDetail) -> ((Int) -> Void)? {
        guard detail.summary.id == id, let peopleProfile, let snapshotID = loadedPeopleSnapshotID,
              loadedProfileIdentity == peopleProfile.reader.identity,
              peopleProfile.reader.identity.accountID != nil else { return nil }
        let identity = peopleProfile.reader.identity
        return { memberID in
            guard identity == peopleProfile.reader.identity,
                  loadedProfileIdentity == identity, loadedPeopleSnapshotID == snapshotID else { return }
            profileSelection = ActivityPersonProfileSelection(activityID: id, memberID: memberID,
                                                              people: detail.people, identity: identity, snapshotID: snapshotID)
        }
    }
    private var registrationAction: some View {
        VStack(spacing:0) {
            Divider()
            Button { showsRegistration=true } label: {
                Text("registration.form.title")
                    .font(.headline)
                    .fixedSize(horizontal:false,vertical:true)
                    .frame(maxWidth:.infinity,minHeight:44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(QuestifyPalette.accent)
            .accessibilityIdentifier("activity.openRegistration")
            .padding(.horizontal,16)
            .padding(.vertical,12)
        }
        .background(Color(uiColor:.secondarySystemGroupedBackground))
    }
    @MainActor private func load() async {
        generation += 1
        let operation=generation
        let profileIdentity = peopleProfile?.reader.identity
        loading=true;failed=false;access=nil;loadedProfileIdentity=nil
        profileSelection=nil;loadedPeopleSnapshotID=nil
        defer { if generation == operation { loading=false } }
        do {
            let result=try await reader.activityDetail(id:id)
            try Task.checkCancellation()
            if generation == operation, profileIdentity == peopleProfile?.reader.identity {
                access=result; loadedProfileIdentity=profileIdentity; loadedPeopleSnapshotID=UUID()
            }
        }
        catch is CancellationError { }
        catch { if generation == operation, !Task.isCancelled { failed=true } }
    }
}
