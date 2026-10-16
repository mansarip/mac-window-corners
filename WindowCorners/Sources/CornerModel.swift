import AppKit
import Observation

@MainActor @Observable
final class CornerModel {
    struct Settings: Equatable {
        var isEnabled: Bool
        var radius: Double
        var includePanels: Bool
    }

    /// What the controls show; becomes active for other apps only after `apply()`.
    var settings: Settings
    private(set) var saved: Settings
    private(set) var appsToRestart: [NSRunningApplication] = []
    private(set) var restarting: Set<pid_t> = []
    var message: String?

    /// When the override was last written; apps launched before this still use the old value.
    private var savedAt: Date
    private static let savedAtKey = "savedAt"

    var hasChanges: Bool { settings != saved }

    /// Radius the preview should draw (macOS Tahoe uses 16 pt for a plain titled window).
    var previewRadius: Double { settings.isEnabled ? settings.radius : 16 }

    init() {
        let window = CornerOverride.read(CornerOverride.windowKey)
        let panel = CornerOverride.read(CornerOverride.panelKey)
        let current = Settings(isEnabled: window != nil,
                               radius: window.map(CornerOverride.displayRadius) ?? 0,
                               includePanels: window == nil || panel != nil)
        settings = current
        saved = current
        if let date = UserDefaults.standard.object(forKey: Self.savedAtKey) as? Date {
            savedAt = date
        } else if current.isEnabled {
            savedAt = CornerOverride.globalPreferencesModified ?? Date()
        } else {
            savedAt = .distantPast
        }
        refreshApps()
    }

    func apply() {
        let radius = settings.isEnabled ? settings.radius : nil
        CornerOverride.write(CornerOverride.windowKey, radius: radius)
        CornerOverride.write(CornerOverride.panelKey, radius: settings.includePanels ? radius : nil)
        saved = settings
        savedAt = Date()
        UserDefaults.standard.set(savedAt, forKey: Self.savedAtKey)
        message = nil
        refreshApps()
    }

    func revert() {
        settings = saved
    }

    func refreshApps() {
        appsToRestart = AppRestarter.apps(launchedBefore: savedAt)
    }

    func restart(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        restarting.insert(pid)
        Task {
            message = await AppRestarter.restart(app)
            restarting.remove(pid)
            refreshApps()
        }
    }
}
