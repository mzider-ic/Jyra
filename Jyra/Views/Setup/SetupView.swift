import SwiftUI

struct SetupView: View {
    @Environment(ConfigService.self) private var configService

    @State private var jiraURL = ""
    @State private var email = ""
    @State private var apiKey = ""
    @State private var isTesting = false
    @State private var testResult: TestResult? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.indigo)
            Text("Welcome to Jyra")
                .font(.title2.bold())
            Text("Connect your Jira instance to get started.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            field("Jira URL", placeholder: "https://your-org.atlassian.net", text: $jiraURL)
            field("Email", placeholder: "you@example.com", text: $email)
            secureField("API Token", placeholder: "Paste your API token here", text: $apiKey)

            if let result = testResult {
                resultBanner(result)
            }

            HStack {
                Spacer()
                Button("Test Connection") {
                    Task { await testConnection() }
                }
                .disabled(isFormEmpty || isTesting)

                Button("Save & Continue") {
                    Task { await saveAndContinue() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isFormEmpty || isTesting)
            }

            Text("Your API token is stored securely in the macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.headline)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }

    private func secureField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.headline)
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func resultBanner(_ result: TestResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.isSuccess ? .green : .red)
            Text(result.message)
                .font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(result.isSuccess ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    private var isFormEmpty: Bool {
        jiraURL.trimmingCharacters(in: .whitespaces).isEmpty ||
        email.trimmingCharacters(in: .whitespaces).isEmpty ||
        apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        let cfg = AppConfig(jiraURL: jiraURL, email: email, apiKey: apiKey)
        let service = JiraService(config: cfg)
        do {
            let boards = try await service.fetchBoards()
            testResult = .success("Connected — \(boards.count) board(s) found.")
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    private func saveAndContinue() async {
        let cfg = AppConfig(jiraURL: jiraURL, email: email, apiKey: apiKey)
        try? configService.save(cfg)
    }
}

private struct TestResult {
    let isSuccess: Bool
    let message: String

    static func success(_ msg: String) -> TestResult { .init(isSuccess: true, message: msg) }
    static func failure(_ msg: String) -> TestResult { .init(isSuccess: false, message: msg) }
}
