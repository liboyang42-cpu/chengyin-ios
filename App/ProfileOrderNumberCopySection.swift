import SwiftUI
import UIKit

@MainActor enum ProfileOrderNumberLocalClipboard {
    static func write(_ text: String) {
        // Same bounded local-only policy as existing settlement/support copy actions.
        UIPasteboard.general.setItems([["public.utf8-plain-text": text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
    }
}
@MainActor struct ProfileOrderNumberCopySection: View {
    let order: ProfileOrder
    let requestedID: Int
    let reader: any ProfileReading
    let writeText: @MainActor (String) throws -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var model: ProfileOrderNumberCopyModel
    private var context: ProfileOrderNumberCopyContext? {
        .capture(order: order, requestedID: requestedID, reader: reader)
    }
    init(order: ProfileOrder, requestedID: Int, reader: any ProfileReading,
        writeText: (@MainActor (String) throws -> Void)? = nil) {
        self.order = order; self.requestedID = requestedID; self.reader = reader; self.writeText = writeText ?? ProfileOrderNumberLocalClipboard.write
        _model = State(initialValue: .init(context: .capture(order: order, requestedID: requestedID, reader: reader)))
    }
    var body: some View {
        // A concrete root activates even before the first presentation permit exists.
        ZStack(alignment: .leading) {
            if model.matches(context), let renderedPermit = model.permit {
                VStack(alignment: .leading, spacing: 8) {
                    Button("profile.orderNumberCopy.open", systemImage: "doc.on.doc") {
                        guard scenePhase == .active,
                              let result = model.copy(renderedPermit, current: { context }, write: writeText) else { return }
                        UIAccessibility.post(notification: .announcement,
                            argument: appLocalized(result == .copied ? "localCopy.copied" : "localCopy.failed", locale: locale))
                    }.frame(minHeight: 44).accessibilityIdentifier("profile.orderNumberCopy.open")
                    if let result = model.result {
                        Text(LocalizedStringKey(result == .copied ? "localCopy.copied" : "localCopy.failed"))
                            .font(.footnote).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(result == .copied ? "profile.orderNumberCopy.copied" : "profile.orderNumberCopy.failed")
                    }
                    Text("profile.orderNumberCopy.privateHint").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .privacySensitive()
        .onAppear { if scenePhase == .active { model.appear(current: context) } }
        .onDisappear { model.suspend() }
        .onChange(of: context) { _, _ in model.retire() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.appear(current: context) } else { model.suspend() }
        }
    }
}
