import SwiftUI

/// Mini-program object-cards empty copy: 还没有收过东西 for 全部, 这一类还没收过东西 for a category.
/// A single Text so the existing `objects.empty` identifier stays a static text.
struct ObjectCardsEmptyTitle: View {
    let isAllCategories: Bool
    var body: some View {
        if isAllCategories { Text("objectCards.emptyAll") } else { Text("objects.empty") }
    }
}
