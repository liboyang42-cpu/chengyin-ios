import SwiftUI
import UIKit

@MainActor struct SettingsAboutView: View {
    let market: RegionalMarket?
    let appInformation: SettingsAppInformation
    let legalReader: any SettingsLegalReading
    var copyText: (String) throws -> Void = { UIPasteboard.general.string = $0 }
    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Image("SettingsBrandMark").resizable().scaledToFit().frame(width: 54, height: 54).accessibilityHidden(true)
                    if let name = appInformation.displayName {
                        Text(verbatim: name).font(.largeTitle.bold()).accessibilityIdentifier("settingsNative.about.appName")
                    } else { Text("settingsNative.about.nameMissing") }
                    Text("settingsNative.about.tagline").foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical)
                LabeledContent("settingsNative.about.version") {
                    if let version = appInformation.version {
                        Text(verbatim: version).accessibilityIdentifier("settingsNative.about.version")
                    } else { Text("settingsNative.about.metadataMissing") }
                }
                LabeledContent("settingsNative.about.build") {
                    if let build = appInformation.build {
                        Text(verbatim: build).accessibilityIdentifier("settingsNative.about.build")
                    } else { Text("settingsNative.about.metadataMissing") }
                }
                LabeledContent("region.market") {
                    Text(verbatim: market?.rawValue ?? "—")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("region.market"))
                .accessibilityValue(Text(verbatim: market?.rawValue ?? "—"))
                .accessibilityIdentifier("settingsNative.about.market")
            }
            Section("settingsNative.about.playerCode") {
                Label {
                    Text("settingsNative.about.playerCodeUnavailable").accessibilityIdentifier("settingsNative.about.codeUnavailable")
                } icon: { Image(systemName: "info.circle").accessibilityHidden(true) }
            }
            Section {
                ForEach([SettingsLegalType.userAgreement, .privacyPolicy]) { type in
                    NavigationLink {
                        SettingsLegalDocumentView(type: type, market: market, reader: legalReader)
                    } label: { Text(LocalizedStringKey(type.titleKey)) }
                    .accessibilityIdentifier("settingsNative.about.openLegal.\(type.rawValue)")
                }
            }
            if let phone = SettingsSourceContact.phone(market: market) {
                Section("settingsNative.about.contact") {
                    Text(verbatim: phone).textSelection(.enabled)
                        .accessibilityIdentifier("settingsNative.about.contactPhone")
                    NativeCopyTextButton(text: phone, title: "settingsNative.about.copyPhone",
                        identifier: "settingsNative.about.copyPhone", copyText: copyText)
                }
            }
            SettingsAttributionsSection(copyText: copyText)
        }
        .appNavigationTitle("settingsNative.about.title")
    }
}
