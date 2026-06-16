import SwiftUI

@main
struct GitifyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await UpdateChecker.checkForUpdates(userInitiated: true) }
                }
            }
            CommandGroup(after: .newItem) {
                Button("Add Repository…") {
                    Task { await model.promptToAddRepository() }
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
