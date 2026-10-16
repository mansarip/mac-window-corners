import SwiftUI

@main
struct WindowCornersApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = CornerModel()

    var body: some Scene {
        Window("Window Corners", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 440, idealWidth: 460, minHeight: 560, idealHeight: 720)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
