import AppKit
import DayHelmCapture
import DayHelmCore
import SwiftUI

@main
struct DayHelmEntry {
    static func main() {
        if VisionOCRWorker.runIfRequested(arguments: CommandLine.arguments) {
            Foundation.exit(0)
        }

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
            MenuBarPopoverHostView(coordinator: coordinator)
        } label: {
            MenuBarLabelView(pillModel: coordinator.pillModel)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarPopoverHostView: View {
    let coordinator: HybridActivityCoordinator
    @State private var isMounted = false

    var body: some View {
        Group {
            if isMounted {
                MenuBarPopoverView(coordinator: coordinator)
            } else {
                Color.clear.frame(width: 330, height: 1)
            }
        }
        .onAppear {
            isMounted = true
            coordinator.setPopoverVisible(true)
        }
        .onDisappear {
            isMounted = false
            coordinator.setPopoverVisible(false)
        }
    }
}
