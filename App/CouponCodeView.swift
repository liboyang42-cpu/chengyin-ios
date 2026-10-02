import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

private struct CouponCodeFactoryKey: EnvironmentKey {
    static let defaultValue: (@MainActor (Int) -> CouponCodeCoordinator)? = nil
}
extension EnvironmentValues {
    var couponCodeFactory: (@MainActor (Int) -> CouponCodeCoordinator)? {
        get { self[CouponCodeFactoryKey.self] }
        set { self[CouponCodeFactoryKey.self] = newValue }
    }
}

@MainActor struct CouponCodeView: View {
    @State var model: CouponCodeCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var review = false
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if model.ownerIsCurrent {
                    if let name = model.couponName { Text(verbatim: name).font(.title2) }
                    if let description = model.couponDescription { Text(verbatim: description) }
                    if let end = AccountCollectionCoupon.calendarDay(model.endTime) {
                        LabeledContent("accountCollection.coupon.validUntil") { Text(verbatim: end) }
                    }
                }
                content
                if model.pollDelayed { Text("couponCode.pollDelayed").font(.footnote) }
                Text("couponCode.authority").font(.footnote).foregroundStyle(.secondary)
            }.padding().frame(maxWidth: .infinity)
        }.navigationTitle("couponCode.title").navigationBarTitleDisplayMode(.inline)
            .privacySensitive().accessibilityIdentifier("couponCode.view")
            .confirmationDialog("couponCode.review", isPresented: $review, titleVisibility: .visible) {
                Button("couponCode.show") { Task { await model.confirmPresentation() } }
            } message: { Text("couponCode.review.detail") }
            .task(id: scenePhase) {
                guard scenePhase == .active else { model.pause(); return }
                await model.resume()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    await model.tick()
                }
            }
            .onDisappear { model.invalidate() }
    }
    @ViewBuilder private var content: some View {
        switch model.phase {
        case .review:
            Text("couponCode.review.detail")
            Button("couponCode.show") { review = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("couponCode.review")
        case .ready:
            if model.canDisplay {
                if let token = model.displayToken { CouponLocalQRImage(token: token) }
                else if let bytes = model.imageBytes, let image = UIImage(data: bytes) {
                    Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(width: 240, height: 240)
                        .padding(24).background(.white).accessibilityLabel("couponCode.image")
                } else { Text("couponCode.renderFailed") }
                LabeledContent("couponCode.remaining") { Text(model.remainingSeconds, format: .number).monospacedDigit() }
            }
        case .loading: ProgressView("couponCode.loading")
        case .waiting: Label("couponCode.waiting", systemImage: "clock")
        case .paused: Label("couponCode.paused", systemImage: "pause.circle")
        case .failed:
            ContentUnavailableView("couponCode.failed", systemImage: "exclamationmark.triangle", description: Text("couponCode.failed.detail"))
            Button("action.retry") { Task { await model.retry() } }
        case .used:
            Label("couponCode.used", systemImage: "checkmark.seal.fill").font(.title2)
            if let time = model.useTime { Text(verbatim: time) }
        case .expired: Label("couponCode.expired", systemImage: "clock.badge.xmark")
        case .invalid: Label("couponCode.invalid", systemImage: "xmark.seal")
        case .unavailable: Label("couponCode.unavailable", systemImage: "nosign")
        case .disabled: Text("couponCode.disabled")
        case .login: Text("couponCode.login")
        case .stale: Text("couponCode.stale")
        }
    }
}
/// Core Image encodes only the exact ephemeral token supplied by a validated issue receipt.
/// Never encode the qrcodeUrl as a new credential, invent an entitlement, or persist pixels.
@MainActor private struct CouponLocalQRImage: View {
    let token: String
    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(token.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
    var body: some View {
        if let image {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(width: 240, height: 240)
                .padding(24).background(.white).accessibilityLabel("couponCode.image").accessibilityIdentifier("couponCode.qr")
        } else { Text("couponCode.renderFailed") }
    }
}
