import SwiftUI

@MainActor struct ProjectEditDatePickerContext {
    let model: ProjectEditModel
    let field: ProjectEditDateSelection.Field
    struct Identity: Hashable { let model: ObjectIdentifier; let field: ProjectEditDateSelection.Field }
    var id: Identity { .init(model: ObjectIdentifier(model), field: field) }
}

@MainActor final class ProjectEditDatePickerController: ObservableObject {
    struct Capture {
        let controllerID: UUID
        let generation: Int
        let incarnation: UUID
        let session: ProjectEditSession?
        let identity: ProjectEditDraftIdentity?
        let revision: Int
        let bytes: Data
        let raw: String
        let timeZoneID: String
    }
    struct Presentation: Identifiable {
        let id = UUID()
        let capture: Capture
        let initialDate: Date
        let wasEmpty: Bool
    }
    let context: ProjectEditDatePickerContext
    private let controllerID = UUID()
    private var generation = 0
    private let timeZone: () -> TimeZone
    private let now: () -> Date
    @Published private(set) var presentation: Presentation?
    @Published private(set) var invalidRange = false
    init(context: ProjectEditDatePickerContext, timeZone: @escaping () -> TimeZone = { .autoupdatingCurrent }, now: @escaping () -> Date = Date.init) {
        self.context = context; self.timeZone = timeZone; self.now = now
    }
    var displayTimeZone: TimeZone { TimeZone(identifier: timeZone().identifier) ?? timeZone() }
    func capture() -> Capture? {
        let model = context.model
        guard model.fullEdit, context.field.editable(in: model.draft), let raw = context.field.raw(in: model.draft),
              raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ProjectEditDateSelection.date(raw, ending: context.field.ending) != nil,
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return nil }
        return .init(controllerID: controllerID, generation: generation, incarnation: model.editorIncarnation,
                     session: model.coordinator.session, identity: model.coordinator.identity,
                     revision: model.draftMutationRevision, bytes: bytes, raw: raw, timeZoneID: timeZone().identifier)
    }
    func isCurrent(_ value: Capture) -> Bool {
        let model = context.model
        return value.controllerID == controllerID && value.generation == generation && model.fullEdit &&
            model.editorIncarnation == value.incarnation && model.coordinator.session == value.session && model.coordinator.identity == value.identity &&
            model.draftMutationRevision == value.revision && ProjectEditPendingMaterials.exactData(model.draft) == value.bytes &&
            timeZone().identifier == value.timeZoneID && context.field.editable(in: model.draft) &&
            context.field.raw(in: model.draft).map { $0.utf8.elementsEqual(value.raw.utf8) } == true
    }
    func isCurrent(_ value: Presentation) -> Bool { presentation?.id == value.id && isCurrent(value.capture) }
    func open(_ value: Capture?) {
        guard let value, isCurrent(value), presentation == nil else { return }
        let original = ProjectEditDateSelection.date(value.raw, ending: context.field.ending)
        guard original != nil || value.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        invalidRange = false
        presentation = .init(capture: value, initialDate: original ?? now(), wasEmpty: original == nil)
    }
    func apply(_ selected: Date, to value: Presentation, explicitlySelected: Bool) {
        guard isCurrent(value), !value.wasEmpty || explicitlySelected else { return }
        do {
            let next = try ProjectEditDateSelection.applying(selected, field: context.field, to: context.model.draft)
            if ProjectEditPendingMaterials.exactData(next) != value.capture.bytes { context.model.draft = next }
            close(value)
        } catch { invalidRange = true }
    }
    func close(_ value: Presentation) {
        guard presentation?.id == value.id else { return }
        presentation = nil; invalidRange = false; generation += 1
    }
    func retire() { presentation = nil; invalidRange = false; generation += 1 }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectEditDatePickerEntry: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectEditDatePickerController
    @Environment(\.locale) private var locale
    init(context: ProjectEditDatePickerContext) {
        model = context.model; _controller = StateObject(wrappedValue: .init(context: context))
    }
    var body: some View {
        let capture = controller.capture(), original = controller.presentation
        VStack(alignment: .leading, spacing: 4) {
            if let raw = controller.context.field.raw(in: model.draft),
               let date = ProjectEditDateSelection.date(raw, ending: controller.context.field.ending) {
                Text(verbatim: formatted(date, zone: controller.displayTimeZone))
                Text(verbatim: controller.displayTimeZone.identifier).font(.caption).foregroundStyle(.secondary)
            }
            Button { controller.open(capture) } label: {
                Text("projectDatePicker.choose", tableName: "ProjectEditDatePicker")
            }.disabled(capture == nil)
                .accessibilityIdentifier("projectDatePicker.open." + controller.context.field.identifier)
            Text("projectDatePicker.manualBeijing", tableName: "ProjectEditDatePicker").font(.caption).foregroundStyle(.secondary)
            if let raw = controller.context.field.raw(in: model.draft), !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               ProjectEditDateSelection.date(raw, ending: controller.context.field.ending) == nil {
                Text("projectDatePicker.unknown", tableName: "ProjectEditDatePicker").font(.caption)
            }
        }
        .sheet(item: controller.binding(original)) { value in ProjectEditDatePickerSheet(controller: controller, original: value) }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in controller.retire() }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onDisappear { controller.retire() }
    }
    private func formatted(_ date: Date, zone: TimeZone) -> String {
        let format = DateFormatter(); format.locale = locale; format.calendar = Calendar(identifier: .gregorian)
        format.timeZone = zone; format.dateStyle = .medium; format.timeStyle = .short
        return format.string(from: date)
    }
}

@MainActor private struct ProjectEditDatePickerSheet: View {
    @ObservedObject var controller: ProjectEditDatePickerController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectEditDatePickerController.Presentation
    @State private var selected: Date
    @State private var explicitlySelected = false
    init(controller: ProjectEditDatePickerController, original: ProjectEditDatePickerController.Presentation) {
        self.controller = controller; model = controller.context.model; self.original = original
        _selected = State(initialValue: original.initialDate)
    }
    var body: some View {
        NavigationStack {
            Form {
                if controller.isCurrent(original) {
                    DatePicker(selection: $selected, displayedComponents: [.date, .hourAndMinute]) {
                        Text("projectDatePicker.phoneTime", tableName: "ProjectEditDatePicker")
                    }.datePickerStyle(.graphical)
                        .environment(\.timeZone, TimeZone(identifier: original.capture.timeZoneID) ?? controller.displayTimeZone)
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                        .onChange(of: selected) { _, _ in explicitlySelected = true }
                    Text(verbatim: original.capture.timeZoneID).font(.caption)
                    Section {
                        LabeledContent {
                            Text(verbatim: ProjectEditDateSelection.beijingValue(selected) ?? "")
                                .accessibilityIdentifier("projectDatePicker.beijingPreview")
                        } label: { Text("projectDatePicker.beijingTime", tableName: "ProjectEditDatePicker") }
                        Text("projectDatePicker.serverAuthority", tableName: "ProjectEditDatePicker").font(.caption)
                    }
                    if original.wasEmpty && !explicitlySelected {
                        Button { explicitlySelected = true } label: { Text("projectDatePicker.useShownTime", tableName: "ProjectEditDatePicker") }
                    }
                    if controller.invalidRange { Text("projectDatePicker.invalidRange", tableName: "ProjectEditDatePicker") }
                    Button { controller.apply(selected, to: original, explicitlySelected: explicitlySelected) } label: {
                        Text("projectDatePicker.confirm", tableName: "ProjectEditDatePicker")
                    }.disabled(original.wasEmpty && !explicitlySelected).accessibilityIdentifier("projectDatePicker.confirm")
                } else { Text("projectStarter.stale") }
            }
            .navigationTitle(Text("projectDatePicker.title", tableName: "ProjectEditDatePicker"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } } }
        }
    }
}
