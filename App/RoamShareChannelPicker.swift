import SwiftUI

@MainActor struct RoamShareChannelPicker: View {
    @Binding var mode: RoamShareChannelPolicy.Mode
    let isBusy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("roam.shareChannels.title", selection: $mode) {
                ForEach(RoamShareChannelPolicy.Mode.allCases) { choice in
                    Text(LocalizedStringKey("roam.shareChannels.mode." + choice.rawValue)).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .disabled(isBusy)
            .accessibilityIdentifier("roam.shareChannels.picker")
            Text("roam.shareChannels.boundary")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("roam.shareChannels.boundary")
            Text(LocalizedStringKey("roam.shareChannels.hint." + mode.rawValue))
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("roam.shareChannels.selected." + mode.rawValue)
        }
    }
}
