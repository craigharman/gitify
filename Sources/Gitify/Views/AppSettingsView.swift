import SwiftUI

/// App-level preferences pane (Cmd+,). Provides tabs for General settings and AI configuration.
struct AppSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 420)
    }
}

/// General settings tab: default terminal and editor pickers.
private struct GeneralSettingsTab: View {
    @State private var terminalID: String = AppDefaults.terminalBundleID
    @State private var editorID: String = AppDefaults.editorBundleID ?? ""

    @State private var installedTerminals: [AppDefaults.KnownApp] = []
    @State private var installedEditors: [AppDefaults.KnownApp] = []

    var body: some View {
        Form {
            Picker("Terminal", selection: $terminalID) {
                ForEach(installedTerminals) { app in
                    AppLabel(app: app).tag(app.bundleID)
                }
            }

            Picker("Editor", selection: $editorID) {
                Text("System Default").tag("")
                ForEach(installedEditors) { app in
                    AppLabel(app: app).tag(app.bundleID)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: terminalID) { _, newValue in
            AppDefaults.terminalBundleID = newValue
        }
        .onChange(of: editorID) { _, newValue in
            AppDefaults.editorBundleID = newValue.isEmpty ? nil : newValue
        }
        .task {
            installedTerminals = AppDefaults.installedTerminals
            installedEditors = AppDefaults.installedEditors
        }
    }
}

/// A picker row showing an app's icon and name.
private struct AppLabel: View {
    let app: AppDefaults.KnownApp

    var body: some View {
        HStack(spacing: 6) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(app.name)
        }
    }
}
