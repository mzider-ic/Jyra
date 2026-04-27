import SwiftUI

struct SettingsView: View {
    @Environment(ConfigService.self) private var configService

    @State private var jiraURL = ""
    @State private var email = ""
    @State private var apiKey = ""
    @State private var gitlabToken = ""
    @State private var isTesting = false
    @State private var isTestingGL = false
    @State private var isSaved = false
    @State private var testResult: String? = nil
    @State private var testSuccess = false
    @State private var glTestResult: String? = nil
    @State private var glTestSuccess = false
    @State private var velocityPalette = VelocityPalette.default

    var body: some View {
        Form {
            Section("Jira Connection") {
                TextField("Jira URL", text: $jiraURL)
                    .help("e.g. https://your-org.atlassian.net")
                TextField("Email", text: $email)
                SecureField("API Token", text: $apiKey)
                    .help("Generate from id.atlassian.com/manage-profile/security/api-tokens")
                HStack {
                    Button("Test Jira Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(isTesting || isFormEmpty)

                    if isTesting { ProgressView().scaleEffect(0.7) }

                    if let result = testResult {
                        Label(result, systemImage: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(testSuccess ? .green : .red)
                            .font(.caption)
                    }
                }
            }

            Section("GitLab Activity (optional)") {
                SecureField("Personal Access Token", text: $gitlabToken)
                    .help("GitLab → User Settings → Access Tokens. Needs read_user + read_api scopes.")
                Text("When set, engineer activity (commits, MRs, reviews) is fetched from GitLab Cloud and shown alongside calibration metrics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Test GitLab Connection") {
                        Task { await testGitLabConnection() }
                    }
                    .disabled(isTestingGL || gitlabToken.isEmpty)

                    if isTestingGL { ProgressView().scaleEffect(0.7) }

                    if let result = glTestResult {
                        Label(result, systemImage: glTestSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(glTestSuccess ? .green : .red)
                            .font(.caption)
                    }
                }
            }

            Section("Default Velocity Colors") {
                ColorPicker("Committed", selection: paletteBinding(\.committedHex))
                ColorPicker("Completed", selection: paletteBinding(\.completedHex))
                ColorPicker("Percent Complete", selection: paletteBinding(\.completionHex))
                ColorPicker("Average Line", selection: paletteBinding(\.averageHex))
            }

            Section {
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
        gitlabToken = cfg.gitlabToken
        velocityPalette = cfg.velocityPalette
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        let cfg = AppConfig(jiraURL: jiraURL, email: email, apiKey: apiKey,
                            velocityPalette: velocityPalette, gitlabToken: gitlabToken)
        do {
            let name = try await JiraService(config: cfg).ping()
            testSuccess = true
            testResult = "Connected as \(name)"
        } catch {
            testSuccess = false
            testResult = error.localizedDescription
        }
    }

    private func testGitLabConnection() async {
        isTestingGL = true
        glTestResult = nil
        defer { isTestingGL = false }
        do {
            let username = try await GitLabService(token: gitlabToken).ping()
            glTestSuccess = true
            glTestResult = "Connected as @\(username)"
        } catch {
            glTestSuccess = false
            glTestResult = error.localizedDescription
        }
    }

    private func saveSettings() {
        let cfg = AppConfig(jiraURL: jiraURL, email: email, apiKey: apiKey,
                            velocityPalette: velocityPalette, gitlabToken: gitlabToken)
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
