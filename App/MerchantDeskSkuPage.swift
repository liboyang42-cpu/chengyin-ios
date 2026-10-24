import SwiftUI

/// Desk SKU page. Home navigation is not attached here.
/// The session supplies `read`. This page calls that entry and does not construct an approval.
@MainActor
struct MerchantDeskSkuPage: View {
    @ObservedObject var desk: MerchantDeskSkuDesk
    let access: MerchantBusinessAccess
    let accountID: Int64
    let token: String
    let productID: Int
    let skuID: Int
    var read: MerchantDeskReadEntry? = nil
    var requestID: String? = nil
    @State private var draft = MerchantDeskSkuDesk.Edit(skuName: "", price: "", stock: 0)
    @State private var shownProductID: Int?
    @State private var shownRequestID: String?
    @State private var saveClosed = true

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
                        if let read {
                            let listed = await productIsListed(read)
                            guard listed else { return }
                        }
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
                    Task { await confirmIfSaveOpen() }
                }
                .disabled(read != nil && saveClosed)
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
            if shownProductID == productID, let shownProductID {
                Text(verbatim: readRow(shownProductID))
                    .font(.footnote)
                    .accessibilityIdentifier("merchant.desk.sku.listed")
            }
        }
        .navigationTitle("merchant.desk.sku")
        .task {
            await desk.reopen(productID: productID, skuID: skuID, access: access, token: token)
            if let read {
                // Appearance does not send save. Detail opens only for a listed product id.
                guard await openListedDetail(read) else { return }
            }
            if case .applied = desk.phase {
                await desk.noteLater(productID: productID, skuID: skuID, access: access, token: token)
            } else if case .idle = desk.phase {
                await desk.present(productID: productID, skuID: skuID, access: access, accountID: accountID, token: token)
                if case .editing(let edit) = desk.phase { draft = edit }
            }
            if let read { await showMatchingReceipt(read) }
        }
        .onDisappear { desk.retire() }
    }

    /// The product list id is the detail id. An id that is not on the list does not open detail.
    private func openListedDetail(_ read: MerchantDeskReadEntry) async -> Bool {
        saveClosed = read.saveStaysClosed(saveProbe(), merchantID: access.merchantID)
        do {
            let listed = try await read.productIDs(access: access, token: token)
            guard listed.contains(productID) else {
                clearShown()
                return false
            }
            guard let detail = try await read.detail(productID: productID, access: access, token: token),
                  detail.object?["productId"]?.integer == productID else {
                clearShown()
                return false
            }
            shownProductID = productID
            shownRequestID = nil
            return true
        } catch {
            clearShown()
            return false
        }
    }

    /// A receipt whose request id is not this one is not shown.
    private func showMatchingReceipt(_ read: MerchantDeskReadEntry) async {
        guard shownProductID == productID, let requestID = currentRequestID() else {
            shownRequestID = nil
            return
        }
        let trimmed = MerchantSkuSaveJourney.javaTrim(requestID)
        do {
            guard let receipt = try await read.receipt(requestID: requestID, access: access, token: token),
                  receipt.object?["requestId"]?.string == trimmed else {
                shownRequestID = nil
                return
            }
            shownRequestID = trimmed
        } catch {
            shownRequestID = nil
        }
    }

    private func productIsListed(_ read: MerchantDeskReadEntry) async -> Bool {
        do {
            let listed = try await read.productIDs(access: access, token: token)
            return listed.contains(productID)
        } catch {
            return false
        }
    }

    /// Nil approval keeps the original writer closed. This does not construct an approval or a second writer.
    private func confirmIfSaveOpen() async {
        if let read {
            let closed = read.saveStaysClosed(saveProbe(), merchantID: access.merchantID)
            saveClosed = closed
            if closed { return }
        }
        await desk.confirm(access: access, token: token)
        await desk.noteLater(productID: productID, skuID: skuID, access: access, token: token)
    }

    private func saveProbe() -> MerchantBusinessMutation {
        if case .frozen(let intent) = desk.phase,
           let product = Int(exactly: intent.productID), let sku = Int(exactly: intent.skuID) {
            return .saveSku(productID: product, skuID: sku, name: intent.skuName, price: intent.price,
                            stock: intent.stock, originalPrice: intent.originalPrice, pic: intent.pic,
                            bookable: intent.bookable, slotMinutes: intent.slotMinutes,
                            capacityPerSlot: intent.capacityPerSlot, ruleVersion: intent.ruleVersion)
        }
        return .saveSku(productID: productID, skuID: skuID, name: draft.skuName, price: draft.price,
                        stock: draft.stock, originalPrice: draft.originalPrice, pic: draft.pic,
                        bookable: draft.bookable, slotMinutes: draft.slotMinutes,
                        capacityPerSlot: draft.capacityPerSlot, ruleVersion: nil)
    }

    private func currentRequestID() -> String? {
        if let requestID, MerchantSkuSaveJourney.javaTrim(requestID).isEmpty == false { return requestID }
        switch desk.phase {
        case .applied(let id, _), .unknown(let id):
            return id
        case .frozen(let intent):
            return intent.requestID
        case .idle, .editing, .failed:
            return nil
        }
    }

    private func readRow(_ id: Int) -> String {
        if let shownRequestID { return "\(id) \(shownRequestID)" }
        return String(id)
    }

    private func clearShown() {
        shownProductID = nil
        shownRequestID = nil
    }
}
