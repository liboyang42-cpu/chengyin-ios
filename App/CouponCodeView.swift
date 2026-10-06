import SwiftUI
import Observation
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
    @State private var viewPresentation = CouponCodeViewPresentation()
    private struct TaskKey: Hashable { let active: Bool; let presentationID: UUID? }
    var body: some View {
        let appearance = viewPresentation
        let presentation = appearance.permit
        return ScrollView {
            VStack(spacing: 20) {
                if model.ownerIsCurrent {
                    if let name = model.couponName { Text(verbatim: name).font(.title2) }
                    if let description = model.couponDescription { Text(verbatim: description) }
                    if let end = AccountCollectionCoupon.calendarDay(model.endTime) {
                        LabeledContent("accountCollection.coupon.validUntil") { Text(verbatim: end) }
                    }
                }
                content(presentation: presentation, appearance: appearance)
                if model.pollDelayed { Text("couponCode.pollDelayed").font(.footnote) }
                Text("couponCode.authority").font(.footnote).foregroundStyle(.secondary)
            }.padding().frame(maxWidth: .infinity)
        }.navigationTitle("couponCode.title").navigationBarTitleDisplayMode(.inline)
            .privacySensitive().accessibilityIdentifier("couponCode.view")
            .confirmationDialog("couponCode.review", isPresented: $review, titleVisibility: .visible) {
                Button("couponCode.show") {
                    guard let offer = model.offerConfirmation(presentation: presentation) else { return }
                    appearance.actionTask?.cancel()
                    appearance.actionTask = Task { await model.confirmPresentation(permit: offer) }
                }
            } message: { Text("couponCode.review.detail") }
            .onAppear {
                guard let permit = appearance.begin(model: model) else { return }
                if scenePhase == .active { resume(presentation: permit, appearance: appearance) } else { model.pause(presentation: permit) }
            }
            .task(id: TaskKey(active: scenePhase == .active, presentationID: presentation?.id)) {
                guard let presentation else { return }
                guard scenePhase == .active else { model.pause(presentation: presentation); return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    await model.tick(presentation: presentation)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard let presentation, model.presentation === presentation else { return }
                if phase == .active { resume(presentation: presentation, appearance: appearance) }
                else { review = false; appearance.actionTask?.cancel(); appearance.foregroundTask?.cancel(); model.pause(presentation: presentation) }
            }
            .onDisappear {
                if appearance.end(model: model) { review = false }
                if viewPresentation === appearance { viewPresentation = CouponCodeViewPresentation() }
            }
    }
    private func resume(presentation: CouponCodePresentationPermit?, appearance: CouponCodeViewPresentation) {
        guard let offer = model.offerResume(presentation: presentation) else { return }
        appearance.foregroundTask?.cancel()
        appearance.foregroundTask = Task { await model.resume(permit: offer) }
    }
    @ViewBuilder private func content(presentation: CouponCodePresentationPermit?, appearance: CouponCodeViewPresentation) -> some View {
        switch model.phase {
        case .review:
            Text("couponCode.review.detail")
            Button("couponCode.show") {
                guard !appearance.isClosed, let presentation, model.presentation === presentation else { return }
                review = true
            }.buttonStyle(.borderedProminent).accessibilityIdentifier("couponCode.review")
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
            Button("action.retry") {
                guard let offer = model.offerRetry(presentation: presentation) else { return }
                appearance.actionTask?.cancel()
                appearance.actionTask = Task { await model.retry(permit: offer) }
            }
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
/// Tasks belong to this single appearance. Old disappearance callbacks can cancel only
/// their own tasks, and cannot borrow the coordinator's newly installed presentation.
@MainActor @Observable final class CouponCodeViewPresentation {
    private(set) var permit: CouponCodePresentationPermit?
    private(set) var isClosed = false
    var actionTask: Task<Void, Never>?
    var foregroundTask: Task<Void, Never>?
    func begin(model: CouponCodeCoordinator) -> CouponCodePresentationPermit? {
        guard !isClosed else { return nil }
        if let permit { return model.presentation === permit ? permit : nil }
        permit = model.beginPresentation(); return permit
    }
    @discardableResult func end(model: CouponCodeCoordinator) -> Bool {
        guard !isClosed else { return false }
        isClosed = true
        actionTask?.cancel(); actionTask = nil; foregroundTask?.cancel(); foregroundTask = nil
        return model.endPresentation(presentation: permit)
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
