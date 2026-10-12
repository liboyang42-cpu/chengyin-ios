import SwiftUI

@MainActor final class CoopPoolApplicationModel: ObservableObject {
    struct Context: Equatable {
        let session: CoopFlowSession
        let readerID: ObjectIdentifier
        let generation: UUID
        let selection: CoopPoolApplicationSelection
        init?(reader: any CoopFlowReading, topicID: Int, pool: CoopFlowJSON?, loadedSession: CoopFlowSession?, generation: UUID) {
            guard let loadedSession, loadedSession == reader.session, let pool,
                  let selection = try? CoopPoolApplicationSelection(pool: pool, topicID: topicID) else { return nil }
            session = loadedSession; readerID = ObjectIdentifier(reader); self.generation = generation; self.selection = selection
        }
    }
    struct Session: Identifiable, Equatable { let id = UUID(); let context: Context }
    struct Review: Identifiable {
        let id = UUID()
        let sessionID: UUID
        let messageBytes: Data
        let operation: CoopFlowMutation
    }
    @Published private(set) var session: Session?
    private var bound: Context?
    private var visible = false
    private var reviewID: UUID?
    func bind(_ context: Context?) { bound = context }
    func appear() { visible = true }
    func leave() { visible = false; cancel() }
    func open(context: Context?, reader: any CoopFlowReading) {
        guard visible, session == nil, let context, bound == context, context.session == reader.session,
              context.readerID == ObjectIdentifier(reader) else { return }
        reviewID = nil; session = .init(context: context)
    }
    func isCurrent(_ candidate: Session, context: Context?, reader: any CoopFlowReading) -> Bool {
        visible && session?.id == candidate.id && bound == candidate.context && context == candidate.context &&
        candidate.context.session == reader.session && candidate.context.readerID == ObjectIdentifier(reader)
    }
    func cancel() { session = nil; reviewID = nil }
    func cancel(id: UUID) { guard session?.id == id else { return }; cancel() }
    func invalidateReview(sessionID: UUID) { guard session?.id == sessionID else { return }; reviewID = nil }
    func review(message: String, session: Session, context: Context?, reader: any CoopFlowReading) -> Review? {
        guard isCurrent(session, context: context, reader: reader),
              let draft = try? CoopPoolApplicationDraft(topicID: session.context.selection.topicID, message: message),
              let operation = try? draft.mutation() else { return nil }
        let review = Review(sessionID: session.id, messageBytes: Data(message.utf8), operation: operation)
        reviewID = review.id; return review
    }
    func allows(_ review: Review, session: Session, message: String, context: Context?, reader: any CoopFlowReading) -> Bool {
        isCurrent(session, context: context, reader: reader) && reviewID == review.id && review.sessionID == session.id &&
        review.messageBytes == Data(message.utf8)
    }
}

/// The pool row only requests entry; it never owns presentation or retires a draft.
@MainActor struct CoopPoolApplicationEntry: View {
    let reader: any CoopFlowReading
    let topicID: Int
    let sourcePool: () -> CoopFlowJSON?
    let sourceSession: () -> CoopFlowSession?
    let sourceGeneration: () -> UUID
    let sourceIsCurrent: () -> Bool
    @ObservedObject var model: CoopPoolApplicationModel
    @ObservedObject var owner: CoopPoolApplicationOwnerBinding
    @Environment(\.scenePhase) private var scenePhase
    private var context: CoopPoolApplicationModel.Context? {
        guard sourceIsCurrent() else { return nil }
        return .init(reader: reader, topicID: topicID, pool: sourcePool(), loadedSession: sourceSession(), generation: sourceGeneration())
    }
    var body: some View {
        Button("coopflow.apply") {
            guard scenePhase == .active, model.session == nil, let current = context else { return }
            owner.open(context: current, reader: reader, model: model)
        }.disabled(!owner.permits(context: context, reader: reader) || model.session != nil || scenePhase != .active)
            .accessibilityIdentifier("club.poolApplication.open")
        if context == nil { Text("coopflow.poolMessage.unavailable").font(.footnote) }
    }
}

/// Only the stable host may replace this source proof. Rows cannot authorize their own old context.
@MainActor final class CoopPoolApplicationOwnerBinding: ObservableObject {
    @Published private(set) var source: CoopPoolApplicationHost.Source?
    func synchronize(_ current: CoopPoolApplicationHost.Source, model: CoopPoolApplicationModel) {
        guard source != current else { return }
        model.bind(nil); model.cancel(); source = current
    }
    func leave(model: CoopPoolApplicationModel) { source = nil; model.bind(nil); model.leave() }
    func permits(context: CoopPoolApplicationModel.Context?, reader: any CoopFlowReading) -> Bool {
        guard let source, source.isCurrent, let context else { return false }
        return source.readerID == ObjectIdentifier(reader) && context.readerID == source.readerID &&
            source.session == reader.session && source.loadedSession == source.session &&
            context.session == source.session && context.generation == source.generation &&
            source.poolBytes == context.selection.sourcePoolBytes
    }
    func open(context: CoopPoolApplicationModel.Context, reader: any CoopFlowReading, model: CoopPoolApplicationModel) {
        guard model.session == nil, permits(context: context, reader: reader) else { return }
        model.bind(context); model.open(context: context, reader: reader)
    }
}

/// Stable read-page ownership; source changes retire state even when its row is offscreen.
@MainActor struct CoopPoolApplicationHost: View {
    struct Source: Equatable {
        let readerID: ObjectIdentifier
        let session: CoopFlowSession?
        let loadedSession: CoopFlowSession?
        let generation: UUID
        let poolBytes: Data?
        let isCurrent: Bool
    }
    let reader: any CoopFlowReading
    let sourcePool: () -> CoopFlowJSON?
    let sourceSession: () -> CoopFlowSession?
    let sourceGeneration: () -> UUID
    let sourceIsCurrent: () -> Bool
    @ObservedObject var model: CoopPoolApplicationModel
    @ObservedObject var owner: CoopPoolApplicationOwnerBinding
    @Environment(\.scenePhase) private var scenePhase
    private var source: Source {
        .init(readerID: ObjectIdentifier(reader), session: reader.session, loadedSession: sourceSession(),
            generation: sourceGeneration(), poolBytes: sourcePool().flatMap { try? $0.canonical() }, isCurrent: sourceIsCurrent() && scenePhase == .active)
    }
    private func context(topicID: Int) -> CoopPoolApplicationModel.Context? {
        guard sourceIsCurrent(), scenePhase == .active else { return nil }
        return .init(reader: reader, topicID: topicID, pool: sourcePool(), loadedSession: sourceSession(), generation: sourceGeneration())
    }
    var body: some View {
        Color.clear.background {
            if let session = model.session {
                CoopPoolApplicationOwner(session: session, model: model, reader: reader,
                    currentContext: { context(topicID: session.context.selection.topicID) })
                    .id(session.id)
            }
        }
        .onAppear { owner.synchronize(source, model: model); model.appear() }
        .onDisappear { owner.leave(model: model) }
        .onChange(of: source) { _, current in owner.synchronize(current, model: model) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { owner.synchronize(source, model: model); model.appear() }
            else { owner.leave(model: model) }
        }
    }
}

@MainActor struct CoopPoolApplicationOwner: View {
    let session: CoopPoolApplicationModel.Session
    @ObservedObject var model: CoopPoolApplicationModel
    let reader: any CoopFlowReading
    let currentContext: () -> CoopPoolApplicationModel.Context?
    var presentationBinding: Binding<Bool> {
        Binding(get: { model.session?.id == session.id }, set: { shown in
            if !shown { model.cancel(id: session.id) }
        })
    }
    var body: some View {
        Color.clear.sheet(isPresented: presentationBinding) {
            NavigationStack {
                CoopPoolApplicationEditor(model: model, session: session, reader: reader, currentContext: currentContext)
            }
        }
    }
}

@MainActor private struct CoopPoolApplicationEditor: View {
    @ObservedObject var model: CoopPoolApplicationModel
    let session: CoopPoolApplicationModel.Session
    let reader: any CoopFlowReading
    let currentContext: () -> CoopPoolApplicationModel.Context?
    @State private var message = ""
    @State private var review: CoopPoolApplicationModel.Review?
    @State private var showReview = false
    @State private var confirmDiscard = false
    private var current: Bool { model.isCurrent(session, context: currentContext(), reader: reader) }
    private var valid: Bool { message.unicodeScalars.count <= CoopPoolApplicationDraft.maximumMessageScalars }
    private var messageBinding: Binding<String> {
        Binding(get: { message }, set: { value in
            guard current else { return }
            model.invalidateReview(sessionID: session.id); review = nil; message = value
        })
    }
    var body: some View {
        Form {
            if current {
                Section {
                    LabeledContent("coopflow.field.topicId", value: String(session.context.selection.topicID))
                    if let name = session.context.selection.topicName { Text(verbatim: name) }
                    Text("coopflow.poolMessage.intent").font(.footnote)
                }
                Section("coopflow.poolMessage.optional") {
                    TextEditor(text: messageBinding).frame(minHeight: 140)
                        .accessibilityLabel("coopflow.poolMessage.optional").accessibilityIdentifier("club.poolApplication.message")
                    Text("coopflow.poolMessage.length \(message.unicodeScalars.count)")
                    if !valid { Text("coopflow.poolMessage.tooLong").foregroundStyle(.red) }
                }
                Button("coopflow.reviewAction") {
                    guard let value = model.review(message: message, session: session, context: currentContext(), reader: reader) else { return }
                    review = value; showReview = true
                }.disabled(!valid).accessibilityIdentifier("club.poolApplication.review")
            } else { Text("coopflow.poolMessage.unavailable") }
            CoopFlowSafetyNotice()
        }
        .navigationTitle("coopflow.apply")
        .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button("action.cancel") {
                guard current else { model.cancel(id: session.id); return }
                if message.isEmpty { model.cancel(id: session.id) } else { confirmDiscard = true }
            }
        } }
        .interactiveDismissDisabled(!message.isEmpty)
        .confirmationDialog("coopflow.poolMessage.discardTitle", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("coopflow.poolMessage.discard", role: .destructive) { model.cancel(id: session.id) }
            Button("coopflow.poolMessage.keep", role: .cancel) {}
        }
        .navigationDestination(isPresented: $showReview) {
            if let review, model.allows(review, session: session, message: message, context: currentContext(), reader: reader) {
                CoopFlowRequestPreview(operation: review.operation)
            } else { Text("coopflow.poolMessage.unavailable") }
        }
    }
}
