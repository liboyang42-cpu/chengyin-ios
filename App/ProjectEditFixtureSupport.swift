#if DEBUG
import SwiftUI

@MainActor private final class ProjectEditFixtureContext: ObservableObject {
    var session: ProjectEditSession? = try? .init(accountID: 901, epoch: 1, storageNamespace: "synthetic-project-editor")
    let storage = ProjectEditMemoryStorage()
    let service: ProjectEditSyntheticService
    let initial: ProjectEditSnapshot
    let disabled: Bool
    private let releasePublicationScenario: ApprovedTopicReleasePublicationSynthetic.Scenario?
    private let releaseReceiptWriteFailure: Bool
    private lazy var releasePublicationJournal = ApprovedTopicReleasePublicationJournal(storage: storage)
    private lazy var releasePublicationSource: ApprovedTopicReleasePublicationSynthetic? = {
        guard let session, let scenario = releasePublicationScenario else { return nil }
        return try? .init(session: session, scenario: scenario, beforeReply: { [weak self] in
            if self?.releaseReceiptWriteFailure == true { self?.storage.failWrites = true }
        }, currentSession: { [weak self] in self?.session })
    }()
    private let reviewScenario: ApprovedTopicReviewSynthetic.Scenario?
    private let reviewReceiptWriteFailure: Bool
    private let reviewObservationEnabled: Bool
    private let reviewSelectedCoverEnabled: Bool
    private let selectedCoverReleaseBound: Bool
    private let storyAudioEnabled: Bool, storyAudioUnknown: Bool, storyAudioCancelFirst: Bool
    private var audioPickerFirst = true
    private lazy var storyAudioJournal = ProjectStoryAudioJournal(storage: storage)
    private lazy var storyAudioSource: ProjectStoryAudioSynthetic? = {
        guard storyAudioEnabled, let session else { return nil }
        return try? .init(session: session, unknownOnce: storyAudioUnknown, currentSession: { [weak self] in self?.session })
    }()
    var storyAudioPicker: (() -> any ProjectStoryAudioSelecting)? {
        guard let source = storyAudioSource else { return nil }
        return { [weak self] in
            let cancel = self?.storyAudioCancelFirst == true && self?.audioPickerFirst == true
            self?.audioPickerFirst = false
            return ProjectStoryAudioSynthetic.Picker(source.picked, cancelNext: cancel)
        }
    }
    private let storyImageEnabled: Bool
    private lazy var storyImageJournal = ProjectStoryImageJournal(storage: storage)
    private lazy var storyImageSource: ProjectStoryImageSynthetic? = {
        guard storyImageEnabled, let session else { return nil }
        return try? .init(session: session, currentSession: { [weak self] in self?.session })
    }()
    var storyImagePicker: (() -> any OwnedTopicCoverSelecting)? {
        guard let source = storyImageSource else { return nil }; return { ProjectStoryImageSynthetic.Picker(source.picked) }
    }
    private let ownedCoverEnabled: Bool, ownedCoverUnknown: Bool, ownedCoverUnknownUpload: Bool
    private lazy var ownedCoverJournal = OwnedTopicCoverJournal(storage: storage)
    private lazy var ownedCoverSource: OwnedTopicCoverSynthetic? = {
        guard ownedCoverEnabled, let session else { return nil }
        return try? .init(session: session, unknownSelection: ownedCoverUnknown, unknownUpload: ownedCoverUnknownUpload, currentSession: { [weak self] in self?.session })
    }()
    var ownedCoverPicker: (() -> any OwnedTopicCoverSelecting)? {
        guard let source = ownedCoverSource else { return nil }
        return { OwnedTopicCoverSynthetic.Picker(source.picked) }
    }
    private lazy var reviewJournal = ApprovedTopicReviewJournal(storage: storage)
    private lazy var reviewSource: ApprovedTopicReviewSynthetic? = {
        guard let session, let scenario = reviewScenario else { return nil }
        return try? .init(session: session, scenario: scenario, observationEnabled: reviewObservationEnabled, selectedCoverEnabled: reviewSelectedCoverEnabled, selectedCoverReleaseBound: selectedCoverReleaseBound, beforeReceipt: { [weak self] in
            if self?.reviewReceiptWriteFailure == true { self?.storage.failWrites = true }
        }, selectedCoverInput: { [weak self] in self?.ownedCoverSource?.reviewInput }, currentSession: { [weak self] in self?.session })
    }()
    private let releaseReadScenario: ApprovedTopicReleaseSyntheticSource.Scenario?
    @Published var revision: UInt64 = 1
    @Published var mount = UUID()
    @Published var inspection = ""
    private var inspectionSequence = 0
    lazy var store = ProjectEditLocalStore(storage: storage)
    lazy var coordinator = makeCoordinator()
    init(arguments: [String]) {
        disabled = arguments.contains("--project-edit-disabled")
        storyAudioEnabled = arguments.contains("--project-story-audio")
        storyAudioUnknown = arguments.contains("--project-story-audio-unknown")
        storyAudioCancelFirst = arguments.contains("--project-story-audio-cancel-first")
        storyImageEnabled = arguments.contains("--project-story-image")
        ownedCoverEnabled = arguments.contains("--project-owned-cover")
        ownedCoverUnknown = arguments.contains("--project-owned-cover-unknown")
        ownedCoverUnknownUpload = arguments.contains("--project-owned-cover-upload-unknown")
        reviewScenario = arguments.contains("--project-review-request") ? (arguments.contains("--project-review-unknown") ? .unknownOnce : .ready) : nil
        reviewReceiptWriteFailure = arguments.contains("--project-review-receipt-write-failure")
        reviewObservationEnabled = arguments.contains("--project-review-current")
        reviewSelectedCoverEnabled = arguments.contains("--project-review-selected-cover")
        selectedCoverReleaseBound = arguments.contains("--project-frozen-cover-binding")
        releasePublicationScenario = arguments.contains("--project-release-publish") ? (arguments.contains("--project-release-publish-unknown") ? .unknownOnce : .ready) : nil
        releaseReceiptWriteFailure = arguments.contains("--project-release-receipt-write-failure")
        releaseReadScenario = arguments.contains("--project-release-read") ? (arguments.contains("--project-release-changed-once") ? .changedOnce : .ready) : nil
        let scope: ProjectEditScope = arguments.contains("--project-edit-whitelist") ? .whitelist : .full
        var existing = ProjectEditSyntheticFixtures.snapshot(scope: scope)
        if arguments.contains("--project-edit-rich-story") { existing.draft = ProjectEditRichStoryFixtures.draft(); existing.draft.baseRevision = "fixture-r1"; existing.draft.publishToCreative = false }
        if arguments.contains("--project-edit-free-explore") { existing.draft.product = .freeExplore }
        service = ProjectEditSyntheticService(scenario: arguments.contains("--project-edit-unknown") ? .unknown : .accepted, snapshot: existing)
        if arguments.contains("--project-edit-edit") || scope == .whitelist { initial = existing }
        else {
            var draft = arguments.contains("--project-edit-blank") ? ProjectEditDraft(product: existing.draft.product) : (arguments.contains("--project-edit-rich-story") ? ProjectEditRichStoryFixtures.draft() : ProjectEditSyntheticFixtures.draft(product: existing.draft.product))
            if arguments.contains("--project-edit-opening") {
                var chapter = ProjectEditChapter(); chapter.name = "Synthetic opening"; chapter.preserved["opening"] = .bool(true)
                chapter.blocks = [.init(kind: .text, content: "Shared opening story")]; draft.chapters = [chapter]
            }
            if arguments.contains("--project-edit-empty-story"), !draft.chapters.isEmpty { draft.chapters[0].description = ""; draft.chapters[0].nodes = []; draft.chapters[0].blocks = nil }
            if arguments.contains("--project-edit-pending") {
                var node = ProjectEditNode(); node.name = "Pending fixture node"; node.description = "  Raw e\u{301}\t"
                node.longitude = "121.5"; node.latitude = "31.2"; node.templateID = 41
                if arguments.contains("--project-pending-no-chapters") { draft.chapters = [] }
                if arguments.contains("--project-pending-missing-coordinates") { node.longitude = ""; node.latitude = "" }
                node.localMetadata = ["hookText": .string("Untouched hook"), "future": .object(["kept": .bool(true)])]
                draft.pendingMaterials = [.init(node: node)]
            }
            if arguments.contains("--project-edit-prepared-values"), draft.pendingMaterials?.isEmpty == false {
                draft.pendingMaterials?[0].node.description = "Original pending description"
                draft.pendingMaterials?[0].node.imgUrl = "fixture:pending-before"
                draft.pendingMaterials?[0].node.nodeTime = 45; draft.pendingMaterials?[0].node.templateID = 73
            }
            if arguments.contains("--project-edit-prepared-order"), !draft.chapters.isEmpty, !draft.chapters[0].nodes.isEmpty {
                var second = draft.chapters[0].nodes[0]; second.id = UUID().uuidString; second.name = "Second staged node"
                second.description = "Second node description"; second.imgUrl = "fixture:second-staged"; second.nodeTime = 45; second.templateID = 73
                draft.chapters[0].nodes[0].templateID = nil
                let first = draft.chapters[0].nodes[0]
                draft.chapters[0].nodes.append(second)
                draft.chapters[0].blocks = [.init(kind: .text, content: draft.chapters[0].description), .init(kind: .node, nodeID: second.id), .init(kind: .node, nodeID: first.id)]
            }
            if storyImageEnabled || storyAudioEnabled, !draft.chapters.isEmpty {
                draft.preserved["publishMode"] = .string("pro")
                let c = draft.chapters[0]
                draft.chapters[0].blocks = [.init(kind: .text, content: c.description)] + c.nodes.map { .init(kind: .node, nodeID: $0.id) }
            }
            initial = .init(draft: draft)
        }
        storage.failWrites = arguments.contains("--project-edit-pending-failure")
        if arguments.contains("--project-edit-bundle-ack") { service.scenario = .bundlePending }
        if arguments.contains("--project-bundle-ack-write-failure") {
            service.beforeSubmit = { [weak storage] in storage?.failWrites = true }
        }
    }
    func makeCoordinator() -> ProjectEditCoordinator {
        let selected: any ProjectEditServing = disabled ? ProjectEditDisabledService() : service
        let releaseSource = session.flatMap { session in releaseReadScenario.flatMap { scenario in
            try? ApprovedTopicReleaseSyntheticSource(session: session, topicID: initial.topicID ?? 7901, scenario: scenario, selectedCoverEnabled: selectedCoverReleaseBound, currentSession: { [weak self] in self?.session })
        } }
        return .init(initial: initial, service: selected, store: store, releasePreparationSource: releaseSource, releasePublicationSource: releasePublicationSource, releasePublicationJournal: releasePublicationJournal, releaseReviewSource: reviewSource, releaseReviewJournal: reviewJournal, ownedCoverSource: ownedCoverSource, ownedCoverJournal: ownedCoverJournal, storyImageSource: storyImageSource, storyImageJournal: storyImageJournal, storyAudioSource: storyAudioSource, storyAudioJournal: storyAudioJournal, currentSession: { [weak self] in self?.session })
    }
    func inspect() {
        inspectionSequence += 1
        var payload: [String: Any] = ["inspectionSequence": inspectionSequence, "submissionCount": service.submissions.count]
        if let source = releasePublicationSource {
            payload["releasePublishCount"] = source.publishCount; payload["releaseStatusCount"] = source.statusCount
            payload["releaseAllocatedCount"] = source.allocatedCount; payload["releaseRequestIDs"] = source.requestIDs
        }
        if let source = storyAudioSource { payload["storyAudioUploadCount"] = source.uploadCount; payload["storyAudioReference"] = source.reference }
        if let source = storyImageSource { payload["storyImageUploadCount"] = source.uploadCount; payload["storyImageReference"] = source.reference }
        if let source = ownedCoverSource {
            payload["coverUploadCount"] = source.uploadCount; payload["coverSelectCount"] = source.selectCount
            payload["coverStatusCount"] = source.statusCount; payload["coverImageCount"] = source.imageCount
            payload["coverHash"] = source.asset.contentHash; payload["coverRequestIDs"] = source.requestIDs
        }
        if let source = reviewSource {
            payload["reviewObservationCount"] = source.observationCount
            payload["reviewPrepareCount"] = source.prepareCount; payload["reviewSubmitCount"] = source.submitCount
            payload["reviewStatusCount"] = source.statusCount; payload["reviewTaskCount"] = source.taskCount; payload["reviewRequestIDs"] = source.requestIDs
        }
        if let session, let identity = coordinator.identity,
           case .ready(let envelope) = store.load(session: session, identity: identity, baseline: initial.draft),
           let data = try? JSONEncoder().encode(envelope.draft), let json = try? JSONSerialization.jsonObject(with: data) {
            payload["savedDraft"] = json
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { inspection = text }
    }
    func restoreStorageAccess() { storage.failWrites = false; revision += 1 }
    func simulateCurrentReviewApproval() { reviewSource?.simulateObservedStatus(.approved) }
    func signOut() { session = nil; coordinator.synchronizeSession(); revision += 1; mount = UUID() }
    func reopen() { coordinator.leaveScreen(); coordinator = makeCoordinator(); mount = UUID() }
}
@MainActor struct ProjectEditFixtureHostView: View {
    @StateObject private var context = ProjectEditFixtureContext(arguments: ProcessInfo.processInfo.arguments)
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("projectEdit.fixture.signOut") { context.signOut() }.accessibilityIdentifier("projectEdit.fixture.signOut")
                Button("projectEdit.fixture.reopen") { context.reopen() }.accessibilityIdentifier("projectEdit.fixture.reopen")
            }.buttonStyle(.bordered).padding(.horizontal)
            if ProcessInfo.processInfo.arguments.contains("--project-edit-starter-probe") {
                Button("projectStarter.inspectFixture") { context.inspect() }
                    .accessibilityIdentifier("projectStarter.fixtureSnapshot").accessibilityValue(context.inspection)
                    .buttonStyle(.borderless).font(.caption).dynamicTypeSize(.large)
            }
            if ProcessInfo.processInfo.arguments.contains("--project-release-receipt-write-failure") || ProcessInfo.processInfo.arguments.contains("--project-review-receipt-write-failure") {
                Button("approvedRelease.fixture.restoreStorage") { context.restoreStorageAccess() }
                    .accessibilityIdentifier("approvedRelease.fixture.restoreStorage").buttonStyle(.borderless).font(.caption).dynamicTypeSize(.large)
            }
            if ProcessInfo.processInfo.arguments.contains("--project-review-current") {
                Button("Test-only: observed task becomes approved") { context.simulateCurrentReviewApproval() }
                    .accessibilityIdentifier("topicReview.fixture.simulateApproval").buttonStyle(.borderless).font(.caption).dynamicTypeSize(.large)
            }
            if ProcessInfo.processInfo.arguments.contains("--project-owned-cover") {
                Text("Test-only generated cover and in-memory server; no Photos or network")
                    .font(.caption).dynamicTypeSize(.large).accessibilityIdentifier("ownedCover.fixture.scope")
            }
            if ProcessInfo.processInfo.arguments.contains("--project-story-audio") {
                Text("Test-only generated audio bytes and in-memory upload; no document, playback or network")
                    .font(.caption).dynamicTypeSize(.large).accessibilityIdentifier("projectStoryAudio.fixture.scope")
            }
            NavigationStack { ProjectEditView(coordinator: context.coordinator, sessionRevision: context.revision, ownedCoverPicker: context.ownedCoverPicker, storyImagePicker: context.storyImagePicker, storyAudioPicker: context.storyAudioPicker) }.id(context.mount)
        }
    }
}
#endif
