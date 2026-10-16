import SwiftUI

struct ContentView: View {
    @Bindable var model: CornerModel

    private let presets: [(name: String, radius: Double)] = [("Sharp", 0), ("Subtle", 4), ("Classic", 10)]
    private let workspace = NSWorkspace.shared.notificationCenter

    var body: some View {
        Form {
            Section {
                WindowPreview(radius: model.previewRadius)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .animation(.snappy, value: model.previewRadius)
            }

            Section {
                Toggle("Custom window corners", isOn: $model.settings.isEnabled)
                if model.settings.isEnabled {
                    LabeledContent("Radius") {
                        HStack {
                            Slider(value: $model.settings.radius, in: 0...30, step: 1)
                            Text(model.settings.radius == 0 ? "Sharp" : "\(Int(model.settings.radius)) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    LabeledContent("Presets") {
                        HStack {
                            ForEach(presets, id: \.name) { preset in
                                Button(preset.name) { model.settings.radius = preset.radius }
                            }
                        }
                    }
                    Toggle("Include panels and utility windows", isOn: $model.settings.includePanels)
                }
            } footer: {
                Text("Off uses the macOS Tahoe default: 16 pt, or 26 pt for windows with a toolbar.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if model.hasChanges {
                        Button("Revert") { model.revert() }
                    }
                    Spacer()
                    Button("Apply to All Apps") { model.apply() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.hasChanges)
                        .keyboardShortcut(.defaultAction)
                }
            }

            Section {
                if model.appsToRestart.isEmpty {
                    Label("All open apps are using the current setting.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.appsToRestart, id: \.processIdentifier) { app in
                        AppRow(app: app, isRestarting: model.restarting.contains(app.processIdentifier)) {
                            model.restart(app)
                        }
                    }
                }
                if let message = model.message {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Apps to restart")
            } footer: {
                Text("Apps only pick up new corners when they reopen. Restart quits an app the normal way, so it can ask you to save first.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in model.refreshApps() }
        .onReceive(workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in model.refreshApps() }
    }
}

/// A drawn mock window, since a running app can't change its own window corners after launch.
struct WindowPreview: View {
    var radius: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(.red)
                Circle().fill(.yellow)
                Circle().fill(.green)
            }
            .frame(height: 12)
            .padding(14)
            VStack(alignment: .leading, spacing: 8) {
                ForEach([0.8, 0.6, 0.7], id: \.self) { width in
                    Capsule().fill(.quaternary).frame(width: 220 * width, height: 8)
                }
            }
            .padding(.horizontal, 14)
            Spacer()
        }
        .frame(width: 260, height: 160)
        .background(.background, in: shape)
        .overlay(shape.strokeBorder(.separator))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}

struct AppRow: View {
    let app: NSRunningApplication
    let isRestarting: Bool
    let restart: () -> Void

    var body: some View {
        HStack {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            }
            Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown app")
            Spacer()
            if isRestarting {
                ProgressView().controlSize(.small)
            } else {
                Button("Restart", action: restart)
            }
        }
    }
}
