import SwiftUI

/// Source-typed navigation only. These forms preview frozen local requests; no dispatcher is mounted.
@MainActor struct MerchantCooperationSupplyView: View {
    let source: MerchantContentSupplyContext
    let reader: any CoopFlowReading
    @State private var templates: [CoopFlowJSON] = []
    @State private var loadedSession: CoopFlowSession?
    @State private var failed = false
    private var context: CoopFlowOfferContext? {
        guard let raw = source.termsMode, let mode = CoopFlowOfferContext.TermsMode(rawValue: raw) else { return nil }
        return try? CoopFlowOfferContext(chapterID: source.chapterID, termsMode: mode,
            offerID: source.canReconfirmOrPause ? source.offerID : nil)
    }
    var body: some View {
        Group {
            if reader.session == nil { Text("cooperation.login") }
            else if let context {
                if source.canReconfirmOrPause {
                    CoopFlowSupplyManagementView(context: context, canManageCircleSupply: source.canReconfirmOrPause)
                } else if source.canEnroll {
                    if context.termsMode != .perk || (loadedSession != nil && loadedSession == reader.session) {
                        CoopFlowOfferEditor(context: context, eligibleTemplates: templates)
                    } else if failed { Text("coopflow.read.failed") }
                    else { ProgressView("cooperation.loading") }
                } else { Text("coopflow.invalid") }
            } else { Text("merchant.content.supplyTermsUnknown") }
        }
        .task(id: "\(reader.session?.accountID ?? 0):\(reader.session?.epoch ?? 0)") {
            templates = []; loadedSession = nil; failed = false
            guard source.canEnroll, context?.termsMode == .perk, let captured = reader.session else { return }
            do {
                let result = try await reader.read(.templates)
                guard !Task.isCancelled, reader.session == captured else { return }
                templates = (result.rows ?? []).filter {
                    (CoopFlowMoney($0["retailValue"]).amount ?? 0) > 0 && ($0["quota"].integer ?? 0) > 0
                }
                loadedSession = captured
            } catch {
                guard !Task.isCancelled, reader.session == captured else { return }
                failed = true
            }
        }
        .privacySensitive()
    }
}
