#if DEBUG
import Observation
import SwiftUI
import UIKit

/// Isolated offline presentation inputs. No network, camera, permission or mutation provider.
@MainActor @Observable final class NativePresentationJourneyReader: PlayerJourneyReading {
    var scope = UUID()
    var expired = false
    var failNextRead = false
    var expireOnDetail = false
    var isAuthenticated: Bool { true }
    var isConfigured: Bool { true }
    private let record = #"{"id":71,"ownerType":1,"ownerId":91,"registrationStatus":2,"paymentStatus":2,"verificationStatus":1,"cmsTopic":{"id":91,"name":"Synthetic completed journey"}}"#
    func participations() async throws -> [ParticipationRecord] {
        if failNextRead { failNextRead = false; throw URLError(.notConnectedToInternet) }
        return [try JSONDecoder().decode(ParticipationRecord.self, from: Data(record.utf8))]
    }
    func detail(id: Int) async throws -> ParticipationDetail {
        if expireOnDetail { expireOnDetail = false; expired = true; scope = UUID() }
        return try JSONDecoder().decode(ParticipationDetail.self, from: Data(record.utf8))
    }
    func completed() async throws -> [CompletedPlayRecord] { [] }
}

@MainActor @Observable final class NativePresentationImageReader: RetainedPublicImageReading {
    let enabled: Bool
    var failNextRead = false
    var readCount = 0
    var onRead: (() -> Void)?
    init(enabled: Bool = true, failNextRead: Bool = false) {
        self.enabled = enabled; self.failNextRead = failNextRead
    }
    func image(url: URL) async throws -> Data {
        guard enabled else { throw RetainedImageFailure.disabled }
        readCount += 1
        let event = onRead; onRead = nil; event?()
        if failNextRead { failNextRead = false; return Data("invalid synthetic image".utf8) }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let size = CGSize(width: 48, height: 48)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }
        guard let bytes = image.jpegData(compressionQuality: 0.8) else { throw RetainedImageFailure.invalid }
        return bytes
    }
}

@MainActor struct NativePresentationFixtureHost: View {
    private let scenario: String
    @State private var journey: NativePresentationJourneyReader
    @State private var images: NativePresentationImageReader
    @State private var mediaScope = UUID()
    @State private var expired = false
    @State private var gallery = false
    @State private var routed = false
    private let lifecycle = OrderLifecycleCoordinator(reader: OrderLifecycleFixtureReader(scenario: .paid))
    private let sources = ["https://example.invalid/synthetic-one.jpg", "https://example.invalid/synthetic-two.jpg"]
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-presentation-scenario")
        let scenario = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "gallery"
        self.scenario = scenario
        let journey = NativePresentationJourneyReader()
        journey.failNextRead = scenario == "journeyFailure"
        journey.expireOnDetail = scenario == "journeyScope"
        _journey = State(initialValue: journey)
        _images = State(initialValue: NativePresentationImageReader(enabled: scenario != "galleryDisabled", failNextRead: scenario == "galleryRetry"))
    }
    var body: some View {
        NavigationStack {
            if scenario.hasPrefix("journey") {
                VStack {
                    if journey.expired { Text(verbatim: "Synthetic scope changed").accessibilityIdentifier("presentation.fixture.expired") }
                    if routed { Text(verbatim: "Root destination opened").accessibilityIdentifier("presentation.fixture.routed") }
                    ParticipationHistoryView(reader: journey, lifecycle: lifecycle, open: { _ in routed = true }, signIn: {})
                }
            } else if scenario == "stampDisabled" {
                RoamStampCameraView()
            } else if scenario == "posterDisabled" {
                if let node = try? JSONDecoder().decode(RoamNodeDetail.self, from: Data(#"{"poiId":7,"name":"Synthetic poster","status":1,"validationMethod":4}"#.utf8)) {
                    RoamPosterScanView(node: node)
                }
            } else {
                Form {
                    if scenario == "galleryRetry" {
                        Button("media.destination.openImage") { gallery = true }
                            .accessibilityIdentifier("presentation.fixture.openFailure")
                    } else {
                        NativeMediaGalleryEntry(sources: sources, scope: mediaScope, reader: images)
                        Text(verbatim: String(images.readCount)).accessibilityIdentifier("presentation.fixture.readCount")
                        Button {
                            images.onRead = { mediaScope = UUID(); expired = true }
                        } label: { Text(verbatim: "Change scope on next image read") }
                        .accessibilityIdentifier("presentation.fixture.expire")
                        if expired { Text(verbatim: "Synthetic scope changed").accessibilityIdentifier("presentation.fixture.expired") }
                    }
                }
                .navigationTitle("media.destination.squareImages")
                .fullScreenCover(isPresented: $gallery) {
                    NativeMediaGallery(snapshot: .init(sources: [sources[0]], selectedIndex: 0), titleKey: "media.destination.squareImages", reader: images)
                }
            }
        }
    }
}
#endif
