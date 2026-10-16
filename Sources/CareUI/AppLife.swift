import AppKit
import ServiceManagement
import SwiftUI

/// How both apps live: in the menu bar all the time, and in the Dock with a full app menu only
/// while one of their windows is open.
public enum AppLife {
    /// The id of the main window scene in both apps.
    public static let mainWindow = "main"
    /// Posted when the last window closes and the app goes back to the menu bar.
    public static let allWindowsClosed = Notification.Name("AppLife.allWindowsClosed")

    public static var hasOpenWindows: Bool { openWindows > 0 }

    private static var openWindows = 0
    private static var launchedAsLoginItem = false
    private static var openMainWindow: OpenWindowAction?
    private static var hasStarted = false

    /// Call from `applicationWillFinishLaunching`, while the launch event is still current.
    public static func recordLaunch() {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return }
        launchedAsLoginItem =
            event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Brings the main window up from anywhere: the menu bar, a reopen from Finder or the Dock.
    public static func showMainWindow() {
        openMainWindow?(id: mainWindow)
        NSApp.activate()
    }

    fileprivate static func started(with open: OpenWindowAction) {
        openMainWindow = open
        guard !hasStarted else { return }
        hasStarted = true
        // Started by the user: show the window. Started at login: stay in the menu bar.
        if !launchedAsLoginItem { open(id: mainWindow) }
    }

    fileprivate static func windowAppeared() {
        openWindows += 1
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
    }

    fileprivate static func windowDisappeared() {
        openWindows = max(openWindows - 1, 0)
        if openWindows == 0 {
            NSApp.setActivationPolicy(.accessory)
            NotificationCenter.default.post(name: allWindowsClosed, object: nil)
        }
    }
}

/// The menu bar picture. It is on screen from the first moment, so it also opens the main
/// window when the app starts, unless macOS started it at login.
public struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    let systemImage: String

    public init(systemImage: String) {
        self.systemImage = systemImage
    }

    public var body: some View {
        Image(systemName: systemImage)
            .onAppear { AppLife.started(with: openWindow) }
    }
}

extension View {
    /// Puts the app in the Dock, with its app menu, while this window is open.
    public func dockWhileOpen() -> some View {
        onAppear { AppLife.windowAppeared() }
            .onDisappear { AppLife.windowDisappeared() }
    }
}

/// Starting the app when you log in. It shows up in System Settings → General → Login Items.
public enum LoginItem {
    public static var isOn: Bool { SMAppService.mainApp.status == .enabled }

    @discardableResult
    public static func set(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}
