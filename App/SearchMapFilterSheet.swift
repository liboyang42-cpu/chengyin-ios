import SwiftUI

@MainActor struct SearchMapFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GlobalSearchQuery
    @State private var minimum: String
    @State private var maximum: String
    @State private var dateDraft: SearchMapDateFilterDraft
    @State private var datePicker: SearchMapDatePickerDraft?
    @State private var invalid = false
    @State private var tag: String
    @State private var cityRole: String
    @State private var sortType: Int
    let applyCityOptions: ((String, String, Int) -> Void)?
    let categories: [DiscoveryCategory]
    let categoryFailed: Bool
    let apply: (GlobalSearchQuery) -> Void
    init(filter: GlobalSearchQuery, categories: [DiscoveryCategory], categoryFailed: Bool,
         tag: String = "", cityRole: String = "", sortType: Int = 1,
         applyCityOptions: ((String, String, Int) -> Void)? = nil, apply: @escaping (GlobalSearchQuery) -> Void) {
        _draft = State(initialValue: filter)
        _tag = State(initialValue: tag); _cityRole = State(initialValue: cityRole); _sortType = State(initialValue: sortType)
        self.applyCityOptions = applyCityOptions
        _minimum = State(initialValue: filter.minimumPrice.map { String($0) } ?? "")
        _maximum = State(initialValue: filter.maximumPrice.map { String($0) } ?? "")
        _dateDraft = State(initialValue: SearchMapDateFilterDraft(filter: filter))
        self.categories = categories; self.categoryFailed = categoryFailed; self.apply = apply
    }
    var body: some View {
        NavigationStack {
            Form {
                if applyCityOptions != nil {
                    Section("searchMap.cityOptions") {
                        TextField("searchMap.tag", text: $tag).accessibilityIdentifier("searchMap.tag")
                        TextField("searchMap.cityRole", text: $cityRole).accessibilityIdentifier("searchMap.cityRole")
                        Picker("searchMap.sort", selection: $sortType) {
                            Text("searchMap.nearest").tag(1); Text("searchMap.popular").tag(2)
                        }
                    }
                }
                Section("searchMap.categories") {
                    Picker("searchMap.category", selection: $draft.categoryID) {
                        Text("searchMap.all").tag(Int?.none)
                        ForEach(categories) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                    }
                    .accessibilityIdentifier("searchMap.filter.category")
                    if categoryFailed { Text("searchMap.categoryFailed").font(.caption) }
                }
                Section("searchMap.dates") {
                    if applyCityOptions != nil {
                        Button("mapDatePreset.today") { selectDatePreset(.today) }
                            .frame(minHeight: 44).accessibilityIdentifier("mapDatePreset.today")
                        Button("mapDatePreset.tomorrow") { selectDatePreset(.tomorrow) }
                            .frame(minHeight: 44).accessibilityIdentifier("mapDatePreset.tomorrow")
                        Text("mapDatePreset.disclosure").font(.footnote).foregroundStyle(.secondary)
                    }
                    TextField("searchMap.startDate", text: $dateDraft.startDate).accessibilityIdentifier("searchMap.filter.start")
                    Button("mapDatePicker.start") { openDatePicker(.start) }
                        .frame(minHeight: 44).accessibilityIdentifier("mapDatePicker.open.start")
                    TextField("searchMap.endDate", text: $dateDraft.endDate).accessibilityIdentifier("searchMap.filter.end")
                    Button("mapDatePicker.end") { openDatePicker(.end) }
                        .frame(minHeight: 44).accessibilityIdentifier("mapDatePicker.open.end")
                    Text("searchMap.dateFormat").font(.caption).foregroundStyle(.secondary)
                }
                Section("searchMap.price") {
                    TextField("searchMap.minimum", text: $minimum).keyboardType(.decimalPad).accessibilityIdentifier("searchMap.filter.min")
                    TextField("searchMap.maximum", text: $maximum).keyboardType(.decimalPad).accessibilityIdentifier("searchMap.filter.max")
                    Text("searchMap.clientFilters").font(.footnote).foregroundStyle(.secondary)
                }
                if invalid { Label("searchMap.invalidInput", systemImage: "exclamationmark.circle").accessibilityIdentifier("searchMap.filter.invalid") }
                Button("searchMap.resetFilters") {
                    draft = GlobalSearchQuery(keyword: draft.keyword); minimum = ""; maximum = ""; dateDraft = SearchMapDateFilterDraft(filter: draft); invalid = false
                    tag = ""; cityRole = ""; sortType = 1
                }.frame(minHeight: 44).accessibilityIdentifier("searchMap.filter.reset")
            }.textInputAutocapitalization(.never).autocorrectionDisabled()
                .appNavigationTitle("searchMap.filters")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("searchMap.cancel") { dismiss() }.accessibilityIdentifier("searchMap.filter.cancel") }
                    ToolbarItem(placement: .confirmationAction) { Button("searchMap.apply") { commit() }.accessibilityIdentifier("searchMap.filter.apply") }
                }
        }
        .sheet(item: $datePicker) { picker in
            SearchMapDatePickerSheet(initial: picker) { selection in
                do {
                    dateDraft = try selection.confirming(in: dateDraft)
                    invalid = false; datePicker = nil
                    return true
                } catch { return false }
            }
        }
    }
    private func openDatePicker(_ field: SearchMapDatePickerField) {
        datePicker = SearchMapDatePickerDraft(field: field, draft: dateDraft)
    }
    private func selectDatePreset(_ preset: SearchMapDatePreset) {
        do { try dateDraft.select(preset); invalid = false } catch { invalid = true }
    }
    private func commit() {
        func optional(_ text: String) -> String? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value
        }
        if let value = optional(minimum), Double(value) == nil { invalid = true; return }
        if let value = optional(maximum), Double(value) == nil { invalid = true; return }
        draft.minimumPrice = optional(minimum).flatMap(Double.init); draft.maximumPrice = optional(maximum).flatMap(Double.init)
        do {
            let applied = try dateDraft.applying(to: draft)
            applyCityOptions?(tag, cityRole, sortType); apply(applied); dismiss()
        } catch { invalid = true }
    }
}

/// Numeric native wheels deliberately keep Gregorian civil dates separate from
/// instants, regardless of the device's preferred calendar or display locale.
@MainActor private struct SearchMapDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var picker: SearchMapDatePickerDraft
    @State private var invalid = false
    let confirm: (SearchMapDatePickerDraft) -> Bool

    init(initial: SearchMapDatePickerDraft, confirm: @escaping (SearchMapDatePickerDraft) -> Bool) {
        _picker = State(initialValue: initial)
        self.confirm = confirm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: picker.value).font(.headline)
                        .accessibilityIdentifier("mapDatePicker.value")
                    Text("mapDatePicker.disclosure").font(.footnote).foregroundStyle(.secondary)
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                    layout {
                        wheel("mapDatePicker.year", values: SearchMapDatePickerDraft.years,
                              selection: Binding(get: { picker.year }, set: { picker.selectYear($0); invalid = false }),
                              identifier: "mapDatePicker.year")
                        wheel("mapDatePicker.month", values: 1...12,
                              selection: Binding(get: { picker.month }, set: { picker.selectMonth($0); invalid = false }),
                              identifier: "mapDatePicker.month")
                        wheel("mapDatePicker.day", values: picker.days,
                              selection: Binding(get: { picker.day }, set: { picker.selectDay($0); invalid = false }),
                              identifier: "mapDatePicker.day")
                    }
                    if invalid {
                        Label("mapDatePicker.invalidOrder", systemImage: "exclamationmark.circle")
                            .accessibilityIdentifier("mapDatePicker.invalidOrder")
                    }
                }.padding()
            }
            .appNavigationTitle(picker.field == .start ? "mapDatePicker.start" : "mapDatePicker.end")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("searchMap.cancel") { dismiss() }.accessibilityIdentifier("mapDatePicker.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("mapDatePicker.confirm") { invalid = !confirm(picker) }
                        .accessibilityIdentifier("mapDatePicker.confirm")
                }
            }
        }
    }

    private func wheel(_ title: LocalizedStringKey, values: ClosedRange<Int>, selection: Binding<Int>, identifier: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.subheadline)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { Text(verbatim: String($0)).tag($0) }
            }
            .pickerStyle(.wheel).labelsHidden().frame(height: 160).clipped()
            .accessibilityIdentifier(identifier)
        }.frame(maxWidth: .infinity)
    }
}
