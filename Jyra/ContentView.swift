import SwiftUI

extension Notification.Name {
    static let showNetworkLog = Notification.Name("JyraShowNetworkLog")
}

struct ContentView: View {
    @Environment(ConfigService.self) private var configService
    @State private var showNetworkLog = false

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
        .onReceive(NotificationCenter.default.publisher(for: .showNetworkLog)) { _ in
            showNetworkLog = true
        }
        .sheet(isPresented: $showNetworkLog) {
            NavigationStack {
                NetworkLogView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showNetworkLog = false }
                        }
                    }
            }
            .frame(width: 1100, height: 680)
        }
    }
}
