import Foundation

/// Unlike String(localized:locale:), the resource locale selects the lookup language
/// as well as formatting. Never derive operational region or currency from this value.
func appLocalized(_ key:String.LocalizationValue,locale:Locale)->String {
    String(localized:LocalizedStringResource(key,locale:locale))
}
