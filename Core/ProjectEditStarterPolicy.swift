import Foundation

/// The shared creation action does not merge the two modes' authoring destinations.
public enum ProjectEditStarterPolicy {
    public enum Destination: Equatable { case story, firstNode }
    public static func usesStoryEditor(product: ProjectEditProduct, chapter: ProjectEditChapter) -> Bool {
        product == .city || chapter.preserved["opening"] == .bool(true)
    }
    public static func destination(product: ProjectEditProduct, chapter: ProjectEditChapter, hadChapters: Bool) -> Destination? {
        if usesStoryEditor(product: product, chapter: chapter) { return .story }
        return hadChapters ? nil : .firstNode
    }
    public static func chapter(name: String, product: ProjectEditProduct) -> ProjectEditChapter {
        var chapter = ProjectEditChapter(); chapter.name = name
        if product == .city { chapter.blocks = []; chapter.schemaVersion = 1; chapter.required = 1 }
        return chapter
    }
    /// This bounded destination adds only the existing formal-node subset. Incomplete
    /// candidates remain in its temporary form, never masquerading as a saved node.
    public static func canAddFormalNode(_ node: ProjectEditNode) -> Bool {
        !node.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && node.hasUsableCoordinates && node.nodeTime >= 0
    }
}
