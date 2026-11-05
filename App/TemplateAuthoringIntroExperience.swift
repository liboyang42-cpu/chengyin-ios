import SwiftUI
import Combine

@MainActor final class TemplateAuthoringIntroController: ObservableObject {
    struct Scope: Equatable {
        let owner: TemplateAuthoringSession?
        let namespace: Data?
        let authorization: Data?
        let identity: TemplateAuthoringIdentity
        let metadata: UUID
        let media: UUID
        let revision: Int
        let draft: Data?
        let canRead: Bool
        let canEdit: Bool
        let busy: Bool
        let reviewing: Bool
        let reader: ObjectIdentifier?
        let readerScope: Data?
        let configured: Bool
    }
    struct Permit: Equatable { let generation: UUID; let scope: Scope }
    enum Phase: Equatable { case idle, loading, ready, empty, failed, unavailable }
    private let model: TemplateAuthoringModel
    private let reader: (any DiscoveryReading)?
    private var observation: AnyCancellable?
    private var generation = UUID()
    private var active = false
    private var originalScope: Scope?
    private var requestID: UUID?
    private var request: Task<Void,Never>?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var examples: TemplateAuthoringIntroExamples?
    init(model: TemplateAuthoringModel, reader: (any DiscoveryReading)?) {
        self.model = model; self.reader = reader
        observation = model.objectWillChange.sink { [weak self] _ in self?.retire() }
    }
    func scope() -> Scope {
        let owner = model.coordinator.session, encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys,.withoutEscapingSlashes]
        return .init(owner:owner, namespace:owner.map { Data($0.namespace.utf8) }, authorization:owner.map { Data($0.authorizationRevision.utf8) },
                     identity:model.coordinator.identity, metadata:model.metadataGeneration, media:model.mediaReviewGeneration, revision:model.revision,
                     draft:try? encoder.encode(model.draft), canRead:model.canReadMetadataDraft, canEdit:model.canEdit, busy:model.busy,
                     reviewing:model.review != nil || model.coordinator.review != nil,
                     reader:reader.map { ObjectIdentifier($0) }, readerScope:reader.map { Data($0.discoveryPresentationIdentity.utf8) }, configured:reader?.isConfigured == true)
    }
    private var current: Bool { active && originalScope == scope() && originalScope?.canRead == true }
    var visibleExamples: TemplateAuthoringIntroExamples? { current ? examples : nil }
    var visiblePhase: Phase { current ? phase : .unavailable }
    var canContinue: Bool { current && model.canEdit && !model.busy && model.review == nil && model.coordinator.review == nil }
    func activate() {
        retire(); originalScope = scope(); active = true
        phase = current && reader?.isConfigured == true ? .idle : .unavailable
    }
    func retire() {
        active = false; generation = UUID(); requestID = nil; request?.cancel(); request = nil
        originalScope = nil; examples = nil; phase = .unavailable
    }
    func permit() -> Permit { .init(generation:generation,scope:scope()) }
    private func accepts(_ permit: Permit) -> Bool { current && permit.generation == generation && permit.scope == scope() }
    @discardableResult func load(_ permit: Permit) -> Task<Void,Never>? {
        guard accepts(permit), requestID == nil else { return nil }
        guard let reader, reader.isConfigured else { phase = .unavailable; return nil }
        let id = UUID(); requestID = id; phase = .loading
        let task = Task { @MainActor [weak self] in
            do {
                let home = try await reader.discoveryTemplateHome()
                guard let self, self.accepts(permit), self.requestID == id, !Task.isCancelled else { return }
                let result = TemplateAuthoringIntroExamples(home:home)
                self.examples = result; self.phase = result.rows.isEmpty ? .empty : .ready
            } catch {
                guard let self, self.accepts(permit), self.requestID == id, !Task.isCancelled else { return }
                // Mini keeps existing real examples when a refresh fails; no invented fallback cards.
                self.phase = self.examples?.rows.isEmpty == false ? .ready : error as? APIError == .notConfigured ? .unavailable : .failed
            }
            guard let self, self.accepts(permit), self.requestID == id else { return }
            self.requestID = nil; self.request = nil
        }
        request = task; return task
    }
    func continueAction(_ advance: @escaping () -> Void) -> () -> Void {
        let captured = permit()
        return { [weak self] in
            guard let self, self.accepts(captured), self.canContinue else { return }
            self.retire(); advance()
        }
    }
}

/// Real examples inform this existing introduction; both exits enter the original naming step.
@MainActor struct TemplateAuthoringIntroExperience: View {
    @ObservedObject var model: TemplateAuthoringModel
    let reader: (any DiscoveryReading)?
    let onContinue: () -> Void
    @StateObject private var controller: TemplateAuthoringIntroController
    @State private var readerRevision: UInt64 = 0
    @Environment(\.scenePhase) private var scenePhase
    private struct LoadKey: Equatable { let scope: TemplateAuthoringIntroController.Scope; let readerRevision: UInt64; let active: Bool }
    init(model: TemplateAuthoringModel, reader: (any DiscoveryReading)?, onContinue: @escaping () -> Void) {
        self.model = model; self.reader = reader; self.onContinue = onContinue
        _controller = StateObject(wrappedValue:.init(model:model,reader:reader))
    }
    var body: some View {
        let key = LoadKey(scope:controller.scope(),readerRevision:readerRevision,active:scenePhase == .active)
        let permit = controller.permit(), advance = controller.continueAction(onContinue)
        // Mini-program publish/template-intro: real featured covers, the two-line value
        // proposition, then one primary action (开始创建). No captions, no second exit.
        VStack(alignment:.leading,spacing:20) {
            if let examples = controller.visibleExamples, !examples.rows.isEmpty {
                HStack(alignment:.top,spacing:10) {
                    ForEach(Array(examples.rows.enumerated()),id:\.offset) { index, item in
                        VStack(alignment:.leading,spacing:6) {
                            DiscoveryArtwork(source:item.imgUrl,height:150)
                                .frame(maxWidth:.infinity)
                                .clipShape(RoundedRectangle(cornerRadius:14,style:.continuous))
                            Text(verbatim:examples.categoryName(at:index))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .accessibilityIdentifier("creatorIntro.example.category.\(index)")
                            Group {
                                if item.title.isEmpty { Text("creatorIntro.unnamed",tableName:"CreatorIntroExamples") }
                                else { Text(verbatim:item.title) }
                            }.font(.footnote.weight(.semibold)).lineLimit(2)
                        }
                        .frame(maxWidth:.infinity,alignment:.leading)
                        .accessibilityElement(children:.combine).accessibilityIdentifier("creatorIntro.example.\(index)")
                    }
                }
            } else {
                switch controller.visiblePhase {
                case .idle,.loading:
                    ProgressView().frame(maxWidth:.infinity,minHeight:150)
                case .failed:
                    VStack(alignment:.leading,spacing:8) {
                        Text("creatorIntro.failed",tableName:"CreatorIntroExamples").font(.footnote).foregroundStyle(.red)
                        Button(action:{ controller.load(permit) }) { Text("creatorIntro.retry",tableName:"CreatorIntroExamples") }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("creatorIntro.retry")
                    }
                case .empty,.ready: Text("creatorIntro.empty",tableName:"CreatorIntroExamples").font(.footnote).foregroundStyle(.secondary)
                case .unavailable: EmptyView()
                }
            }
            VStack(alignment:.leading,spacing:4) {
                Text("publishParity.intro.lead").font(.title3)
                Text("publishParity.intro.tail").font(.title2.bold())
            }
            .fixedSize(horizontal:false,vertical:true)
            .accessibilityElement(children:.combine).accessibilityIdentifier("publishParity.intro.value")
            Button(action:advance) { Text("templateAuthor.begin").frame(maxWidth:.infinity) }
                .buttonStyle(.questifyPrimary).controlSize(.large)
                .disabled(!controller.canContinue || scenePhase != .active).accessibilityIdentifier("templateAuthor.begin")
        }
        .padding(.vertical,8)
        .task(id:key) {
            guard scenePhase == .active else { controller.retire(); return }
            controller.activate(); let task = controller.load(controller.permit()); await task?.value
        }
        .onReceive(reader?.discoveryPresentationChanges ?? Empty<Void,Never>().eraseToAnyPublisher()) { _ in controller.retire(); readerRevision &+= 1 }
        .onChange(of:scenePhase) { _, phase in if phase != .active { controller.retire() } }
        .onDisappear { controller.retire() }
    }
}
