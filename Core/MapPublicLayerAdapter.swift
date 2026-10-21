import Foundation

/// Wire and pagination for `POST /api/map/public-layers`.
/// Builds the GCJ-02 body, keeps a failed page's cursor, and maps only fields the payload actually carries.
/// It does not read a location fix, attach a credential, or open a connection.
public enum MapPublicLayerAdapter {
    public static let path = "/api/map/public-layers"
    public static let datum = "GCJ-02"
    public static let pageLimit = 1...50
    public static let layerCount = 1...5
    /// Abuse cap published with the wire (`min(1, 4)` square degrees). Not a product radius.
    public static let maxAreaSquareDegrees = Decimal(1)
    public static let knownSources = ["roam_poi", "store", "activity", "theme", "story_node"]

    /// `story_node` is absent on purpose. It is not `sideQuest`.
    public static func clientType(wire: String) -> MapSourceType? {
        switch wire {
        case "roam_poi": return .roamPOI
        case "store": return .store
        case "activity": return .registrableActivity
        case "theme": return .themeNode
        case "story_node": return nil
        default: return nil
        }
    }

    public static func open(viewerID: Int, datum: String, minLat: String, maxLat: String, minLng: String, maxLng: String, layers: [String], limit: Int) throws -> MapPublicLayerSession {
        guard viewerID > 0 else { throw MapPublicAdapterFailure.viewerRejected }
        guard datum == Self.datum else { throw MapPublicAdapterFailure.datumRejected }
        guard Self.pageLimit.contains(limit) else { throw MapPublicAdapterFailure.limitRejected }
        let south = try coordinate(minLat, latitude: true)
        let north = try coordinate(maxLat, latitude: true)
        let west = try coordinate(minLng, latitude: false)
        let east = try coordinate(maxLng, latitude: false)
        guard south.value <= north.value, west.value <= east.value else { throw MapPublicAdapterFailure.bboxRejected }
        guard (north.value - south.value) * (east.value - west.value) <= maxAreaSquareDegrees else { throw MapPublicAdapterFailure.areaRejected }
        guard layerCount.contains(layers.count) else { throw MapPublicAdapterFailure.layersRejected }
        var seen: Set<String> = []
        for layer in layers {
            guard layer.range(of: "^[a-z][a-z0-9_]{0,31}$", options: .regularExpression) != nil,
                  knownSources.contains(layer), seen.insert(layer).inserted else { throw MapPublicAdapterFailure.layersRejected }
        }
        let fingerprint = [datum, south.plain, north.plain, west.plain, east.plain, String(limit), layers.joined(separator: ",")].joined(separator: "\n")
        return MapPublicLayerSession(viewerID: viewerID, fingerprint: fingerprint, limit: limit, layers: layers,
                                     minLat: south.plain, maxLat: north.plain, minLng: west.plain, maxLng: east.plain,
                                     token: 0, cursor: nil, complete: false,
                                     pages: layers.map { MapPublicLayerPage(source: $0, status: .idle, reason: nil, read: nil, items: []) })
    }

    /// New account or new query. The previous token can no longer apply a callback.
    public static func replace(_ session: MapPublicLayerSession, viewerID: Int, datum: String, minLat: String, maxLat: String, minLng: String, maxLng: String, layers: [String], limit: Int) throws -> MapPublicLayerSession {
        var next = try open(viewerID: viewerID, datum: datum, minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng, layers: layers, limit: limit)
        next.token = session.token &+ 1
        if next.token == 0 { next.token = 1 }
        return next
    }

    /// One in-flight read. A newer request or a replaced query makes this token stale.
    public static func request(_ session: MapPublicLayerSession) -> (session: MapPublicLayerSession, request: MapPublicLayerRequest) {
        var next = session
        next.token = session.token &+ 1
        if next.token == 0 { next.token = 1 }
        let body = jsonBody(next)
        let issued = MapPublicLayerRequest(attempt: next.token, viewerID: next.viewerID, fingerprint: next.fingerprint, cursor: next.cursor, body: body)
        return (next, issued)
    }

    public static func accept(_ session: MapPublicLayerSession, request: MapPublicLayerRequest, json: Data) -> MapPublicIngest {
        guard request.attempt == session.token, request.viewerID == session.viewerID, request.fingerprint == session.fingerprint else {
            return .stale
        }
        guard json.count <= 1_048_576, let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            return .rejected(.payloadRejected)
        }
        guard (object["datum"] as? String) == datum else { return .rejected(.payloadRejected) }
        if object.keys.contains("aggregatedQueryEnabled"), bool(object["aggregatedQueryEnabled"]) != false {
            return .rejected(.payloadRejected)
        }
        guard let rawLayers = object["layers"] as? [Any], rawLayers.count == session.layers.count else { return .rejected(.payloadRejected) }
        var pages = session.pages
        var failed = false
        for (index, raw) in rawLayers.enumerated() {
            guard let layer = raw as? [String: Any], (layer["sourceType"] as? String) == session.layers[index],
                  let status = layer["status"] as? String else { return .rejected(.payloadRejected) }
            let source = session.layers[index]
            if (source == "story_node" || source == "theme") && status != "UNAVAILABLE" {
                return .rejected(.payloadRejected)
            }
            let reason = layer["reason"] as? String
            let read = bool((layer["capabilities"] as? [String: Any])?["read"])
            guard let rawItems = layer["items"] as? [Any] else { return .rejected(.payloadRejected) }
            switch status {
            case "FAILED":
                guard rawItems.isEmpty else { return .rejected(.payloadRejected) }
                failed = true
                pages[index].status = .failed
                pages[index].reason = reason
                pages[index].read = read
            case "UNAVAILABLE":
                guard rawItems.isEmpty else { return .rejected(.payloadRejected) }
                pages[index].status = .unavailable
                pages[index].reason = reason
                pages[index].read = read
            case "OK":
                guard let parsed = items(rawItems, source: session.layers[index]) else { return .rejected(.payloadRejected) }
                if let blocked = unpublished(parsed, source: session.layers[index]) {
                    failed = true
                    pages[index].status = .failed
                    pages[index].reason = blocked
                    pages[index].read = read
                } else {
                    pages[index].status = .ok
                    pages[index].reason = reason
                    pages[index].read = read
                    pages[index].items = deduped(pages[index].items + parsed)
                }
            default:
                return .rejected(.payloadRejected)
            }
        }
        var applied = session
        applied.pages = pages
        if failed {
            applied.cursor = request.cursor
            applied.complete = false
        } else if let nextCursor = object["nextCursor"] as? String {
            guard !nextCursor.isEmpty, nextCursor.count <= 2048 else { return .rejected(.payloadRejected) }
            applied.cursor = nextCursor
            applied.complete = false
        } else if object["nextCursor"] == nil || object["nextCursor"] is NSNull {
            applied.cursor = nil
            applied.complete = true
        } else {
            return .rejected(.payloadRejected)
        }
        return .applied(applied)
    }

    /// Items that have a real client type, a server visibility version, and a server visual state.
    /// Layer `read` does not add navigate, register, or any other action.
    public static func readyItems(in session: MapPublicLayerSession) -> [MapLayerItem] {
        var ready: [MapLayerItem] = []
        for (index, page) in session.pages.enumerated() where page.status == .ok || page.status == .failed {
            for item in page.items {
                guard let mapped = mapItem(item, layerIndex: index) else { continue }
                ready.append(mapped)
            }
        }
        return MapLayerMerge.merge([], ready)
    }

    public static func withheld(in session: MapPublicLayerSession) -> [MapPublicWithheldItem] {
        var rows: [MapPublicWithheldItem] = []
        for page in session.pages where page.status == .ok || page.status == .failed {
            for item in page.items {
                let missing = missingFields(item)
                if !missing.isEmpty { rows.append(MapPublicWithheldItem(source: item.source, sourceID: item.sourceID, missing: missing)) }
            }
        }
        return rows
    }

    private static func mapItem(_ item: MapPublicWireItem, layerIndex: Int) -> MapLayerItem? {
        guard let type = clientType(wire: item.source), let version = item.visibilityVersion, let ordering = orderingInt(version),
              let stateName = item.visualState, let state = markerState(wire: stateName),
              versionAllowed(version, source: item.source), stateAllowed(stateName, source: item.source),
              let key = try? MapSourceKey(type: type, id: String(item.sourceID)),
              let south = try? coordinate(item.latitude, latitude: true),
              let west = try? coordinate(item.longitude, latitude: false),
              let coordinate = try? MapCoordinateObservation(latitude: NSDecimalNumber(decimal: south.value).doubleValue,
                                                            longitude: NSDecimalNumber(decimal: west.value).doubleValue,
                                                            datum: .gcj02, source: .backend) else { return nil }
        let title = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 300 else { return nil }
        let sortKey = String(format: "%02d:%020d", layerIndex, item.sourceID)
        return try? MapLayerItem(key: key, placeID: nil, visibilityVersion: ordering, state: state, coordinate: coordinate,
                                  capabilities: exposedActions(item), sortKey: sortKey, title: title)
    }

    private static func missingFields(_ item: MapPublicWireItem) -> Set<MapPublicMissingField> {
        var missing: Set<MapPublicMissingField> = []
        if clientType(wire: item.source) == nil { missing.insert(.clientType) }
        if item.visibilityVersion == nil || !versionAllowed(item.visibilityVersion ?? "", source: item.source) { missing.insert(.visibilityVersion) }
        if item.visualState == nil || !stateAllowed(item.visualState ?? "", source: item.source) { missing.insert(.visualState) }
        if item.actions == nil { missing.insert(.actions) }
        if (try? coordinate(item.latitude, latitude: true)) == nil || (try? coordinate(item.longitude, latitude: false)) == nil {
            missing.insert(.coordinate)
        }
        let title = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.count > 300 { missing.insert(.title) }
        return missing
    }

    /// `navigate` is exposed only when this store row lists it. `register` is never exposed.
    /// Layer `read` is not an item action.
    private static func exposedActions(_ item: MapPublicWireItem) -> Set<MapItemCapability> {
        guard item.source == "store", let names = item.actions, names.contains("navigate"), !names.contains("register") else { return [] }
        return [.navigate]
    }

    /// Null, blank, or the wrong source's version is not published and is not replaced with 1.
    private static func unpublished(_ items: [MapPublicWireItem], source: String) -> String? {
        for item in items {
            guard let version = item.visibilityVersion, versionAllowed(version, source: source) else { return "VISIBILITY_VERSION_ABSENT" }
            guard let state = item.visualState, stateAllowed(state, source: source), state != "available" else { return "VISUAL_STATE_ABSENT" }
            if item.actions?.contains("register") == true { return "ACTION_REJECTED" }
        }
        return nil
    }

    /// Wire visual state. There is no fallback to a generic available marker.
    static func markerState(wire: String) -> MapMarkerVisualState? {
        switch wire {
        case "unfound": return .locked
        case "found": return .completed
        case "pending_redeem": return .active
        case "open": return .interactive
        case "closed": return .unavailable
        case "notStarted": return .locked
        case "running": return .active
        case "completed": return .completed
        default: return nil
        }
    }

    private static func stateAllowed(_ state: String, source: String) -> Bool {
        switch source {
        case "roam_poi": return state == "unfound" || state == "found" || state == "pending_redeem"
        case "store": return state == "open" || state == "closed"
        case "activity": return state == "notStarted" || state == "running" || state == "completed"
        default: return false
        }
    }

    private static func versionAllowed(_ version: String, source: String) -> Bool {
        switch source {
        case "roam_poi": return version.range(of: "^[1-9][0-9]*$", options: .regularExpression) != nil
        case "store", "activity": return version.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil
        default: return false
        }
    }

    /// Digit form of the same version string so `MapLayerMerge` can order it. Not a default of 1.
    private static func orderingInt(_ version: String) -> Int? {
        if version.range(of: "^[1-9][0-9]*$", options: .regularExpression) != nil { return Int(version) }
        guard versionAllowed(version, source: "store") else { return nil }
        return Int(version.filter(\.isNumber))
    }

    private static func items(_ rawItems: [Any], source: String) -> [MapPublicWireItem]? {
        var parsed: [MapPublicWireItem] = []
        for raw in rawItems {
            guard let object = raw as? [String: Any], (object["sourceType"] as? String) == source,
                  let sourceID = positiveID(object["sourceId"]), let name = object["name"] as? String,
                  let latitude = decimalText(object["latitude"]), let longitude = decimalText(object["longitude"]) else { return nil }
            parsed.append(MapPublicWireItem(source: source, sourceID: sourceID, name: name, latitude: latitude, longitude: longitude,
                                             visibilityVersion: object.keys.contains("visibilityVersion") ? versionText(object["visibilityVersion"]) : nil,
                                             visualState: object["visualState"] as? String,
                                             actions: object.keys.contains("actions") ? stringList(object["actions"]) : nil,
                                             found: object.keys.contains("found") ? bool(object["found"]) : nil,
                                             pendingRedeem: object.keys.contains("pendingRedeem") ? bool(object["pendingRedeem"]) : nil,
                                             businessStatus: object.keys.contains("businessStatus") ? integer(object["businessStatus"]) : nil))
        }
        return parsed
    }

    private static func deduped(_ items: [MapPublicWireItem]) -> [MapPublicWireItem] {
        var byID: [Int: MapPublicWireItem] = [:]
        var order: [Int] = []
        for item in items {
            if let current = byID[item.sourceID] {
                byID[item.sourceID] = prefer(current, item)
            } else {
                order.append(item.sourceID)
                byID[item.sourceID] = item
            }
        }
        return order.sorted().compactMap { byID[$0] }
    }

    private static func prefer(_ current: MapPublicWireItem, _ incoming: MapPublicWireItem) -> MapPublicWireItem {
        guard let new = incoming.visibilityVersion else { return current }
        guard let old = current.visibilityVersion else { return incoming }
        return versionRanksAbove(new, old) ? incoming : current
    }

    private static func versionRanksAbove(_ incoming: String, _ current: String) -> Bool {
        let digits = "^[1-9][0-9]*$"
        let incomingDigits = incoming.range(of: digits, options: .regularExpression) != nil
        let currentDigits = current.range(of: digits, options: .regularExpression) != nil
        if incomingDigits && currentDigits {
            if incoming.count != current.count { return incoming.count > current.count }
            return incoming >= current
        }
        return incoming >= current
    }

    private static func versionText(_ value: Any?) -> String? {
        if value == nil || value is NSNull { return nil }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let text = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func jsonBody(_ session: MapPublicLayerSession) -> String {
        var fields = [
            "\"datum\":\"\(datum)\"",
            "\"minLat\":\(session.minLat)",
            "\"maxLat\":\(session.maxLat)",
            "\"minLng\":\(session.minLng)",
            "\"maxLng\":\(session.maxLng)",
            "\"limit\":\(session.limit)",
            "\"layers\":[" + session.layers.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        ]
        if let cursor = session.cursor { fields.append("\"cursor\":" + jsonString(cursor)) }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private static func jsonString(_ value: String) -> String {
        var encoded = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": encoded += "\\\\"
            case "\"": encoded += "\\\""
            case "\n": encoded += "\\n"
            case "\r": encoded += "\\r"
            case "\t": encoded += "\\t"
            default:
                if scalar.value < 0x20 { encoded += String(format: "\\u%04x", scalar.value) }
                else { encoded.unicodeScalars.append(scalar) }
            }
        }
        encoded += "\""
        return encoded
    }

    private struct CanonicalCoordinate {
        let plain: String
        let value: Decimal
    }

    private static func coordinate(_ raw: String, latitude: Bool) throws -> CanonicalCoordinate {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expression = try? NSRegularExpression(pattern: "^-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?$"),
              expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.range.length == (text as NSString).length else {
            throw MapPublicAdapterFailure.coordinateRejected
        }
        let negative = text.hasPrefix("-")
        let body = negative ? String(text.dropFirst()) : text
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        var fraction = parts.count == 2 ? String(parts[1]) : ""
        while fraction.last == "0" { fraction.removeLast() }
        let plainBody = fraction.isEmpty ? String(parts[0]) : String(parts[0]) + "." + fraction
        let significant = plainBody.replacingOccurrences(of: ".", with: "").drop { $0 == "0" }
        guard fraction.count <= 8, (significant.isEmpty ? 1 : significant.count) <= 12,
              let value = Decimal(string: plainBody, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MapPublicAdapterFailure.coordinateRejected
        }
        let bound: Decimal = latitude ? 90 : 180
        guard value >= -bound, value <= bound else { throw MapPublicAdapterFailure.coordinateRejected }
        let plain = negative && plainBody != "0" ? "-" + plainBody : plainBody
        return CanonicalCoordinate(plain: plain, value: negative && plainBody != "0" ? -value : value)
    }

    private static func decimalText(_ value: Any?) -> String? {
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.stringValue
    }

    private static func positiveID(_ value: Any?) -> Int? {
        guard let number = integer(value), number > 0 else { return nil }
        return number
    }

    private static func integer(_ value: Any?) -> Int? {
        if let text = value as? String {
            guard text.range(of: "^-?[0-9]+$", options: .regularExpression) != nil, let number = Int(text) else { return nil }
            return number
        }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let text = number.stringValue
        guard text.range(of: "^-?[0-9]+$", options: .regularExpression) != nil, let parsed = Int(text) else { return nil }
        return parsed
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func stringList(_ value: Any?) -> [String]? {
        guard let list = value as? [Any] else { return nil }
        var names: [String] = []
        for item in list {
            guard let name = item as? String else { return nil }
            names.append(name)
        }
        return names
    }
}

public enum MapPublicAdapterFailure: Error, Equatable {
    case viewerRejected, datumRejected, coordinateRejected, bboxRejected, areaRejected, limitRejected, layersRejected, payloadRejected
}

public enum MapPublicLayerStatus: String, Equatable {
    case idle, ok, unavailable, failed
}

public enum MapPublicMissingField: String, Hashable, Equatable {
    case clientType, visibilityVersion, visualState, actions, coordinate, title
}

public struct MapPublicWireItem: Equatable {
    public let source: String
    public let sourceID: Int
    public let name: String
    public let latitude: String
    public let longitude: String
    /// Server string. `roam_poi` depends on the unexecuted candidate column `visibility_version`
    /// (`docs/w13/map-public-visibility-version.sql`). Until that column exists the roam select fails
    /// as `SOURCE_FAILED` and this stays nil, not 1. Store and activity use `update_time`.
    public let visibilityVersion: String?
    /// Nil when the key is absent. Never filled with a local state.
    public let visualState: String?
    /// Nil when the key is absent. Never filled from layer `read`.
    public let actions: [String]?
    public let found: Bool?
    public let pendingRedeem: Bool?
    public let businessStatus: Int?
}

public struct MapPublicLayerPage: Equatable {
    public var source: String
    public var status: MapPublicLayerStatus
    public var reason: String?
    public var read: Bool?
    /// Layer read capability. Empty `items` with `.unavailable` is not an empty successful page.
    public var items: [MapPublicWireItem]
    public var isEmptySuccess: Bool { status == .ok && items.isEmpty }
}

public struct MapPublicLayerSession: Equatable {
    public var viewerID: Int
    public var fingerprint: String
    public var limit: Int
    public var layers: [String]
    public var minLat: String
    public var maxLat: String
    public var minLng: String
    public var maxLng: String
    public var token: UInt64
    public var cursor: String?
    public var complete: Bool
    public var pages: [MapPublicLayerPage]
}

public struct MapPublicLayerRequest: Equatable {
    public let attempt: UInt64
    public let viewerID: Int
    public let fingerprint: String
    public let cursor: String?
    public let body: String
}

public struct MapPublicWithheldItem: Equatable {
    public let source: String
    public let sourceID: Int
    public let missing: Set<MapPublicMissingField>
}

public enum MapPublicIngest: Equatable {
    case applied(MapPublicLayerSession)
    case stale
    case rejected(MapPublicAdapterFailure)
}
