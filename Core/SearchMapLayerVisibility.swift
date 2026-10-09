import Foundation

/// Local visibility of the two already-returned search-map sources. This does
/// not authorize, fetch, merge or reinterpret any source, and is never persisted.
public struct SearchMapLayerVisibility: Equatable {
    public enum Layer: CaseIterable, Hashable { case activities, cityPlaces }
    private var visible: Set<Layer> = Set(Layer.allCases)
    public private(set) var revision = UUID()
    public init() {}
    public var isEmpty: Bool { visible.isEmpty }
    public func shows(_ layer: Layer) -> Bool { visible.contains(layer) }
    public mutating func set(_ layer: Layer, visible shouldShow: Bool) {
        guard shows(layer) != shouldShow else { return }
        if shouldShow { visible.insert(layer) } else { visible.remove(layer) }
        revision = UUID()
    }
    public mutating func showAll() { visible = Set(Layer.allCases); revision = UUID() }
}
