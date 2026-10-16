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
        TidyApp.main()
    }
}

struct TidyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        let model = delegate.model
        Window(TidyStrings.appName, id: AppLife.mainWindow) {
            RootView(model: model)
                .frame(minWidth: 860, minHeight: 600)
                .tidyLook()
                .dockWhileOpen()
                .task { model.refreshFacts() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: Metric.windowWidth, height: Metric.windowHeight)
        .defaultLaunchBehavior(.suppressed)
        .commands { TidyCommands(model: model) }

        Settings {
            SettingsView().tidyLook().dockWhileOpen()
        }

        // Tidy lives here: the panel shows the live numbers, and the app keeps running after its
        // window is closed.
        MenuBarExtra {
            MenuBarPanel(model: model).tidyLook()
        } label: {
            MenuBarLabel(systemImage: "circle.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.live()

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppLife.recordLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The menu bar panel shows what can be removed, so the count starts at once.
        model.refreshFacts()
        Task { await model.junk.measure() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { AppLife.showMainWindow() }
        return true
    }
}

/// View: one shortcut per section, and counting again.
struct TidyCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            ForEach(Array(RootView.entries.enumerated()), id: \.offset) { index, entry in
                Button(entry.title) { model.section = entry.id }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Divider()
            Button(TidyStrings.Commands.countAgain) { Task { await model.junk.measure() } }
                .keyboardShortcut("r")
                .disabled(model.junk.isMeasuring || model.junk.phase == .cleaning)
            Divider()
        }
    }
}

extension View {
    /// Tidy's accent on everything below: links, the main button, the chosen sidebar row.
    func tidyLook() -> some View {
        environment(\.accent, .tidy).tint(Accent.tidy.primary.color)
    }
}
