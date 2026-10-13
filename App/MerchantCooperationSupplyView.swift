import SwiftUI

@MainActor final class MerchantSupplyContextOwner: ObservableObject {
    private var source: MerchantContentSupplyContext?
    private var readerID: ObjectIdentifier?
    private var session: CoopFlowSession?
    private(set) var revision = UUID()
    func bind(_ source: MerchantContentSupplyContext, reader: any CoopFlowReading) -> UUID {
        if self.source != source || readerID != ObjectIdentifier(reader) || session != reader.session {
            self.source = source; readerID = ObjectIdentifier(reader); session = reader.session; revision = UUID()
        }
        return revision
    }
    func accepts(_ captured: UUID, reader: any CoopFlowReading) -> Bool {
        revision == captured && readerID == ObjectIdentifier(reader) && session != nil && session == reader.session
    }
}

/// Source-typed navigation only. These forms preview frozen local requests; no dispatcher is mounted.
@MainActor struct MerchantCooperationSupplyView: View {
    let source: MerchantContentSupplyContext
    let reader: any CoopFlowReading
    @StateObject private var sourceOwner = MerchantSupplyContextOwner()
    @State private var templates: [CoopFlowJSON] = []
    @State private var loadedSession: CoopFlowSession?
    @State private var loadedRevision: UUID?
    @State private var failed = false
    private var context: CoopFlowOfferContext? {
        guard let raw = source.termsMode, let mode = CoopFlowOfferContext.TermsMode(rawValue: raw) else { return nil }
        return try? CoopFlowOfferContext(chapterID: source.chapterID, termsMode: mode,
            offerID: source.canReconfirmOrPause ? source.offerID : nil)
    }
    var body: some View {
        let capturedRevision = sourceOwner.bind(source, reader: reader)
        Group {
            if reader.session == nil { Text("cooperation.login") }
            else if let context {
                if source.canReconfirmOrPause {
                    CoopFlowSupplyManagementView(context: context, canManageCircleSupply: source.canReconfirmOrPause)
                } else if source.canEnroll {
                    if context.termsMode != .perk || (loadedRevision == capturedRevision && loadedSession != nil && loadedSession == reader.session) {
                        CoopFlowOfferEditor(context: context, eligibleTemplates: templates,
                            circleMode: !(source.circleThemeCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            sourceIsCurrent: { sourceOwner.accepts(capturedRevision, reader: reader) })
                            .id(capturedRevision)
                    } else if failed { Text("coopflow.read.failed") }
                    else { ProgressView("cooperation.loading") }
                } else { Text("coopflow.invalid") }
            } else { Text("merchant.content.supplyTermsUnknown") }
        }
        .task(id: capturedRevision) {
            templates = []; loadedSession = nil; loadedRevision = nil; failed = false
            guard source.canEnroll, context?.termsMode == .perk, let captured = reader.session else { return }
            do {
                let result = try await reader.read(.templates, isCurrent: { sourceOwner.accepts(capturedRevision, reader: reader) })
                guard !Task.isCancelled, sourceOwner.accepts(capturedRevision, reader: reader), reader.session == captured else { return }
                templates = (result.rows ?? []).filter {
                    (CoopFlowMoney($0["retailValue"]).amount ?? 0) > 0 && ($0["quota"].integer ?? 0) > 0
                }
                loadedSession = captured; loadedRevision = capturedRevision
            } catch {
                guard !Task.isCancelled, sourceOwner.accepts(capturedRevision, reader: reader), reader.session == captured else { return }
                failed = true
            }
        }
        .privacySensitive()
    }
}
