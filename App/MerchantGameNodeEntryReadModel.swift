import SwiftUI

@MainActor final class MerchantGameNodeEntryReadModel: ObservableObject {
    struct Request: Equatable {
        let id = UUID()
        let scope: UUID
    }
    @Published private(set) var request: Request?
    @Published private(set) var result: MerchantGameNodeEntriesResult?
    private(set) var loadedScope: UUID?
    private var owner: (any MerchantGameNodeServing)?
    private var active = false
    private var claimed: UUID?

    func appear(service: any MerchantGameNodeServing) {
        guard !active || owner !== service else { return }
        active = true
        if owner !== service || loadedScope != service.scope || result == nil {
            owner = service; refresh(service: service)
        }
    }
    func refresh(service: any MerchantGameNodeServing) {
        guard active, owner === service else { return }
        result = nil; loadedScope = nil; claimed = nil
        request = .init(scope: service.scope)
    }
    func disappear() {
        active = false; request = nil; claimed = nil
        // Preserve completed rows while their NavigationLink destination is pushed.
    }
    func read(_ ticket: Request, service: any MerchantGameNodeServing) async {
        guard !Task.isCancelled, active, owner === service, request == ticket,
              service.scope == ticket.scope, claimed != ticket.id else { return }
        claimed = ticket.id
        let value = await service.loadEntries()
        guard !Task.isCancelled, active, owner === service, request == ticket,
              service.scope == ticket.scope else { return }
        result = value; loadedScope = ticket.scope
    }
    func currentResult(service: any MerchantGameNodeServing) -> MerchantGameNodeEntriesResult? {
        guard owner === service, loadedScope == service.scope else { return nil }
        return result
    }
}
