import Foundation

/// Local app preferences only. `airplane` is an ambient sound, not the OS airplane-mode setting.
public enum SettingsSoundKey: String, CaseIterable, Codable, Identifiable {
    case sound, haptics, airplane, ocean, raindrop, forest
    public var id: String { rawValue }
    public var titleKey: String { "settingsNative.sound.\(rawValue)" }
}

public struct SettingsSoundPreferences: Codable, Equatable {
    public static let storageKey = "scene_sound_haptics"
    public static let defaults = SettingsSoundPreferences()
    public var sound = true
    public var haptics = true
    public var airplane = true
    public var ocean = false
    public var raindrop = false
    public var forest = false
    public init() {}
    private enum CodingKeys: String, CodingKey { case sound, haptics, airplane, ocean, raindrop, forest }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Missing fields retain source defaults; explicit null or non-Boolean data is corruption.
        for key in SettingsSoundKey.allCases {
            let codingKey = CodingKeys(rawValue: key.rawValue)!
            if container.contains(codingKey) { self[key] = try container.decode(Bool.self, forKey: codingKey) }
        }
    }
    public subscript(_ key: SettingsSoundKey) -> Bool {
        get {
            switch key {
            case .sound: return sound
            case .haptics: return haptics
            case .airplane: return airplane
            case .ocean: return ocean
            case .raindrop: return raindrop
            case .forest: return forest
            }
        }
        set {
            switch key {
            case .sound: sound = newValue
            case .haptics: haptics = newValue
            case .airplane: airplane = newValue
            case .ocean: ocean = newValue
            case .raindrop: raindrop = newValue
            case .forest: forest = newValue
            }
        }
    }
    public static func decodeStored(_ data: Data?) throws -> Self {
        guard let data else { return .defaults }
        return try JSONDecoder().decode(Self.self, from: data)
    }
}

@MainActor public protocol SettingsSoundStoring: AnyObject {
    func read() async throws -> SettingsSoundPreferences
    func write(_ value: SettingsSoundPreferences) async throws
}

/// Non-sensitive local preferences. Does not access Keychain, hardware, location, or a server.
/// No claim is made that Flutter's secure-storage entry has been migrated to UserDefaults.
@MainActor public final class SettingsLocalSoundStore: SettingsSoundStoring {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func read() async throws -> SettingsSoundPreferences {
        let raw = defaults.object(forKey: SettingsSoundPreferences.storageKey)
        guard raw != nil else { return .defaults }
        guard let data = raw as? Data else { throw SettingsSoundStoreError.invalidStoredValue }
        return try SettingsSoundPreferences.decodeStored(data)
    }
    public func write(_ value: SettingsSoundPreferences) async throws {
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: SettingsSoundPreferences.storageKey)
        guard defaults.data(forKey: SettingsSoundPreferences.storageKey) == data else {
            throw SettingsSoundStoreError.writeFailed
        }
    }
}
public enum SettingsSoundStoreError: Error { case invalidStoredValue, writeFailed }

public struct SettingsSoundState: Equatable {
    public var preferences: SettingsSoundPreferences?
    public var isBusy = false
    public var messageKey: String?
    public init() {}
}

/// Serializes writes and commits visible state only after storage succeeds. A failed read
/// never silently overwrites corrupt data with defaults. Cancelled results cannot repaint a screen.
@MainActor public final class SettingsSoundCoordinator {
    public private(set) var state = SettingsSoundState()
    public var onChange: ((SettingsSoundState) -> Void)?
    private let store: any SettingsSoundStoring
    private var generation: UInt64 = 0
    public init(store: any SettingsSoundStoring) { self.store = store }
    private func publish() { onChange?(state) }
    public func load() async {
        guard !state.isBusy else { return }
        generation &+= 1
        let current = generation
        state.isBusy = true; state.messageKey = nil; publish()
        defer { if generation == current { state.isBusy = false; publish() } }
        do {
            let value = try await store.read()
            guard generation == current, !Task.isCancelled else { return }
            state.preferences = value
        } catch {
            guard generation == current, !Task.isCancelled else { return }
            state.preferences = nil; state.messageKey = "settingsNative.sound.loadFailed"
        }
    }
    public func set(_ key: SettingsSoundKey, to value: Bool) async {
        guard !state.isBusy, var next = state.preferences, next[key] != value else { return }
        generation &+= 1
        let current = generation
        next[key] = value
        state.isBusy = true; state.messageKey = nil; publish()
        defer { if generation == current { state.isBusy = false; publish() } }
        do {
            try await store.write(next)
            guard generation == current, !Task.isCancelled else { return }
            state.preferences = next
        } catch {
            guard generation == current, !Task.isCancelled else { return }
            state.messageKey = "settingsNative.sound.saveFailed"
        }
    }
}
