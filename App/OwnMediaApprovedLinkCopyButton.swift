import SwiftUI
import UIKit
import Observation

@MainActor @Observable final class OwnMediaApprovedLinkCopyModel {
    enum Phase: Equatable { case idle, loading, copied, failed }
    let asset: OwnMediaAsset
    private let access: OwnMediaApprovedLinkAccess?
    private let currentAsset: () -> OwnMediaAsset?
    private let copyText: (String) throws -> Void
    private let source: UUID?
    private var mounted = false, foreground = false
    private var operation = UUID()
    private var reader: OwnMediaApprovedLinkReader?
    private var task: Task<Void, Never>?
    private var phase: Phase = .idle
    init(asset: OwnMediaAsset, access: OwnMediaApprovedLinkAccess?, currentAsset: @escaping () -> OwnMediaAsset?,
         copyText: @escaping (String) throws -> Void = { value in
             UIPasteboard.general.setItems([["public.utf8-plain-text": value]], options: [.localOnly: true])
         }) {
        self.asset = asset; self.access = access; self.currentAsset = currentAsset; self.copyText = copyText
        source = access?.sourceRevision(asset)
    }
    deinit { task?.cancel() }
    var available: Bool {
        guard mounted, foreground, OwnMediaApprovedLinkReader.canCopy(asset), let source,
              access?.sourceRevision(asset) == source, let row = currentAsset() else { return false }
        return OwnMediaApprovedLinkReader.sameAsset(asset, row)
    }
    var visiblePhase: Phase { available ? phase : .idle }
    func appear(foreground: Bool) { mounted = true; self.foreground = foreground }
    func setForeground(_ value: Bool) { foreground = value; if !value { cancel() } }
    func disappear() { mounted = false; cancel() }
    func cancel() {
        operation = UUID(); task?.cancel(); task = nil; reader?.retire(); reader = nil; phase = .idle
        // Do not clear/replace the system clipboard or pretend to recall a delivered URL.
    }
    private func accepts(_ run: UUID) -> Bool { available && operation == run }
    @discardableResult func copy() -> Task<Void, Never>? {
        guard available, phase != .loading else { return nil }
        cancel(); let run = operation
        guard let next = access?.makeReader(asset), next.sourceRevision == source else { phase = .failed; return nil }
        reader = next; phase = .loading
        let work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.operation == run { self.task = nil } }
            do {
                guard !Task.isCancelled, self.accepts(run) else { return }
                let delivery = try await next.readForCopy(asset: self.asset, currentAsset: self.currentAsset,
                    actionIsCurrent: { [weak self] in self?.accepts(run) == true })
                guard !Task.isCancelled, self.accepts(run), next.isConfigured else { return }
                try delivery.deliver(to: self.copyText)
                guard self.accepts(run) else { return }; self.phase = .copied
            } catch {
                guard !Task.isCancelled, self.accepts(run) else { return }; self.phase = .failed
            }
        }
        task = work; return work
    }
}
private struct OwnMediaApprovedLinkViewIdentity: Hashable {
    let id: Int64, state: String, reason: [UInt8], type: Int, source: UUID?
    @MainActor init(asset: OwnMediaAsset, access: OwnMediaApprovedLinkAccess?) {
        id = asset.id; state = asset.reviewState.rawValue; reason = Array(asset.reviewReason.utf8); source = access?.sourceRevision(asset)
        switch asset.mediaType { case .image: type = 0; case .audio: type = 1; case .model3D: type = 2; case .other: type = 3 }
    }
}
@MainActor struct OwnMediaApprovedLinkCopyButton: View {
    let asset: OwnMediaAsset
    let access: OwnMediaApprovedLinkAccess?
    let currentAsset: () -> OwnMediaAsset?
    var body: some View {
        if asset.reviewState == .approved {
            OwnMediaApprovedLinkCopyOwner(asset: asset, access: access, currentAsset: currentAsset)
                .id(OwnMediaApprovedLinkViewIdentity(asset: asset, access: access))
        }
    }
}
@MainActor private struct OwnMediaApprovedLinkCopyOwner: View {
    @State private var model: OwnMediaApprovedLinkCopyModel
    @Environment(\.scenePhase) private var scenePhase
    init(asset: OwnMediaAsset, access: OwnMediaApprovedLinkAccess?, currentAsset: @escaping () -> OwnMediaAsset?) {
        _model = State(initialValue: OwnMediaApprovedLinkCopyModel(asset: asset, access: access, currentAsset: currentAsset))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Explain the original long-lived/public URL before the explicit delivery action.
            Text("longLived", tableName: "OwnMediaApprovedLink").font(.footnote).foregroundStyle(.secondary)
            Button { model.copy() } label: { Label { Text("copy", tableName: "OwnMediaApprovedLink") } icon: { Image(systemName: "doc.on.doc") } }
                .frame(minHeight: 44).disabled(!model.available || model.visiblePhase == .loading)
                .accessibilityIdentifier("member.media.approvedLink.\(model.asset.id)")
            if !model.available { Text("unavailable", tableName: "OwnMediaApprovedLink").font(.footnote).foregroundStyle(.secondary) }
            switch model.visiblePhase {
            case .idle: EmptyView()
            case .loading: ProgressView { Text("loading", tableName: "OwnMediaApprovedLink") }
            case .copied: Text("copied", tableName: "OwnMediaApprovedLink").font(.footnote)
            case .failed: Text("failed", tableName: "OwnMediaApprovedLink").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .privacySensitive()
        .onAppear { model.appear(foreground: scenePhase == .active) }
        .onDisappear { model.disappear() }
        .onChange(of: scenePhase) { _, value in model.setForeground(value == .active) }
        .onChange(of: model.available) { _, available in if !available { model.cancel() } }
    }
}
