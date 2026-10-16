import Foundation

/// The AppKit corner-radius override, stored in the global defaults domain
/// (the same place `defaults write -g` writes to).
///
/// `-[NSThemeFrame _getCachedWindowCornerRadius]` uses these keys when they are non-zero,
/// so "sharp" is stored as a tiny positive value instead of 0.
enum CornerOverride {
    /// Titled windows, sheets and alerts.
    static let windowKey = "NSConvolutionOverride1"
    /// Utility windows and panels.
    static let panelKey = "NSConvolutionOverride2"
    /// Smallest value AppKit honours; renders as a square corner.
    static let sharpValue = 0.01

    static func read(_ key: String) -> Double? {
        let value = CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (value as? NSNumber)?.doubleValue
    }

    /// Writes `radius` (in points) for `key`, or removes the key when `radius` is nil.
    static func write(_ key: String, radius: Double?) {
        let number = radius.map { NSNumber(value: Float(max($0, sharpValue))) }
        CFPreferencesSetValue(key as CFString, number, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    /// Maps a stored value back to what the slider shows (the 0.01 "sharp" value shows as 0).
    static func displayRadius(_ stored: Double) -> Double {
        stored <= sharpValue * 1.5 ? 0 : stored.rounded()
    }

    /// Last time the global preferences file changed; used as a conservative guess for
    /// when the override was written if this app has never saved it.
    static var globalPreferencesModified: Date? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Preferences/.GlobalPreferences.plist")
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
