#if DEBUG
import SwiftUI
import UIKit

/// Offline host for `MiniCropView`: two synthetic drawn images, no photo library, camera or upload.
@MainActor struct MiniCropFixtureHostView: View {
    @State private var ratio = "1:1"
    @State private var outcome: String?
    @State private var visit = UUID()
    private static func swatch(_ color: UIColor, width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    private let images = [swatch(.systemTeal, width: 400, height: 300), swatch(.systemOrange, width: 300, height: 400)]
    var body: some View {
        NavigationStack {
            VStack {
                Picker("publishParity.crop.ratio", selection: $ratio) {
                    ForEach(MiniCropGeometry.presets, id: \.self) { Text(verbatim: $0).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("miniCrop.ratio")
                if let outcome { Text(verbatim: outcome).accessibilityIdentifier("miniCrop.outcome") }
                MiniCropView(images: images, ratio: ratio, onFinish: { results in
                    outcome = results.map { result -> String in
                        switch result {
                        case .original: return "original"
                        case .crop(let rect): return "crop \(Int(rect.width.rounded()))x\(Int(rect.height.rounded()))"
                        }
                    }.joined(separator: ", ")
                    visit = UUID()
                }, onCancel: { outcome = "cancelled"; visit = UUID() }).id("\(ratio)-\(visit)")
            }
        }
    }
}
#endif
