import Combine
import Foundation
import MicLineUpdaterSupport
import Sparkle

@MainActor
public final class MicLineUpdater: ObservableObject {
    public typealias ConfigurationIssue = MicLineUpdateConfiguration.Issue

    public enum Availability: Equatable, Sendable {
        case unavailable(ConfigurationIssue)
        case ready
    }

    @Published public private(set) var canCheckForUpdates = false
    public let availability: Availability

    private let controller: SPUStandardUpdaterController?

    public init(bundle: Bundle = .main) {
        do {
            _ = try MicLineUpdateConfiguration(infoDictionary: bundle.infoDictionary ?? [:])
        } catch let issue as MicLineUpdateConfiguration.Issue {
            availability = .unavailable(issue)
            controller = nil
            return
        } catch {
            availability = .unavailable(.invalidPublicKey)
            controller = nil
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        availability = .ready
        controller.updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        controller.startUpdater()
    }

    public var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            guard let updater = controller?.updater else { return }
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    public var automaticallyDownloadsUpdates: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            guard let updater = controller?.updater else { return }
            objectWillChange.send()
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    public func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller?.updater.checkForUpdates()
    }
}
