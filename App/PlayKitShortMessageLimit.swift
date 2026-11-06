/// Note and daily-sign inputs share the Core contract's nonpositive fallback.
/// Other kit kinds (for example DIY names) intentionally have different rules.
enum PlayKitShortMessageLimit {
    static func resolve(_ value: PlayWireValue) -> Int {
        let limit = value.integer ?? 40
        return limit > 0 ? limit : 40
    }
}
