import SwiftUI

struct ProjectChapterAtmosphereHostIdentity: Hashable {
    let model: ObjectIdentifier
    let chapterID: String
}

/// Each tap owns the rendered editor/chapter snapshot. A stale tap cannot choose
/// a color for a replacement account, draft, chapter or re-created view host.
@MainActor final class ProjectChapterAtmosphereController: ObservableObject {
    struct Selection {
        let host: ProjectChapterAtmosphereHostIdentity
        let hostGeneration: Int
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let draftBytes: Data
    }
    let model: ProjectEditModel
    let hostIdentity: ProjectChapterAtmosphereHostIdentity
    private var hostGeneration = 0
    @Published private(set) var saveUnconfirmed = false
    init(model: ProjectEditModel, chapterID: String) {
        self.model = model
        hostIdentity = .init(model: ObjectIdentifier(model), chapterID: chapterID)
    }
    func matchesHost(model: ProjectEditModel, chapterID: String) -> Bool {
        self.model === model && hostIdentity == .init(model: ObjectIdentifier(model), chapterID: chapterID)
    }
    var chapter: ProjectEditChapter? {
        guard model.draft.chapters.filter({ $0.id == hostIdentity.chapterID }).count == 1 else { return nil }
        return model.draft.chapters.first { $0.id == hostIdentity.chapterID }
    }
    func capture() -> Selection? {
        guard model.draft.product == .city, let lease = model.captureStarterLease(),
              chapter != nil,
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return nil }
        return .init(host: hostIdentity, hostGeneration: hostGeneration, lease: lease,
                     revision: model.draftMutationRevision, draftBytes: bytes)
    }
    func isCurrent(_ value: Selection) -> Bool {
        guard value.host == hostIdentity, value.hostGeneration == hostGeneration,
              model.draft.product == .city, model.isCurrentStarterLease(value.lease),
              model.draftMutationRevision == value.revision,
              ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes,
              chapter != nil else { return false }
        return true
    }
    func select(_ preset: ProjectChapterAtmosphere, captured value: Selection?) {
        guard let value, isCurrent(value),
              let index = model.draft.chapters.firstIndex(where: { $0.id == hostIdentity.chapterID }) else { return }
        let nextChapter = preset.applying(to: model.draft.chapters[index])
        // An already-canonical repeated selection performs no local write.
        guard model.draft.chapters[index].preserved["atmospherePreset"] != .string(preset.rawValue) else {
            saveUnconfirmed = false; return
        }
        var next = model.draft; next.chapters[index] = nextChapter
        guard model.persistLocalChange(next, lease: value.lease) else { saveUnconfirmed = true; return }
        saveUnconfirmed = false
    }
    func retire() { hostGeneration += 1; saveUnconfirmed = false }
}

@MainActor struct ProjectChapterAtmosphereFields: View {
    @ObservedObject var model: ProjectEditModel
    let chapterID: String
    var body: some View {
        ProjectChapterAtmosphereHost(model: model, chapterID: chapterID)
            .id(ProjectChapterAtmosphereHostIdentity(model: ObjectIdentifier(model), chapterID: chapterID))
    }
}

@MainActor private struct ProjectChapterAtmosphereHost: View {
    @ObservedObject var model: ProjectEditModel
    let chapterID: String
    @StateObject private var controller: ProjectChapterAtmosphereController
    init(model: ProjectEditModel, chapterID: String) {
        self.model = model; self.chapterID = chapterID
        _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID))
    }
    var body: some View {
        let ownsHost = controller.matchesHost(model: model, chapterID: chapterID)
        let captured = ownsHost ? controller.capture() : nil
        let selected = ownsHost ? controller.chapter.flatMap {
            ProjectChapterAtmosphere.canSubmit($0) ? ProjectChapterAtmosphere.selected(in: $0) : nil
        } : nil
        Section("projectChapterAtmosphere.title") {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(ProjectChapterAtmosphere.allCases) { preset in
                        Button {
                            guard controller.matchesHost(model: model, chapterID: chapterID) else { return }
                            controller.select(preset, captured: captured)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: selected == preset ? "checkmark.circle.fill" : "circle")
                                    .accessibilityHidden(true)
                                Text(LocalizedStringKey("projectChapterAtmosphere.color." + preset.rawValue)).font(.headline)
                                Text(LocalizedStringKey("projectChapterAtmosphere.note." + preset.rawValue)).font(.caption)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14).frame(minWidth: 112, maxWidth: 160, minHeight: 112, alignment: .leading)
                            .foregroundStyle(color(preset.foregroundRGB))
                            .background(color(preset.backgroundRGB), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(selected == preset ? 1 : 0.25), lineWidth: selected == preset ? 3 : 1))
                            .padding(2)
                        }
                        .buttonStyle(.plain).disabled(captured == nil)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(LocalizedStringKey("projectChapterAtmosphere.color." + preset.rawValue)))
                        .accessibilityValue(Text(LocalizedStringKey(selected == preset ? "projectChapterAtmosphere.selected" : "projectChapterAtmosphere.notSelected")))
                        .accessibilityAddTraits(selected == preset ? .isSelected : [])
                        .accessibilityIdentifier("projectChapterAtmosphere.choose." + preset.rawValue)
                    }
                }
            }.scrollIndicators(.hidden)
            if let selected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("projectChapterAtmosphere.preview").font(.caption)
                    Text(LocalizedStringKey("projectChapterAtmosphere.color." + selected.rawValue)).font(.headline)
                    if let name = controller.chapter?.name, !name.isEmpty { Text(verbatim: name).font(.title3) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .foregroundStyle(color(selected.foregroundRGB))
                .background(color(selected.backgroundRGB), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.25)))
                .accessibilityIdentifier("projectChapterAtmosphere.preview")
            }
            if let chapter = controller.chapter, !ProjectChapterAtmosphere.canSubmit(chapter) {
                ProjectChapterAtmosphereUnsupportedNotice(chapter: chapter, supportsSelection: true)
            }
            Text("projectChapterAtmosphere.hint").font(.footnote).foregroundStyle(.secondary)
            if controller.saveUnconfirmed {
                Text("projectChapterAtmosphere.saveUnconfirmed").font(.footnote)
                    .accessibilityIdentifier("projectChapterAtmosphere.saveUnconfirmed")
            }
        }
        .onDisappear { controller.retire() }
    }
    private func color(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255,
              green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255, opacity: 1)
    }
}

/// Free-exploration chapters do not gain a palette. If future data cannot pass
/// the existing backend contract, name the affected chapter without discarding it.
struct ProjectChapterAtmosphereUnsupportedNotice: View {
    let chapter: ProjectEditChapter
    let supportsSelection: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(supportsSelection ? "projectChapterAtmosphere.unsupported" : "projectChapterAtmosphere.unsupportedReadOnly")).font(.footnote)
            if chapter.name.isEmpty { Text("projectChapterAtmosphere.untitled") }
            else { Text(verbatim: chapter.name).font(.subheadline.bold()) }
        }.accessibilityElement(children: .combine)
            .accessibilityIdentifier("projectChapterAtmosphere.unsupported")
    }
}
