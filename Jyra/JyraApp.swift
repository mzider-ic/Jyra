import SwiftUI

@main
struct JyraApp: App {
    @State private var configService = ConfigService()
    @State private var metricsStore = MetricsStore()
    @State private var dataCache = JiraDataCache()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(configService)
                .environment(metricsStore)
                .environment(dataCache)
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
