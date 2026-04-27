import Foundation
import Security

@Observable
final class ConfigService {
    private(set) var config: AppConfig?

    var isConfigured: Bool { config != nil }

    private let keychainService       = "com.jyra.apikey"
    private let gitlabKeychainService = "com.jyra.gitlabtoken"
    private let defaultsURL            = "jira_url"
    private let defaultsEmail          = "jira_email"
    private let defaultsVelocityPalette = "velocity_palette"

    init() {
        load()
    }

    func save(_ config: AppConfig) throws {
        try saveSecret(config.apiKey, service: keychainService)
        saveGitLabToken(config.gitlabToken)
        UserDefaults.standard.set(config.jiraURL, forKey: defaultsURL)
        UserDefaults.standard.set(config.email, forKey: defaultsEmail)
        if let paletteData = try? JSONEncoder().encode(config.velocityPalette) {
            UserDefaults.standard.set(paletteData, forKey: defaultsVelocityPalette)
        }
        self.config = config
    }

    func clear() {
        deleteSecret(service: keychainService)
        deleteSecret(service: gitlabKeychainService)
        UserDefaults.standard.removeObject(forKey: defaultsURL)
        UserDefaults.standard.removeObject(forKey: defaultsEmail)
        UserDefaults.standard.removeObject(forKey: defaultsVelocityPalette)
        config = nil
    }

    private func load() {
        if let mockURL = ProcessInfo.processInfo.environment["JYRA_MOCK_URL"] {
            config = AppConfig(jiraURL: mockURL, email: "mock@example.com", apiKey: "mock-key")
            return
        }
        guard
            let url   = UserDefaults.standard.string(forKey: defaultsURL),
            let email = UserDefaults.standard.string(forKey: defaultsEmail),
            let key   = loadSecret(service: keychainService),
            !url.isEmpty, !email.isEmpty, !key.isEmpty
        else { return }
        let palette: VelocityPalette = {
            guard let data    = UserDefaults.standard.data(forKey: defaultsVelocityPalette),
                  let decoded = try? JSONDecoder().decode(VelocityPalette.self, from: data) else {
                return .default
            }
            return decoded
        }()
        let gitlabToken = loadSecret(service: gitlabKeychainService) ?? ""
        config = AppConfig(jiraURL: url, email: email, apiKey: key,
                           velocityPalette: palette, gitlabToken: gitlabToken)
    }

    // MARK: - GitLab token (optional — no error thrown if empty)

    private func saveGitLabToken(_ token: String) {
        if token.isEmpty {
            deleteSecret(service: gitlabKeychainService)
        } else {
            try? saveSecret(token, service: gitlabKeychainService)
        }
    }

    // MARK: - Generic Keychain helpers

    private func saveSecret(_ value: String, service: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ConfigError.keychainWrite(status)
        }
    }

    private func loadSecret(service: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteSecret(service: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum ConfigError: LocalizedError {
    case keychainWrite(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainWrite(let s): return "Keychain write failed (OSStatus \(s))"
        }
    }
}
