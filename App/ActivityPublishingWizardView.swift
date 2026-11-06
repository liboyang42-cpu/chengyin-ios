import SwiftUI

/// Step dots from the mini-program activity page (基本信息 · 活动内容 · 票务与合作).
/// The step table in `ActivityPublishingWizard` stays the source; titles are localized keys here.
/// Field errors are shown under their field by the form; this only shows a reason no field owns.
@MainActor struct ActivityPublishingWizardChrome: View {
    let step: Int
    let block: String?
    @Environment(\.locale) private var locale
    private static let fieldOwned: Set<String> = ["name", "addressName", "startDate", "endDate", "categoryIds",
        "description", "imgUrl", "templateId", "collaborators", "ticket"]
    private static let ticketPrefixes = ["ticketName", "ticketPrice", "ticketStock", "ticketStart", "ticketEnd"]
    private var unownedBlock: String? {
        guard let block, !Self.fieldOwned.contains(block),
              !Self.ticketPrefixes.contains(where: { block.hasPrefix($0) }) else { return nil }
        return block
    }
    var body: some View {
        let current = ActivityPublishingWizard.clamp(step)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(ActivityPublishingWizard.progress(current)) { item in
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(item.state == "todo" ? Color.secondary.opacity(0.25) : Color.accentColor)
                            .frame(height: 4)
                        Text(Self.titleKey(item.key))
                            .font(item.state == "current" ? .footnote.weight(.semibold) : .footnote)
                            .foregroundStyle(item.state == "todo" ? .secondary : .primary)
                            .lineLimit(2).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("publishModes.activity.wizard.progress." + item.key)
                    .accessibilityAddTraits(item.state == "current" ? .isSelected : [])
                }
            }
            if let unownedBlock {
                Text(verbatim: ActivityPublishingWizardValidationPresentation(locale: locale).message(for: unownedBlock))
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("publishModes.activity.wizard.validation")
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("publishModes.activity.wizard.step." + String(current))
    }
    private static func titleKey(_ key: String) -> LocalizedStringKey {
        switch key {
        case "basic": return "publishModes.wizard.step.basic"
        case "content": return "publishModes.wizard.step.content"
        case "ticket": return "publishModes.wizard.step.ticket"
        default: return LocalizedStringKey(key)
        }
    }
}

/// Mini-program bottom bar: Cancel (step 0) or Back on the left, Next or Review as the one primary action.
/// The last step opens the existing review, not a second publish.
@MainActor struct ActivityPublishingWizardNavigation: View {
    let step: Int
    let enabled: Bool
    let onCancel: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    let onReview: () -> Void
    var body: some View {
        let current = ActivityPublishingWizard.clamp(step)
        HStack(spacing: 12) {
            if current == 0 {
                Button(action: onCancel) { Text("publishModes.cancel").frame(minWidth: 72) }
                    .buttonStyle(.bordered)
                    .disabled(!enabled)
                    .accessibilityIdentifier("publishModes.activity.wizard.cancel")
            } else {
                Button(action: onBack) { Text("publishModes.wizard.back").frame(minWidth: 72) }
                    .buttonStyle(.bordered)
                    .disabled(!enabled)
                    .accessibilityIdentifier("publishModes.activity.wizard.back")
            }
            if current < ActivityPublishingWizard.steps.count - 1 {
                Button(action: onNext) { Text("publishModes.wizard.next").frame(maxWidth: .infinity) }
                    .buttonStyle(.questifyPrimary)
                    .disabled(!enabled)
                    .accessibilityIdentifier("publishModes.activity.wizard.next")
            } else {
                Button(action: onReview) { Text("publishModes.review").frame(maxWidth: .infinity) }
                    .buttonStyle(.questifyPrimary)
                    .disabled(!enabled)
                    .accessibilityIdentifier("publishModes.activity.review")
            }
        }
        .controlSize(.large)
    }
}
