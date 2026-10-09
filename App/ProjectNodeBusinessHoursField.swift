import SwiftUI

struct ProjectNodeBusinessHoursHostIdentity: Hashable {
    let owner: ObjectIdentifier
    let chapter: Data
    let node: Data
}

@MainActor final class ProjectNodeBusinessHoursController: ObservableObject {
    struct Capture {
        let controllerID: UUID
        let generation: Int
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let snapshot: ProjectNodeBusinessHours
    }
    struct Opening: Identifiable { let id = UUID(); let capture: Capture }
    let model: ProjectEditModel
    let chapterID: String, nodeID: String
    private let controllerID = UUID()
    private var generation = 0
    @Published private(set) var opening: Opening?
    @Published private(set) var selection: ProjectNodeBusinessHours.Value?
    @Published private(set) var clearSelected = false
    init(model: ProjectEditModel, chapterID: String, nodeID: String) { self.model = model; self.chapterID = chapterID; self.nodeID = nodeID }
    var snapshot: ProjectNodeBusinessHours { .init(draft: model.draft, chapterID: chapterID, nodeID: nodeID) }
    func capture(_ snapshot: ProjectNodeBusinessHours) -> Capture? {
        guard model.fullEdit, snapshot.chapterID.utf8.elementsEqual(chapterID.utf8), snapshot.nodeID.utf8.elementsEqual(nodeID.utf8),
              snapshot.isCurrent(in: model.draft), let lease = model.captureStarterLease() else { return nil }
        return .init(controllerID: controllerID, generation: generation, lease: lease, revision: model.draftMutationRevision, snapshot: snapshot)
    }
    private func isCurrent(_ capture: Capture) -> Bool {
        capture.controllerID == controllerID && capture.generation == generation && model.fullEdit &&
        model.isCurrentStarterLease(capture.lease) && model.draftMutationRevision == capture.revision &&
        capture.snapshot.chapterID.utf8.elementsEqual(chapterID.utf8) && capture.snapshot.nodeID.utf8.elementsEqual(nodeID.utf8) && capture.snapshot.isCurrent(in: model.draft)
    }
    func open(_ capture: Capture) {
        guard opening == nil, isCurrent(capture) else { return }; selection = capture.snapshot.value; clearSelected = false; opening = .init(capture: capture)
    }
    func isCurrent(_ original: Opening) -> Bool { opening?.id == original.id && isCurrent(original.capture) }
    func beginReplacement(_ original: Opening) {
        guard isCurrent(original), selection == nil, !clearSelected else { return }
        // Source picker defaults are staged only after this explicit action.
        // Neither opening the sheet nor staging defaults mutates the draft.
        selection = .init(startHour: 9, startMinute: 0, endHour: 18, endMinute: 0)
    }
    func select(_ value: ProjectNodeBusinessHours.Value, in original: Opening) {
        guard isCurrent(original), selection != nil else { return }; selection = value
    }
    func chooseClear(_ original: Opening) {
        guard isCurrent(original), original.capture.snapshot.value != nil else { return }
        selection = nil; clearSelected = true
    }
    func undoClear(_ original: Opening) {
        guard isCurrent(original), clearSelected else { return }
        selection = original.capture.snapshot.value; clearSelected = false
    }
    func canApply(_ original: Opening) -> Bool {
        isCurrent(original) && (clearSelected ? original.capture.snapshot.value != nil : selection != nil && selection != original.capture.snapshot.value)
    }
    @discardableResult func apply(_ original: Opening) -> Bool {
        guard isCurrent(original) else { return false }
        let next: ProjectEditDraft
        if clearSelected {
            guard original.capture.snapshot.value != nil, let cleared = try? original.capture.snapshot.clearing(in: model.draft) else { return false }
            next = cleared
        } else {
            guard let selection, let replaced = try? original.capture.snapshot.replacing(with: selection, in: model.draft) else { return false }
            next = replaced
        }
        if ProjectEditPendingMaterials.exactData(next) != ProjectEditPendingMaterials.exactData(model.draft) {
            model.draft = next // Existing observer/autosave and Save local own persistence.
        }
        close(original); return true
    }
    func close(_ original: Opening) { guard opening?.id == original.id else { return }; retire() }
    func retire() { opening = nil; selection = nil; clearSelected = false; generation += 1 }
    func binding(_ original: Opening?) -> Binding<Opening?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectNodeBusinessHoursField: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectNodeBusinessHoursController
    init(model: ProjectEditModel, chapterID: String, nodeID: String) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID, nodeID: nodeID))
    }
    var body: some View {
        let snapshot = controller.snapshot
        let capture = controller.capture(snapshot)
        let original = controller.opening
        Section {
            if let text = snapshot.rawText, !text.isEmpty { Text(verbatim: text).textSelection(.enabled) }
            else if snapshot.reason == nil { Text("projectNodeHours.empty", tableName: "ProjectNodeBusinessHours") }
            if let reason = snapshot.reason { Text(LocalizedStringKey("projectNodeHours.reason." + reason.rawValue), tableName: "ProjectNodeBusinessHours").font(.caption) }
            Button { if let capture { controller.open(capture) } } label: { Text("projectNodeHours.edit", tableName: "ProjectNodeBusinessHours") }
                .disabled(capture == nil || original != nil).accessibilityIdentifier("projectNodeHours.edit")
        } header: { Text("projectNodeHours.title", tableName: "ProjectNodeBusinessHours") }
        .sheet(item: controller.binding(original)) { original in sheet(original) }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onDisappear { controller.retire() }
    }
    private func sheet(_ original: ProjectNodeBusinessHoursController.Opening) -> some View {
        NavigationStack {
            Form {
                if let value = controller.selection {
                    Section {
                        timeFields(original, start: true)
                        timeFields(original, start: false)
                        Text(verbatim: value.text).font(.headline).accessibilityIdentifier("projectNodeHours.preview")
                        if original.capture.snapshot.value != nil {
                            Button(role: .destructive) { controller.chooseClear(original) } label: {
                                Text("projectNodeHours.clear", tableName: "ProjectNodeBusinessHours")
                            }.accessibilityIdentifier("projectNodeHours.clear")
                        }
                    }
                } else if controller.clearSelected {
                    Section {
                        Text("projectNodeHours.clearPending", tableName: "ProjectNodeBusinessHours")
                            .accessibilityIdentifier("projectNodeHours.clearPending")
                        Button { controller.undoClear(original) } label: {
                            Text("projectNodeHours.keep", tableName: "ProjectNodeBusinessHours")
                        }.accessibilityIdentifier("projectNodeHours.keep")
                    }
                } else {
                    Section {
                        Text("projectNodeHours.empty", tableName: "ProjectNodeBusinessHours")
                        Button { controller.beginReplacement(original) } label: { Text("projectNodeHours.begin", tableName: "ProjectNodeBusinessHours") }
                            .accessibilityIdentifier("projectNodeHours.begin")
                    }
                }
                Section { Text("projectNodeHours.scope", tableName: "ProjectNodeBusinessHours").font(.caption) }
            }
            .navigationTitle(Text("projectNodeHours.title", tableName: "ProjectNodeBusinessHours"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { controller.apply(original) } label: { Text("projectNodeHours.apply", tableName: "ProjectNodeBusinessHours") }
                        .disabled(!controller.canApply(original)).accessibilityIdentifier("projectNodeHours.apply")
                }
            }
        }
    }
    private func timeFields(_ original: ProjectNodeBusinessHoursController.Opening, start: Bool) -> some View {
        VStack(alignment: .leading) {
            Text(start ? "projectNodeHours.start" : "projectNodeHours.end", tableName: "ProjectNodeBusinessHours").font(.headline)
            HStack {
                Picker(selection: component(original, start: start, hour: true)) {
                    ForEach(0...23, id: \.self) { Text(verbatim: String($0)).tag($0) }
                } label: { Text("projectNodeHours.hour", tableName: "ProjectNodeBusinessHours") }
                Picker(selection: component(original, start: start, hour: false)) {
                    ForEach(0...59, id: \.self) { Text(verbatim: String($0)).tag($0) }
                } label: { Text("projectNodeHours.minute", tableName: "ProjectNodeBusinessHours") }
            }
        }
    }
    private func component(_ original: ProjectNodeBusinessHoursController.Opening, start: Bool, hour: Bool) -> Binding<Int> {
        .init(get: {
            guard controller.isCurrent(original), let value = controller.selection else { return 0 }
            return start ? (hour ? value.startHour : value.startMinute) : (hour ? value.endHour : value.endMinute)
        }, set: { next in
            guard controller.isCurrent(original), let current = controller.selection,
                  let value = ProjectNodeBusinessHours.Value(startHour: start && hour ? next : current.startHour,
                    startMinute: start && !hour ? next : current.startMinute, endHour: !start && hour ? next : current.endHour,
                    endMinute: !start && !hour ? next : current.endMinute) else { return }
            controller.select(value, in: original)
        })
    }
}
