import SwiftUI

/// Injectable local closure for the purchased-detail version compare / upgrade-draft flow.
/// CompareModVersions / UpgradeInstallDraft have no reviewed backend, so production wiring stays nil
/// (no entry is shown). `compare` must return a presentation built only from trusted facts
/// (verified license term, real versions, server coverage); returning nil means "unknown" and hides the flow.
/// `saveDraft` stores the confirmed request locally only; it never sends anything. It throws when the write does not finish.
struct WorkshopPurchasedUpgradeHandlers {
    let compare: @MainActor (WorkshopPurchasedItem) async -> WorkshopModUpgradePresentation?
    let saveDraft: @MainActor (WorkshopUpgradeDraftRequest) throws -> Void
    let flow: WorkshopUpgradeFlow?
    init(compare: @escaping @MainActor (WorkshopPurchasedItem) async -> WorkshopModUpgradePresentation?,
         saveDraft: @escaping @MainActor (WorkshopUpgradeDraftRequest) throws -> Void,
         flow: WorkshopUpgradeFlow? = nil) {
        self.compare = compare
        self.saveDraft = saveDraft
        self.flow = flow
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
    @State private var saveFailed = false
    @State private var compareToken: UUID?
    @State private var receipt: WorkshopUpgradeDraftReceipt?
    static func performBeginCompare(checking: inout Bool, unavailable: inout Bool) -> Bool {
        guard !checking else { return false }
        checking = true; unavailable = false; return true
    }
    static func performFinishCompare(item: WorkshopPurchasedItem, result: WorkshopModUpgradePresentation?, checking: inout Bool, unavailable: inout Bool, presentation: inout WorkshopModUpgradePresentation?, showing: inout Bool) {
        checking = false
        if let result, result.useTermPresentation.term.licenseId == item.licenseId, result.preview.installed.versionId == item.purchasedVersionId, result.preview.installed.moduleId == item.moduleId, result.preview.installed.contentHash == item.contentHash {
            presentation = result; showing = true
        } else { presentation = nil; unavailable = true; showing = false }
    }
    static func performAcceptCompare(token: UUID, current: UUID?, item: WorkshopPurchasedItem, result: WorkshopModUpgradePresentation?, checking: inout Bool, unavailable: inout Bool, presentation: inout WorkshopModUpgradePresentation?, showing: inout Bool) {
        guard token == current else { return }
        performFinishCompare(item: item, result: result, checking: &checking, unavailable: &unavailable, presentation: &presentation, showing: &showing)
    }
    static func performSaveDraft(_ draft: WorkshopUpgradeDraftRequest, handlers: WorkshopPurchasedUpgradeHandlers, draftSaved: inout Bool, showing: inout Bool) {
        do {
            try handlers.saveDraft(draft)
            draftSaved = true
            showing = false
        } catch {
            return
        }
    }
    @discardableResult
    static func performCommitDraft(_ draft: WorkshopUpgradeDraftRequest, handlers: WorkshopPurchasedUpgradeHandlers, item: WorkshopPurchasedItem, presentation: WorkshopModUpgradePresentation, token: UUID, current: UUID?, draftSaved: inout Bool, showing: inout Bool, saveFailed: inout Bool, receipt: inout WorkshopUpgradeDraftReceipt?) throws -> WorkshopUpgradeDraftReceipt? {
        do {
            guard token == current else { throw WorkshopUpgradeDraftIssue.stalePresentation }
            if let flow = handlers.flow {
                let saved = try flow.commit(item: item, presentation: presentation, confirmedByBuyer: true, requestId: draft.requestId, generation: token)
                guard saved.persisted, saved.fromVersionId == item.purchasedVersionId, saved.fromContentHash == item.contentHash else { throw WorkshopUpgradeDraftIssue.saveFailed }
                receipt = saved
                draftSaved = true
                showing = false
                saveFailed = false
                return saved
            }
            try handlers.saveDraft(draft)
            draftSaved = true
            showing = false
            saveFailed = false
            receipt = nil
            return nil
        } catch {
            saveFailed = true
            throw error
        }
    }
    static func performRestore(item: WorkshopPurchasedItem, handlers: WorkshopPurchasedUpgradeHandlers, draftSaved: inout Bool, receipt: inout WorkshopUpgradeDraftReceipt?) {
        guard let flow = handlers.flow else { return }
        do {
            if let restored = try flow.restore(item: item), restored.persisted {
                receipt = restored
                draftSaved = true
            }
        } catch {
            receipt = nil
        }
    }
    static func performDismissSheet(showing: inout Bool) { showing = false }
    static func performCancel(showing: inout Bool, compareToken: inout UUID?, flow: WorkshopUpgradeFlow?) {
        flow?.cancel()
        compareToken = nil
        showing = false
    }
    var body: some View {
        Section {
            Button {
                guard Self.performBeginCompare(checking: &checking, unavailable: &unavailable) else { return }
                let token: UUID
                if let flow = handlers.flow {
                    do { token = try flow.begin(item: item) }
                    catch { checking = false; unavailable = true; return }
                } else { token = UUID() }
                compareToken = token
                Task {
                    let result = await handlers.compare(item)
                    Self.performAcceptCompare(token: token, current: compareToken, item: item, result: result, checking: &checking, unavailable: &unavailable, presentation: &presentation, showing: &showing)
                }
            } label: { Text(verbatim: "比较版本 / 升级草稿") }
                .disabled(checking)
                .accessibilityIdentifier("workshopPurchased.upgrade.compare")
            if checking {
                ProgressView()
                Button {
                    Self.performCancel(showing: &showing, compareToken: &compareToken, flow: handlers.flow)
                    checking = false
                } label: { Text(verbatim: "取消") }
                    .accessibilityIdentifier("workshopPurchased.upgrade.cancelCompare")
            }
            if unavailable { Text(verbatim: "暂无可信的新版本信息，无法比较。").font(.footnote).accessibilityIdentifier("workshopPurchased.upgrade.unavailable") }
            if draftSaved { Text(verbatim: receipt.map { "已保存本地升级草稿 \($0.requestId)；现有版本与场次保持不变。" } ?? "已保存本地升级草稿；现有版本与场次保持不变。").font(.footnote).accessibilityIdentifier("workshopPurchased.upgrade.draftSaved") }
            if saveFailed { Text(verbatim: "升级草稿没有保存，现有版本与场次保持不变。").font(.footnote).accessibilityIdentifier("workshopPurchased.upgrade.saveFailed") }
        }
        .onAppear { Self.performRestore(item: item, handlers: handlers, draftSaved: &draftSaved, receipt: &receipt) }
        .sheet(isPresented: $showing) {
            if let presentation {
                NavigationStack {
                    WorkshopModUpgradeSheetView(presentation: presentation) { draft in
                        guard let token = compareToken else { throw WorkshopUpgradeDraftIssue.stalePresentation }
                        _ = try Self.performCommitDraft(draft, handlers: handlers, item: item, presentation: presentation, token: token, current: compareToken, draftSaved: &draftSaved, showing: &showing, saveFailed: &saveFailed, receipt: &receipt)
                    }
                    .navigationTitle(Text(verbatim: "版本比较"))
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button { Self.performCancel(showing: &showing, compareToken: &compareToken, flow: handlers.flow) } label: { Text(verbatim: "返回") }.accessibilityIdentifier("workshopPurchased.upgrade.back") } }
                }
            }
        }
    }
}
