import SwiftUI

@MainActor
struct MerchantStoreHoursEditor: View {
    @ObservedObject var model: MerchantOperationsViewModel
    @State private var hours: MerchantStoreHours?
    private var profile: MerchantStoreProfile? {
        guard case .profile(let value) = model.coordinator.draft else { return nil }
        return value
    }
    private var editable: Bool {
        model.coordinator.isCurrent && !model.coordinator.isBusy && !model.coordinator.isLocked
            && model.coordinator.confirmation == nil
    }
    var body: some View {
        Section("merchant.operations.businessTime") {
            Text(verbatim: profile?.displayedBusinessTime ?? "—")
                .accessibilityIdentifier("merchant.operations.hours.current")
            Text("merchant.operations.hoursPreserved").font(.footnote).foregroundStyle(.secondary)
            if let current = hours {
                ForEach(0..<7, id: \.self) { day in
                    Toggle(LocalizedStringKey("merchant.onboarding.day." + String(day)), isOn: Binding(
                        get: { hours?.days.contains(day) ?? false },
                        set: { selected in
                            guard editable else { return }
                            if selected { hours?.days.insert(day) } else { hours?.days.remove(day) }
                        }))
                        .accessibilityIdentifier("merchant.operations.hours.day." + String(day))
                }
                clockPicker("merchant.onboarding.opens", start: true)
                clockPicker("merchant.onboarding.closes", start: false)
                if current.overnight { Text("merchant.operations.hoursOvernight") }
                if let blocker = current.blocker { Text(LocalizedStringKey(blocker)).foregroundStyle(.secondary) }
                Button("merchant.operations.hoursUseDraft") {
                    guard editable, let value = hours, let wire = try? value.wireValue(), var profile else { return }
                    profile.businessTimeReplacement = wire
                    model.edit(.profile(profile)); hours = nil
                }.disabled(!editable || current.blocker != nil)
                    .accessibilityIdentifier("merchant.operations.hours.apply")
                Button("action.cancel") { hours = nil }.accessibilityIdentifier("merchant.operations.hours.cancel")
            } else {
                Button("merchant.operations.hoursEdit") {
                    guard editable else { return }
                    hours = profile?.displayedBusinessTime.flatMap { MerchantStoreHours(wireValue: $0) } ?? MerchantStoreHours()
                }.disabled(!editable).accessibilityIdentifier("merchant.operations.hours.edit")
            }
            if profile?.businessTimeReplacement != nil {
                Button("merchant.operations.hoursRestore") {
                    guard editable, var profile else { return }
                    profile.businessTimeReplacement = nil; model.edit(.profile(profile)); hours = nil
                }.disabled(!editable).accessibilityIdentifier("merchant.operations.hours.restore")
            }
        }
        .disabled(!editable)
        .onChange(of: model.coordinator.draftIdentity) { _, _ in hours = nil }
        .onChange(of: model.coordinator.isCurrent) { _, current in if !current { hours = nil } }
    }
    private func clockPicker(_ title: LocalizedStringKey, start: Bool) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            HStack {
                timeComponent(start: start, hour: true)
                timeComponent(start: start, hour: false)
            }
        }
    }
    private func timeComponent(start: Bool, hour: Bool) -> some View {
        Picker(LocalizedStringKey(hour ? "merchant.operations.hoursHour" : "merchant.operations.hoursMinute"), selection: Binding(get: {
            let minute = start ? (hours?.startMinutes ?? 600) : (hours?.endMinutes ?? 1320)
            return hour ? minute / 60 : minute % 60
        }, set: { selected in
            guard editable else { return }
            let old = start ? (hours?.startMinutes ?? 600) : (hours?.endMinutes ?? 1320)
            let minute = hour ? selected * 60 + old % 60 : (old / 60) * 60 + selected
            if start { hours?.startMinutes = minute } else { hours?.endMinutes = minute }
        })) {
            ForEach(0..<(hour ? 24 : 60), id: \.self) { value in Text(verbatim: String(format: "%02d", value)).tag(value) }
        }.accessibilityIdentifier("merchant.operations.hours." + (start ? "start." : "end.") + (hour ? "hour" : "minute"))
    }
}
