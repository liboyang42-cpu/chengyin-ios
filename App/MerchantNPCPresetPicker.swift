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
    @ObservedObject var presentation: MerchantNPCPresetPresentation
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        let permit = presentation.generation
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
            Button("merchantPreset.choose") {
                guard scenePhase == .active else { return }
                presentation.open(permit: permit, document: document)
            }
                .disabled(!presentation.active || !document.coordinator.isCurrent || document.coordinator.isBusy || document.coordinator.isLocked || document.coordinator.confirmation != nil)
                .frame(minHeight: 44).accessibilityIdentifier("merchantPreset.open")
            Text("merchantPreset.localSelection").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// The full editor retains selection independently of virtualized rows.
@MainActor final class MerchantNPCPresetPresentation: ObservableObject {
    @Published private(set) var picker: MerchantNPCPresetPickerModel?
    @Published private(set) var generation = UUID()
    @Published private(set) var active = false
    private(set) var visible = false
    func appear(active: Bool) { visible = true; sceneChanged(active: active) }
    func disappear() { visible = false; active = false; invalidate() }
    func sceneChanged(active: Bool) {
        self.active = visible && active
        if !self.active { invalidate() }
    }
    func invalidate() { picker?.cancel(); picker = nil; generation = UUID() }
    func open(permit: UUID, document: MerchantOperationsViewModel) {
        guard visible, active, permit == generation, picker == nil else { return }
        picker = MerchantNPCPresetPickerModel(document: document)
    }
    func close(_ id: UUID) {
        guard picker?.id == id else { return }
        invalidate()
    }
    func binding(_ original: MerchantNPCPresetPickerModel) -> Binding<MerchantNPCPresetPickerModel?> {
        Binding(get: { self.picker?.id == original.id && original.isCurrent ? original : nil }, set: { value in
            if value == nil { self.close(original.id) }
        })
    }
}

@MainActor struct MerchantNPCPresetStablePresentation: ViewModifier {
    @ObservedObject var document: MerchantOperationsViewModel
    @ObservedObject var presentation: MerchantNPCPresetPresentation
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content.background {
            if let original = presentation.picker {
                Color.clear.frame(width: 0, height: 0)
                    .sheet(item: presentation.binding(original), onDismiss: { presentation.close(original.id) }) { picker in
                        MerchantNPCPresetPicker(model: picker) { presentation.close(original.id) }
                    }.id(original.id)
            }
        }
        .onAppear { presentation.appear(active: scenePhase == .active) }
        .onDisappear { presentation.disappear() }
        .onChange(of: scenePhase) { _, phase in presentation.sceneChanged(active: phase == .active) }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in presentation.invalidate() }
        .onChange(of: document.coordinator.reader.scope) { _, _ in presentation.invalidate() }
        .onChange(of: document.revision) { _, _ in
            if presentation.picker?.isCurrent == false { presentation.invalidate() }
        }
    }
}

@MainActor private struct MerchantNPCPresetPicker: View {
    @ObservedObject var model: MerchantNPCPresetPickerModel
    @ObservedObject private var document: MerchantOperationsViewModel
    let close: () -> Void
    init(model: MerchantNPCPresetPickerModel, close: @escaping () -> Void) {
        self.model = model; document = model.document; self.close = close
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
                    Button("action.cancel") { model.cancel(); close() }.accessibilityIdentifier("merchantPreset.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("merchantPreset.use") { if model.apply() { close() } }
                        .disabled(!model.canApply).accessibilityIdentifier("merchantPreset.apply")
                }
            }
        }.privacySensitive().onDisappear { model.cancel() }
    }
}
