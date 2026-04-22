import SwiftUI

struct ContentView: View {
    @Environment(ConfigService.self) private var configService

    var body: some View {
        Group {
            if configService.isConfigured {
                DashboardView()
            } else {
                SetupView()
                    .frame(width: 520, height: 600)
            }
        }
        .preferredColorScheme(.dark)
    }
}
