import Foundation

enum Preferences {
    private enum Key {
        static let appLanguage = "appLanguage"
        static let onboardingCompleted = "onboardingCompleted"
        static let reminderMode = "reminderMode"
        static let reminderTheme = "reminderTheme"
        static let randomThemeRotationEnabled = "randomThemeRotationEnabled"
        static let randomThemeRotationIntervalMinutes = "randomThemeRotationIntervalMinutes"
        static let randomThemeRotationNextChangeAt = "randomThemeRotationNextChangeAt"
        static let randomThemeRotationPendingTheme = "randomThemeRotationPendingTheme"
        static let workMinutes = "workMinutes"
        static let restSeconds = "restSeconds"
        static let inactivityRestEnabled = "inactivityRestEnabled"
        static let inactivityRestMinutes = "inactivityRestMinutes"
    }

    static let defaultWorkMinutes = 20
    static let defaultRestSeconds = 20
    static let defaultInactivityRestMinutes = 5
    static let defaultRandomThemeRotationIntervalMinutes = 60
    static let workMinutesRange = 1...180
    static let restSecondsRange = 5...300
    static let inactivityRestMinutesRange = 1...180
    static let randomThemeRotationIntervalMinutesRange = 5...1_440

    static var appLanguage: AppLanguage {
        get {
            let storedValue = UserDefaults.standard.string(forKey: Key.appLanguage)
            let language = AppLanguage.restored(fromPersistedValue: storedValue)
            if storedValue != language.rawValue {
                UserDefaults.standard.set(language.rawValue, forKey: Key.appLanguage)
            }
            return language
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.appLanguage) }
    }

    static var onboardingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: Key.onboardingCompleted) }
        set { UserDefaults.standard.set(newValue, forKey: Key.onboardingCompleted) }
    }

    static var reminderMode: ReminderMode {
        get {
            let storedValue = UserDefaults.standard.string(forKey: Key.reminderMode)
            let mode = ReminderMode.restored(fromPersistedValue: storedValue)
            if storedValue != mode.rawValue {
                UserDefaults.standard.set(mode.rawValue, forKey: Key.reminderMode)
            }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.reminderMode) }
    }

    static var reminderTheme: ReminderTheme {
        get {
            let storedValue = UserDefaults.standard.string(forKey: Key.reminderTheme)
            let theme = ReminderTheme.restored(fromPersistedValue: storedValue)
            if storedValue != theme.rawValue {
                UserDefaults.standard.set(theme.rawValue, forKey: Key.reminderTheme)
            }
            return theme
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.reminderTheme) }
    }

    static var randomThemeRotationEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.randomThemeRotationEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.randomThemeRotationEnabled) }
    }

    static var randomThemeRotationIntervalMinutes: Int {
        get {
            let stored = UserDefaults.standard.object(
                forKey: Key.randomThemeRotationIntervalMinutes
            ) as? NSNumber
            return normalizedRandomThemeRotationIntervalMinutes(
                stored?.intValue ?? defaultRandomThemeRotationIntervalMinutes
            )
        }
        set {
            UserDefaults.standard.set(
                normalizedRandomThemeRotationIntervalMinutes(newValue),
                forKey: Key.randomThemeRotationIntervalMinutes
            )
        }
    }

    static var randomThemeRotationNextChangeAt: Date? {
        get {
            UserDefaults.standard.object(forKey: Key.randomThemeRotationNextChangeAt) as? Date
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Key.randomThemeRotationNextChangeAt)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.randomThemeRotationNextChangeAt)
            }
        }
    }

    static var randomThemeRotationPendingTheme: ReminderTheme? {
        get {
            guard let rawValue = UserDefaults.standard.string(
                forKey: Key.randomThemeRotationPendingTheme
            ) else { return nil }
            return ReminderTheme(rawValue: rawValue)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(
                    newValue.rawValue,
                    forKey: Key.randomThemeRotationPendingTheme
                )
            } else {
                UserDefaults.standard.removeObject(forKey: Key.randomThemeRotationPendingTheme)
            }
        }
    }

    static var workMinutes: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: Key.workMinutes) as? NSNumber
            return normalizedWorkMinutes(stored?.intValue ?? defaultWorkMinutes)
        }
        set {
            UserDefaults.standard.set(normalizedWorkMinutes(newValue), forKey: Key.workMinutes)
        }
    }

    static var restSeconds: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: Key.restSeconds) as? NSNumber
            return normalizedRestSeconds(stored?.intValue ?? defaultRestSeconds)
        }
        set {
            UserDefaults.standard.set(normalizedRestSeconds(newValue), forKey: Key.restSeconds)
        }
    }

    static var inactivityRestEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.inactivityRestEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.inactivityRestEnabled) }
    }

    static var inactivityRestMinutes: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: Key.inactivityRestMinutes) as? NSNumber
            return normalizedInactivityRestMinutes(
                stored?.intValue ?? defaultInactivityRestMinutes
            )
        }
        set {
            UserDefaults.standard.set(
                normalizedInactivityRestMinutes(newValue),
                forKey: Key.inactivityRestMinutes
            )
        }
    }

    static func normalizedWorkMinutes(_ value: Int) -> Int {
        min(max(value, workMinutesRange.lowerBound), workMinutesRange.upperBound)
    }

    static func normalizedRestSeconds(_ value: Int) -> Int {
        min(max(value, restSecondsRange.lowerBound), restSecondsRange.upperBound)
    }

    static func normalizedInactivityRestMinutes(_ value: Int) -> Int {
        min(
            max(value, inactivityRestMinutesRange.lowerBound),
            inactivityRestMinutesRange.upperBound
        )
    }

    static func normalizedRandomThemeRotationIntervalMinutes(_ value: Int) -> Int {
        min(
            max(value, randomThemeRotationIntervalMinutesRange.lowerBound),
            randomThemeRotationIntervalMinutesRange.upperBound
        )
    }
}
