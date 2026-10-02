import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Device side effects are separately gated from backend approval. Default construction is inert.
@MainActor final class MerchantContactDeviceAdapter: MerchantContactDelivering {
    private let deviceEffectsAllowed: Bool
    init(deviceEffectsAllowed: Bool = false) { self.deviceEffectsAllowed = deviceEffectsAllowed }
    func deliverSynthetic(phone: String, purpose: MerchantContactPurpose) async throws {
        guard deviceEffectsAllowed else { throw MerchantBusinessFailure.disabled }
        switch purpose {
        case .copy:
            UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: phone]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        case .call:
            // Do not allow a contact response to become an arbitrary URL scheme or dialer command.
            guard phone.range(of: #"^\+?[0-9 ()-]{3,32}$"#, options: .regularExpression) != nil else { throw MerchantBusinessFailure.malformed }
            var components = URLComponents(); components.scheme = "tel"; components.path = phone
            guard let url = components.url, UIApplication.shared.canOpenURL(url) else { throw MerchantBusinessFailure.invalid }
            let opened = await UIApplication.shared.open(url)
            guard opened else { throw MerchantBusinessFailure.invalid }
        }
    }
}
struct MerchantExportFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "xlsx") ?? .data] }
    let bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw MerchantBusinessFailure.malformed }; self.bytes = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}
/// Explicit native save UI. Does not open a share sheet or send a workbook to another person.
@MainActor struct MerchantExportSaveView: View {
    let taskID: Int
    let bytes: Data
    var deviceExportAllowed = false
    @State private var presenting = false
    @State private var outcome: String?
    var body: some View {
        VStack(alignment: .leading) {
            Button("merchant.engagement.saveWorkbook") { presenting = true }.disabled(!deviceExportAllowed)
            if !deviceExportAllowed { Text("merchant.engagement.deviceExportDisabled").font(.footnote).foregroundStyle(.secondary) }
            if let outcome { Text(LocalizedStringKey(outcome)).font(.footnote) }
        }
        .fileExporter(isPresented: $presenting, document: MerchantExportFileDocument(bytes: bytes), contentType: UTType(filenameExtension: "xlsx") ?? .data,
                      defaultFilename: "merchant-customers-\(taskID).xlsx") { result in
            switch result { case .success: outcome = "merchant.engagement.workbookSaved"; case .failure: outcome = "merchant.engagement.workbookSaveFailed" }
        }
    }
}
