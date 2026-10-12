import SwiftUI

/// A normal personal link using the existing, authenticated read composition. This
/// does not construct a service, issue a grant, or inherit cooperation write access.
@MainActor struct ProfileComplaintPreparationLink: View {
    @ObservedObject var session: AppSession
    var body: some View {
        let revision = session.sessionRevision
        let owner = session.cooperationFlowReader.session
        NavigationLink {
            ProfileComplaintPreparationView(reader: session.cooperationFlowReader,
                isCurrent: { session.sessionRevision == revision && session.cooperationFlowReader.session == owner })
                .id(revision)
        } label: { Label("profile.complaint.title", systemImage: "text.bubble") }
            .accessibilityIdentifier("profile.complaint.open")
    }
}

private struct ProfileComplaintPresentationKey: Hashable {
    let reader: ObjectIdentifier
    let accountID: Int?
    let epoch: UInt64?
    @MainActor init(_ reader: any CoopFlowReading) {
        self.reader = ObjectIdentifier(reader); accountID = reader.session?.accountID; epoch = reader.session?.epoch
    }
}
@MainActor struct ProfileComplaintPreparationView: View {
    let reader: any CoopFlowReading
    let isCurrent: @MainActor () -> Bool
    var body: some View {
        ProfileComplaintPreparationScreen(reader: reader, isCurrent: isCurrent)
            .id(ProfileComplaintPresentationKey(reader))
    }
}
@MainActor private struct ProfileComplaintPreparationScreen: View {
    let reader: any CoopFlowReading
    @State private var model: ProfileComplaintPreparationController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Field?
    private enum Field: Hashable { case reason, contact }
    init(reader: any CoopFlowReading, isCurrent: @escaping @MainActor () -> Bool) {
        self.reader = reader
        _model = State(initialValue: .init(reader: reader, isCurrent: isCurrent))
    }
    var body: some View {
        Form {
            Section {
                Text("profile.complaint.localOnly").font(.footnote)
                    .accessibilityIdentifier("profile.complaint.localOnly")
            }
            if !model.contextMatches {
                Text("profile.complaint.retired").accessibilityIdentifier("profile.complaint.retired")
            } else if let review = model.review {
                reviewSection(review)
            } else {
                if model.isLoading { ProgressView("profile.loading").accessibilityIdentifier("profile.complaint.loading") }
                if let issue = model.issue {
                    Section {
                        Text(LocalizedStringKey(issue.titleKey)).accessibilityIdentifier("profile.complaint.issue")
                        if issue == .failed {
                            Button("action.retry") { Task { await model.load() } }
                                .disabled(model.isLoading).accessibilityIdentifier("profile.complaint.retry")
                        }
                    }
                }
                if let topics = model.topics {
                    if topics.isEmpty && model.issue == nil && !model.isLoading {
                        Section { Text("profile.complaint.empty").accessibilityIdentifier("profile.complaint.empty") }
                    } else if !topics.isEmpty {
                        editor(topics).disabled(!model.canEdit)
                    }
                }
            }
        }
        .navigationTitle("profile.complaint.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.close") { model.retire(); dismiss() }
                    .accessibilityIdentifier("profile.complaint.close")
            }
            ToolbarItem(placement: .primaryAction) {
                if model.review == nil {
                    Button("profile.refresh", systemImage: "arrow.clockwise") { focused = nil; Task { await model.load() } }
                        .disabled(!model.contextMatches || model.isLoading)
                        .accessibilityIdentifier("profile.complaint.refresh")
                }
            }
        }
        .task { await model.load() }
        .onChange(of: reader.session) { _, _ in model.retire() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { focused = nil; model.retire() }
        }
        .onDisappear { model.retire() }
        .privacySensitive()
    }
    private func editor(_ topics: [ProfileComplaintTopic]) -> some View {
        Group {
            Section("profile.complaint.topic") {
                Picker("profile.complaint.topic", selection: Binding<Int?>(
                    get: { model.draft.topicID }, set: { value in model.change { $0.topicID = value } })) {
                    Text("profile.complaint.chooseTopic").tag(Optional<Int>.none)
                    ForEach(topics) { topic in
                        topicLabel(topic).tag(Optional(topic.id))
                    }
                }.accessibilityIdentifier("profile.complaint.topic")
                Picker("profile.complaint.kind", selection: Binding<ProfileComplaintKind?>(
                    get: { model.draft.kind }, set: { value in model.change { $0.kind = value } })) {
                    Text("profile.complaint.optional").tag(Optional<ProfileComplaintKind>.none)
                    ForEach(ProfileComplaintKind.allCases) { kind in
                        Text(LocalizedStringKey(kind.titleKey)).tag(Optional(kind))
                    }
                }.accessibilityIdentifier("profile.complaint.kind")
            }
            Section("profile.complaint.reason") {
                TextEditor(text: Binding(get: { model.draft.reason }, set: { value in model.change { $0.reason = value } }))
                    .frame(minHeight: 140).focused($focused, equals: .reason)
                    .accessibilityLabel(Text("profile.complaint.reason"))
                    .accessibilityIdentifier("profile.complaint.reason")
                Text("profile.complaint.reasonHint").font(.caption).foregroundStyle(.secondary)
            }
            Section("profile.complaint.contact") {
                TextField("profile.complaint.optional", text: Binding(get: { model.draft.contact },
                    set: { value in model.change { $0.contact = value } }))
                    .focused($focused, equals: .contact).textInputAutocapitalization(.never)
                    .accessibilityLabel(Text("profile.complaint.contact"))
                    .accessibilityIdentifier("profile.complaint.contact")
                Text("profile.complaint.contactHint").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if let validation = model.validation {
                    Text(LocalizedStringKey(validation.titleKey)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.complaint.validation")
                }
                Button("profile.complaint.review") {
                    focused = nil
                    if !model.beginReview() {
                        switch model.validation {
                        case .reasonShort, .reasonLong: focused = .reason
                        case .contactLong: focused = .contact
                        default: break
                        }
                    }
                }.accessibilityIdentifier("profile.complaint.review")
            }
        }
    }
    private func reviewSection(_ review: ProfileComplaintReview) -> some View {
        Group {
            Section("profile.complaint.reviewTitle") {
                topicLabel(review.topic).font(.headline)
                Text(verbatim: review.reason).accessibilityIdentifier("profile.complaint.reviewText")
                Text("profile.complaint.notSubmitted").font(.footnote)
                    .accessibilityIdentifier("profile.complaint.notSubmitted")
            }
            Section {
                Button("profile.complaint.continueEditing") { model.continueEditing() }
                    .accessibilityIdentifier("profile.complaint.continueEditing")
            }
        }
    }
    private func topicLabel(_ topic: ProfileComplaintTopic) -> Text {
        if let name = topic.name { return Text(verbatim: name) }
        return Text("profile.complaint.unnamed") + Text(verbatim: " #\(topic.id)")
    }
}
