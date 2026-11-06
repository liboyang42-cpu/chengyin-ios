import SwiftUI

/// Mini-program scene-settings-deregister: executeAfter is shown as a time, or 执行时间待确认.
/// Reform plan v9 U03: display follows the phone's zone; the Beijing wall time is added when
/// the zones differ, and the cooling-off deadline itself is decided by the server.
struct DeregistrationExecuteAfterRow: View {
    let raw: String?
    var phoneTimeZone: TimeZone = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                if let display = BeijingServerTime(raw).display(phoneTimeZone: phoneTimeZone) {
                    Text(verbatim: display.phone + (display.phoneZoneAbbreviation.map { " (" + $0 + ")" } ?? ""))
                        .accessibilityIdentifier("authEntry.deregister.executeAfter")
                } else {
                    Text("authEntry.deregister.timePending", tableName: "AuthEntry")
                        .accessibilityIdentifier("authEntry.deregister.timePending")
                }
            } label: { Text("authEntry.deregister.executeAfter", tableName: "AuthEntry") }
            if let beijing = BeijingServerTime(raw).display(phoneTimeZone: phoneTimeZone)?.beijing {
                HStack(spacing: 4) {
                    Text("authEntry.deregister.beijingTime", tableName: "AuthEntry")
                    Text(verbatim: beijing)
                }.font(.footnote).foregroundStyle(.secondary).accessibilityElement(children: .combine)
            }
            Text("authEntry.deregister.serverDecides", tableName: "AuthEntry").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// WECHAT reconfirmation needs a mini-program wx.login code; UNAVAILABLE has no method at all.
/// Neither records the cancellation-notice consent nor offers SMS.
struct DeregistrationVerificationUnavailableSection: View {
    let method: String?
    let recheck: () -> Void

    var body: some View {
        Section {
            if method == "WECHAT" {
                Text("authEntry.deregister.wechatUnavailable", tableName: "AuthEntry")
                    .accessibilityIdentifier("authEntry.deregister.wechatUnavailable")
            } else {
                Text("authEntry.deregister.verificationUnavailable", tableName: "AuthEntry")
                    .accessibilityIdentifier("authEntry.deregister.verificationUnavailable")
            }
            Button(action: recheck) { Text("authEntry.deregister.recheck", tableName: "AuthEntry") }
                .accessibilityIdentifier("authEntry.deregister.recheck")
        }
    }
}
