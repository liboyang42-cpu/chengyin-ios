import SwiftUI

/// Injectable local closure for the purchased-detail version compare / upgrade-draft flow.
/// CompareModVersions / UpgradeInstallDraft have no reviewed backend, so production wiring stays nil
/// (no entry is shown). `compare` must return a presentation built only from trusted facts
/// (verified license term, real versions, server coverage); returning nil means "unknown" and hides the flow.
/// `saveDraft` stores the confirmed request locally only; it never sends anything.
struct WorkshopPurchasedUpgradeHandlers {
    let compare: @MainActor (WorkshopPurchasedItem) async -> WorkshopModUpgradePresentation?
    let saveDraft: @MainActor (WorkshopUpgradeDraftRequest) -> Void
    init(compare: @escaping @MainActor (WorkshopPurchasedItem) async -> WorkshopModUpgradePresentation?,
         saveDraft: @escaping @MainActor (WorkshopUpgradeDraftRequest) -> Void) {
        self.compare = compare; self.saveDraft = saveDraft
    }
}
typealias WorkshopPurchasedUpgradeFactory = () -> WorkshopPurchasedUpgradeHandlers?

/// Detail-page entry: compare versions → existing upgrade sheet → local draft → dismiss back to detail.
@MainActor struct WorkshopPurchasedUpgradeEntry: View {
    let item: WorkshopPurchasedItem
    let handlers: WorkshopPurchasedUpgradeHandlers
    @State private var presentation: WorkshopModUpgradePresentation?
    @State private var checking = false
    @State private var unavailable = false
    @State private var showing = false
    @State private var draftSaved = false
    var body: some View {
        Section {
            Button {
                guard !checking else { return }
                checking = true; unavailable = false
                Task {
                    let result = await handlers.compare(item)
                    checking = false
                    if let result, result.preview.installed.versionId == item.purchasedVersionId, result.preview.installed.moduleId == item.moduleId {
                        presentation = result; showing = true
                    } else { presentation = nil; unavailable = true }
                }
            } label: { Text(verbatim: "比较版本 / 升级草稿") }
                .disabled(checking)
                .accessibilityIdentifier("workshopPurchased.upgrade.compare")
            if checking { ProgressView() }
            if unavailable { Text(verbatim: "暂无可信的新版本信息，无法比较。").font(.footnote).accessibilityIdentifier("workshopPurchased.upgrade.unavailable") }
            if draftSaved { Text(verbatim: "已保存本地升级草稿；现有版本与场次保持不变。").font(.footnote).accessibilityIdentifier("workshopPurchased.upgrade.draftSaved") }
        }
        .sheet(isPresented: $showing) {
            if let presentation {
                NavigationStack {
                    WorkshopModUpgradeSheetView(presentation: presentation) { draft in
                        handlers.saveDraft(draft); draftSaved = true; showing = false
                    }
                    .navigationTitle(Text(verbatim: "版本比较"))
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button { showing = false } label: { Text(verbatim: "返回") }.accessibilityIdentifier("workshopPurchased.upgrade.back") } }
                }
            }
        }
    }
}
