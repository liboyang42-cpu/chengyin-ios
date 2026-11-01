import SwiftUI

/// Progress and the three headings from the mini-program activity page.
/// English strings are display only. The step table in `ActivityPublishingWizard` stays the source.
@MainActor struct ActivityPublishingWizardChrome: View {
    let step: Int
    let block: String?
    @Environment(\.locale) private var locale
    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        let current = ActivityPublishingWizard.clamp(step)
        let model = ActivityPublishingWizard.steps[current]
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(ActivityPublishingWizard.progress(current)) { item in
                    Text(verbatim: chinese ? item.title : Self.englishTitle(item.key))
                        .font(item.state == "current" ? .headline : .caption)
                        .foregroundStyle(item.state == "todo" ? .secondary : .primary)
                        .accessibilityIdentifier("publishModes.activity.wizard.progress." + item.key)
                        .accessibilityAddTraits(item.state == "current" ? .isSelected : [])
                        .accessibilityLabel(Text(verbatim: item.title))
                }
            }
            Text(verbatim: chinese ? model.heading : Self.englishHeading(model.key))
                .font(.subheadline)
                .accessibilityIdentifier("publishModes.activity.wizard.heading")
        }
        .accessibilityIdentifier("publishModes.activity.wizard.step." + String(current))
        .accessibilityValue(Text(verbatim: block ?? ""))
    }
    private static func englishTitle(_ key: String) -> String {
        switch key {
        case "basic": return "Basics"
        case "content": return "Activity content"
        case "ticket": return "Tickets and collaborators"
        default: return key
        }
    }
    private static func englishHeading(_ key: String) -> String {
        switch key {
        case "basic": return "What is this activity, and where is it held?"
        case "content": return "What does this activity play?"
        case "ticket": return "How are tickets sold?"
        default: return key
        }
    }
}

/// Step 0 cancels. Later steps go back one. The last step opens the existing review, not a second publish.
@MainActor struct ActivityPublishingWizardNavigation: View {
    let step: Int
    let enabled: Bool
    let onCancel: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    let onReview: () -> Void
    @Environment(\.locale) private var locale
    private var chinese: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        let current = ActivityPublishingWizard.clamp(step)
        Section {
            if current == 0 {
                Button(action: onCancel) { Text("publishModes.cancel") }
                    .disabled(!enabled)
                    .accessibilityIdentifier("publishModes.activity.wizard.cancel")
            } else {
                Button(action: onBack) { Text(verbatim: chinese ? "上一步" : "Back") }
                    .disabled(!enabled)
                    .accessibilityIdentifier("publishModes.activity.wizard.back")
            }
            if current < ActivityPublishingWizard.steps.count - 1 {
                Button(action: onNext) { Text(verbatim: chinese ? "下一步" : "Next") }
                    .disabled(!enabled)
                    .accessibilityIdentifier("publishModes.activity.wizard.next")
            } else {
                Button(action: onReview) { Text("publishModes.review") }
                    .disabled(!enabled)
                    .accessibilityIdentifier("publishModes.activity.review")
            }
        }
    }
}
