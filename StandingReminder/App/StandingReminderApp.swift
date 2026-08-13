import SwiftData
import SwiftUI

@main
@MainActor
struct StandingReminderApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var controller: SessionController
    @StateObject private var reminderService: SittingReminderService

    init() {
        let storage = Self.makeModelContainer()
        modelContainer = storage.container

        let reminder = SittingReminderService()
        _reminderService = StateObject(wrappedValue: reminder)
        _controller = StateObject(
            wrappedValue: SessionController(
                context: storage.container.mainContext,
                reminderService: reminder,
                initialStorageError: storage.errorMessage
            )
        )
    }

    private static func makeModelContainer() -> (
        container: ModelContainer,
        errorMessage: String?
    ) {
        do {
            let dataDirectory = try dataDirectory()
            try FileManager.default.createDirectory(
                at: dataDirectory,
                withIntermediateDirectories: true
            )
            let configuration = ModelConfiguration(
                url: dataDirectory.appending(path: "StandingReminder.store")
            )
            let container = try ModelContainer(
                for: WorkSession.self,
                configurations: configuration
            )
            return (container, nil)
        } catch {
            let persistentError = error
            do {
                let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
                let container = try ModelContainer(
                    for: WorkSession.self,
                    configurations: fallback
                )
                let message = "无法打开本地数据库，原有数据未被修改。请重新启动应用后重试：\(persistentError.localizedDescription)"
                return (container, message)
            } catch {
                fatalError("应用无法启动：本地数据库和安全备用容器均不可用（\(error.localizedDescription)）")
            }
        }
    }

    private static func dataDirectory() throws -> URL {
        #if DEBUG
        if let testingPath = ProcessInfo.processInfo.environment["STANDING_REMINDER_TEST_DATA_DIRECTORY"],
           !testingPath.isEmpty {
            return URL(fileURLWithPath: testingPath, isDirectory: true)
        }
        #endif

        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport.appending(
            path: "StandingReminder",
            directoryHint: .isDirectory
        )
    }

    var body: some Scene {
        WindowGroup("StandingReminder", id: "main") {
            RootView()
                .environmentObject(controller)
                .environmentObject(reminderService)
                .modelContainer(modelContainer)
        }
        .defaultSize(width: 760, height: 620)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(controller)
                .environmentObject(reminderService)
                .modelContainer(modelContainer)
        } label: {
            MenuBarLabel()
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.menu)
    }
}
