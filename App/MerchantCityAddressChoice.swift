import SwiftUI
import UIKit

@MainActor final class MerchantCityAddressChoice: ObservableObject {
    struct Source: Equatable {
        let scope: UUID
        let observedAt: Date
        let merchantID: Int
        let templateID: Int
        let addressGeneration: UUID
        let fields: [String: Data]
        let addressConfirmed: Bool
    }
    struct Item: Identifiable {
        let id = UUID()
        let attachment: UUID
        let source: Source
        let provider: (any PublishingPlaceSearching)?
    }
    @Published private(set) var item: Item?
    @Published private(set) var attachment: UUID?
    private var visible = false, active = false, covered = false
    private var generation = UUID()
    static func replacingAddress(in fields: [String: String], with place: PublishingPlace) -> [String: String] {
        var result = fields
        result["name"] = place.name; result["address"] = place.address
        result["latitude"] = String(place.latitude); result["longitude"] = String(place.longitude)
        return result
    }
    func appear(active: Bool) {
        if attachment == nil { attachment = UUID() }
        visible = true; covered = false; self.active = active
        if !active { item = nil; generation = UUID() }
    }
    func sceneChanged(active: Bool) { self.active = active; if !active { item = nil; covered = false; generation = UUID() } }
    func cover(_ id: UUID) { guard attachment == id else { return }; visible = false; covered = item != nil }
    func reappear(_ id: UUID) { guard attachment == id else { return }; visible = true; covered = false }
    func depart(_ id: UUID) { guard attachment == id else { return }; item = nil; attachment = nil; visible = false; covered = false }
    func invalidate() { item = nil; attachment = nil; visible = false; covered = false }
    func openAction(_ source: Source, provider: (any PublishingPlaceSearching)?, current: @escaping () -> Source?) -> () -> Void {
        let originalAttachment = attachment, originalGeneration = generation
        return { [weak self] in
            guard let self, self.attachment == originalAttachment, self.generation == originalGeneration else { return }
            self.open(source, provider: provider, current: current)
        }
    }
    private func open(_ source: Source, provider: (any PublishingPlaceSearching)?, current: () -> Source?) {
        guard visible, active, item == nil, let attachment, let provider, current() == source else { return }
        item = Item(attachment: attachment, source: source, provider: provider)
    }
    func matches(_ original: Item, current: () -> Source?) -> Bool {
        active && (visible || covered) && attachment == original.attachment && item?.id == original.id && current() == original.source
    }
    func cancel(_ original: Item) { guard item?.id == original.id else { return }; item = nil; generation = UUID() }
    func binding(_ original: Item, current: @escaping () -> Source?) -> Binding<Item?> {
        .init(get: { self.matches(original, current: current) ? original : nil }, set: { if $0 == nil { self.cancel(original) } })
    }
    @discardableResult func confirm(_ place: PublishingPlace, original: Item, current: () -> Source?, apply: (Source, PublishingPlace) -> Bool) -> Bool {
        guard matches(original, current: current), apply(original.source, place) else { return false }
        item = nil; generation = UUID(); return true
    }
}

@MainActor struct MerchantCityAddressChoicePresentation: View {
    @ObservedObject var owner: MerchantCityAddressChoice
    let original: MerchantCityAddressChoice.Item
    let current: () -> MerchantCityAddressChoice.Source?
    let apply: (MerchantCityAddressChoice.Source, PublishingPlace) -> Bool
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .sheet(item: owner.binding(original, current: current)) { shown in
                PublishingPlacePicker(provider: shown.provider) { place in
                    _ = owner.confirm(place, original: shown, current: current, apply: apply)
                }
            }
    }
}

@MainActor struct MerchantCityAddressChoiceLifetime: UIViewControllerRepresentable {
    let owner: MerchantCityAddressChoice
    let attachment: UUID
    func makeUIViewController(context: Context) -> Controller { .init(owner: owner, attachment: attachment) }
    func updateUIViewController(_ controller: Controller, context: Context) {}
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.owner?.depart(controller.attachment) }
    @MainActor final class Controller: UIViewController {
        weak var owner: MerchantCityAddressChoice?
        let attachment: UUID
        init(owner: MerchantCityAddressChoice, attachment: UUID) { self.owner = owner; self.attachment = attachment; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { return nil }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); owner?.reappear(attachment) }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            var current: UIViewController? = self
            while let value = current {
                if value.isBeingDismissed || value.isMovingFromParent { owner?.depart(attachment); return }
                if value.presentedViewController != nil { owner?.cover(attachment); return }
                current = value.parent
            }
            owner?.cover(attachment)
        }
    }
}
