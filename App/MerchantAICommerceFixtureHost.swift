#if DEBUG
import SwiftUI

/// Explicit offline fixture for reform plan v9 W04/W05/W06/W07/W17 client contracts. Synthetic
/// values only: no transport, provider, credential, price, reward amount or coordinate.
struct MerchantAICommerceFixtureHost: View {
    private let gates = MerchantAICommerceGates.disabled
    private let revision = MerchantAuthoringRevision(
        draftID: "synthetic-draft", version: 2, stage: .approved, authorID: "synthetic-editor", contentHash: "synthetic-hash-2",
        touchesThemeContent: true,
        merchantFactsApproval: .init(authority: .storeOwner, approverID: "synthetic-owner", approvedHash: "synthetic-hash-1"),
        themeContentApproval: nil)
    private let branchDecision = EnvironmentBranchSelector.decide(
        proposedBranchID: "synthetic-outdoor",
        branches: [ApprovedBranch(branchID: "synthetic-indoor", window: nil, indoor: true, requiresOpenStore: false, requiredPlaceIDs: [], isDeterministicFallback: true)],
        snapshot: nil, serverNow: Date(timeIntervalSince1970: 0))
    private let order = CommerceOrderReadback(
        orderID: "synthetic-order", merchantID: "synthetic-merchant", asOf: Date(timeIntervalSince1970: 0), payment: .paid,
        lines: [CommerceOrderLine(lineID: "synthetic-line", skuID: "synthetic-sku", kind: .mixed, unitPriceMinor: 0, quantity: 1, currency: "CNY",
                                  fulfilment: [.init(sequence: 1, mode: .pickup, quantity: 1, state: .ready)],
                                  entitlements: [.init(grantSequence: 1, themeID: "synthetic-theme", releaseID: nil, state: .active)], refunds: [])])
    private let poolItem = SponsoredPoolItem(
        itemID: "synthetic-item", pledgeID: "synthetic-pledge", pledgeVersion: "1", merchantID: "synthetic-merchant", storeID: "synthetic-store",
        kind: .coupon, allocation: .firstFinders, title: "Synthetic reward", termsVersion: "1", termsText: "Synthetic merchant terms",
        validFrom: Date(timeIntervalSince1970: 0), validUntil: Date(timeIntervalSince1970: 86_400), remaining: nil, guaranteeReserved: false,
        asOf: Date(timeIntervalSince1970: 0))

    var body: some View {
        NavigationStack {
            List {
                Section {
                    gate(Text("merchantAICommerce.gate.sceneAI", tableName: "MerchantAICommerce"), on: gates.sceneAI.globalGenerationEnabled)
                    gate(Text("merchantAICommerce.gate.authoring", tableName: "MerchantAICommerce"), on: gates.merchantAuthoringPublish)
                    gate(Text("merchantAICommerce.gate.orders", tableName: "MerchantAICommerce"), on: gates.orderLineReadback)
                    gate(Text("merchantAICommerce.gate.staff", tableName: "MerchantAICommerce"), on: gates.staffScopeReadback)
                    gate(Text("merchantAICommerce.gate.ledger", tableName: "MerchantAICommerce"), on: gates.rewardLedgerReadback)
                    gate(Text("merchantAICommerce.gate.rewards", tableName: "MerchantAICommerce"), on: gates.sponsoredRewards.nonCash)
                    gate(Text("merchantAICommerce.gate.payment", tableName: "MerchantAICommerce"), on: gates.paymentAndCashEnabled)
                } header: { Text("merchantAICommerce.section.gates", tableName: "MerchantAICommerce") }

                Section {
                    ForEach(MerchantAuthoringGuard.publishBlockers(revision, capabilityEnabled: gates.merchantAuthoringPublish), id: \.self) { blocker in
                        blockerText(blocker).accessibilityIdentifier("merchantAICommerce.blocker." + blocker.rawValue)
                    }
                } header: { Text("merchantAICommerce.section.authoring", tableName: "MerchantAICommerce") }

                Section {
                    branchText.accessibilityIdentifier("merchantAICommerce.branchDecision")
                } header: { Text("merchantAICommerce.section.branch", tableName: "MerchantAICommerce") }

                Section {
                    orderText.accessibilityIdentifier("merchantAICommerce.orderProjection")
                    Text("merchantAICommerce.order.entitlementSeparate", tableName: "MerchantAICommerce")
                } header: { Text("merchantAICommerce.section.order", tableName: "MerchantAICommerce") }

                Section {
                    Text(verbatim: poolItem.title)
                    disclosureText.accessibilityIdentifier("merchantAICommerce.poolDisclosure")
                    if !poolItem.isPresentable(gates.sponsoredRewards) {
                        Text("merchantAICommerce.reward.notEnabled", tableName: "MerchantAICommerce")
                    }
                } header: { Text("merchantAICommerce.section.reward", tableName: "MerchantAICommerce") }

                Section {
                    Text("merchantAICommerce.notice.offline", tableName: "MerchantAICommerce")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Text("merchantAICommerce.title", tableName: "MerchantAICommerce"))
        }
        .accessibilityIdentifier("merchantAICommerce.root")
    }

    private func gate(_ title: Text, on: Bool) -> some View {
        HStack {
            title
            Spacer()
            if on { Text("merchantAICommerce.state.on", tableName: "MerchantAICommerce") }
            else { Text("merchantAICommerce.state.off", tableName: "MerchantAICommerce").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func blockerText(_ blocker: MerchantPublishBlocker) -> some View {
        switch blocker {
        case .notApproved: Text("merchantAICommerce.blocker.notApproved", tableName: "MerchantAICommerce")
        case .missingMerchantFacts: Text("merchantAICommerce.blocker.missingMerchantFacts", tableName: "MerchantAICommerce")
        case .missingThemeApproval: Text("merchantAICommerce.blocker.missingThemeApproval", tableName: "MerchantAICommerce")
        case .wrongAuthority: Text("merchantAICommerce.blocker.wrongAuthority", tableName: "MerchantAICommerce")
        case .selfApproval: Text("merchantAICommerce.blocker.selfApproval", tableName: "MerchantAICommerce")
        case .editedAfterReview: Text("merchantAICommerce.blocker.editedAfterReview", tableName: "MerchantAICommerce")
        case .capabilityDisabled: Text("merchantAICommerce.blocker.capabilityDisabled", tableName: "MerchantAICommerce")
        }
    }

    @ViewBuilder private var branchText: some View {
        switch branchDecision {
        case .selected: Text("merchantAICommerce.branch.selected", tableName: "MerchantAICommerce")
        case .fallback: Text("merchantAICommerce.branch.fallback", tableName: "MerchantAICommerce")
        case .pausedForSafety: Text("merchantAICommerce.branch.paused", tableName: "MerchantAICommerce")
        case .noBranchAvailable: Text("merchantAICommerce.branch.none", tableName: "MerchantAICommerce")
        }
    }

    @ViewBuilder private var orderText: some View {
        switch order?.projection {
        case .fulfilled?: Text("merchantAICommerce.order.fulfilled", tableName: "MerchantAICommerce")
        case .partiallyFulfilled?: Text("merchantAICommerce.order.partial", tableName: "MerchantAICommerce")
        case .awaitingFulfilment?: Text("merchantAICommerce.order.awaiting", tableName: "MerchantAICommerce")
        case .refundInProgress?, .refundUnknown?: Text("merchantAICommerce.order.refund", tableName: "MerchantAICommerce")
        default: Text("merchantAICommerce.order.checkServer", tableName: "MerchantAICommerce")
        }
    }

    @ViewBuilder private var disclosureText: some View {
        switch poolItem.disclosure {
        case .limitedWhileSuppliesLast: Text("merchantAICommerce.reward.limited", tableName: "MerchantAICommerce")
        case .guaranteedReserved: Text("merchantAICommerce.reward.guaranteed", tableName: "MerchantAICommerce")
        }
    }
}
#endif
