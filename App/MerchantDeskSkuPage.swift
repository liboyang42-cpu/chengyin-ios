import SwiftUI

/// Desk SKU page. Home navigation is not attached here.
@MainActor
struct MerchantDeskSkuPage: View {
    @ObservedObject var desk: MerchantDeskSkuDesk
    let access: MerchantBusinessAccess
    let accountID: Int64
    let token: String
    let productID: Int
    let skuID: Int
    @State private var draft = MerchantDeskSkuDesk.Edit(skuName: "", price: "", stock: 0)

    var body: some View {
        List {
            switch desk.phase {
            case .idle:
                Text("merchant.desk.sku.loading")
            case .editing:
                TextField("merchant.desk.sku.name", text: $draft.skuName)
                TextField("merchant.desk.sku.price", text: $draft.price)
                Stepper(value: $draft.stock, in: 0...1_000_000) {
                    Text("merchant.desk.sku.stock \(draft.stock)")
                }
                Button("merchant.desk.sku.freeze") {
                    Task {
                        await desk.load(productID: productID, skuID: skuID, edit: draft, access: access,
                                        accountID: accountID, token: token)
                    }
                }
                .accessibilityIdentifier("merchant.desk.sku.freeze")
            case .frozen(let intent):
                Text(intent.skuName)
                Text(intent.price)
                TextField("merchant.desk.sku.price", text: $draft.price)
                Button("merchant.desk.sku.confirm") {
                    Task {
                        await desk.confirm(access: access, token: token)
                        await desk.noteLater(productID: productID, skuID: skuID, access: access, token: token)
                    }
                }
                .accessibilityIdentifier("merchant.desk.sku.confirm")
            case .applied(let requestID, _):
                Text("merchant.desk.sku.applied")
                Text(requestID)
                if let later = desk.laterRuleVersion {
                    Text("merchant.desk.sku.later \(later)")
                }
            case .unknown(let requestID):
                Text("merchant.desk.sku.unknown")
                Text(requestID)
            case .failed:
                Text("merchant.desk.sku.failed")
            }
        }
        .navigationTitle("merchant.desk.sku")
        .task {
            await desk.reopen(skuID: skuID, access: access, token: token)
            if case .applied = desk.phase {
                await desk.noteLater(productID: productID, skuID: skuID, access: access, token: token)
            } else if case .idle = desk.phase {
                await desk.present(productID: productID, skuID: skuID, access: access, accountID: accountID, token: token)
                if case .editing(let edit) = desk.phase { draft = edit }
            }
        }
    }
}
