import Foundation

/// Ephemeral action filtering, never a promise about another app's audience or privacy settings.
/// The broad default preserves the previously available native sharing options.
public struct RoamShareChannelPolicy: Equatable {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case allOptions, momentsGuide, saveOnly
        public var id: Self { self }
    }
    public enum Channel: String, CaseIterable, Sendable {
        case savePhoto, momentsGuide, xiaohongshuGuide, systemShare
    }
    public private(set) var mode: Mode = .allOptions
    public init() {}
    public var allowedChannels: [Channel] {
        switch mode {
        case .allOptions: return [.savePhoto, .momentsGuide, .xiaohongshuGuide, .systemShare]
        case .momentsGuide: return [.savePhoto, .momentsGuide]
        case .saveOnly: return [.savePhoto]
        }
    }
    public func permits(_ channel: Channel) -> Bool { allowedChannels.contains(channel) }
    /// A currently requested Photos operation must settle before the user changes its guidance.
    @discardableResult public mutating func select(_ mode: Mode, operationInFlight: Bool) -> Bool {
        guard !operationInFlight, mode != self.mode else { return false }
        self.mode = mode; return true
    }
    public mutating func reset() { mode = .allOptions }
}
