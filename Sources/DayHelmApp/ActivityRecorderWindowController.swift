import AppKit
import Combine
import DayHelmCapture
import SwiftUI

enum ActivityRecorderSection: String, CaseIterable, Hashable {
    case tasks = "事项与配额"
    case capture = "活动采集"
    case privacyStorage = "隐私与存储"
    case history = "历史会话"

    var isSettingsSection: Bool {
        self != .history
    }
}

@MainActor
final class ActivityRecorderNavigationState: ObservableObject {
    @Published var activeSection: ActivityRecorderSection = .tasks {
        didSet {
            if activeSection.isSettingsSection {
                lastSettingsSection = activeSection
            }
        }
    }
    @Published var lastSettingsSection: ActivityRecorderSection = .tasks
    @Published var selectedSessionId: String?
    @Published var refreshNonce: Int = 0
    @Published var isHistorySidebarVisible: Bool = true
}

@MainActor
final class ActivityRecorderWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let shared = ActivityRecorderWindowController()

    private enum ToolbarItemID {
        static let leftNav = NSToolbarItem.Identifier("dayhelm.recorder.leftNav")
        static let rightStatus = NSToolbarItem.Identifier("dayhelm.recorder.rightStatus")
    }

    private var window: NSWindow?
    private weak var hostedCoordinator: HybridActivityCoordinator?
    private let navState = ActivityRecorderNavigationState()

    private override init() {
        super.init()
    }

    func show(
        coordinator: HybridActivityCoordinator,
        section: ActivityRecorderSection? = nil,
        preferSettingsIfOnHistory: Bool = false,
        selectedSessionId: String? = nil
    ) {
        if let section {
            navState.activeSection = section
        } else if preferSettingsIfOnHistory && !navState.activeSection.isSettingsSection {
            navState.activeSection = navState.lastSettingsSection
        }

        if let selectedSessionId {
            navState.selectedSessionId = selectedSessionId
        }

        coordinator.setRecorderWindowVisible(true)
        coordinator.refreshPermissions()
        coordinator.refreshRecorderCounts()
        if coordinator.recentSessions.isEmpty {
            coordinator.refreshRecorderSessions()
        }

        let targetWindow: NSWindow
        if let existing = window {
            targetWindow = existing
            if hostedCoordinator !== coordinator || existing.contentView == nil {
                existing.contentView = NSHostingView(
                    rootView: ActivityRecorderView(coordinator: coordinator, navState: navState)
                )
                hostedCoordinator = coordinator
                existing.toolbar = makeToolbar()
            }
        } else {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            created.title = "DayHelm"
            created.titleVisibility = .hidden
            created.titlebarAppearsTransparent = true
            created.toolbarStyle = .unified
            created.minSize = NSSize(width: 760, height: 620)
            created.isReleasedWhenClosed = false
            created.delegate = self
            created.contentView = NSHostingView(
                rootView: ActivityRecorderView(coordinator: coordinator, navState: navState)
            )
            created.center()
            window = created
            hostedCoordinator = coordinator
            created.toolbar = makeToolbar()
            targetWindow = created
        }

        NSApp.activate(ignoringOtherApps: true)
        targetWindow.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak targetWindow] in
            guard let targetWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            targetWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "DayHelmRecorderMainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.showsBaselineSeparator = true
        return toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemID.leftNav,
            .flexibleSpace,
            ToolbarItemID.rightStatus
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemID.leftNav,
            .flexibleSpace,
            ToolbarItemID.rightStatus
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let coordinator = hostedCoordinator else { return nil }

        switch itemIdentifier {
        case ToolbarItemID.leftNav:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let hosting = NSHostingView(
                rootView: ActivityRecorderTitlebarNavView(coordinator: coordinator, navState: navState)
            )
            hosting.sizingOptions = .intrinsicContentSize
            item.view = hosting
            item.isBordered = false
            return item

        case ToolbarItemID.rightStatus:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let hosting = NSHostingView(
                rootView: ActivityRecorderTitlebarStatusView(coordinator: coordinator, navState: navState)
            )
            hosting.sizingOptions = .intrinsicContentSize
            item.view = hosting
            item.isBordered = false
            return item

        default:
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Keep window cached with isReleasedWhenClosed = false so reopening preserves frame,
        // while releasing the SwiftUI view hierarchy and decoded thumbnail memory.
        window?.contentView = nil
        hostedCoordinator?.setRecorderWindowVisible(false)
        hostedCoordinator?.releaseHistoryWindowCaches()
    }
}
