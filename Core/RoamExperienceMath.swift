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

/// A bounded local display schedule; it never reads, changes or saves a route.
public struct RoamRouteReplayPlan: Equatable {
    public static let intervalNanoseconds: UInt64 = 120_000_000
    public static let maximumFrames = 24
    public let counts: [Int]
    public init(segmentCount: Int) {
        let total = max(0, segmentCount)
        guard total > 0 else { counts = []; return }
        let frames = min(total, Self.maximumFrames)
        let step = total / frames + (total % frames == 0 ? 0 : 1)
        var result: [Int] = [], count = 0
        while count < total {
            count = total - count <= step ? total : count + step
            result.append(count)
        }
        counts = result
    }
}

/// Value-only replay authority. Timers live in the SwiftUI detail presentation.
/// A context belongs to an exact reader/scope, complete record value and visible lifetime.
public struct RoamRouteReplayState {
    public struct Owner: Equatable {
        public let readerID: ObjectIdentifier
        public let identity: RoamExperienceIdentity?
        public let storageKey: String?
        public let configured: Bool
        public let record: RoamHistoryRecord
        @MainActor public init(reader: any RoamExperienceReading, record: RoamHistoryRecord) {
            readerID = ObjectIdentifier(reader); identity = reader.identity
            storageKey = identity?.scope.storageKey
            configured = reader.isConfigured; self.record = record
        }
    }
    public struct Context: Equatable {
        fileprivate let owner: Owner
        fileprivate let generation: UUID
    }
    public enum Phase: Equatable { case ready, playing, completed }
    public private(set) var phase: Phase = .ready
    public private(set) var totalSegments = 0
    /// nil means the unchanged full static sketch, including non-replay callers.
    public private(set) var visibleSegments: Int?
    private var owner: Owner?
    private var active = false
    private var reduceMotion = false
    private var generation = UUID()
    public init() {}
    public var progress: Double {
        guard totalSegments > 0 else { return 0 }
        return Double(visibleSegments ?? totalSegments) / Double(totalSegments)
    }
    public var plan: RoamRouteReplayPlan { .init(segmentCount: totalSegments) }
    public mutating func update(owner: Owner, active: Bool, reduceMotion: Bool) {
        if self.owner != owner || self.active != active {
            generation = UUID(); phase = .ready; visibleSegments = nil
            let points = RoamRouteSketch(track: owner.record.track, places: owner.record.pois.map(\.point)).track
            let hasLine = zip(points, points.dropFirst()).contains { pair in pair.0 != pair.1 }
            totalSegments = hasLine ? max(0, points.count - 1) : 0
        }
        self.owner = owner; self.active = active; self.reduceMotion = reduceMotion
        if reduceMotion && phase == .playing { complete() }
    }
    public func context(for current: Owner) -> Context? {
        guard active, owner == current, totalSegments > 0 else { return nil }
        return Context(owner: current, generation: generation)
    }
    public func accepts(_ context: Context, current: Owner) -> Bool {
        self.context(for: current) == context
    }
    @discardableResult public mutating func start(in context: Context, current: Owner) -> Context? {
        guard accepts(context, current: current), phase != .playing else { return nil }
        generation = UUID()
        if reduceMotion { phase = .completed; visibleSegments = nil; return nil }
        phase = .playing; visibleSegments = 0
        return self.context(for: current)
    }
    public mutating func advance(to count: Int, in context: Context, current: Owner) {
        guard accepts(context, current: current), phase == .playing else { return }
        let bounded = min(totalSegments, max(0, count))
        guard bounded >= (visibleSegments ?? 0) else { return }
        visibleSegments = bounded
        if bounded == totalSegments { complete() }
    }
    public mutating func skip(in context: Context, current: Owner) {
        guard accepts(context, current: current), phase == .playing else { return }
        complete()
    }
    private mutating func complete() {
        generation = UUID(); phase = .completed; visibleSegments = nil
    }
}

/// P128 local share projection only. Historical records remain unchanged.
/// Saved tracks are simplified, so clip by polyline length rather than sample count.
public enum RoamShareRoutePrivacy {
    public static let endpointFraction = 0.1

    public static func clippedTrack(_ track: [RoamHistoryPoint]) -> [RoamHistoryPoint] {
        guard track.count >= 2 else { return [] }
        var lengths: [Double] = []
        for index in 1..<track.count {
            let a = track[index - 1], b = track[index]
            // A schematic cannot safely interpolate a longitude wrap. Hide it rather than
            // drawing a trans-world segment or returning the original endpoints.
            guard abs(b.lng - a.lng) <= 180 else { return [] }
            lengths.append(RoamExperienceMath.distanceMeters(a.coordinate, b.coordinate))
        }
        let total = lengths.reduce(0, +)
        guard total.isFinite, total > 0 else { return [] }
        let start = total * endpointFraction, end = total - start
        var travelled = 0.0
        var result: [RoamHistoryPoint] = []
        for index in 1..<track.count {
            let length = lengths[index - 1], next = travelled + length
            if length > 0, next > start, travelled < end {
                let a = track[index - 1], b = track[index]
                func interpolate(_ distance: Double) -> RoamHistoryPoint? {
                    let fraction = min(1, max(0, (distance - travelled) / length))
                    guard let coordinate = RoamCoordinate(
                        latitude: a.lat + (b.lat - a.lat) * fraction,
                        longitude: a.lng + (b.lng - a.lng) * fraction
                    ) else { return nil }
                    return RoamHistoryPoint(coordinate: coordinate)
                }
                if result.isEmpty {
                    guard let point = interpolate(max(start, travelled)) else { return [] }
                    result.append(point)
                }
                guard let point = interpolate(min(end, next)) else { return [] }
                result.append(point)
            }
            travelled = next
            if travelled >= end { break }
        }
        guard result.count >= 2 else { return [] }
        // Interpolation may round back to an original endpoint for adjacent Doubles.
        // A nominal 10% calculation is not evidence that the exported endpoint moved.
        let startInset = RoamExperienceMath.distanceMeters(track[0].coordinate, result[0].coordinate)
        let endInset = RoamExperienceMath.distanceMeters(track[track.count - 1].coordinate, result[result.count - 1].coordinate)
        guard startInset.isFinite, startInset > 0, endInset.isFinite, endInset > 0 else { return [] }
        var retainedLength = 0.0
        for index in 1..<result.count {
            retainedLength += RoamExperienceMath.distanceMeters(result[index - 1].coordinate, result[index].coordinate)
        }
        guard retainedLength.isFinite, retainedLength > 0 else { return [] }
        return result
    }

    public static func sketch(for record: RoamHistoryRecord) -> RoamRouteSketch {
        // POIs could independently reveal the removed home/work endpoint. Do not export them.
        RoamRouteSketch(track: clippedTrack(record.track), places: [])
    }
}
