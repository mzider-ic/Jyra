import SwiftUI

@main
struct JyraApp: App {
    @State private var configService = ConfigService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(configService)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(configService)
        }
    }
}
