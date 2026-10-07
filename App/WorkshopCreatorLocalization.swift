import Foundation

/// Named creator catalogs are not Localizable. Preserve the selected UI locale for lookup;
/// this function never interprets complete source/terms text or infers commercial choices.
func workshopCreatorLocalized(_ key: String, locale: Locale) -> String {
    let table: String
    if key.hasPrefix("workshopPending.") { table = "WorkshopCreatorPending" }
    else { table = "WorkshopCreatorConsent" }
    return String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key), table: table, locale: locale))
}
