import SwiftUI

/// Route ownership is independent of fetched rows. Disappearance purges data, not the link host.
@MainActor final class NativeFriendDirectoryNavigation: ObservableObject {
    let flow: NativeFriendDirectoryFlow
    @Published var selection: NativeFriendDirectoryDetailModel? {
        didSet { if oldValue !== selection { oldValue?.retire() } }
    }
    init(_ flow: NativeFriendDirectoryFlow) {
        self.flow = flow
        flow.onChange = { [weak self] in
            guard let self else { return }
            if !self.flow.isCurrent { self.selection = nil }
            self.objectWillChange.send()
        }
    }
    func open(_ item: NativeFriendItem) {
        guard flow.isCurrent, !flow.busy, flow.phase == .ready, flow.items.contains(item), selection == nil else { return }
        let destination = NativeFriendDirectoryDetailModel(flow.makeDetail(peerID: item.peerID))
        destination.onRetired = { [weak self, weak destination] in
            if self?.selection === destination { self?.selection = nil }
        }
        selection = destination
    }
}
@MainActor struct NativeFriendDirectoryView: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: NativeFriendDirectoryNavigation
    let metadataFactory: ((NativeFriendItem) -> NativeFriendMetadataFlow)?
    let removalFactory: ((NativeFriendItem?) -> NativeFriendRemovalFlow)?
    let publicProfile: ((Int, @escaping () -> Bool) -> AnyView)?
    let conversation: (Int) -> AnyView
    let progressCard: ((NativeFriendItem, @escaping () -> Bool) -> AnyView)?
    init(flow: NativeFriendDirectoryFlow, navigation: NativeFriendDirectoryNavigation? = nil, metadataFactory: ((NativeFriendItem) -> NativeFriendMetadataFlow)? = nil,
         removalFactory: ((NativeFriendItem?) -> NativeFriendRemovalFlow)? = nil, publicProfile: ((Int, @escaping () -> Bool) -> AnyView)? = nil, progressCard: ((NativeFriendItem, @escaping () -> Bool) -> AnyView)? = nil, conversation: @escaping (Int) -> AnyView) {
        _model = StateObject(wrappedValue: navigation ?? NativeFriendDirectoryNavigation(flow)); self.metadataFactory = metadataFactory
        self.removalFactory = removalFactory; self.publicProfile = publicProfile; self.progressCard = progressCard; self.conversation = conversation
    }
    private var flow: NativeFriendDirectoryFlow { model.flow }
    private var filterActive: Bool { flow.filter.groupID != nil || flow.filter.starredOnly }
    var body: some View {
        List {
            Section {
                Picker(localized("friendDirectory.partition"), selection: Binding(get: { flow.filter.section }, set: { value in
                    var filter = flow.filter; filter.section = value; Task { await flow.select(filter) }
                })) {
                    ForEach(NativeFriendDirectorySection.allCases, id: \.self) { section in
                        text("friendDirectory." + section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                .accessibilityIdentifier("friendDirectory.partition")
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if flow.busy { ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("friendDirectory.loading") }
            if flow.phase == .closed { text("friendDirectory.closed") }
            if let issue = flow.issue {
                Section {
                    Label { text(issue) } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
                        .accessibilityIdentifier("friendDirectory.issue")
                    Button { Task { await flow.retry() } } label: { text(flow.paginationFailed ? "friendDirectory.retryPage" : "friendDirectory.refresh") }.disabled(flow.busy)
                }
            }
            Section {
                if flow.phase == .ready && flow.items.isEmpty {
                    ContentUnavailableView { Label { text("friendDirectory.empty") } icon: { Image(systemName: "person.2") } }
                        .accessibilityIdentifier("friendDirectory.empty")
                }
                ForEach(flow.items) { item in
                    Button { model.open(item) } label: {
                        HStack(spacing: Theme.Space.s3) {
                            Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
                            Text(verbatim: item.displayName.isEmpty ? "—" : item.displayName).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                            if item.starred == 1 { Image(systemName: "star.fill").font(Theme.Font.label).foregroundStyle(.yellow).accessibilityLabel(Text("friendMeta.starred", tableName: "NativeFriendMetadata")) }
                            Spacer()
                            Image(systemName: "chevron.right").font(Theme.Font.label.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                        }
                    }.disabled(flow.busy).accessibilityIdentifier("friendDirectory.peer.\(item.peerID)")
                }
                if flow.nextCursor != nil {
                    Button { Task { await flow.loadMore() } } label: { text("friendDirectory.more") }
                        .disabled(flow.busy).accessibilityIdentifier("friendDirectory.more")
                }
            } header: {
                Text(verbatim: localized("friendDirectory." + flow.filter.section.rawValue) + (flow.counts[flow.filter.section.rawValue].map { " · \($0)" } ?? ""))
            }
        }
        .listStyle(.insetGrouped)
        .font(Theme.Font.body)
        .navigationTitle(localized("friendDirectory.title"))
        .accessibilityIdentifier("friendDirectory.home")
        .task { await flow.load() }
        .refreshable { await flow.load() }
        .onDisappear { flow.invalidate() }
        .onChange(of: scenePhase) { _, value in if value == .active { if model.selection == nil { Task { await flow.load() } } } else { flow.invalidate() } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker(localized("friendDirectory.group"), selection: Binding(get: { flow.filter.groupID }, set: { value in
                        var filter = flow.filter; filter.groupID = value; Task { await flow.select(filter) }
                    })) {
                        text("friendDirectory.allGroups").tag(Int64?.none)
                        ForEach(flow.groups) { group in
                            Text(verbatim: group.isDefault == 1 ? localized("friendDirectory.defaultGroup") : group.name).tag(Optional(group.id ?? 0))
                        }
                    }.accessibilityIdentifier("friendDirectory.group")
                    Toggle(isOn: Binding(get: { flow.filter.starredOnly }, set: { value in
                        var filter = flow.filter; filter.starredOnly = value; Task { await flow.select(filter) }
                    })) { text("friendDirectory.starredOnly") }.accessibilityIdentifier("friendDirectory.starredOnly")
                } label: {
                    Label { text("d7.friendDirectory.filter") } icon: {
                        Image(systemName: filterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }.disabled(flow.busy)
            }
        }
        // Always hosted outside ForEach: clearing the parent's rows cannot remove this destination.
        .navigationDestination(isPresented: detailBinding) {
            if let detail = model.selection {
                NativeFriendDirectoryDetailView(model: detail, metadataFactory: metadataFactory,
                    removalFactory: removalFactory, publicProfile: publicProfile, progressCard: progressCard, conversation: conversation).id(detail.id)
            }
        }
        .tint(Theme.Color.accent(in: domain))
    }
    private var detailBinding: Binding<Bool> {
        let captured = model.selection
        return Binding(get: { model.selection != nil }, set: { presented in
            if !presented, model.selection === captured { model.selection = nil }
        })
    }
    private func localized(_ key: String) -> String { String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "NativeFriendDirectory", locale: locale)) }
    private func text(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "NativeFriendDirectory") }
}

@MainActor final class NativeFriendDirectoryDetailModel: ObservableObject, Identifiable {
    struct ProfileRoute: Equatable, Identifiable {
        let id = UUID()
        let memberID: Int
    }
    @MainActor enum Child {
        case metadata(NativeFriendMetadataFlow, String)
        case removal(NativeFriendRemovalFlow)
        case profile(ProfileRoute)
        case conversation(Int)
        func invalidate() {
            switch self {
            case .metadata(let flow, _): flow.invalidate()
            case .removal(let flow): flow.invalidate()
            case .profile, .conversation: break
            }
        }
    }
    let id = UUID()
    let flow: NativeFriendDirectoryDetailFlow
    var onRetired: (() -> Void)?
    @Published var child: Child? { didSet { routeGeneration &+= 1; oldValue?.invalidate() } }
    private var retiring = false
    private(set) var routeGeneration: UInt64 = 0
    init(_ flow: NativeFriendDirectoryDetailFlow) {
        self.flow = flow
        flow.onChange = { [weak self] in
            guard let self else { return }
            if !self.flow.isCurrent { self.retire(); self.onRetired?() }
            self.objectWillChange.send()
        }
    }
    func openMetadata(using factory: (NativeFriendItem) -> NativeFriendMetadataFlow) {
        guard flow.canOpen, let item = flow.detail?.item, item.peerID == flow.peerID, child == nil else { return }
        child = .metadata(factory(item), item.nickname)
    }
    func openRemoval(using factory: (NativeFriendItem?) -> NativeFriendRemovalFlow) {
        guard flow.canOpen, let item = flow.detail?.item, item.peerID == flow.peerID, child == nil else { return }
        child = .removal(factory(item))
    }
    func openProfile() async {
        guard child == nil, flow.canOpen else { return }
        let stamp = routeGeneration
        guard let item = await flow.currentFriend(), !Task.isCancelled,
              stamp == routeGeneration, child == nil, flow.isCurrent,
              item.peerID == flow.peerID, let memberID = Int(exactly: item.peerID) else { return }
        child = .profile(.init(memberID: memberID))
    }
    func owns(_ profile: ProfileRoute) -> Bool {
        guard flow.isCurrent, case .profile(let current)? = child else { return false }
        return current == profile
    }
    func openConversation() async {
        guard child == nil, flow.canOpen else { return }
        let stamp = routeGeneration
        guard let id = await flow.existingConversation(), !Task.isCancelled,
              stamp == routeGeneration, child == nil, flow.isCurrent else { return }
        child = .conversation(id)
    }
    func closeChild(generation: UInt64) {
        guard generation == routeGeneration else { return }
        child = nil
    }
    func retire() {
        guard !retiring else { return }; retiring = true
        child = nil; flow.invalidate(); retiring = false
    }
}
@MainActor private struct NativeFriendDirectoryDetailView: View {
    @Environment(\.themeDomain) private var domain
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: NativeFriendDirectoryDetailModel
    let metadataFactory: ((NativeFriendItem) -> NativeFriendMetadataFlow)?
    let removalFactory: ((NativeFriendItem?) -> NativeFriendRemovalFlow)?
    let publicProfile: ((Int, @escaping () -> Bool) -> AnyView)?
    let conversation: (Int) -> AnyView
    let progressCard: ((NativeFriendItem, @escaping () -> Bool) -> AnyView)?
    init(model: NativeFriendDirectoryDetailModel, metadataFactory: ((NativeFriendItem) -> NativeFriendMetadataFlow)?,
         removalFactory: ((NativeFriendItem?) -> NativeFriendRemovalFlow)?, publicProfile: ((Int, @escaping () -> Bool) -> AnyView)?, progressCard: ((NativeFriendItem, @escaping () -> Bool) -> AnyView)?, conversation: @escaping (Int) -> AnyView) {
        _model = StateObject(wrappedValue: model); self.metadataFactory = metadataFactory
        self.removalFactory = removalFactory; self.publicProfile = publicProfile; self.progressCard = progressCard; self.conversation = conversation
    }
    private var flow: NativeFriendDirectoryDetailFlow { model.flow }
    var body: some View {
        List {
            Section {
                VStack(spacing: Theme.Space.s3) {
                    Image(systemName: "person.crop.circle.fill").font(.largeTitle).imageScale(.large).foregroundStyle(.secondary).accessibilityHidden(true)
                    if let item = flow.detail?.item {
                        QuestifyHeroValue(value: Text(verbatim: item.displayName.isEmpty ? "—" : item.displayName))
                            .accessibilityIdentifier("friendDirectory.detailName")
                    } else if flow.busy {
                        ProgressView()
                    }
                    if let detail = flow.detail {
                        HStack(alignment: .top, spacing: Theme.Space.s2) {
                            if detail.conversationID != nil {
                                QuestifyRoundAction(title: "d7.friendProfile.message", systemImage: "message.fill") { Task { await model.openConversation() } }
                                    .disabled(!flow.canOpen).accessibilityIdentifier("friendDirectory.chat")
                            }
                            if publicProfile != nil {
                                QuestifyRoundAction(title: "d7.friendProfile.profile", systemImage: "person.text.rectangle") { Task { await model.openProfile() } }
                                    .disabled(!flow.canOpen).accessibilityIdentifier("friendDirectory.profile")
                            }
                            if let metadataFactory {
                                QuestifyRoundAction(title: "d7.friendProfile.settings", systemImage: "slider.horizontal.3") { model.openMetadata(using: metadataFactory) }
                                    .disabled(!flow.canOpen).accessibilityIdentifier("friendDirectory.metadata")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            if let issue = flow.issue {
                Section {
                    Label { text(issue) } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary) }
                        .accessibilityIdentifier("friendDirectory.detailIssue")
                    Button { Task { await flow.load() } } label: { text("friendDirectory.refresh") }.disabled(flow.busy)
                }
            }
            if let detail = flow.detail {
                let item = detail.item
                Section {
                    LabeledContent {
                        text(item.starred == 1 ? "friendDirectory.starred" : "friendDirectory.notStarred")
                    } label: { Text("friendMeta.starred", tableName: "NativeFriendMetadata") }
                }
                if let progressCard, flow.canOpen {
                    progressCard(item, { flow.isCurrent && flow.canOpen && flow.detail?.item.peerID == item.peerID && flow.detail?.item.version == item.version })
                }
                if let removalFactory {
                    Section {
                        Button(role: .destructive) { model.openRemoval(using: removalFactory) } label: {
                            Text("friendRemoval.title", tableName: "NativeFriendRemoval").frame(maxWidth: .infinity)
                        }
                            .disabled(!flow.canOpen).accessibilityIdentifier("friendDirectory.remove")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .font(Theme.Font.body)
        .navigationTitle(localized("friendDirectory.detail"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("friendDirectory.detail")
        .task { await flow.load() }
        .refreshable { await flow.load() }
        .onDisappear { flow.invalidate() }
        .onChange(of: scenePhase) { _, value in if value == .active { if model.child == nil { Task { await flow.load() } } } else { model.retire() } }
        // Child route owns only the original flow/peer identity; it does not require retained detail data.
        .navigationDestination(isPresented: childBinding) {
            if flow.isCurrent, let child = model.child {
                switch child {
                case .metadata(let metadata, let nickname): NativeFriendMetadataView(flow: metadata, nickname: nickname)
                case .removal(let removal): NativeFriendRemovalView(flow: removal)
                case .profile(let profile):
                    if let publicProfile { publicProfile(profile.memberID, { model.owns(profile) }).id(profile.id) }
                case .conversation(let id): conversation(id)
                }
            }
        }
        .tint(Theme.Color.accent(in: domain))
    }
    private var childBinding: Binding<Bool> {
        let captured = model.routeGeneration
        return Binding(get: { model.child != nil }, set: { presented in
            if !presented { model.closeChild(generation: captured) }
        })
    }
    private func localized(_ key: String) -> String { String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: "NativeFriendDirectory", locale: locale)) }
    private func text(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "NativeFriendDirectory") }
}
