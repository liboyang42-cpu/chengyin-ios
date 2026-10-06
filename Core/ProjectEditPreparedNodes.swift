import Foundation

/// Read-only view of the already prepared request. It never serializes mutable editor state.
public struct ProjectEditPreparedNodes: Equatable {
    public enum Field: String, CaseIterable, Identifiable {
        case name, description, address, longitude, latitude, imgUrl, nodeTime, templateId, sortID
        public var id: String { rawValue }
    }
    public struct Value: Equatable {
        public let raw: ProjectEditJSON?
        public var text: String? {
            guard let raw else { return nil }
            if case .string(let value) = raw { return value }
            if case .number(let value) = raw, value.isNaN { return nil }
            guard let bytes = try? JSONEncoder().encode(raw) else { return nil }
            return String(decoding: bytes, as: UTF8.self)
        }
        public init(_ raw: ProjectEditJSON?) { self.raw = raw }
    }
    public struct Node: Identifiable, Equatable {
        public let id: Int
        public let raw: ProjectEditJSON
        public var isObject: Bool { raw.object != nil }
        public func value(_ field: Field) -> Value { .init(raw.object?[field.rawValue]) }
    }
    public struct Chapter: Identifiable, Equatable {
        public let id: Int
        public let raw: ProjectEditJSON
        public var isObject: Bool { raw.object != nil }
        public var name: Value { .init(raw.object?["name"]) }
        public var description: Value { .init(raw.object?["description"]) }
        public var nodes: [Node]? { raw.object?["nodes"]?.array?.enumerated().map { .init(id: $0.offset, raw: $0.element) } }
        public var nodesOmitted: Bool { raw.object?["nodes"] == nil }
    }
    public let raw: ProjectEditJSON?
    public var omitted: Bool { raw == nil }
    public var chapters: [Chapter]? { raw?.array?.enumerated().map { .init(id: $0.offset, raw: $0.element) } }
    public init(payload: [String: ProjectEditJSON]) { raw = payload["chapters"] }
}
