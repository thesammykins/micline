import Foundation

public struct MicLineUpdateConfiguration: Equatable, Sendable {
    public enum Issue: String, Error, Equatable, Sendable {
        case missingFeedURL
        case insecureFeedURL
        case embeddedFeedCredentials
        case unsupportedFeedURLComponents
        case missingPublicKey
        case invalidPublicKey
    }

    public let feedURL: URL
    public let publicEdKey: String

    public init(infoDictionary: [String: Any]) throws {
        guard let feedValue = infoDictionary["SUFeedURL"] as? String,
              let feedURL = URL(string: feedValue),
              feedURL.host?.isEmpty == false else {
            throw Issue.missingFeedURL
        }
        guard feedURL.scheme?.lowercased() == "https" else {
            throw Issue.insecureFeedURL
        }
        guard feedURL.user == nil, feedURL.password == nil else {
            throw Issue.embeddedFeedCredentials
        }
        guard feedURL.query == nil, feedURL.fragment == nil else {
            throw Issue.unsupportedFeedURLComponents
        }

        guard let keyValue = infoDictionary["SUPublicEDKey"] as? String else {
            throw Issue.missingPublicKey
        }
        let publicEdKey = keyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !publicEdKey.isEmpty else {
            throw Issue.missingPublicKey
        }
        guard let keyData = Data(base64Encoded: publicEdKey), keyData.count == 32 else {
            throw Issue.invalidPublicKey
        }

        self.feedURL = feedURL
        self.publicEdKey = publicEdKey
    }
}
