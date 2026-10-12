import SwiftUI

/// Value identity drives preference updates; the live check fences a retained old close/tick.
struct TemplateAuthoringSavedResultSignal: Equatable {
    let result: TemplateAuthoringSavedResult
    let metadata: UUID
    let media: UUID
    let revision: Int
    let draft: Data
    let isCurrent: @MainActor () -> Bool
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.result == rhs.result && lhs.metadata == rhs.metadata && lhs.media == rhs.media &&
        lhs.revision == rhs.revision && lhs.draft == rhs.draft
    }
    @MainActor static func capture(model: TemplateAuthoringModel, eligible: Bool) -> Self? {
        guard eligible, !model.busy, model.review == nil, model.coordinator.review == nil,
              model.canReadMetadataDraft, let result = TemplateAuthoringSavedResult(coordinator: model.coordinator),
              let draft = snapshot(model.draft) else { return nil }
        let metadata = model.metadataGeneration, media = model.mediaReviewGeneration, revision = model.revision
        return .init(result: result, metadata: metadata, media: media, revision: revision, draft: draft, isCurrent: { [weak model] in
            guard let model else { return false }
            return !model.busy && model.review == nil && model.coordinator.review == nil && model.canReadMetadataDraft &&
                model.metadataGeneration == metadata && model.mediaReviewGeneration == media && model.revision == revision &&
                snapshot(model.draft) == draft && result.isCurrent(in: model.coordinator)
        })
    }
    private static func snapshot(_ draft: TemplateAuthoringDraft) -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(draft)
    }
}
/// Observing this exact editable visit is required before a receipt may show as a new success.
/// A terminal receipt restored when opening an editor is not a new save event.
struct TemplateAuthoringSavedResultObservation: Equatable {
    let state: TemplateAuthoringCoordinator.State
    let session: TemplateAuthoringSession?
    let identity: TemplateAuthoringIdentity
    let metadata: UUID
    let revision: Int
    let signal: TemplateAuthoringSavedResultSignal?
    let editableNow: @MainActor () -> Bool
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state == rhs.state && lhs.session == rhs.session && lhs.identity == rhs.identity &&
        lhs.metadata == rhs.metadata && lhs.revision == rhs.revision && lhs.signal == rhs.signal
    }
    @MainActor static func capture(model: TemplateAuthoringModel, eligible: Bool) -> Self? {
        guard eligible else { return nil }
        let session = model.coordinator.session, identity = model.coordinator.identity
        let metadata = model.metadataGeneration, revision = model.revision
        return .init(state: model.coordinator.state, session: session, identity: identity, metadata: metadata, revision: revision,
                     signal: TemplateAuthoringSavedResultSignal.capture(model: model, eligible: eligible), editableNow: { [weak model] in
            guard let model, let session, let current = model.coordinator.session else { return false }
            return model.canEdit && !model.busy && model.coordinator.state == .editing && model.coordinator.identity == identity &&
                TemplateAuthoringSavedResult.exactSession(current, session) && model.metadataGeneration == metadata && model.revision == revision
        })
    }
}
struct TemplateAuthoringSavedResultPreferenceKey: PreferenceKey {
    static let defaultValue: TemplateAuthoringSavedResultObservation? = nil
    static func reduce(value: inout TemplateAuthoringSavedResultObservation?, nextValue: () -> TemplateAuthoringSavedResultObservation?) {
        if let next = nextValue() { value = next }
    }
}

@MainActor struct TemplateAuthoringSavedResultPanel: View {
    let result: TemplateAuthoringSavedResult
    let close: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
            Text("templateSavedResult.title", tableName: "CreatorSavedResult").font(.title2.bold())
            Text(verbatim: result.title).font(.headline)
            Text("templateSavedResult.detail", tableName: "CreatorSavedResult")
            LabeledContent { Text(verbatim: String(result.memberTemplateID.rawValue)) } label: {
                Text("templateSavedResult.identity", tableName: "CreatorSavedResult")
            }
            Text("templateSavedResult.destination", tableName: "CreatorSavedResult").font(.footnote).foregroundStyle(.secondary)
            Button(action: close) { Text("templateSavedResult.openLibrary", tableName: "CreatorSavedResult") }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("templateSavedResult.openLibrary")
        }.padding(24).presentationDetents([.medium]).interactiveDismissDisabled(true)
            .accessibilityIdentifier("templateSavedResult.panel")
    }
}
