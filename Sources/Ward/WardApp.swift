import AppKit
import CareCore
import CareUI
import SwiftUI

@main
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--snapshot"), arguments.count > flag + 1 {
            Snapshots.write(to: URL(fileURLWithPath: arguments[flag + 1]))
            return
        }
        WardApp.main()
    }
}

struct WardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        let model = delegate.model
        Window(WardStrings.appName, id: AppLife.mainWindow) {
            RootView(model: model)
                .frame(minWidth: 860, minHeight: 600)
                .wardLook()
                .dockWhileOpen()
                .task { await model.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: Metric.windowWidth, height: Metric.windowHeight)
        .defaultLaunchBehavior(.suppressed)
        .commands { WardCommands(model: model, updates: delegate.updates) }

        Settings {
            SettingsView(model: model, updates: delegate.updates).wardLook().dockWhileOpen()
        }

        // The menu bar item keeps Ward running when its window is closed, so live protection goes on.
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuBarLabel(systemImage: Self.menuBarSymbol(model.live))
        }
    }
}

extension WardApp {
    /// The shield, half filled while live protection runs, with a warning mark while its engine is down.
    static func menuBarSymbol(_ live: LiveModel) -> String {
        if live.engineIsDown { return "shield.lefthalf.filled.trianglebadge.exclamationmark" }
        return live.isOn ? "shield.lefthalf.filled" : "shield"
    }
}

private struct MenuContent: View {
    let model: AppModel

    var body: some View {
        Text(liveState)
        Text(lastScan)
        Divider()
        Toggle(
            WardStrings.Menu.live,
            isOn: Binding(get: { model.live.isOn }, set: { on in Task { await model.live.setOn(on) } })
        )
        .disabled(model.live.isStarting)
        Button(WardStrings.Menu.quickScan) {
            AppLife.showMainWindow()
            model.startQuickCheck()
        }
        .keyboardShortcut("k")
        .disabled(model.shield.isBusy)
        Button(WardStrings.Menu.open) { AppLife.showMainWindow() }
            .keyboardShortcut("o")
        Divider()
        SettingsLink { Text(WardStrings.Menu.settings) }
            .keyboardShortcut(",")
        Button(WardStrings.Menu.about) {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        }
        Button(WardStrings.Menu.quit) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var liveState: String {
        if model.live.engineIsDown { return WardStrings.Menu.liveDown }
        return model.live.isOn ? WardStrings.Menu.liveOn : WardStrings.Menu.liveOff
    }

    private var lastScan: String {
        guard let date = model.shield.lastScanDate else { return WardStrings.Menu.neverScanned }
        return WardStrings.Menu.lastScan(AppLocale.relative(date), found: model.shield.lastScanFound)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let updates: Updates

    override init() {
        let model = AppModel.live()
        self.model = model
        // A restart would cut a scan or a move to or from quarantine short. Live protection comes
        // back with the new version.
        updates = Updates { model.shield.isBusy || !model.shield.working.isEmpty }
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppLife.recordLaunch()
    }

    /// Live protection comes back here, also when macOS starts Ward at login without a window.
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.refresh() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { AppLife.showMainWindow() }
        return true
    }

    /// The engine is a separate process; it must not outlive the app.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.engine.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// View: one shortcut per section, and a quick scan.
struct WardCommands: Commands {
    let model: AppModel
    let updates: Updates

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if updates.isAvailable {
                Button(WardStrings.Commands.checkForUpdates) { updates.checkNow() }
            }
        }
        CommandGroup(before: .sidebar) {
            ForEach(Array(RootView.entries.enumerated()), id: \.offset) { index, entry in
                Button(entry.title) { model.section = entry.id }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
            Button(WardStrings.Commands.quickScan) { model.startQuickCheck() }
                .keyboardShortcut("k")
                .disabled(model.shield.isBusy)
            Divider()
        }
    }
}

extension View {
    /// Ward's accent on everything below: links, the main button, the chosen sidebar row.
    func wardLook() -> some View {
        environment(\.accent, .ward).tint(Accent.ward.primary.color)
    }
}
