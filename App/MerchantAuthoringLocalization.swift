import SwiftUI

func merchantAuthoringText(_ key: String) -> Text { Text(LocalizedStringKey(key), tableName: "MerchantAuthoring") }
func merchantAuthoringButton(_ key: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
    Button(role: role, action: action) { merchantAuthoringText(key) }
}
func merchantAuthoringLabeled(_ key: String, value: String) -> some View {
    LabeledContent { Text(verbatim: value) } label: { merchantAuthoringText(key) }
}
// M06 presentation helpers are intentionally opt-in: shared authoring callers retain their styling.
extension View {
    /// A persistent visual label remains visible after the native field contains text.
    /// The native control keeps its original accessibility label and binding.
    func merchantCreationFieldLabel(_ title: Text) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            title.font(Theme.Font.label).foregroundStyle(Theme.Color.textSecondary(in: .merchant))
                .fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
            self
        }
        .padding(.vertical, Theme.Space.s1)
    }

    func merchantCreationSurface() -> some View {
        self.font(Theme.Font.body)
            .listSectionSpacing(Theme.Space.s4)
            .scrollContentBackground(.hidden)
            .background(Theme.Color.bgPage(in: .merchant))
            .foregroundStyle(Theme.Color.textPrimary(in: .merchant))
            .tint(Theme.Color.accent(in: .merchant))
            .themeDomain(.merchant)
    }
}

func merchantCreationNotice(_ text: Text, systemImage: String = "info.circle", attention: Bool = false) -> some View {
    HStack(alignment: .top, spacing: Theme.Space.s3) {
        Image(systemName: systemImage).accessibilityHidden(true)
            .foregroundStyle(attention ? Theme.Color.danger(in: .merchant) : Theme.Color.accent(in: .merchant))
        text.font(.footnote).foregroundStyle(Theme.Color.textSecondary(in: .merchant))
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, Theme.Space.s2)
}

func merchantCreationLabeled(_ key: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.Space.s1_5) {
        merchantAuthoringText(key).font(Theme.Font.label)
            .foregroundStyle(Theme.Color.textSecondary(in: .merchant))
        Text(verbatim: value).font(Theme.Font.body).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, Theme.Space.s1)
    .accessibilityElement(children: .combine)
}

/// Render all original JSON types without changing the stored result or treating it as current.
enum MerchantCreationOriginalValue {
    static func display(_ value: ProjectEditJSON?) -> String {
        guard let value else { return "" }
        if let text = value.text { return text }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let bytes = try? encoder.encode(value) else { return "" }
        return String(decoding: bytes, as: UTF8.self)
    }
}

enum MerchantAuthoringLabels {
    static func generationFailure(_ code: String) -> String? {
        switch code {
        case "CONFIG_ADMISSION", "ADMISSION_POLICY_CHANGED": return "merchantAuthoring.admission.unconfigured"
        case "ADMISSION_USER_LIMIT", "ADMISSION_MERCHANT_LIMIT", "ADMISSION_THEME_LIMIT", "ADMISSION_GLOBAL_LIMIT": return "merchantAuthoring.admission.capacityExceeded"
        case "MODEL_FACT_CHANGED": return "merchantAuthoring.modelChangedFacts"
        case "MODEL_INCOMPLETE": return "merchantAuthoring.modelIncomplete"
        case "FACT_VERSION_CHANGED": return "merchantAuthoring.factsChanged"
        default: return nil
        }
    }
    static func environmentReason(_ code: String) -> String {
        switch code {
        case "READY": return "merchantAuthoring.environment.reason.READY"
        case "CLOSED": return "merchantAuthoring.environment.reason.CLOSED"
        case "TIME_WINDOW_EXPIRED": return "merchantAuthoring.environment.reason.TIME_WINDOW_EXPIRED"
        case "SEVERE_WEATHER": return "merchantAuthoring.environment.reason.SEVERE_WEATHER"
        case "STORE_STATUS_UNAVAILABLE": return "merchantAuthoring.environment.reason.STORE_STATUS_UNAVAILABLE"
        case "HOURS_UNAVAILABLE": return "merchantAuthoring.environment.reason.HOURS_UNAVAILABLE"
        case "NO_APPROVED_BRANCH": return "merchantAuthoring.environment.reason.NO_APPROVED_BRANCH"
        case "RAIN_NO_SAFE_BRANCH": return "merchantAuthoring.environment.reason.RAIN_NO_SAFE_BRANCH"
        case "RELEASE_UNAVAILABLE": return "merchantAuthoring.environment.reason.RELEASE_UNAVAILABLE"
        default: return "merchantAuthoring.environment.reason.ENVIRONMENT_UNAVAILABLE"
        }
    }
    static func field(_ key: String) -> String {
        switch key {
        case "store_knowledge": return "merchantAuthoring.knowledge"
        case "service_information": return "merchantAuthoring.services"
        case "canonical_plot": return "merchantAuthoring.plot"
        case "allowed_variables": return "merchantAuthoring.variables"
        case "approved_branches": return "merchantAuthoring.branches"
        case "server_action_rules": return "merchantAuthoring.actionRules"
        case "duration_minutes": return "merchantAuthoring.duration"
        case "headcount": return "merchantAuthoring.participants"
        case "business_segment": return "merchantAuthoring.businessHours"
        case "staff_need": return "merchantAuthoring.staff"
        case "noise_limit": return "merchantAuthoring.noise"
        case "photo_limit": return "merchantAuthoring.photo"
        case "accessibility_alternative": return "merchantAuthoring.accessible"
        case "offline_alternative": return "merchantAuthoring.offline"
        case "fail_exit": return "merchantAuthoring.failureExit"
        case "reward_rule_ref": return "merchantAuthoring.rewardRule"
        case "product_facts": return "merchantAuthoring.product.savedFacts"
        case "product_id": return "merchantAuthoring.productID"
        case "sku_id": return "merchantAuthoring.skuID"
        default: return "merchantAuthoring.otherField"
        }
    }
}
