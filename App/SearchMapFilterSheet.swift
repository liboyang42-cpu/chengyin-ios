import SwiftUI

@MainActor struct SearchMapFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GlobalSearchQuery
    @State private var minimum: String
    @State private var maximum: String
    @State private var start: String
    @State private var end: String
    @State private var invalid = false
    let categories: [DiscoveryCategory]
    let categoryFailed: Bool
    let apply: (GlobalSearchQuery) -> Void
    init(filter: GlobalSearchQuery, categories: [DiscoveryCategory], categoryFailed: Bool, apply: @escaping (GlobalSearchQuery) -> Void) {
        _draft = State(initialValue: filter)
        _minimum = State(initialValue: filter.minimumPrice.map { String($0) } ?? "")
        _maximum = State(initialValue: filter.maximumPrice.map { String($0) } ?? "")
        _start = State(initialValue: filter.startDate ?? ""); _end = State(initialValue: filter.endDate ?? "")
        self.categories = categories; self.categoryFailed = categoryFailed; self.apply = apply
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("searchMap.categories") {
                    Picker("searchMap.category", selection: $draft.categoryID) {
                        Text("searchMap.all").tag(Int?.none)
                        ForEach(categories) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                    }
                    if categoryFailed { Text("searchMap.categoryFailed").font(.caption) }
                }
                Section("searchMap.dates") {
                    TextField("searchMap.startDate", text: $start).accessibilityIdentifier("searchMap.filter.start")
                    TextField("searchMap.endDate", text: $end).accessibilityIdentifier("searchMap.filter.end")
                    Text("searchMap.dateFormat").font(.caption).foregroundStyle(.secondary)
                }
                Section("searchMap.price") {
                    TextField("searchMap.minimum", text: $minimum).keyboardType(.decimalPad).accessibilityIdentifier("searchMap.filter.min")
                    TextField("searchMap.maximum", text: $maximum).keyboardType(.decimalPad).accessibilityIdentifier("searchMap.filter.max")
                    Text("searchMap.clientFilters").font(.footnote).foregroundStyle(.secondary)
                }
                if invalid { Label("searchMap.invalidInput", systemImage: "exclamationmark.circle").accessibilityIdentifier("searchMap.filter.invalid") }
                Button("searchMap.resetFilters") {
                    draft = GlobalSearchQuery(keyword: draft.keyword); minimum = ""; maximum = ""; start = ""; end = ""; invalid = false
                }.frame(minHeight: 44)
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
                .appNavigationTitle("searchMap.filters")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("searchMap.cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("searchMap.apply") { commit() }.accessibilityIdentifier("searchMap.filter.apply") }
                }
        }
    }
    private func commit() {
        func optional(_ text: String) -> String? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value
        }
        if let value = optional(minimum), Double(value) == nil { invalid = true; return }
        if let value = optional(maximum), Double(value) == nil { invalid = true; return }
        draft.minimumPrice = optional(minimum).flatMap(Double.init); draft.maximumPrice = optional(maximum).flatMap(Double.init)
        draft.startDate = optional(start); draft.endDate = optional(end)
        do { try draft.validate(); apply(draft); dismiss() } catch { invalid = true }
    }
}
