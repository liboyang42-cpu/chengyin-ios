import SwiftUI

@MainActor final class MerchantOnboardingHoursSession: ObservableObject, Identifiable {
    let id = UUID()
    let model: MerchantOnboardingModel
    private let identity: ProfileReadIdentity
    private let revision: Int
    private let original: MerchantOnboardingDraft
    private let initialHours: MerchantOnboardingHours?
    @Published private(set) var hours: MerchantOnboardingHours
    @Published private(set) var edited = false
    private var consumed = false
    var originalValue: String { original.businessTime }
    var hasUnknownValue: Bool { !originalValue.isEmpty && initialHours == nil }
    init?(model: MerchantOnboardingModel) {
        guard let identity = model.identity, identity == model.coordinator.identity,
              !model.isBusy, !model.coordinator.submission.isLocked, model.confirmation == nil else { return nil }
        let value = model.draft, parsed = MerchantOnboardingHours(wireValue: model.draft.businessTime)
        self.model = model; self.identity = identity; revision = model.revision; original = value
        initialHours = parsed; hours = parsed ?? .init()
    }
    var isCurrent: Bool {
        !consumed && model.identity == identity && model.coordinator.identity == identity
            && model.revision == revision && model.draft == original
            && !model.isBusy && !model.coordinator.submission.isLocked && model.confirmation == nil
    }
    var canApply: Bool { isCurrent && hours.blocker == nil && (!hasUnknownValue || edited) }
    func edit(_ change: (inout MerchantOnboardingHours) -> Void) {
        guard isCurrent else { return }; change(&hours); edited = true
    }
    @discardableResult func apply() -> Bool {
        guard canApply, let formatted = try? hours.wireValue() else { return false }
        let value = initialHours == hours ? originalValue : formatted
        consumed = true
        if value != originalValue { model.draft.businessTime = value }
        return true
    }
    func cancel() { consumed = true }
}

@MainActor struct MerchantOnboardingHoursEditor: View {
    @ObservedObject var editor: MerchantOnboardingHoursSession
    let close: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                if editor.hasUnknownValue {
                    Section {
                        Text(verbatim: editor.originalValue).textSelection(.enabled)
                        Text("merchant.onboarding.hoursUnknown").font(.footnote)
                    }
                }
                Section("merchant.onboarding.days") {
                    ForEach(0..<7, id: \.self) { day in
                        Toggle(LocalizedStringKey("merchant.onboarding.day." + String(day)), isOn: Binding(
                            get: { editor.hours.days.contains(day) },
                            set: { selected in editor.edit { if selected { $0.days.insert(day) } else { $0.days.remove(day) } } }))
                            .accessibilityIdentifier("merchant.onboarding.hours.day." + String(day))
                    }
                }
                Section {
                    clock("merchant.onboarding.opens", start: true)
                    clock("merchant.onboarding.closes", start: false)
                    if editor.hours.overnight { Text("merchant.onboarding.hoursNextDay").font(.footnote) }
                    if let blocker = editor.hours.blocker { Text(LocalizedStringKey(blocker)).foregroundStyle(.secondary) }
                }
                Text("merchant.onboarding.hoursLocalDraft").font(.footnote).foregroundStyle(.secondary)
            }.disabled(!editor.isCurrent)
                .appNavigationTitle("merchant.onboarding.hours")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("action.cancel", action: close).disabled(false) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("merchant.onboarding.saveHours") { if editor.apply() { close() } }
                            .disabled(!editor.canApply).accessibilityIdentifier("merchant.onboarding.hours.apply")
                    }
                }
        }
    }
    private func clock(_ title: LocalizedStringKey, start: Bool) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            HStack { component(start: start, hour: true); component(start: start, hour: false) }
        }
    }
    private func component(start: Bool, hour: Bool) -> some View {
        Picker(LocalizedStringKey(hour ? "merchant.operations.hoursHour" : "merchant.operations.hoursMinute"), selection: Binding(get: {
            let minutes = start ? editor.hours.startMinutes : editor.hours.endMinutes
            return hour ? minutes / 60 : minutes % 60
        }, set: { selected in
            editor.edit {
                let old = start ? $0.startMinutes : $0.endMinutes
                let minutes = hour ? selected * 60 + old % 60 : (old / 60) * 60 + selected
                if start { $0.startMinutes = minutes } else { $0.endMinutes = minutes }
            }
        })) {
            ForEach(0..<(hour ? 24 : 60), id: \.self) { value in Text(verbatim: String(format: "%02d", value)).tag(value) }
        }.accessibilityIdentifier("merchant.onboarding.hours." + (start ? "start." : "end.") + (hour ? "hour" : "minute"))
    }
}
