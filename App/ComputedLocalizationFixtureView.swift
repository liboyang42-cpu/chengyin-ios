#if DEBUG
import SwiftUI

struct ComputedLocalizationFixtureView:View {
    @Environment(\.locale) private var locale
    @AppStorage("preferences.language") private var language=AppLanguage.system.rawValue
    var body:some View {
        VStack(spacing:24) {
            Text(verbatim:appLocalized("settings.title",locale:locale))
                .accessibilityIdentifier("localization.fixture.computed")
            Button("简体中文") { language=AppLanguage.simplifiedChinese.rawValue }
                .accessibilityIdentifier("localization.fixture.chinese")
            Button("English") { language=AppLanguage.english.rawValue }
                .accessibilityIdentifier("localization.fixture.english")
        }
    }
}
#endif
