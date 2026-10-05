import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

private struct VerificationCodeFactoryKey: EnvironmentKey {
    static let defaultValue: (@MainActor (VerificationCodeTarget) -> VerificationCodeCoordinator)? = nil
}
extension EnvironmentValues {
    var verificationCodeFactory: (@MainActor (VerificationCodeTarget) -> VerificationCodeCoordinator)? {
        get { self[VerificationCodeFactoryKey.self] }
        set { self[VerificationCodeFactoryKey.self] = newValue }
    }
}

/// Native presentation uses the exact validated server payload and never a screenshot,
/// decorative QR, remote URL encoded as a token, or persistent credential/image cache.
@MainActor struct VerificationCodeView: View {
    @State var model: VerificationCodeCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var operation: Task<Void, Never>?
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: model.target.kind == .ticket ? "ticket" : "mappin.circle")
                    .font(.largeTitle).accessibilityHidden(true)
                Text(model.target.kind == .ticket ? "verificationCode.ticket.title" : "verificationCode.city.title").font(.title2.bold())
                content
                if model.target.kind == .ticket, model.readback != nil {
                    Button("verificationCode.checkOrder") { run { await model.checkOrder() } }
                        .disabled(model.checkingOrder || model.phase == .loading)
                        .accessibilityIdentifier("verificationCode.checkOrder")
                    if model.checkingOrder { ProgressView("verificationCode.checking") }
                    if model.readbackFailed { Text("verificationCode.readbackFailed").font(.footnote) }
                    if let detail = model.readback {
                        Text(detail.registrationStatus == 2 ? "verificationCode.order.active" : "verificationCode.order.ended")
                            .accessibilityIdentifier("verificationCode.orderState")
                    }
                }
                Text(model.target.kind == .ticket ? "verificationCode.ticket.authority" : "verificationCode.city.authority")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding().frame(maxWidth: .infinity)
        }
        .navigationTitle(model.target.kind == .ticket ? "verificationCode.ticket.title" : "verificationCode.city.title")
        .navigationBarTitleDisplayMode(.inline).privacySensitive()
        .task(id: scenePhase) {
            guard scenePhase == .active else { cancel(); return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                await model.tick()
            }
        }
        .onChange(of: scenePhase) { _, value in if value != .active { cancel() } }
        .onDisappear { operation?.cancel(); operation = nil; model.invalidate() }
        .accessibilityIdentifier("verificationCode.view")
    }
    @ViewBuilder private var content: some View {
        if model.phase == .ready, let code = model.displayCode {
            VerificationLocalQRCode(code: code)
            Button("verificationCode.retry") { run { await model.present() } }
                .accessibilityIdentifier("verificationCode.refresh")
            LabeledContent("verificationCode.remaining") { Text(model.remainingSeconds, format: .number).monospacedDigit() }
        } else if model.phase == .loading {
            ProgressView("verificationCode.loading")
        } else {
            Text(LocalizedStringKey("verificationCode.phase." + model.phase.rawValue))
                .multilineTextAlignment(.center).accessibilityIdentifier("verificationCode.phase")
            if [.review, .expired, .paused, .failed, .invalid].contains(model.phase) {
                Button(model.phase == .review ? "verificationCode.show" : "verificationCode.retry") { run { await model.present() } }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("verificationCode.show")
            }
        }
    }
    private func run(_ work: @escaping @MainActor () async -> Void) {
        operation?.cancel(); operation = Task { await work() }
    }
    private func cancel() { operation?.cancel(); operation = nil; model.pause() }
}

@MainActor private struct VerificationLocalQRCode: View {
    let code: String
    private var image: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8); filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let bitmap = CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: bitmap)
    }
    var body: some View {
        if let image {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                .frame(maxWidth: 280).padding(24).background(.white)
                .accessibilityLabel("verificationCode.image").accessibilityIdentifier("verificationCode.qr")
        } else { Text("verificationCode.renderFailed") }
    }
}
