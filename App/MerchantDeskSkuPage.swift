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
    let edit: MerchantDeskSkuDesk.Edit

    var body: some View {
        List {
            switch desk.phase {
            case .idle:
                Text("merchant.desk.sku.loading")
            case .frozen(let intent):
                Text(intent.skuName)
                Text(intent.price)
                Button("merchant.desk.sku.confirm") {
                    Task { await desk.confirm(access: access, token: token) }
                }
                .accessibilityIdentifier("merchant.desk.sku.confirm")
            case .applied(let requestID, _):
                Text("merchant.desk.sku.applied")
                Text(requestID)
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
            if case .idle = desk.phase {
                await desk.load(productID: productID, skuID: skuID, edit: edit, access: access, accountID: accountID, token: token)
            }
        }
    }
}
