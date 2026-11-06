/// Offset pagination can repeat a review when new reviews shift page boundaries.
/// Keep its original display position, but replace the whole row and its readback
/// page together. No old version or permission is combined with a newer page.
struct PublicMerchantReviewRows {
    private(set) var items: [PublicMerchantReviewPage.Item] = []
    private(set) var pages: [Int: Int] = [:]

    mutating func accept(_ page: PublicMerchantReviewPage) {
        if page.pageNum == 1 { items = []; pages = [:] }
        var indices = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        for item in page.items {
            if let index = indices[item.id] { items[index] = item }
            else { indices[item.id] = items.count; items.append(item) }
            pages[item.id] = page.pageNum
        }
    }
}
