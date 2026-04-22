import SwiftUI

struct SettingsView: View {
    @Environment(ConfigService.self) private var configService

    @State private var jiraURL = ""
    @State private var email = ""
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var isSaved = false
    @State private var testResult: String? = nil
    @State private var testSuccess = false
    @State private var velocityPalette = VelocityPalette.default

    var body: some View {
        Form {
            Section("Jira Connection") {
                TextField("Jira URL", text: $jiraURL)
                    .help("e.g. https://your-org.atlassian.net")
                TextField("Email", text: $email)
                SecureField("API Token", text: $apiKey)
                    .help("Generate from id.atlassian.com/manage-profile/security/api-tokens")
            }

            Section("Default Velocity Colors") {
                ColorPicker("Committed", selection: paletteBinding(\.committedHex))
                ColorPicker("Completed", selection: paletteBinding(\.completedHex))
                ColorPicker("Percent Complete", selection: paletteBinding(\.completionHex))
                ColorPicker("Average Line", selection: paletteBinding(\.averageHex))
            }

            Section {
                HStack {
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isTesting || isFormEmpty)

                    if isTesting {
                        ProgressView().scaleEffect(0.7)
                    }

                    if let result = testResult {
                        Label(result, systemImage: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(testSuccess ? .green : .red)
                            .font(.caption)
                    }
                }

                Button("Save Settings") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isFormEmpty)

                if isSaved {
                    Text("Settings saved.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section {
                Button("Disconnect & Reset", role: .destructive) {
                    configService.clear()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .navigationTitle("Settings")
        .onAppear { prefill() }
    }

    private var isFormEmpty: Bool {
        jiraURL.trimmingCharacters(in: .whitespaces).isEmpty ||
        email.trimmingCharacters(in: .whitespaces).isEmpty ||
        apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func prefill() {
        guard let cfg = configService.config else { return }
        jiraURL = cfg.jiraURL
        email = cfg.email
        apiKey = cfg.apiKey
        velocityPalette = cfg.velocityPalette
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        let cfg = AppConfig(jiraURL: jiraURL, email: email, apiKey: apiKey, velocityPalette: velocityPalette)
        do {
            let name = try await JiraService(config: cfg).ping()
            testSuccess = true
            testResult = "Connected as \(name)"
        } catch {
            testSuccess = false
            testResult = error.localizedDescription
        }
    }

    private func saveSettings() {
        let cfg = AppConfig(jiraURL: jiraURL, email: email, apiKey: apiKey, velocityPalette: velocityPalette)
        try? configService.save(cfg)
        isSaved = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            isSaved = false
        }
    }

    private func paletteBinding(_ keyPath: WritableKeyPath<VelocityPalette, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: velocityPalette[keyPath: keyPath]) },
            set: { velocityPalette[keyPath: keyPath] = $0.hexString }
        )
    }
}
