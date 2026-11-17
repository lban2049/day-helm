import AppKit
import DayHelmCapture
import DayHelmCore
import SwiftUI

@main
struct DayHelmEntry {
    static func main() {
        if let result = DayHelmCLI.run(arguments: CommandLine.arguments) {
            if !result.stdout.isEmpty {
                FileHandle.standardOutput.write(Data(result.stdout.utf8))
            }
            if !result.stderr.isEmpty {
                FileHandle.standardError.write(Data(result.stderr.utf8))
            }
            Foundation.exit(result.exitCode)
        }

        DayHelmMenuBarApp.main()
    }
}

final class DayHelmAppDelegate: NSObject, NSApplicationDelegate {
    private var hudController: SupervisorHUDWindowController?
    weak var coordinator: HybridActivityCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let coordinator {
            hudController = SupervisorHUDWindowController(coordinator: coordinator)
            coordinator.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}

struct DayHelmMenuBarApp: App {
    @NSApplicationDelegateAdaptor(DayHelmAppDelegate.self) private var appDelegate
    @StateObject private var coordinator: HybridActivityCoordinator

    init() {
        let isDemo = CommandLine.arguments.contains("--synthetic-demo")
        let coord = isDemo
            ? HybridActivityCoordinator.makeSyntheticDemo()
            : HybridActivityCoordinator.makeLive()
        _coordinator = StateObject(wrappedValue: coord)
        appDelegate.coordinator = coord
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(coordinator: coordinator)
        } label: {
            MenuBarLabelView(coordinator: coordinator)
        }
        .menuBarExtraStyle(.window)
    }
}
