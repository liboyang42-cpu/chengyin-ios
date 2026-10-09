"""Bounded source checks, not Swift compilation or XCTest execution."""
from pathlib import Path
import hashlib,json,re,unittest
ROOT=Path(__file__).resolve().parents[2]
BASE_HASHES={'Core/MerchantContentService.swift': 'cf85b10be41628a483a5954d37b49a03a3f88c5946fe2987e224d9c0f07e1434', 'App/MerchantHomeView.swift': 'c4b775780654f919777733ffcdec105a4506e281a2e0c2ea343fd02a9720e20f', 'App/MerchantProjectsView.swift': 'b9cd63020d33ed4d39ff03573fcc133550cde2203253683d5761c9f676331493', 'App/MerchantContentViews.swift': '334b0060952d2a927feb9e2185a413145e991f97a60e2987fafd2f60235c22a5', 'Tests/CoreTests/MerchantContentContractTests.swift': 'ac9ebf10a83e5f104ffb0dcd29de2c996bae69e59c6682112da1632bb008b91d'}
INVERSE_BLOCKS={'Core/MerchantContentService.swift': [{'post_start': 199, 'post_end': 202, 'before': ['        case .project(let id): value = try await read("api/project/home", .json(optionalTopic(id)), session: s)\n'], 'after': ['        case .project(let id):\n', '            var fields = optionalTopic(id); fields["scope"] = .string("MERCHANT")\n', '            value = try await read("api/project/home", .json(fields), session: s)\n']}], 'App/MerchantHomeView.swift': [{'post_start': 180, 'post_end': 181, 'before': ['                        NavigationLink { MerchantProjectsView(reader: reader) } label: { Label("merchant.projects", systemImage: "calendar") }\n'], 'after': ['                        NavigationLink { MerchantProjectsView(reader: reader, contentService: contentService) } label: { Label("merchant.projects", systemImage: "calendar") }\n']}], 'App/MerchantProjectsView.swift': [{'post_start': 5, 'post_end': 6, 'before': [], 'after': ['    @Environment(\\.scenePhase) private var scenePhase\n']}, {'post_start': 7, 'post_end': 12, 'before': ['    @StateObject private var model = MerchantLoadModel<MerchantProjectPage>()\n', '    @State private var selection: ProjectSelection?\n', '    private struct ProjectSelection: Identifiable {\n', '        let id = UUID()\n', '        let project: MerchantProject\n', '        let revision: UInt64\n', '    }\n'], 'after': ['    var contentService: (any MerchantContentServing)? = nil\n', '    @StateObject private var model = MerchantLoadModel<MerchantProjectWorkspaceSnapshot>()\n', '    @StateObject private var presentation = MerchantProjectWorkspacePresentation()\n', '    private var context: MerchantProjectWorkspaceContext { .init(reader: reader, service: contentService) }\n', '    private var sourceFresh: Bool { !model.isLoading && model.errorKey == nil && model.loadedRevision == reader.sessionRevision }\n']}, {'post_start': 18, 'post_end': 21, 'before': ['            } else if model.loadedRevision == reader.sessionRevision, let page = model.value {\n'], 'after': ['            } else if model.loadedRevision == reader.sessionRevision, let snapshot = model.value {\n', '                let page = snapshot.page\n', '                let permit = presentation.permit(snapshot: snapshot)\n']}, {'post_start': 35, 'post_end': 39, 'before': ['                        Button { selection = ProjectSelection(project: project, revision: reader.sessionRevision) } label: {\n'], 'after': ['                        Button {\n', '                            guard model.value?.id == snapshot.id else { return }\n', '                            presentation.openSummary(project: project, snapshot: snapshot, context: context, permit: permit)\n', '                        } label: {\n']}, {'post_start': 56, 'post_end': 64, 'before': ['        .onChange(of: reader.sessionRevision) { _, _ in selection = nil }\n', '        .sheet(item: $selection) { selected in\n'], 'after': ['        .onChange(of: context) { _, _ in presentation.invalidate() }\n', '        .onChange(of: model.value?.id) { _, _ in presentation.invalidate() }\n', '        .onChange(of: scenePhase) { _, phase in\n', '            if phase == .active { presentation.activate() } else { presentation.retire() }\n', '        }\n', '        .onAppear { if scenePhase == .active { presentation.activate() } }\n', '        .onDisappear { if presentation.selection == nil { presentation.retire() } }\n', '        .sheet(item: presentation.summaryBinding()) { selected in\n']}, {'post_start': 65, 'post_end': 81, 'before': ['                if reader.isSignedIn && selected.revision == reader.sessionRevision {\n', '                    MerchantProjectSummary(project: selected.project)\n', '                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("merchant.done") { selection = nil } } }\n', '                } else { ContentUnavailableView("merchant.signIn", systemImage: "lock") }\n', '            }\n'], 'after': ['                if let snapshot = model.value, presentation.selectionIsCurrent(selected, snapshot: snapshot, context: context) {\n', '                    MerchantProjectSummary(project: selected.project, canOpenWorkspace: presentation.canOpenWorkspace(selected, snapshot: snapshot, context: context, sourceFresh: sourceFresh)) {\n', '                        guard model.value?.id == snapshot.id else { return }\n', '                        presentation.openWorkspace(selected, snapshot: snapshot, context: context, sourceFresh: sourceFresh)\n', '                    }\n', '                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("merchant.done") { presentation.closeSummary(id: selected.id) } } }\n', '                    .navigationDestination(item: presentation.workspaceBinding()) { route in\n', '                        if let contentService, presentation.workspaceIsCurrent(route, snapshot: model.value, context: context, sourceFresh: sourceFresh) {\n', '                            MerchantContentDocumentView(service: contentService, query: .project(topicID: route.topicID),\n', '                                focusedTopicID: route.topicID, focusedMerchantID: route.merchantID,\n', '                                projectEntryIsCurrent: { presentation.workspaceIsCurrent(route, snapshot: model.value, context: context, sourceFresh: sourceFresh) })\n', '                                .id(route.id)\n', '                        } else { Text("merchant.projectWorkspace.changed") }\n', '                    }\n', '                } else { ContentUnavailableView("merchant.projectWorkspace.changed", systemImage: "lock") }\n', '            }.onDisappear { presentation.closeSummary(id: selected.id) }\n']}, {'post_start': 84, 'post_end': 86, 'before': ['        let revision = reader.sessionRevision\n'], 'after': ['        presentation.invalidate()\n', '        let captured = context, revision = reader.sessionRevision\n']}, {'post_start': 91, 'post_end': 94, 'before': ['            return try await reader.merchantProjects(access: access)\n'], 'after': ['            let page = try await reader.merchantProjects(access: access)\n', '            guard context == captured, reader.isSignedIn else { throw CancellationError() }\n', '            return .init(page: page, access: access, context: captured)\n']}, {'post_start': 101, 'post_end': 103, 'before': [], 'after': ['    var canOpenWorkspace = false\n', '    var openWorkspace: () -> Void = {}\n']}, {'post_start': 115, 'post_end': 122, 'before': [], 'after': ['            if canOpenWorkspace {\n', '                Section {\n', '                    Button("merchant.projectWorkspace.open", action: openWorkspace)\n', '                        .accessibilityIdentifier("merchant.projectWorkspace.open")\n', '                    Text("merchant.projectWorkspace.explanation").font(.footnote).foregroundStyle(.secondary)\n', '                }\n', '            }\n']}, {'post_start': 131, 'post_end': 227, 'before': [], 'after': ['\n', '/// A list row proves only which project the user selected. Server reads still\n', '/// establish membership, host/join visibility and every existing operation grant.\n', 'struct MerchantProjectWorkspaceContext: Hashable {\n', '    let readerID: ObjectIdentifier\n', '    let revision: UInt64\n', '    let configured: Bool\n', '    let signedIn: Bool\n', '    let serviceID: ObjectIdentifier?\n', '    let serviceScope: UUID?\n', '    let serviceConfigured: Bool\n', '    let serviceAuthenticated: Bool\n', '    @MainActor init<Reader: MerchantReading>(reader: Reader, service: (any MerchantContentServing)?) {\n', '        readerID = ObjectIdentifier(reader); revision = reader.sessionRevision\n', '        configured = reader.isConfigured; signedIn = reader.isSignedIn\n', '        serviceID = service.map { ObjectIdentifier($0) }; serviceScope = service?.scope\n', '        serviceConfigured = service?.isConfigured == true; serviceAuthenticated = service?.isAuthenticated == true\n', '    }\n', '}\n', 'struct MerchantProjectWorkspaceSnapshot {\n', '    let id = UUID()\n', '    let page: MerchantProjectPage\n', '    let access: MerchantAccess\n', '    let context: MerchantProjectWorkspaceContext\n', '}\n', '@MainActor final class MerchantProjectWorkspacePresentation: ObservableObject {\n', '    struct Permit { let generation: UUID; let snapshotID: UUID }\n', '    struct Selection: Identifiable {\n', '        let id = UUID()\n', '        let project: MerchantProject\n', '        let snapshotID: UUID\n', '        let context: MerchantProjectWorkspaceContext\n', '        let generation: UUID\n', '    }\n', '    struct Route: Identifiable, Hashable {\n', '        let id = UUID()\n', '        let selectionID: UUID\n', '        let topicID: Int\n', '        let merchantID: Int\n', '        let snapshotID: UUID\n', '        let context: MerchantProjectWorkspaceContext\n', '        let generation: UUID\n', '    }\n', '    @Published private(set) var selection: Selection?\n', '    @Published private(set) var route: Route?\n', '    private var generation = UUID()\n', '    private(set) var active = true\n', '    func permit(snapshot: MerchantProjectWorkspaceSnapshot) -> Permit { .init(generation: generation, snapshotID: snapshot.id) }\n', '    func activate() { if !active { active = true; invalidate() } }\n', '    func invalidate() { generation = UUID(); selection = nil; route = nil }\n', '    func retire() { active = false; invalidate() }\n', '    private func current(_ snapshot: MerchantProjectWorkspaceSnapshot, _ context: MerchantProjectWorkspaceContext) -> Bool {\n', '        active && context == snapshot.context && context.configured && context.signedIn && snapshot.access.allows(.projects) && (snapshot.access.merchantID ?? 0) > 0\n', '    }\n', '    func openSummary(project: MerchantProject, snapshot: MerchantProjectWorkspaceSnapshot, context: MerchantProjectWorkspaceContext, permit: Permit) {\n', '        guard selection == nil, current(snapshot, context), permit.generation == generation, permit.snapshotID == snapshot.id,\n', '              snapshot.page.rows.filter({ $0.id == project.id }).count == 1, snapshot.page.rows.contains(project) else { return }\n', '        selection = .init(project: project, snapshotID: snapshot.id, context: context, generation: generation)\n', '    }\n', '    func selectionIsCurrent(_ selected: Selection, snapshot: MerchantProjectWorkspaceSnapshot, context: MerchantProjectWorkspaceContext) -> Bool {\n', '        current(snapshot, context) && selection?.id == selected.id && selected.generation == generation && selected.snapshotID == snapshot.id && selected.context == context\n', '    }\n', '    func canOpenWorkspace(_ selected: Selection, snapshot: MerchantProjectWorkspaceSnapshot, context: MerchantProjectWorkspaceContext, sourceFresh: Bool) -> Bool {\n', '        sourceFresh && selectionIsCurrent(selected, snapshot: snapshot, context: context) && selected.project.bizType == "topic" && selected.project.projectID > 0 &&\n', '            context.serviceID != nil && context.serviceConfigured && context.serviceAuthenticated\n', '    }\n', '    func openWorkspace(_ selected: Selection, snapshot: MerchantProjectWorkspaceSnapshot, context: MerchantProjectWorkspaceContext, sourceFresh: Bool) {\n', '        guard route == nil, canOpenWorkspace(selected, snapshot: snapshot, context: context, sourceFresh: sourceFresh), let merchantID = snapshot.access.merchantID else { return }\n', '        route = .init(selectionID: selected.id, topicID: selected.project.projectID, merchantID: merchantID,\n', '                      snapshotID: snapshot.id, context: context, generation: generation)\n', '    }\n', '    func workspaceIsCurrent(_ value: Route, snapshot: MerchantProjectWorkspaceSnapshot?, context: MerchantProjectWorkspaceContext, sourceFresh: Bool) -> Bool {\n', '        guard let snapshot, let selected = selection, route?.id == value.id, value.generation == generation,\n', '              selected.id == value.selectionID, snapshot.id == value.snapshotID, snapshot.access.merchantID == value.merchantID,\n', '              selected.project.projectID == value.topicID, value.context == context else { return false }\n', '        return canOpenWorkspace(selected, snapshot: snapshot, context: context, sourceFresh: sourceFresh)\n', '    }\n', '    static func matches(snapshot: MerchantContentSnapshot, topicID: Int?, merchantID: Int?) -> Bool {\n', '        guard let topicID, topicID > 0, let merchantID, merchantID > 0,\n', '              snapshot.query == .project(topicID: topicID), snapshot.access.allows(.projects),\n', '              snapshot.access.merchantID == merchantID else { return false }\n', '        guard case .integer(let receivedID) = snapshot.value["topic"]["id"] else { return false }\n', '        return receivedID == topicID\n', '    }\n', '    func closeSummary(id: UUID) { guard selection?.id == id else { return }; invalidate() }\n', '    func summaryBinding() -> Binding<Selection?> {\n', '        let captured = selection?.id\n', '        return Binding(get: { [weak self] in self?.selection?.id == captured ? self?.selection : nil },\n', '                       set: { [weak self] value in if value == nil, let captured { self?.closeSummary(id: captured) } })\n', '    }\n', '    func workspaceBinding() -> Binding<Route?> {\n', '        let captured = route?.id\n', '        return Binding(get: { [weak self] in self?.route?.id == captured ? self?.route : nil },\n', '                       set: { [weak self] value in if value == nil, let captured, self?.route?.id == captured { self?.route = nil } })\n', '    }\n', '}\n']}], 'App/MerchantContentViews.swift': [{'post_start': 30, 'post_end': 63, 'before': ['    init(service: any MerchantContentServing, query: MerchantContentQuery) { coordinator = .init(service: service, query: query) }\n', '    func load() async { revision += 1; await coordinator.load(); revision += 1 }\n', '    func prepare(_ c: MerchantContentCommand) { coordinator.prepare(c); revision += 1 }\n'], 'after': ['    private let projectEntryIsCurrent: (() -> Bool)?\n', '    private let focusedTopicID: Int?\n', '    private let focusedMerchantID: Int?\n', '    private var rejectedProjectProjection = false\n', '    init(service: any MerchantContentServing, query: MerchantContentQuery, focusedTopicID: Int? = nil, focusedMerchantID: Int? = nil, projectEntryIsCurrent: (() -> Bool)? = nil) {\n', '        coordinator = .init(service: service, query: query); self.projectEntryIsCurrent = projectEntryIsCurrent\n', '        self.focusedTopicID = focusedTopicID; self.focusedMerchantID = focusedMerchantID\n', '    }\n', '    // A guarded list entry owns the entire document, including recovery/status controls.\n', '    // Other existing document callers retain their original coordinator behavior.\n', '    var projectPresentationIsCurrent: Bool {\n', '        guard projectEntryIsCurrent != nil else { return true }\n', '        guard projectEntryIsCurrent?() == true, !rejectedProjectProjection else { return false }\n', '        guard let snapshot = coordinator.snapshot else { return true }\n', '        return snapshot.scope == coordinator.service.scope && MerchantProjectWorkspacePresentation.matches(snapshot: snapshot, topicID: focusedTopicID, merchantID: focusedMerchantID)\n', '    }\n', '    var projectActionsAreCurrent: Bool {\n', '        guard projectEntryIsCurrent != nil else { return true }\n', '        return projectPresentationIsCurrent && coordinator.isCurrent && coordinator.snapshot != nil\n', '    }\n', '    func load() async {\n', '        guard projectEntryIsCurrent?() != false else { return }\n', '        rejectedProjectProjection = false\n', '        revision += 1; await coordinator.load()\n', '        if projectEntryIsCurrent?() == false { coordinator.invalidate() }\n', '        else if !projectPresentationIsCurrent {\n', '            rejectedProjectProjection = true\n', '            // Only retire the rejected local projection. Never reconcile or remove a journal record.\n', '            coordinator.invalidate()\n', '        }\n', '        revision += 1\n', '    }\n', '    func prepare(_ c: MerchantContentCommand) { guard projectActionsAreCurrent else { return }; coordinator.prepare(c); revision += 1 }\n']}, {'post_start': 64, 'post_end': 67, 'before': ['    func confirm(_ r: MerchantContentReview) async { revision += 1; await coordinator.confirm(r); revision += 1 }\n', '    func reconcile() async { revision += 1; await coordinator.reconcile(); revision += 1 }\n', '    func retryStation() async { revision += 1; await coordinator.retryStation(); revision += 1 }\n'], 'after': ['    func confirm(_ r: MerchantContentReview) async { guard projectActionsAreCurrent else { return }; revision += 1; await coordinator.confirm(r); revision += 1 }\n', '    func reconcile() async { guard projectActionsAreCurrent else { return }; revision += 1; await coordinator.reconcile(); revision += 1 }\n', '    func retryStation() async { guard projectActionsAreCurrent else { return }; revision += 1; await coordinator.retryStation(); revision += 1 }\n']}, {'post_start': 79, 'post_end': 80, 'before': [], 'after': ['    let projectEntryIsCurrent: (() -> Bool)?\n']}, {'post_start': 81, 'post_end': 86, 'before': ['    init(service: any MerchantContentServing, query: MerchantContentQuery, focusedTopicID: Int? = nil, focusedMerchantID: Int? = nil) { self.service = service; self.query = query; self.focusedTopicID = focusedTopicID; self.focusedMerchantID = focusedMerchantID; _model = StateObject(wrappedValue: .init(service: service, query: query)) }\n'], 'after': ['    init(service: any MerchantContentServing, query: MerchantContentQuery, focusedTopicID: Int? = nil, focusedMerchantID: Int? = nil, projectEntryIsCurrent: (() -> Bool)? = nil) {\n', '        self.service = service; self.query = query; self.focusedTopicID = focusedTopicID; self.focusedMerchantID = focusedMerchantID\n', '        self.projectEntryIsCurrent = projectEntryIsCurrent\n', '        _model = StateObject(wrappedValue: .init(service: service, query: query, focusedTopicID: focusedTopicID, focusedMerchantID: focusedMerchantID, projectEntryIsCurrent: projectEntryIsCurrent))\n', '    }\n']}, {'post_start': 91, 'post_end': 93, 'before': [], 'after': ['                if !model.projectPresentationIsCurrent { Text("merchant.projectWorkspace.changed") }\n', '                else {\n']}, {'post_start': 99, 'post_end': 100, 'before': [], 'after': ['                }\n']}, {'post_start': 108, 'post_end': 109, 'before': ['        .sheet(item: Binding(get: { c.isCurrent ? c.review : nil }, set: { if $0 == nil { model.cancel() } })) { MerchantContentReviewView(model: model, review: $0) }\n'], 'after': ['        .sheet(item: Binding(get: { c.isCurrent && model.projectActionsAreCurrent ? c.review : nil }, set: { if $0 == nil { model.cancel() } })) { MerchantContentReviewView(model: model, review: $0) }\n']}], 'Tests/CoreTests/MerchantContentContractTests.swift': [{'post_start': 208, 'post_end': 209, 'before': ['    func testProjectListCarriesMerchantScopeButWorkspaceDoesNotInventScope() async throws {\n'], 'after': ['    func testProjectListAndWorkspaceCarryDocumentedMerchantScope() async throws {\n']}, {'post_start': 213, 'post_end': 214, 'before': ['        XCTAssertEqual(try JSONDecoder().decode([String: Int].self, from: t.requests[3].httpBody!), ["topicId": 70])\n'], 'after': ['        XCTAssertEqual(try JSONDecoder().decode([String: MerchantContentValue].self, from: t.requests[3].httpBody!), ["topicId": .integer(70), "scope": .string("MERCHANT")])\n']}]}
PROTECTED = dict(zip(
    (
        'Core/MerchantContentCoordinator.swift',
        'Core/MerchantContentCommands.swift',
        'Core/MerchantContentDomain.swift',
        'Core/MerchantService.swift',
        'Core/MerchantAccess.swift',
        'Core/MerchantContracts.swift',
        'App/MerchantReading.swift',
        'App/AppSession.swift',
        'App/AccountView.swift',
        'App/MerchantContentEditor.swift',
        'App/MerchantBusinessViews.swift',
        'Core/MerchantBusinessCoordinator.swift',
        'Core/MerchantOperatorInvitationPresentation.swift',
        'App/MerchantOperatorInvitationReceiptView.swift',
        'App/MerchantEngagementViews.swift',
        'App/MerchantNPCViews.swift',
        'App/ActivityDetailView.swift',
    ),
    (
        '9648d423ec3e1648ef6b764a7ca708b91f9c005f096fd2c683760c3267ee9b84',
        'bd0b132835c2e2fdc19ed7dcacc87de08d435cff8e828599b40a11eb261940c5',
        '3b0c38a01132ed9bfbb164b0b2b5e81113df6869e0afa48376df3afded7ae19f',
        '3d2f2b5636417c8e95f278020cc96fe0fba1f44791d905030465603c8772d00f',
        '1b1c35dfe2d0bc2144484bc9a73ad816d98ea89df76cf221044c6ffcbfc30443',
        '1ca6e11dbd92af3fca350a0735dfb39cde70ec3faf8ca186593bc60595b681bc',
        'd2e42ca2521e0044cc4d61840c7f637b6bc0a189b6f119eef79746e3687bb378',
        '56e188e6c1cf80050ea642a4ebe53a7fd03645d0dda9635ce189b7e9a4d033f0',
        '75efa83972f6265c69849969b1e40de488508d58e04ffda9f1a8530f17bb4012',
        '6cb6e94542efe2d4b25a163b5be5d504961c5c42694c4ce31722f502c865637b',
        'ff06016dfbaf4c95c82fee87379905d8e6ea9261ab8e0fa74430a7f56eee91a7',
        'b3977dd4e64edeaa9ecf8b168cf0a6de8ad53bb1a9f8d71ae1099f03dfda9899',
        '91de455344f7d34dda4880b507847a5dd1730d8f8224ea377bc2b7dee772bc1a',
        'cab6567b0fd9969b1b38f3632d1e786cfcad84de419aab21c6ffb54004749829',
        '7664daffbe1e9846bac66b8de675761fffd2cd0e93b2e792699ae04cae5c1128',
        'a3ef38e33c2154a8c9951d0abbf3ca3cf234c69ac92330572efdf7a75d14ccd5',
        '3553c0524eac4f2858801c6cefe2b65b932e8e50a075faba8a48e6f01ace9c35',
    ),
))
class ProjectWorkspaceContracts(unittest.TestCase):
    def setUp(self):
        self.app=(ROOT/'App/MerchantProjectsView.swift').read_text()
        self.views=(ROOT/'App/MerchantContentViews.swift').read_text()
        self.service=(ROOT/'Core/MerchantContentService.swift').read_text()
    def test_exact_inverse_of_all_five_existing_files(self):
        for path,blocks in INVERSE_BLOCKS.items():
            lines=(ROOT/path).read_text().splitlines(keepends=True)
            for block in reversed(blocks):
                self.assertEqual(lines[block['post_start']:block['post_end']],block['after'],path)
                lines[block['post_start']:block['post_end']]=block['before']
            self.assertEqual(hashlib.sha256(''.join(lines).encode()).hexdigest(),BASE_HASHES[path],path)
    def test_existing_transactions_grants_sensitive_routes_and_invitation_remain_exact(self):
        for path,expected in PROTECTED.items():self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),expected,path)
    def test_project_home_is_the_only_core_request_change(self):
        blocks=INVERSE_BLOCKS['Core/MerchantContentService.swift'];self.assertEqual(len(blocks),1)
        self.assertEqual(''.join(blocks[0]['before']).strip(),'case .project(let id): value = try await read("api/project/home", .json(optionalTopic(id)), session: s)')
        self.assertIn('fields["scope"] = .string("MERCHANT")',self.service)
        self.assertIn('case .players(let id): value = try await read("api/project/players", .json(optionalTopic(id)), session: s)',self.service)
    def test_server_role_permission_and_current_session_checks_stay_in_place(self):
        for text in ['let access = try await access(session, query: query)','access.allows(.projects)','try ensure(session)','throw MerchantContentFailure.denied']:
            self.assertIn(text,self.service)
        self.assertNotIn('ownerMemberId',self.service)
    def test_only_supplied_service_is_mounted(self):
        home=(ROOT/'App/MerchantHomeView.swift').read_text()
        self.assertIn('MerchantProjectsView(reader: reader, contentService: contentService)',home)
        self.assertIn('if let contentService, presentation.workspaceIsCurrent',self.app)
        for text in ['MerchantContentService(', 'AppSession(', 'URLSession','APIConfiguration(','ProductionFactory','runtimeDependencies']:self.assertNotIn(text,self.app)
    def test_snapshot_binds_access_and_rows_from_the_same_current_read(self):
        for text in ['MerchantLoadModel<MerchantProjectWorkspaceSnapshot>','let access = try await reader.merchantAccess()',
                     'let page = try await reader.merchantProjects(access: access)','guard context == captured, reader.isSignedIn',
                     'return .init(page: page, access: access, context: captured)']:
            self.assertIn(text,self.app)
        self.assertEqual(self.app.count('guard model.value?.id == snapshot.id else { return }'),2)
    def test_current_owner_reader_service_scope_and_authentication_are_bound(self):
        for text in ['readerID = ObjectIdentifier(reader)','revision = reader.sessionRevision','serviceID = service.map { ObjectIdentifier($0) }',
                     'serviceScope = service?.scope','service?.isAuthenticated == true','context == snapshot.context',
                     'snapshot.access.allows(.projects)','snapshot.access.merchantID == value.merchantID']:
            self.assertIn(text,self.app)
    def test_rendered_action_and_selection_require_exact_generation_and_single_row(self):
        for text in ['permit.generation == generation','permit.snapshotID == snapshot.id','snapshot.page.rows.filter({ $0.id == project.id }).count == 1',
                     'selected.generation == generation','selected.snapshotID == snapshot.id','route?.id == value.id','selected.id == value.selectionID']:
            self.assertIn(text,self.app)
    def test_only_topic_rows_can_open_workspace_and_failure_keeps_summary_only(self):
        self.assertIn('selected.project.bizType == "topic"',self.app)
        self.assertIn('sourceFresh && selectionIsCurrent',self.app)
        self.assertIn('!model.isLoading && model.errorKey == nil && model.loadedRevision == reader.sessionRevision',self.app)
        self.assertIn('MerchantProjectSummary(project: selected.project',self.app)
        self.assertIn('Text("merchant.summarySnapshot")',self.app)
        self.assertNotIn('ActivityDetailView(',self.app)
    def test_no_auto_entry_or_new_write_request(self):
        self.assertIn('Button("merchant.projectWorkspace.open", action: openWorkspace)',self.app)
        self.assertIn('query: .project(topicID: route.topicID)',self.app)
        for text in ['.perform(','.prepare(','.confirm(','.reconcile(','.retryStation(','.load(.players','UIPasteboard','openURL','UserDefaults']:self.assertNotIn(text,self.app)
    def test_fresh_workspace_store_topic_and_query_must_match(self):
        for text in ['snapshot.query == .project(topicID: topicID)','snapshot.access.merchantID == merchantID',
                     'case .integer(let receivedID) = snapshot.value["topic"]["id"]','return receivedID == topicID']:
            self.assertIn(text,self.app)
        self.assertIn('return snapshot.scope == coordinator.service.scope && MerchantProjectWorkspacePresentation.matches(snapshot: snapshot, topicID: focusedTopicID, merchantID: focusedMerchantID)',self.views)
    def test_queued_and_suspended_loads_are_guarded_without_touching_core_journal(self):
        load=self.views[self.views.index('    func load() async {'):self.views.index('    func prepare(')]
        self.assertLess(load.index('guard projectEntryIsCurrent?() != false'),load.index('await coordinator.load()'))
        self.assertIn('if projectEntryIsCurrent?() == false { coordinator.invalidate() }',load)
        self.assertIn('projectEntryIsCurrent: (() -> Bool)? = nil',self.views)
        self.assertNotIn('journal.',load)
    def test_old_summary_and_navigation_bindings_are_id_bound(self):
        for text in ['let captured = selection?.id','let captured = route?.id','self?.selection?.id == captured',
                     'self?.route?.id == captured','self?.closeSummary(id: captured)']:
            self.assertIn(text,self.app)
        self.assertIn('.sheet(item: presentation.summaryBinding())',self.app)
        self.assertIn('.navigationDestination(item: presentation.workspaceBinding())',self.app)
    def test_scene_departure_and_refresh_retire_original_permits(self):
        for text in ['.onChange(of: context)', '.onChange(of: model.value?.id)', '.onChange(of: scenePhase)',
                     'else { presentation.retire() }','func retire() { active = false; invalidate() }',
                     '.onDisappear { presentation.closeSummary(id: selected.id) }','generation = UUID(); selection = nil; route = nil']:
            self.assertIn(text,self.app)
    def test_obsolete_request_assertion_only_is_corrected(self):
        blocks=INVERSE_BLOCKS['Tests/CoreTests/MerchantContentContractTests.swift']
        removed=''.join(''.join(b['before']) for b in blocks);added=''.join(''.join(b['after']) for b in blocks)
        self.assertEqual(len(blocks),2)
        self.assertIn('testProjectListCarriesMerchantScopeButWorkspaceDoesNotInventScope',removed)
        self.assertIn('decode([String: Int].self',removed)
        self.assertIn('testProjectListAndWorkspaceCarryDocumentedMerchantScope',added)
        self.assertIn('"scope": .string("MERCHANT")',added)
    def test_actual_urlrequest_tests_are_authored_with_negative_server_paths(self):
        tests=(ROOT/'Tests/CoreTests/MerchantProjectWorkspaceScopeTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',tests)),10)
        for text in ['testEmployeeWorkspaceUsesExactMerchantScopeAndExistingRoute','testServerEmployeeDenialIsNeverConvertedIntoMembership',
                     'testMissingPermissionStopsBeforeWorkspaceRequest','testAccountChangeDuringAccessPreventsWorkspaceDispatch',
                     'testExistingSensitivePlayersRequestRemainsByteEquivalent','testWorkspaceReadDoesNotActivateWrites']:
            self.assertIn(text,tests)
    def test_hosted_lifecycle_tests_are_authored(self):
        tests=(ROOT/'Tests/AppUnitTests/MerchantProjectWorkspaceEntryTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test',tests)),24)
        for text in ['testOldRenderedPermitFailsAfterRetirementAndSameReaderReturn','testOldSummaryBindingCannotDismissReopenedSummary',
                     'testOldWorkspaceBindingCannotPopReopenedWorkspace','testSuspendedReadCannotPublishAfterEntryRetirement',
                     'testFreshWorkspaceMustMatchExactRequestedStoreTopicAndQuery','testFailedOrInProgressReloadCannotOpenWorkspaceFromRetainedSummary']:
            self.assertIn(text,tests)
    def test_focused_projection_gate_precedes_status_and_covers_all_actions(self):
        document=self.views[self.views.index('@MainActor struct MerchantContentDocumentView'):self.views.index('@MainActor struct MerchantContentStatus')]
        self.assertLess(document.index('if !model.projectPresentationIsCurrent'),document.index('MerchantContentStatus(model: model)'))
        self.assertIn('focusedTopicID: focusedTopicID, focusedMerchantID: focusedMerchantID, projectEntryIsCurrent:',document)
        self.assertIn('c.isCurrent && model.projectActionsAreCurrent ? c.review : nil',document)
        model=self.views[self.views.index('@MainActor final class MerchantContentViewModel'):self.views.index('struct MerchantContentBoundary')]
        self.assertEqual(model.count('guard projectActionsAreCurrent else { return }'),4)
        self.assertIn('else if !projectPresentationIsCurrent {',model)
        self.assertIn('rejectedProjectProjection = true',model)
        self.assertIn('return projectPresentationIsCurrent && coordinator.isCurrent && coordinator.snapshot != nil',model)
        self.assertNotIn('journal.',model)
    def test_actual_model_pending_wrong_owner_regressions_are_authored(self):
        tests=(ROOT/'Tests/AppUnitTests/MerchantProjectWorkspaceEntryTests.swift').read_text()
        for text in ['testWrongStorePendingProjectionCannotPresentRecoverOrPerformAndJournalRemainsExact',
                     'testWrongTopicQueryAndResponseScopeAreRejectedByActualModel',
                     'testSuspendedWrongStoreReadCannotAcceptPendingProjection',
                     'testMatchingPendingProjectionKeepsExistingExplicitRecoveryBehavior',
                     'testRejectedResponseCanOnlyRecoverThroughAnotherExplicitMatchingLoad',
                     'testMissingFocusedIdentityFailsClosedOnlyForGuardedEntry',
                     'XCTAssertEqual(try source.journal.records(), [record])',
                     'XCTAssertEqual(source.reconcileCount, 0); XCTAssertEqual(source.retryCount, 0)']:
            self.assertIn(text,tests)
    def test_localization_fragment_covers_only_new_labels(self):
        fragment=json.loads((ROOT/'Resources/MerchantProjectWorkspaceLocalizations.fragment.json').read_text())
        keys=set(re.findall(r'merchant\.projectWorkspace\.[A-Za-z]+',self.app+self.views));self.assertEqual(keys,set(fragment));self.assertEqual(len(keys),3)
        for value in fragment.values():self.assertEqual(set(value['localizations']),{'en','zh-Hans'})
        self.assertIn('server checks access again',fragment['merchant.projectWorkspace.explanation']['localizations']['en']['stringUnit']['value'])

if __name__=='__main__':unittest.main(verbosity=2)
