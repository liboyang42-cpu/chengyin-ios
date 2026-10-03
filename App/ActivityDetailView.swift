import SwiftUI
import MapKit

@MainActor
struct ActivityDetailView: View {
    let id: Int
    let reader: any ActivityReading
    var playReaderForActivity: ((Int)->PlaySessionReader)? = nil
    var registrationEnabled = false
    var body: some View {
        if let session = reader as? AppSession {
            SessionActivityDetailView(id: id, session: session,
                playReaderForActivity: playReaderForActivity, registrationEnabled: registrationEnabled)
        } else {
            ActivityDetailContentView(id: id, reader: reader,
                playReaderForActivity: playReaderForActivity, registrationEnabled: registrationEnabled)
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
                    playReaderForActivity: playReaderForActivity, registrationEnabled: registrationEnabled)
                    .id(session.contentDetailRevision)
            }
        }.appNavigationTitle("activity.details")
    }
}

@MainActor private struct ActivityDetailContentView: View {
    let id: Int
    let reader: any ActivityReading
    var playReaderForActivity: ((Int)->PlaySessionReader)? = nil
    var registrationEnabled=false
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
            Section { Button("context.review.title") { showsReview = true }.accessibilityIdentifier("activity.openReview") }
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
        loading=true;failed=false;access=nil
        defer { if generation == operation { loading=false } }
        do {
            let result=try await reader.activityDetail(id:id)
            try Task.checkCancellation()
            if generation == operation { access=result }
        }
        catch is CancellationError { }
        catch { if generation == operation, !Task.isCancelled { failed=true } }
    }
}
