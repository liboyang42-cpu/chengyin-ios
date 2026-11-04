import Foundation

/// Display only: consumes the existing wizard reason without validating or editing a draft.
/// The caller supplies App Environment.locale, including when it differs from the device language.
struct ActivityPublishingWizardValidationPresentation {
    let locale: Locale

    func message(for field: String?) -> String {
        guard let field else { return text("activityWizardValidation.none") }
        switch field {
        case "name": return text("activityWizardValidation.name")
        case "addressName": return text("activityWizardValidation.venue")
        case "startDate": return text("activityWizardValidation.start")
        case "endDate": return text("activityWizardValidation.end")
        case "categoryIds": return text("activityWizardValidation.categories")
        case "description": return text("activityWizardValidation.description")
        case "templateId": return text("activityWizardValidation.template")
        case "imgUrl": return text("activityWizardValidation.cover")
        case "collaborators": return text("activityWizardValidation.collaborators")
        case "ticket": return text("activityWizardValidation.tickets")
        default: break
        }
        let ticketFields = [
            ("ticketName", "activityWizardValidation.ticketName"),
            ("ticketPrice", "activityWizardValidation.ticketPrice"),
            ("ticketStock", "activityWizardValidation.ticketStock"),
            ("ticketStart", "activityWizardValidation.ticketStart"),
            ("ticketEnd", "activityWizardValidation.ticketEnd")
        ]
        for (prefix, key) in ticketFields where field.hasPrefix(prefix) {
            let suffix = field.dropFirst(prefix.count)
            // Core interpolates an enumerated Int: ASCII decimal, no sign or leading zeroes.
            // Int.max cannot be converted to a one-based ordinal; fail conservatively.
            guard !suffix.isEmpty,
                  suffix.utf8.allSatisfy({ (48...57).contains($0) }),
                  suffix == "0" || suffix.first != "0",
                  let index = Int(suffix), index < Int.max else { break }
            return String(format: text(key), locale: locale, arguments: [String(index + 1)])
        }
        // Unknown and malformed reasons never become a field name or an invented validation rule.
        return text("activityWizardValidation.unknown")
    }

    private func text(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
            table: "ActivityPublishingWizardValidation", locale: locale))
    }
}
