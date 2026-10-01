import Foundation

/// Unlike String(localized:locale:), the resource locale selects the lookup language
/// as well as formatting. Never derive operational region or currency from this value.
func appLocalized(_ key:String.LocalizationValue,locale:Locale)->String {
    String(localized:LocalizedStringResource(key,locale:locale))
}

import SwiftUI
private struct AppNavigationTitle: ViewModifier {
    let key: String.LocalizationValue
    @Environment(\.locale) private var locale
    func body(content: Content) -> some View {
        content.navigationTitle(appLocalized(key, locale: locale))
    }
}
extension View {
    func appNavigationTitle(_ key: String.LocalizationValue) -> some View {
        modifier(AppNavigationTitle(key: key))
    }
    func appNavigationTitle(key: String) -> some View {
        modifier(AppNavigationTitle(key: String.LocalizationValue(stringLiteral: key)))
    }
}
