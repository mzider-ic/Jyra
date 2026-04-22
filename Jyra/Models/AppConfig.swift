import Foundation
import SwiftUI
import AppKit

struct AppConfig: Codable, Equatable {
    var jiraURL: String
    var email: String
    var apiKey: String
    var velocityPalette: VelocityPalette = .default

    var authHeader: String {
        let raw = "\(email):\(apiKey)"
        return "Basic \(Data(raw.utf8).base64EncodedString())"
    }

    var baseURL: URL {
        URL(string: jiraURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))!
    }
}

struct VelocityPalette: Codable, Equatable {
    var committedHex: String
    var completedHex: String
    var completionHex: String
    var averageHex: String

    static let `default` = VelocityPalette(
        committedHex: "#6688FF",
        completedHex: "#41CFA0",
        completionHex: "#6FD3FF",
        averageHex: "#FFB454"
    )

    var committedColor: Color { Color(hex: committedHex) }
    var completedColor: Color { Color(hex: completedHex) }
    var completionColor: Color { Color(hex: completionHex) }
    var averageColor: Color { Color(hex: averageHex) }
}

extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&int)

        let r, g, b: UInt64
        switch sanitized.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (102, 136, 255)
        }

        self = Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }

    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? .systemBlue
        let red = Int(round(nsColor.redComponent * 255))
        let green = Int(round(nsColor.greenComponent * 255))
        let blue = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
