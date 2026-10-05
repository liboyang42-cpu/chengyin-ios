import Foundation

public enum RoamExperienceMath {
    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    public static func isValidTile(_ key: String) -> Bool { (1...12).contains(key.count) && key.allSatisfy { alphabet.contains($0) } }
    public static func tileKey(_ point: RoamCoordinate, precision: Int = 7) -> String? {
        guard (1...12).contains(precision) else { return nil }
        var lat = (-90.0, 90.0), lng = (-180.0, 180.0), even = true, value = 0, bit = 0
        var output = ""
        while output.count < precision {
            let mid = even ? (lng.0 + lng.1) / 2 : (lat.0 + lat.1) / 2
            let upper = (even ? point.longitude : point.latitude) >= mid
            value = (value << 1) | (upper ? 1 : 0)
            if even { if upper { lng.0 = mid } else { lng.1 = mid } }
            else { if upper { lat.0 = mid } else { lat.1 = mid } }
            even.toggle(); bit += 1
            if bit == 5 { output.append(alphabet[value]); bit = 0; value = 0 }
        }
        return output
    }
    public static func distanceMeters(_ a: RoamCoordinate, _ b: RoamCoordinate) -> Double {
        let radians = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * radians, dLng = (b.longitude - a.longitude) * radians
        let term = pow(sin(dLat / 2), 2) + cos(a.latitude * radians) * cos(b.latitude * radians) * pow(sin(dLng / 2), 2)
        return 2 * 6_371_000 * asin(sqrt(min(1, max(0, term))))
    }
    public static func elapsed(_ seconds: Int) -> String {
        let value = max(0, seconds), hours = value / 3600, minutes = (value % 3600) / 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, value % 60) : String(format: "%02d:%02d", minutes, value % 60)
    }
    /// Source length limits use UTF-16 code units, not Swift grapheme-cluster count.
    public static func validCaption(_ caption: String) -> Bool { caption.utf16.count <= 30 }
    public static func validHangoutTitle(_ title: String) -> Bool {
        (2...30).contains(title.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count)
    }
    public static func validHangoutDescription(_ description: String) -> Bool {
        description.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 120
    }
    public struct BarcodeBar: Equatable { public let width: Int; public let gap: Int }
    /// Deliberately reproduces the source's JS double rounding BEFORE ToInt32, not an integer LCG.
    /// This decorative stamp serial barcode must never be used as a redeemable voucher code.
    public static func stampBarcode(serial: Int) -> [BarcodeBar] {
        var seed = 77.0 + Double(serial) * 31.0
        func random() -> Double {
            let product = (seed * 1_103_515_245 + 12_345).rounded(.towardZero)
            var modulo = product.truncatingRemainder(dividingBy: 4_294_967_296)
            if modulo < 0 { modulo += 4_294_967_296 }
            seed = Double(UInt64(modulo) & 0x7fff_ffff)
            return seed / 2_147_483_647
        }
        let widths = [1, 1, 1, 2, 2, 3]
        return (0..<46).map { _ in BarcodeBar(width: widths[Int(floor(random() * 6)) % 6], gap: 1 + Int(floor(random() * 2)) % 2) }
    }
}
/// Platform-neutral normalized route drawing. This is a local schematic, never a navigation map.
public struct RoamRouteSketch {
    public struct Point: Equatable { public let x: Double; public let y: Double }
    public let track: [Point]
    public let places: [Point]
    public init(track: [RoamHistoryPoint], places: [RoamHistoryPoint]) {
        guard track.count >= 2 else { self.track = []; self.places = []; return }
        let longitudeScale = cos(track[0].lat * .pi / 180)
        let raw = (track + places).map { Point(x: $0.lng * longitudeScale, y: -$0.lat) }
        let minX = raw.map(\.x).min()!, maxX = raw.map(\.x).max()!
        let minY = raw.map(\.y).min()!, maxY = raw.map(\.y).max()!
        let span = max(1e-9, max(maxX - minX, maxY - minY))
        let centeredX = (minX + maxX) / 2, centeredY = (minY + maxY) / 2
        let normalized = raw.map { Point(x: 0.5 + ($0.x - centeredX) / span * 0.8, y: 0.5 + ($0.y - centeredY) / span * 0.8) }
        self.track = Array(normalized.prefix(track.count)); self.places = Array(normalized.dropFirst(track.count))
    }
}
