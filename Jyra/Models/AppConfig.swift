import Foundation

struct AppConfig: Codable, Equatable {
    var jiraURL: String
    var email: String
    var apiKey: String

    var authHeader: String {
        let raw = "\(email):\(apiKey)"
        return "Basic \(Data(raw.utf8).base64EncodedString())"
    }

    var baseURL: URL {
        URL(string: jiraURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))!
    }
}
