import Foundation

public enum AuthMode: String, Codable, Sendable {
    case apiKey = "api_key"
    case chatGPT = "chat_gpt"
}
