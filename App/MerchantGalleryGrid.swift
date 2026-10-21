import SwiftUI

/// Pure 3x3 slot layout for the merchant album. Slot index == draft array index, so
/// removing or appending never reorders surviving images, and empty slots are inert.
struct MerchantGalleryGridLayout: Equatable {
    static let columns = 3
    static let capacity = 9
    static let cellAspectRatio: CGFloat = 1
    enum Slot: Equatable { case image(index: Int, reference: String), empty(index: Int) }
    let slots: [Slot]
    init(gallery: [String]) {
        let bounded = Array(gallery.prefix(Self.capacity))
        slots = (0..<Self.capacity).map { index in
            index < bounded.count ? .image(index: index, reference: bounded[index]) : .empty(index: index)
        }
    }
    var imageCount: Int { slots.reduce(0) { if case .image = $1 { return $0 + 1 }; return $0 } }
    var isFull: Bool { imageCount >= Self.capacity }
    var rows: [[Slot]] { stride(from: 0, to: slots.count, by: Self.columns).map { Array(slots[$0..<$0 + Self.columns]) } }
    /// Removing is valid only for an occupied, in-range slot of the *current* draft.
    static func canRemove(index: Int, in gallery: [String]) -> Bool { gallery.indices.contains(index) && index < capacity }
}

@MainActor
struct MerchantGalleryGrid: View {
    let gallery: [String]
    let isExample: Bool
    let remove: (Int) -> Void
    var body: some View {
        let layout = MerchantGalleryGridLayout(gallery: gallery)
        VStack(spacing: 8) {
            ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) { ForEach(row, id: \.slotIndex) { cell($0) } }
            }
        }
        .accessibilityIdentifier("merchant.operations.gallery.grid")
    }
    @ViewBuilder private func cell(_ slot: MerchantGalleryGridLayout.Slot) -> some View {
        switch slot {
        case .image(let index, let reference):
            ZStack(alignment: .topTrailing) {
                QuestifyImageEntityCard(imageSource: isExample ? nil : reference, title: "", fallbackTitle: "merchant.operations.galleryImage", minimumHeight: 96) {
                    if isExample { Text("merchant.operations.syntheticArtwork") }
                }
                Button(role: .destructive) { remove(index) } label: {
                    Image(systemName: "minus.circle.fill").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("merchant.operations.removeImage")
                .accessibilityIdentifier("merchant.operations.gallery.remove." + String(index))
            }
            .aspectRatio(MerchantGalleryGridLayout.cellAspectRatio, contentMode: .fit)
            .accessibilityIdentifier("merchant.operations.gallery.slot." + String(index))
        case .empty(let index):
            RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.4))
                .frame(maxWidth: .infinity, minHeight: 96)
                .aspectRatio(MerchantGalleryGridLayout.cellAspectRatio, contentMode: .fit)
                .accessibilityHidden(true)
                .accessibilityIdentifier("merchant.operations.gallery.empty." + String(index))
        }
    }
}

private extension MerchantGalleryGridLayout.Slot {
    var slotIndex: Int { switch self { case .image(let index, _), .empty(let index): return index } }
}
