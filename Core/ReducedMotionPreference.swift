/// One device-local app preference, matching the source's shared motion setting.
/// It can reduce motion further; it can never turn off the system accessibility choice.
public enum ReducedMotionPreference {
    public static let storageKey = "chengyin.preferences.reduceMotion"
    public static let defaultValue = false
    public static func effective(system: Bool, local: Bool) -> Bool { system || local }
}
