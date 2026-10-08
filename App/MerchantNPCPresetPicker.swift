import SwiftUI

/// Review artwork is a value projection of the frozen confirmation, never a live editor read.
struct MerchantNPCCharacterAvatarSnapshot: Equatable {
    let rawValue: String
    var preset: MerchantNPCPresetAvatar? { MerchantNPCPresetAvatar.matching(code: rawValue) }
    init?(draft: MerchantOperationsDraft) {
        guard case .character(let value) = draft else { return nil }
        rawValue = value.avatar
    }
}

/// A picker owns an immutable draft/session snapshot. Only an explicit, still-current
/// confirmation may replace avatar. It uses the existing document edit/review/save path.
@MainActor final class MerchantNPCPresetPickerModel: ObservableObject, Identifiable {
    let id = UUID()
    let document: MerchantOperationsViewModel
    private let scope: UUID
    private let draftIdentity: UUID
    private let original: MerchantStoreCharacter
    @Published private(set) var selectedID: String?
    @Published private(set) var consumed = false
    init?(document: MerchantOperationsViewModel) {
        let owner = document.coordinator
        guard owner.isCurrent, !owner.isBusy, !owner.isLocked, owner.confirmation == nil,
              case .character(let value) = owner.draft else { return nil }
        self.document = document; scope = owner.reader.scope
        draftIdentity = owner.draftIdentity; original = value
        selectedID = MerchantNPCPresetAvatar.matching(code: value.avatar)?.id
    }
    var isCurrent: Bool {
        let owner = document.coordinator
        return !consumed && owner.isCurrent && !owner.isBusy && !owner.isLocked && owner.confirmation == nil
            && owner.reader.scope == scope && owner.draftIdentity == draftIdentity
            && owner.draft == .character(original)
    }
    var canApply: Bool {
        guard isCurrent, let selectedID, let avatar = MerchantNPCPresetAvatar.matching(id: selectedID) else { return false }
        return avatar.code != original.avatar
    }
    func select(_ id: String) {
        guard isCurrent, MerchantNPCPresetAvatar.matching(id: id) != nil else { return }
        selectedID = id
    }
    @discardableResult func apply() -> Bool {
        guard canApply, let selectedID, let avatar = MerchantNPCPresetAvatar.matching(id: selectedID) else { return false }
        var edited = original; edited.avatar = avatar.code
        consumed = true
        document.edit(.character(edited))
        return document.coordinator.draft == .character(edited)
    }
    func cancel() { consumed = true; selectedID = nil }
}

/// Bundled run-length pixels are drawn directly, without a remote image fallback.
struct MerchantNPCPresetArtwork: View {
    let avatar: MerchantNPCPresetAvatar
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color(avatar.backgroundRGB)))
            let scale = max(1, floor(min(size.width, size.height) / CGFloat(avatar.gridSize)))
            let side = CGFloat(avatar.gridSize) * scale
            let x = floor((size.width - side) / 2), y = floor((size.height - side) / 2)
            for run in avatar.runs {
                let rect = CGRect(x: x + CGFloat(run.x) * scale, y: y + CGFloat(run.y) * scale,
                                  width: CGFloat(run.width) * scale, height: scale)
                context.fill(Path(rect), with: .color(color(avatar.paletteRGB[run.paletteIndex])))
            }
        }.clipped().accessibilityHidden(true)
    }
    private func color(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, opacity: 1)
    }
}

@MainActor struct MerchantNPCPresetSection: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @State private var picker: MerchantNPCPresetPickerModel?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Section("merchant.operations.avatar") {
            if case .character(let value) = document.coordinator.draft {
                if let avatar = MerchantNPCPresetAvatar.matching(code: value.avatar) {
                    MerchantNPCPresetArtwork(avatar: avatar)
                        .frame(width: 192, height: 192).clipShape(RoundedRectangle(cornerRadius: 20))
                        .frame(maxWidth: .infinity)
                    Text(LocalizedStringKey(avatar.titleKey))
                        .accessibilityIdentifier("merchantPreset.current." + avatar.id)
                } else if value.avatar.hasPrefix("px1:") {
                    Text("merchantPreset.unsupportedCode").accessibilityIdentifier("merchantPreset.unsupportedCode")
                }
            }
            Button("merchantPreset.choose") { picker = .init(document: document) }
                .disabled(!document.coordinator.isCurrent || document.coordinator.isBusy || document.coordinator.isLocked || document.coordinator.confirmation != nil)
                .frame(minHeight: 44).accessibilityIdentifier("merchantPreset.open")
            Text("merchantPreset.localSelection").font(.footnote).foregroundStyle(.secondary)
        }
        .sheet(item: $picker, onDismiss: cancelPicker) { selection in
            MerchantNPCPresetPicker(model: selection)
        }
        .onDisappear { cancelPicker() }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in cancelPicker() }
        .onChange(of: document.coordinator.reader.scope) { _, _ in cancelPicker() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { cancelPicker() } }
    }
    private func cancelPicker() { picker?.cancel(); picker = nil }
}

@MainActor private struct MerchantNPCPresetPicker: View {
    @ObservedObject var model: MerchantNPCPresetPickerModel
    @ObservedObject private var document: MerchantOperationsViewModel
    @Environment(\.dismiss) private var dismiss
    init(model: MerchantNPCPresetPickerModel) {
        self.model = model; document = model.document
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("merchantPreset.localSelection").font(.footnote).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 16)], spacing: 16) {
                        ForEach(MerchantNPCPresetAvatar.all) { avatar in
                            Button { model.select(avatar.id) } label: {
                                VStack(spacing: 8) {
                                    MerchantNPCPresetArtwork(avatar: avatar).frame(height: 144)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                    HStack {
                                        Text(LocalizedStringKey(avatar.titleKey)).fixedSize(horizontal: false, vertical: true)
                                        if model.selectedID == avatar.id { Image(systemName: "checkmark.circle.fill") }
                                    }
                                }.frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.plain).disabled(!model.isCurrent)
                                .accessibilityLabel(Text(LocalizedStringKey(avatar.titleKey)))
                                .accessibilityAddTraits(model.selectedID == avatar.id ? .isSelected : [])
                                .accessibilityIdentifier("merchantPreset.option." + avatar.id)
                        }
                    }
                    if !model.isCurrent { Text("merchantPreset.stale").accessibilityIdentifier("merchantPreset.stale") }
                }.padding()
            }
            .navigationTitle("merchantPreset.choose").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { model.cancel(); dismiss() }.accessibilityIdentifier("merchantPreset.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("merchantPreset.use") { if model.apply() { dismiss() } }
                        .disabled(!model.canApply).accessibilityIdentifier("merchantPreset.apply")
                }
            }
        }.privacySensitive().onDisappear { model.cancel() }
    }
}
