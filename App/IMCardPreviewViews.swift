import SwiftUI
import MapKit

/// Mini-program im/chat `fetchTopics`: a route/signup card carries only a topic ID
/// and its display is read fresh from `/api/topic/info-to-user` (TopicReading.topicDetail).
/// Values the server omits stay hidden; nothing (mileage, point count) defaults to 0.
/// Unlike the source, a failed read is not reported as 已下架: only a successful
/// read proves anything, so failure shows an unavailable state with retry.
@MainActor struct IMRouteCardPreview: View {
    let topicID: Int
    let isSignup: Bool
    let reader: any TopicReading
    @State private var detail: TopicDetail?
    @State private var failed = false
    @State private var loading = false
    @State private var loadedScope: UUID?
    var body: some View {
        Group {
            if let detail, loadedScope == reader.scope {
                VStack(alignment: .leading, spacing: 4) {
                    if isSignup { Text("im.card.signupFlag").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor) }
                    Text(verbatim: detail.name).font(.headline)
                    if let summary = summary(detail) { summary.font(.subheadline).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("im.card.route.loaded")
            } else if failed {
                VStack(alignment: .leading, spacing: 6) {
                    Label("im.card.routeUnavailable", systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("im.card.route.unavailable")
                    Button("messaging.retry") { Task { await load() } }
                        .disabled(loading).accessibilityIdentifier("im.card.route.retry")
                }
            } else {
                ProgressView("im.card.routeLoading").accessibilityIdentifier("im.card.route.loading")
            }
        }
        .task(id: reader.scope) { await load() }
    }
    /// "x km · N 个点" with only the parts the server actually returned.
    private func summary(_ detail: TopicDetail) -> Text? {
        var mileage: Text?
        if let value = detail.totalMileage, value.isFinite, value >= 0 {
            mileage = Text(verbatim: value.formatted(.number.precision(.fractionLength(0...1))) + " km")
        }
        var points: Text?
        if let count = detail.locationCount, count >= 0 { points = Text("im.card.pointCount \(count)") }
        switch (mileage, points) {
        case let (m?, p?): return m + Text(verbatim: " · ") + p
        case let (m?, nil): return m
        case let (nil, p?): return p
        default: return nil
        }
    }
    private func load() async {
        guard reader.isConfigured, !loading else { failed = !reader.isConfigured; return }
        let scope = reader.scope
        loading = true; failed = false
        defer { loading = false }
        do {
            let value = try await reader.topicDetail(id: topicID)
            guard !Task.isCancelled, reader.scope == scope, value.id == topicID else { return }
            detail = value; loadedScope = scope
        } catch {
            guard !Task.isCancelled, reader.scope == scope else { return }
            detail = nil; failed = true
        }
    }
}

/// Mini-program `onLocationTap` opens an in-app map at the card's coordinates.
/// iOS shows a static MapKit preview; no device location is requested or shown.
struct IMLocationCardMap: View {
    let title: String?
    let latitude: Double
    let longitude: Double
    var body: some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
            Marker(title ?? "", coordinate: coordinate)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel(Text("im.card.locationMap"))
        .accessibilityIdentifier("im.card.locationMap")
    }
}
