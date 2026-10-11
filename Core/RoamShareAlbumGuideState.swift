import Foundation

/// Publication preparation, not a publishing API. A guide is a receipt for a saved
/// image only; selecting a destination never means it has received the image.
public struct RoamShareAlbumGuideState {
    public enum Destination: String, CaseIterable, Identifiable {
        case moments, xiaohongshu
        public var id: Self { self }
    }
    public struct Copy: Equatable {
        public let recordedAt: Date?
        public let shops: Int?
        public let kilometers: Double?
        public let explorationPercent: Int?
        public init(record: RoamHistoryRecord) {
            recordedAt = record.recordedAt; shops = record.shops
            kilometers = record.distance
            explorationPercent = record.explorePct.flatMap { (0...100).contains($0) ? $0 : nil }
        }
    }
    public struct Request: Equatable {
        private let id = UUID()
        public let destination: Destination
        public let selection: RoamSharePhotoSaveState.Selection
        fileprivate init(destination: Destination, selection: RoamSharePhotoSaveState.Selection) {
            self.destination = destination; self.selection = selection
        }
    }
    public struct Guide: Equatable, Identifiable {
        public let id = UUID()
        public let destination: Destination
        public let copy: Copy
        fileprivate init(request: Request) {
            destination = request.destination; copy = Copy(record: request.selection.record)
        }
    }
    public private(set) var pending: Request?
    public private(set) var guide: Guide?
    public init() {}
    public mutating func begin(destination: Destination, selection: RoamSharePhotoSaveState.Selection, saveInFlight: Bool) -> Request? {
        guard !saveInFlight, pending == nil, guide == nil else { return nil }
        let request = Request(destination: destination, selection: selection)
        pending = request; return request
    }
    public func accepts(_ request: Request) -> Bool { pending == request }
    public mutating func receive(_ request: Request, phase: RoamSharePhotoSaveState.Phase,
                                 current: RoamSharePhotoSaveState.Selection, sourceIsCurrent: Bool) {
        guard accepts(request) else { return }
        guard sourceIsCurrent, request.selection == current else { invalidate(); return }
        switch phase {
        case .saved:
            guide = Guide(request: request); pending = nil
        case .permissionDenied, .restricted, .unavailable, .sourceChanged, .failed:
            pending = nil
        case .ready, .requestingPermission, .saving:
            break
        }
    }
    public mutating func dismissGuide() { guide = nil }
    public mutating func invalidate() { pending = nil; guide = nil }
}
