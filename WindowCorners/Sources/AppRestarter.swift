import AppKit

/// Finds apps that still use the old corner radius and restarts them.
///
/// AppKit reads the override once per process, so an app only picks up a change after relaunching.
enum AppRestarter {
    private static let finderID = "com.apple.finder"

    /// Regular (Dock) apps launched before `date`.
    static func apps(launchedBefore date: Date) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0 != .current && ($0.launchDate ?? .distantPast) < date }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
    }

    /// Asks `app` to quit like ⌘Q (so it can prompt to save), then reopens it.
    /// Returns a message for the user on failure, or nil on success.
    @MainActor
    static func restart(_ app: NSRunningApplication) async -> String? {
        let name = app.localizedName ?? "The app"
        guard let url = app.bundleURL else { return "Couldn't find where \(name) is installed." }
        let isFinder = app.bundleIdentifier == finderID

        app.terminate()
        if await !waitForExit(app, seconds: isFinder ? 3 : 30) {
            guard isFinder else {
                return "\(name) didn't quit. It may be waiting for you to save; reopen it once it closes."
            }
            app.forceTerminate()
            guard await waitForExit(app, seconds: 3) else { return "Finder didn't quit." }
        }

        // The system usually brings Finder back by itself.
        if isFinder {
            try? await Task.sleep(for: .seconds(1))
            if !NSRunningApplication.runningApplications(withBundleIdentifier: finderID).isEmpty { return nil }
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            return "\(name) quit but couldn't be reopened: \(error.localizedDescription)"
        }
        return nil
    }

    @MainActor
    private static func waitForExit(_ app: NSRunningApplication, seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !app.isTerminated && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return app.isTerminated
    }
}
