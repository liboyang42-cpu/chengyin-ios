import SwiftUI

/// Mini-program pages/merchant/index block-level reminders (index.wxml:113-132).
/// Each reminder appears only from a loaded, current todo-summary with a positive count;
/// a failed or loading summary never claims "nothing pending". Destinations re-check
/// their own authorization; the reminder itself carries no grant.
@MainActor struct MerchantWorkbenchReminders: View {
    @ObservedObject var todo: MerchantLoadModel<MerchantTodo>
    let access: MerchantAccess
    let aftercareRoute: MerchantWorkbenchBusinessRoute?
    let predictionReader: MerchantPredictionReader?

    static func aftercareCount(_ todo: MerchantTodo?, access: MerchantAccess, isLoading: Bool) -> Int? {
        guard !isLoading, let todo, access.canReadAftercare, todo.refundCount > 0 else { return nil }
        return todo.refundCount
    }
    static func predictCount(_ todo: MerchantTodo?, access: MerchantAccess, isLoading: Bool) -> Int? {
        guard !isLoading, let todo, access.allows(.projects), todo.pendingPredict > 0 else { return nil }
        return todo.pendingPredict
    }

    var body: some View {
        let aftercare = Self.aftercareCount(todo.value, access: access, isLoading: todo.isLoading)
        let predict = Self.predictCount(todo.value, access: access, isLoading: todo.isLoading)
        if aftercare != nil || predict != nil {
            Section {
                if let aftercare {
                    if let aftercareRoute {
                        NavigationLink(value: aftercareRoute) { reminder(Text("merchant.workbench.aftercareReminder \(aftercare)")) }
                            .accessibilityIdentifier("merchant.workbench.reminder.aftercare")
                    } else {
                        unavailable(Text("merchant.workbench.aftercareReminder \(aftercare)"), id: "aftercare")
                    }
                }
                if let predict {
                    if let predictionReader, predictionReader.isConfigured {
                        NavigationLink { MerchantPredictionInboxView(reader: predictionReader.isolatedReader()) } label: {
                            reminder(Text("merchant.workbench.predictReminder \(predict)"))
                        }.accessibilityIdentifier("merchant.workbench.reminder.predict")
                    } else {
                        unavailable(Text("merchant.workbench.predictReminder \(predict)"), id: "predict")
                    }
                }
            }
        }
    }
    private func reminder(_ text: Text) -> some View {
        Label { text } icon: { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange) }
    }
    private func unavailable(_ text: Text, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            reminder(text)
            Text("merchant.workbench.reminderUnavailable").font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("merchant.workbench.reminder." + id)
    }
}
