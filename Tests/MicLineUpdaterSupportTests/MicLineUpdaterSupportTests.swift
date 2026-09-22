import Foundation
import Testing
@testable import MicLineUpdaterSupport

private let validPublicKey = Data(repeating: 0xA5, count: 32).base64EncodedString()

@Test func updateConfigurationRequiresFeedAndPublicKey() {
    #expect(throws: MicLineUpdateConfiguration.Issue.missingFeedURL) {
        try MicLineUpdateConfiguration(infoDictionary: [:])
    }
    #expect(throws: MicLineUpdateConfiguration.Issue.missingPublicKey) {
        try MicLineUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://updates.example.com/appcast.xml",
        ])
    }
    #expect(throws: MicLineUpdateConfiguration.Issue.missingFeedURL) {
        try MicLineUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://:443/appcast.xml",
            "SUPublicEDKey": validPublicKey,
        ])
    }
}

@Test func updateConfigurationRejectsInsecureOrCredentialedFeeds() {
    #expect(throws: MicLineUpdateConfiguration.Issue.insecureFeedURL) {
        try MicLineUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "http://updates.example.com/appcast.xml",
            "SUPublicEDKey": validPublicKey,
        ])
    }
    #expect(throws: MicLineUpdateConfiguration.Issue.embeddedFeedCredentials) {
        try MicLineUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://token@updates.example.com/appcast.xml",
            "SUPublicEDKey": validPublicKey,
        ])
    }
}

@Test func updateConfigurationRequiresAnEd25519SizedPublicKey() {
    #expect(throws: MicLineUpdateConfiguration.Issue.invalidPublicKey) {
        try MicLineUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "SUPublicEDKey": Data(repeating: 0xA5, count: 31).base64EncodedString(),
        ])
    }
}

@Test func updateConfigurationAcceptsSecurePublicMetadata() throws {
    let configuration = try MicLineUpdateConfiguration(infoDictionary: [
        "SUFeedURL": "https://updates.example.com/micline/appcast.xml",
        "SUPublicEDKey": "  \(validPublicKey)\n",
    ])

    #expect(configuration.feedURL.absoluteString == "https://updates.example.com/micline/appcast.xml")
    #expect(configuration.publicEdKey == validPublicKey)
}
