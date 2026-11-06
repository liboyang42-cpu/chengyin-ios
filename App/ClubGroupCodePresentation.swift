import SwiftUI
import UIKit

/// Display the original bounded inline PNG only. No download, export, renewal or redemption.
@MainActor struct ClubGroupCodePresentation: View {
    let value: ClubGovernanceGroupCode
    let current: Bool
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.periodic(from: value.receivedAt, by: 1)) { timeline in
            if current, scenePhase == .active, value.isActive(at: timeline.date) {
                if let bytes = value.inlinePNG, let image = UIImage(data: bytes) {
                    VStack(spacing: Theme.Space.s2) {
                        Text("club.gov.codeAvailable").font(.headline)
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 300)
                            .background(Color.white)
                            .accessibilityLabel(Text("groupCode.image", tableName: "ClubGroupCodeDisplay"))
                            .privacySensitive().accessibilityIdentifier("club.gov.groupCode")
                        Text("club.gov.codeExpires \(Text(value.expiresAt, style: .timer))")
                            .font(.subheadline).monospacedDigit()
                    }.frame(maxWidth: .infinity)
                } else {
                    Text("groupCode.imageUnavailable", tableName: "ClubGroupCodeDisplay")
                }
            } else {
                Label("club.gov.expiredCode", systemImage: "clock.badge.exclamationmark")
                    .accessibilityIdentifier("club.gov.expiredCode")
            }
        }
    }
}
