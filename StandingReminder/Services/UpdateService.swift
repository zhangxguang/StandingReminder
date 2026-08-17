import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateService: ObservableObject {
    private let updaterController: SPUStandardUpdaterController?

    @Published private(set) var canCheckForUpdates = false

    private var canCheckForUpdatesObservation: AnyCancellable?

    init() {
        guard !Self.isRunningTests else {
            updaterController = nil
            return
        }

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = updaterController

        canCheckForUpdatesObservation = updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["STANDING_REMINDER_DISABLE_UPDATES"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    var versionDescription: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "未知"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "未知"
        return "\(version)（\(build)）"
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
