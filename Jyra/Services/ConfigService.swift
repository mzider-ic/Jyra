import Foundation
import Security

@Observable
final class ConfigService {
    private(set) var config: AppConfig?

    var isConfigured: Bool { config != nil }

    private let keychainService = "com.jyra.apikey"
    private let defaultsURL = "jira_url"
    private let defaultsEmail = "jira_email"
    private let defaultsVelocityPalette = "velocity_palette"

    init() {
        load()
    }

    func save(_ config: AppConfig) throws {
        try saveApiKey(config.apiKey)
        UserDefaults.standard.set(config.jiraURL, forKey: defaultsURL)
        UserDefaults.standard.set(config.email, forKey: defaultsEmail)
        if let paletteData = try? JSONEncoder().encode(config.velocityPalette) {
            UserDefaults.standard.set(paletteData, forKey: defaultsVelocityPalette)
        }
        self.config = config
    }

    func clear() {
        deleteApiKey()
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
            let url = UserDefaults.standard.string(forKey: defaultsURL),
            let email = UserDefaults.standard.string(forKey: defaultsEmail),
            let key = loadApiKey(),
            !url.isEmpty, !email.isEmpty, !key.isEmpty
        else { return }
        let palette: VelocityPalette = {
            guard let data = UserDefaults.standard.data(forKey: defaultsVelocityPalette),
                  let decoded = try? JSONDecoder().decode(VelocityPalette.self, from: data) else {
                return .default
            }
            return decoded
        }()
        config = AppConfig(jiraURL: url, email: email, apiKey: key, velocityPalette: palette)
    }

    // MARK: Keychain

    private func saveApiKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ConfigError.keychainWrite(status)
        }
    }

    private func loadApiKey() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteApiKey() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService
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
