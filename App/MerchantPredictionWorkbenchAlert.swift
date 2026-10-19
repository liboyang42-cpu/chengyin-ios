import SwiftUI

/// Hosts may inject the session-scoped prediction entry; nil keeps the alert informational only.
private struct MerchantPredictionWorkbenchEntryKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> AnyView)? = nil
}
extension EnvironmentValues {
    var merchantPredictionWorkbenchEntry: (@MainActor () -> AnyView)? {
        get { self[MerchantPredictionWorkbenchEntryKey.self] }
        set { self[MerchantPredictionWorkbenchEntryKey.self] = newValue }
    }
}

/// Source pages/merchant/index/index.wxml: "有 N 轮竞猜待给答案" when the role manages projects and
/// todo.pendingPredict > 0. The count only announces work; details and deadlines stay in the inbox.
@MainActor struct MerchantPredictionWorkbenchAlert: View {
    let pending: Int
    @Environment(\.merchantPredictionWorkbenchEntry) private var entry
    var body: some View {
        Label { Text(verbatim: MerchantOpsCopy.text("merchantOps.predict.workbenchAlert %lld", pending)) } icon: { Image(systemName: "questionmark.bubble") }
            .foregroundStyle(.orange).accessibilityIdentifier("merchantOps.predict.workbenchAlert")
        if let entry { entry() }
    }
}
