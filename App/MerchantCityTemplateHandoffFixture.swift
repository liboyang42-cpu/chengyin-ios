#if DEBUG
import SwiftUI

/// Synthetic records only. No live session, network, filesystem or permission prompt.
@MainActor final class MerchantCityTemplateHandoffFixtureState: ObservableObject {
    let reader = MerchantOperationsFixtureReader()
    @Published var scope = UUID()
    @Published var local = MerchantCityTemplateLocalDraft(fields: ["name": "My unfinished location", "address": "  Keep this address  ", "latitude": "31.2000", "longitude": "121.4000"], templateID: 71, confirmedAddress: true, dirty: false)
    @Published var snapshot: MerchantContentSnapshot?
    @Published var permitted = true
    @Published var locked = false
    var readCount = 0, applyCount = 0
    var includeReturnedTemplate = true, failRead = false, album = false
    var holdRead = false
    var pendingRead: CheckedContinuation<Void, Never>?
    init() { snapshot = makeSnapshot(includeReturned: false) }
    func makeSnapshot(includeReturned: Bool, observedAt: Date = Date()) -> MerchantContentSnapshot {
        let access = try! JSONDecoder().decode(MerchantAccess.self, from: Data(#"{"active":true,"merchant":{"id":31,"name":"Synthetic store"},"roleCode":"MERCHANT_MANAGER","permissions":["merchant:project:manage"]}"#.utf8))
        var rows: [MerchantContentValue] = [.object(["id": .integer(71), "title": .string("Existing synthetic template")])]
        if includeReturned {
            rows.append(.object(["id": .integer(73), "title": .string("Saved synthetic template"), "advancedConfigJson": .object(["album": .object(["enabled": .bool(album)])])]))
        }
        return .init(query: .cityPlacement, scope: scope, access: access,
            value: .object(["templates": .array(rows), "catalog": .object(["used": .integer(0), "max": .integer(3)]), "profile": .object([:])]), observedAt: observedAt)
    }
    var binding: MerchantCityTemplateHandoffBinding {
        .init(scope: { self.scope }, isAuthenticated: { self.permitted }, snapshot: { self.snapshot }, draft: { self.local },
              canOpen: { self.permitted && !self.locked && self.snapshot != nil }, canReload: { self.permitted && !self.locked },
              reload: {
            self.readCount += 1
            self.snapshot = nil
            if self.holdRead { self.holdRead = false; await withCheckedContinuation { self.pendingRead = $0 } }
            if !self.failRead { self.snapshot = self.makeSnapshot(includeReturned: self.includeReturnedTemplate) }
        }, apply: { original, id, refreshed in
            guard self.permitted, !self.locked, self.local == original,
                  MerchantCityTemplateHandoff.sameSnapshot(self.snapshot, refreshed) else { return false }
            self.applyCount += 1
            self.local = .init(fields: original.fields, templateID: id, confirmedAddress: original.confirmedAddress, dirty: true)
            return true
        }, isOfflineFixture: true)
    }
    func releaseRead() { let held = pendingRead; pendingRead = nil; held?.resume() }
}

@MainActor struct MerchantCityTemplateHandoffFixtureHost: View {
    @StateObject private var state = MerchantCityTemplateHandoffFixtureState()
    @StateObject private var handoff = MerchantCityTemplateHandoffModel()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("merchant.cityTemplate.fixtureBoundary")
                    Text(verbatim: state.local.fields["name"] ?? "").accessibilityIdentifier("merchant.cityTemplate.fixture.name")
                    Text(verbatim: state.local.fields["address"] ?? "").accessibilityIdentifier("merchant.cityTemplate.fixture.address")
                    Text(verbatim: String(state.local.templateID)).accessibilityIdentifier("merchant.cityTemplate.fixture.selection")
                    MerchantCityTemplateHandoffField(binding: state.binding, model: handoff)
                }
            }.modifier(MerchantCityTemplateHandoffPresentation(model: handoff, binding: state.binding))
                .appNavigationTitle("merchant.cityTemplate.fixtureTitle")
        }
        .environment(\.merchantCityTemplateHandoffFactory, { .init(reader: state.reader) })
    }
}
#endif
