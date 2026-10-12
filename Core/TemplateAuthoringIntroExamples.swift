import Foundation

/// P040 selects a single real home-data pool before taking three examples; it never mixes or seeds drafts.
public struct TemplateAuthoringIntroExamples: Equatable {
    public enum Pool: String, Equatable { case recommended, hot, latest }
    public static let maximum = 3
    public let pool: Pool
    public let rows: [DiscoveryPlayTemplate]
    public init(home: DiscoveryTemplateHome) {
        let source: [DiscoveryPlayTemplate]
        if !home.recommended.isEmpty { pool = .recommended; source = home.recommended }
        else if !home.hot.isEmpty { pool = .hot; source = home.hot }
        else { pool = .latest; source = home.latest }
        rows = Array(source.prefix(Self.maximum))
    }
}
