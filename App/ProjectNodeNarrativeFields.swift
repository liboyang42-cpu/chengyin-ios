import SwiftUI

struct ProjectNodeNarrativeHostIdentity: Hashable {
    let model: ObjectIdentifier
    let chapterID: String
    let nodeID: String
}

@MainActor final class ProjectNodeNarrativeController: ObservableObject {
    struct Destination: Identifiable {
        let id = UUID()
        let lease: ProjectEditStarterController.Lease
        let chapterID: String
        let nodeID: String
        let hostGeneration: Int
        let revision: Int
        let draftBytes: Data
        let name: String
    }
    let model: ProjectEditModel
    let hostIdentity: ProjectNodeNarrativeHostIdentity
    private var hostGeneration = 0
    @Published private(set) var destination: Destination?
    @Published private(set) var text = ""
    @Published private(set) var saveUnconfirmed = false
    init(model: ProjectEditModel, chapterID: String, nodeID: String) {
        self.model = model
        hostIdentity = .init(model: ObjectIdentifier(model), chapterID: chapterID, nodeID: nodeID)
    }
    func matchesHost(model: ProjectEditModel, chapterID: String, nodeID: String) -> Bool {
        self.model === model && hostIdentity == .init(model: ObjectIdentifier(model), chapterID: chapterID, nodeID: nodeID)
    }

    func capture(chapterID: String, nodeID: String) -> Destination? {
        guard matchesHost(model: model, chapterID: chapterID, nodeID: nodeID), let lease = model.captureStarterLease(),
              model.draft.chapters.filter({ $0.id == chapterID }).count == 1,
              let chapter = model.draft.chapters.first(where: { $0.id == chapterID }),
              chapter.nodes.filter({ $0.id == nodeID }).count == 1,
              let node = chapter.nodes.first(where: { $0.id == nodeID }),
              (try? ProjectNodeNarrative.mergedDescription(in: node)) != nil,
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return nil }
        return .init(lease: lease, chapterID: chapterID, nodeID: nodeID,
            hostGeneration: hostGeneration, revision: model.draftMutationRevision, draftBytes: bytes, name: node.name)
    }
    func isCurrent(_ value: Destination) -> Bool {
        guard matchesHost(model: model, chapterID: value.chapterID, nodeID: value.nodeID),
              value.hostGeneration == hostGeneration,
              destination?.id == value.id, model.isCurrentStarterLease(value.lease),
              model.draftMutationRevision == value.revision,
              ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes else { return false }
        return model.draft.chapters.first(where: { $0.id == value.chapterID })?.nodes.contains(where: { $0.id == value.nodeID }) == true
    }
    func open(_ value: Destination?) {
        guard let value, matchesHost(model: model, chapterID: value.chapterID, nodeID: value.nodeID),
              value.hostGeneration == hostGeneration,
              destination == nil, model.isCurrentStarterLease(value.lease),
              value.revision == model.draftMutationRevision,
              ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes,
              let node = model.draft.chapters.first(where: { $0.id == value.chapterID })?.nodes.first(where: { $0.id == value.nodeID }),
              let merged = try? ProjectNodeNarrative.mergedDescription(in: node) else { return }
        text = merged; saveUnconfirmed = false; destination = value
    }
    func binding(_ value: Destination) -> Binding<String> {
        Binding(get: { self.isCurrent(value) ? self.text : "" }, set: { next in
            guard self.isCurrent(value) else { return }; self.text = next
        })
    }
    func canSave(_ value: Destination) -> Bool { isCurrent(value) && text.utf16.count <= ProjectNodeNarrative.maximumLength }
    func save(_ value: Destination) {
        guard canSave(value), let ci = model.draft.chapters.firstIndex(where: { $0.id == value.chapterID }),
              let ni = model.draft.chapters[ci].nodes.firstIndex(where: { $0.id == value.nodeID }),
              let node = try? ProjectNodeNarrative.applying(text, to: model.draft.chapters[ci].nodes[ni]) else { return }
        var next = model.draft; next.chapters[ci].nodes[ni] = node
        guard model.persistLocalChange(next, lease: value.lease) else { saveUnconfirmed = true; return }
        close(value)
    }
    func close(_ value: Destination) {
        guard destination?.id == value.id else { return }
        destination = nil; text = ""; saveUnconfirmed = false
    }
    func retire() { hostGeneration += 1; destination = nil; text = ""; saveUnconfirmed = false }
}

/// The complete reference/route identity owns the StateObject below. Equal draft bytes
/// do not let a replacement model inherit the previous host's controller or callbacks.
@MainActor struct ProjectNodeNarrativeEntry: View {
    @ObservedObject var model: ProjectEditModel
    let chapterID: String
    let nodeID: String
    var body: some View {
        ProjectNodeNarrativeHost(model: model, chapterID: chapterID, nodeID: nodeID)
            .id(ProjectNodeNarrativeHostIdentity(model: ObjectIdentifier(model), chapterID: chapterID, nodeID: nodeID))
    }
}

@MainActor private struct ProjectNodeNarrativeHost: View {
    @ObservedObject var model: ProjectEditModel
    let chapterID: String
    let nodeID: String
    @StateObject private var controller: ProjectNodeNarrativeController
    init(model: ProjectEditModel, chapterID: String, nodeID: String) {
        self.model = model; self.chapterID = chapterID; self.nodeID = nodeID
        _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID, nodeID: nodeID))
    }
    var body: some View {
        let ownsHost = controller.matchesHost(model: model, chapterID: chapterID, nodeID: nodeID)
        let opening = ownsHost ? controller.capture(chapterID: chapterID, nodeID: nodeID) : nil
        let original = controller.destination
        Section {
            Button("projectNodeNarrative.open") {
                guard controller.matchesHost(model: model, chapterID: chapterID, nodeID: nodeID) else { return }
                controller.open(opening)
            }
                .disabled(opening == nil).accessibilityIdentifier("projectNodeNarrative.open")
            Text("projectNodeNarrative.hint").font(.footnote).foregroundStyle(.secondary)
            if opening == nil { Text("projectNodeNarrative.unavailable").font(.footnote) }
        }
        .sheet(item: Binding(get: {
            controller.matchesHost(model: model, chapterID: chapterID, nodeID: nodeID) ? controller.destination : nil
        }, set: { next in
            if next == nil, let original { controller.close(original) }
        })) { value in
            NavigationStack {
                Form {
                    if controller.isCurrent(value) {
                        Section { Text(verbatim: value.name) }
                        Section("projectNodeNarrative.title") {
                            TextField("projectNodeNarrative.title", text: controller.binding(value), axis: .vertical)
                                .lineLimit(6...16).accessibilityIdentifier("projectNodeNarrative.text")
                            if controller.text.utf16.count > ProjectNodeNarrative.maximumLength {
                                Text("projectNodeNarrative.tooLong").accessibilityIdentifier("projectNodeNarrative.tooLong")
                            }
                        }
                        if controller.saveUnconfirmed { Section { Text("projectNodeNarrative.saveUnconfirmed") } }
                    } else { Text("projectNodeNarrative.stale").accessibilityIdentifier("projectNodeNarrative.stale") }
                }
                .navigationTitle("projectNodeNarrative.title").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("projectNodeNarrative.cancel") { controller.close(value) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("projectNodeNarrative.save") { controller.save(value) }
                            .disabled(!controller.canSave(value)).accessibilityIdentifier("projectNodeNarrative.save")
                    }
                }
            }
        }
        .onDisappear { controller.retire() }
    }
}
