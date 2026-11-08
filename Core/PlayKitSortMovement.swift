/// Local adjacent-row movement by the existing public item ID. This never
/// examines an answer order or determines whether the task was completed.
public enum PlayKitSortMovement {
    public static func moving(_ itemID: String, by offset: Int, in order: [String]) -> [String]? {
        guard offset == -1 || offset == 1,
              Set(order).count == order.count,
              let index = order.firstIndex(of: itemID) else { return nil }
        let destination = index + offset
        guard order.indices.contains(destination) else { return nil }
        var next = order
        let item = next.remove(at: index)
        next.insert(item, at: destination)
        return next
    }
}
