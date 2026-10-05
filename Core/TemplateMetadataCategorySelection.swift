import Foundation

/// A local projection. Reading, retrying, and a no-op Save retain the original bytes.
public struct TemplateMetadataCategorySelection: Equatable {
    public let original: String?
    public private(set) var selectedIDs: [Int]
    public private(set) var isSupported: Bool
    private let originalIDs: [Int]
    private var explicitlyReplaced = false

    public init(raw: String?) {
        original = raw
        if raw == nil || raw == "" {
            selectedIDs = []; originalIDs = []; isSupported = true
            return
        }
        let parts = raw!.components(separatedBy: ",")
        var ids: [Int] = []
        for part in parts {
            let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
                  let id = Int(value), id > 0, String(id) == value, !ids.contains(id) else {
                selectedIDs = []; originalIDs = []; isSupported = false
                return
            }
            ids.append(id)
        }
        selectedIDs = ids; originalIDs = ids; isSupported = true
    }
    public var hasChanges: Bool { explicitlyReplaced || selectedIDs != originalIDs }
    public var savedValue: String? {
        guard isSupported, hasChanges else { return original }
        return selectedIDs.map(String.init).joined(separator: ",")
    }
    public mutating func toggle(_ id: Int) {
        guard isSupported, id > 0 else { return }
        if selectedIDs.contains(id) { selectedIDs.removeAll { $0 == id } }
        else { selectedIDs.append(id) }
    }
    /// Malformed historical text is replaced only by this separate deliberate action.
    public mutating func replaceUnsupportedSelection() {
        guard !isSupported else { return }
        selectedIDs = []; isSupported = true; explicitlyReplaced = true
    }
}
