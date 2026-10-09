import SwiftUI
import Combine

private struct ProjectNodePlaceReaderKey: EnvironmentKey {
    static let defaultValue: (any SearchMapReading)? = nil
}
extension EnvironmentValues {
    var projectNodePlaceReader: (any SearchMapReading)? {
        get { self[ProjectNodePlaceReaderKey.self] }
        set { self[ProjectNodePlaceReaderKey.self] = newValue }
    }
}

@MainActor final class ProjectNodePlacePickerController: ObservableObject {
    struct Opening: Identifiable {
        let id = UUID()
        let controllerID: UUID
        let generation: UUID
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let scope: UUID?
        let snapshot: ProjectNodePlaceTargetSnapshot
    }
    struct Input: Equatable {
        var latitude = "", longitude = "", keyword = ""
        static func == (a: Self, b: Self) -> Bool {
            Data(a.latitude.utf8) == Data(b.latitude.utf8) && Data(a.longitude.utf8) == Data(b.longitude.utf8) && Data(a.keyword.utf8) == Data(b.keyword.utf8)
        }
    }
    struct SearchAction { let openingID: UUID; let generation: UUID; let input: Input }
    enum State: Equatable { case idle, loading, loaded, empty, unavailable, failed, invalid }
    let model: ProjectEditModel
    let reader: (any SearchMapReading)?
    let chapterID: String, nodeID: String
    let pendingTarget: ProjectPendingNodePlaceContext?
    @Published private(set) var opening: Opening?
    @Published private(set) var input = Input()
    @Published private(set) var state: State = .idle
    @Published private(set) var rows: [SearchMapCityNode] = []
    @Published private(set) var selected: SearchMapCityNode?
    private let controllerID = UUID()
    private var generation = UUID()
    @Published private var active = false
    private var requestID = UUID()
    private var resultsAreaRevision: UInt64?
    private var pendingChanges: AnyCancellable?
    init(model: ProjectEditModel, reader: (any SearchMapReading)?, chapterID: String, nodeID: String, pendingTarget: ProjectPendingNodePlaceContext? = nil) {
        self.model = model; self.reader = reader; self.chapterID = chapterID; self.nodeID = nodeID; self.pendingTarget = pendingTarget
        pendingChanges = pendingTarget?.controller.objectWillChange.sink { [weak self] _ in self?.retire() }
    }
    func setActive(_ value: Bool) { active = value; if !value { retire() } }
    func capture() -> Opening? {
        guard active, opening == nil, model.fullEdit, let lease = model.captureStarterLease() else { return nil }
        let snapshot: ProjectNodePlaceTargetSnapshot
        if let pendingTarget {
            guard pendingTarget.controller.model === model, let captured = pendingTarget.capture() else { return nil }
            snapshot = .pending(captured)
        } else {
            let saved = ProjectNodePlaceSelection(draft: model.draft, chapterID: chapterID, nodeID: nodeID)
            guard saved.available else { return nil }; snapshot = .saved(saved)
        }
        return .init(controllerID: controllerID, generation: generation, lease: lease,
            revision: model.draftMutationRevision, scope: reader?.scope, snapshot: snapshot)
    }
    private func isValid(_ value: Opening) -> Bool {
        active && value.controllerID == controllerID && value.generation == generation &&
        model.fullEdit && model.isCurrentStarterLease(value.lease) &&
        model.draftMutationRevision == value.revision && value.snapshot.isCurrent(model: model) && reader?.scope == value.scope
    }
    func open(_ value: Opening) {
        guard opening == nil, isValid(value) else { return }
        input = Input(); invalidateResults(); opening = value
        if reader?.isConfigured != true || reader?.isAuthenticated != true { state = .unavailable }
    }
    func isCurrent(_ value: Opening) -> Bool { opening?.id == value.id && isValid(value) }
    func edit(_ value: Input, in original: Opening) {
        guard isCurrent(original), input != value else { return }
        input = value; invalidateResults()
    }
    private func invalidateResults() {
        requestID = UUID(); resultsAreaRevision = nil; rows = []; selected = nil; state = .idle
    }
    func captureSearch(_ original: Opening) -> SearchAction? {
        guard isCurrent(original), state != .loading else { return nil }
        return .init(openingID: original.id, generation: requestID, input: input)
    }
    func search(_ original: Opening, action: SearchAction?) async {
        guard let action, action.openingID == original.id, action.generation == requestID,
              action.input == input, isCurrent(original), state != .loading else { return }
        invalidateResults()
        guard let reader, reader.isConfigured, reader.isAuthenticated else { state = .unavailable; return }
        let capturedInput = input
        guard let area = try? RoamSearchArea.manual(latitude: input.latitude, longitude: input.longitude),
              input.keyword.utf8.count <= 256,
              input.keyword == input.keyword.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.keyword.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { state = .invalid; return }
        reader.selectManualArea(area)
        let areaRevision = reader.manualAreaRevision, ticket = requestID
        guard isCurrent(original) else { return }
        state = .loading
        func accepts() -> Bool {
            !Task.isCancelled && isCurrent(original) && requestID == ticket && input == capturedInput && reader.manualAreaRevision == areaRevision
        }
        do {
            let result = try await reader.cityNodes(.init(filter: .init(keyword: capturedInput.keyword), area: area))
            guard accepts() else { return }
            guard Set(result.map(\.id)).count == result.count, result.allSatisfy({ $0.id > 0 }) else { throw APIError.malformedResponse }
            rows = result; resultsAreaRevision = areaRevision; state = result.isEmpty ? .empty : .loaded
        } catch {
            guard accepts() else { return }
            state = error as? APIError == .notConfigured || error as? APIError == .unauthorized ? .unavailable : .failed
        }
    }
    func choose(_ row: SearchMapCityNode, in original: Opening) {
        guard isCurrent(original), state == .loaded, resultsAreaRevision == reader?.manualAreaRevision,
              rows.contains(row), ProjectNodePlaceSelection.permits(row) else { return }
        selected = row
    }
    func canApply(_ original: Opening) -> Bool {
        guard isCurrent(original), reader?.isConfigured == true, reader?.isAuthenticated == true,
              state == .loaded, resultsAreaRevision == reader?.manualAreaRevision,
              let selected, rows.contains(selected), ProjectNodePlaceSelection.permits(selected) else { return false }
        return true
    }
    @discardableResult func apply(_ original: Opening) -> Bool {
        guard canApply(original), let selected, original.snapshot.apply(selected, model: model) else { return false }
        close(original); return true
    }
    func close(_ original: Opening) { guard opening?.id == original.id else { return }; retire() }
    func retire() { generation = UUID(); opening = nil; input = Input(); invalidateResults() }
    func binding(_ original: Opening?) -> Binding<Opening?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectNodePlacePickerEntry: View {
    @ObservedObject var model: ProjectEditModel
    let chapterID: String, nodeID: String
    @Environment(\.projectNodePlaceReader) private var reader
    private struct Identity: Hashable { let model: ObjectIdentifier; let reader: ObjectIdentifier?; let chapter: Data; let node: Data }
    var body: some View {
        ProjectNodePlacePickerHost(model: model, reader: reader, chapterID: chapterID, nodeID: nodeID)
            .id(Identity(model: ObjectIdentifier(model), reader: reader.map(ObjectIdentifier.init), chapter: Data(chapterID.utf8), node: Data(nodeID.utf8)))
    }
}
@MainActor struct ProjectNodePlacePickerHost: View {
    @ObservedObject var model: ProjectEditModel
    @StateObject private var controller: ProjectNodePlacePickerController
    @Environment(\.scenePhase) private var scenePhase
    init(model: ProjectEditModel, reader: (any SearchMapReading)?, chapterID: String, nodeID: String, pendingTarget: ProjectPendingNodePlaceContext? = nil) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, reader: reader, chapterID: chapterID, nodeID: nodeID, pendingTarget: pendingTarget))
    }
    var body: some View {
        let original = controller.opening, captured = controller.capture()
        Section {
            Button { guard scenePhase == .active, let captured else { return }; controller.open(captured) } label: {
                Text("projectPlace.open", tableName: "ProjectNodePlacePicker")
            }.disabled(captured == nil || original != nil).accessibilityIdentifier("projectPlace.open")
        }
        .sheet(item: controller.binding(original)) { value in ProjectNodePlacePickerSheet(controller: controller, original: value) }
        .onAppear { controller.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in controller.setActive(phase == .active) }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onDisappear { controller.setActive(false) }
    }
}
@MainActor private struct ProjectNodePlacePickerSheet: View {
    @ObservedObject var controller: ProjectNodePlacePickerController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectNodePlacePickerController.Opening
    init(controller: ProjectNodePlacePickerController, original: ProjectNodePlacePickerController.Opening) {
        self.controller = controller; self.original = original; model = controller.model
    }
    private func input(_ path: WritableKeyPath<ProjectNodePlacePickerController.Input, String>) -> Binding<String> {
        .init(get: { controller.input[keyPath: path] }, set: { value in var next = controller.input; next[keyPath: path] = value; controller.edit(next, in: original) })
    }
    var body: some View {
        NavigationStack {
            Form {
                if controller.isCurrent(original) {
                    Section {
                        Text("projectPlace.centerHint", tableName: "ProjectNodePlacePicker")
                        TextField(text: input(\.latitude)) { Text("projectPlace.latitude", tableName: "ProjectNodePlacePicker") }.keyboardType(.numbersAndPunctuation)
                        TextField(text: input(\.longitude)) { Text("projectPlace.longitude", tableName: "ProjectNodePlacePicker") }.keyboardType(.numbersAndPunctuation)
                        TextField(text: input(\.keyword)) { Text("projectPlace.keyword", tableName: "ProjectNodePlacePicker") }
                        Button { let action = controller.captureSearch(original); Task { await controller.search(original, action: action) } } label: { Text("projectPlace.search", tableName: "ProjectNodePlacePicker") }
                            .disabled(controller.state == .loading).accessibilityIdentifier("projectPlace.search")
                    }
                    switch controller.state {
                    case .idle: EmptyView()
                    case .loading: ProgressView()
                    case .loaded: EmptyView()
                    case .empty: Text("projectPlace.empty", tableName: "ProjectNodePlacePicker")
                    case .failed: Text("projectPlace.failed", tableName: "ProjectNodePlacePicker")
                    case .unavailable: Text("projectPlace.unavailable", tableName: "ProjectNodePlacePicker")
                    case .invalid: Text("projectPlace.invalid", tableName: "ProjectNodePlacePicker")
                    }
                    ForEach(controller.rows) { row in
                        Button { controller.choose(row, in: original) } label: {
                            VStack(alignment: .leading) {
                                Text(verbatim: row.name)
                                if let coordinate = row.coordinate { Text(verbatim: "GCJ-02: \(coordinate.latitude), \(coordinate.longitude)").font(.caption) }
                                if !ProjectNodePlaceSelection.permits(row) { Text("projectPlace.invalidResult", tableName: "ProjectNodePlacePicker") }
                                if controller.selected == row { Image(systemName: "checkmark") }
                            }
                        }.disabled(!ProjectNodePlaceSelection.permits(row))
                    }
                    if let selected = controller.selected {
                        Section {
                            Text("projectPlace.applyHint", tableName: "ProjectNodePlacePicker")
                            Text(verbatim: selected.name)
                            Button { controller.apply(original) } label: { Text("projectPlace.apply", tableName: "ProjectNodePlacePicker") }
                                .disabled(!controller.canApply(original)).accessibilityIdentifier("projectPlace.apply")
                        }
                    }
                } else { Text("projectStarter.stale") }
            }.navigationTitle(Text("projectPlace.title", tableName: "ProjectNodePlacePicker"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } } }
        }
    }
}
