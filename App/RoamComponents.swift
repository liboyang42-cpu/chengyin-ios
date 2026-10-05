import SwiftUI

extension RoamMapItem {
    var symbol: String {
        switch self {
        case .place(let place): return place.type == 2 ? "storefront" : "mappin"
        case .route: return "point.topleft.down.to.point.bottomright.curvepath"
        case .event(let event): return event.kind == "topic" ? "map" : "calendar"
        case .player: return "figure.walk"
        }
    }
    var kindLabel: LocalizedStringKey {
        switch self {
        case .place(let place): return place.type == 2 ? "roam.filter.merchant" : "roam.filter.city"
        case .route: return "roam.layer.routes"
        case .event(let event): return event.kind == "topic" ? "roam.filter.topic" : "roam.filter.activity"
        case .player: return "roam.layer.players"
        }
    }
    var address: String? {
        switch self {
        case .place(let place): return place.address
        case .route(let node): return node.address
        case .event(let event): return event.addressName
        case .player: return nil
        }
    }
    var distance: Double? {
        switch self {
        case .route(let node): return node.distance
        case .event(let event): return event.distance
        default: return nil // Never compute a precise player distance.
        }
    }
}
struct RoamTitle: View {
    let value: String
    init(_ value: String) { self.value = value }
    var body: some View {
        if value.isEmpty { Text("roam.unnamed") } else { Text(verbatim: value) }
    }
}
struct RoamDistanceLabel: View {
    let meters: Double
    var body: some View {
        LabeledContent("roam.distanceFromArea") {
            Text(Measurement(value: meters, unit: UnitLength.meters), format: .measurement(width: .abbreviated))
                .monospacedDigit()
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}
enum RoamScreenIssue {
    case notConfigured, unauthorized, areaRequired, notFound, failed
    init(error: Error) {
        if error as? APIError == .notConfigured { self = .notConfigured }
        else if error as? APIError == .unauthorized { self = .unauthorized }
        else if error as? RoamReadFailure == .searchAreaRequired { self = .areaRequired }
        else if error as? RoamReadFailure == .nodeNotFound { self = .notFound }
        else { self = .failed }
    }
    var title: LocalizedStringKey {
        switch self {
        case .notConfigured: return "roam.notConfigured"
        case .unauthorized: return "roam.signInRequired"
        case .areaRequired: return "roam.areaRequired"
        case .notFound: return "roam.notFound"
        case .failed: return "roam.failed"
        }
    }
    var message: LocalizedStringKey {
        switch self {
        case .notConfigured: return "roam.notConfiguredHint"
        case .unauthorized: return "roam.signInHint"
        case .areaRequired: return "roam.areaRequiredHint"
        case .notFound: return "roam.notFoundHint"
        case .failed: return "roam.failedHint"
        }
    }
}
struct RoamStatusView: View {
    let issue: RoamScreenIssue
    var retry: (() -> Void)? = nil
    var body: some View {
        ContentUnavailableView {
            Label(issue.title, systemImage: "map")
        } description: {
            Text(issue.message)
        } actions: {
            if case .failed = issue, let retry { Button("action.retry", action: retry) }
        }
        .accessibilityIdentifier("roam.error")
    }
}
