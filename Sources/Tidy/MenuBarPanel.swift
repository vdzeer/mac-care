import AppKit
import CareCore
import CareUI
import SwiftUI

/// The panel that drops down from the menu bar: what can be removed, the live numbers, and the
/// app's menu.
struct MenuBarPanel: View {
    let model: AppModel

    var body: some View {
        let snapshot = model.metrics.snapshot
        let junk = model.junk
        VStack(alignment: .leading, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(TidyStrings.appName).textStyle(.bodyStrong)
                    Spacer()
                    Text(TidyStrings.Menu.updated).textStyle(.caption, .muted)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(ByteFormat.string(junk.headlineBytes)).textStyle(.display, size: 22).monospacedDigit()
                    Text(junk.isMeasuring ? TidyStrings.Overview.counting : TidyStrings.Menu.canRemove)
                        .textStyle(.body, .muted)
                }
                meter(TidyStrings.Speed.memory, SpeedScreen.percent(snapshot.memoryFraction), snapshot.memoryFraction)
                meter(TidyStrings.Speed.cpu, SpeedScreen.percent(snapshot.cpu), snapshot.cpu)
                if let volume = model.metrics.volume ?? model.volume {
                    meter(
                        TidyStrings.Speed.disk, TidyStrings.Speed.free(ByteFormat.string(volume.free)),
                        volume.usedFraction)
                }
                meter(
                    TidyStrings.Speed.network,
                    TidyStrings.Speed.traffic(
                        ByteFormat.rate(snapshot.networkIn), ByteFormat.rate(snapshot.networkOut)),
                    nil)
            }
            .padding(.horizontal, Space.s + 2)
            .padding(.top, Space.s)
            .padding(.bottom, Space.s + 2)

            Divider().padding(.horizontal, Space.s)
            MenuRow(TidyStrings.Menu.cleanUpNow, shortcut: "K") {
                AppLife.showMainWindow()
                model.section = .junk
                junk.isSheetShown = true
            }
            .keyboardShortcut("k")
            .disabled(junk.phase != .ready || junk.plan.isEmpty)
            MenuRow(TidyStrings.Menu.open, shortcut: "O") { AppLife.showMainWindow() }
                .keyboardShortcut("o")
            Menu {
                ForEach(RootView.entries) { entry in
                    Button(entry.title) {
                        model.section = entry.id
                        AppLife.showMainWindow()
                    }
                }
            } label: {
                HStack {
                    Text(TidyStrings.Menu.goTo)
                    Spacer(minLength: Space.m)
                    Image(systemName: "chevron.right").opacity(0.6)
                }
                .textStyle(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.button)
            .buttonStyle(MenuRowStyle())
            Divider().padding(.horizontal, Space.s)
            SettingsLink {
                MenuRowLabel(title: TidyStrings.Menu.settings, shortcut: ",")
            }
            .buttonStyle(MenuRowStyle())
            MenuRow(TidyStrings.Menu.about) {
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            MenuRow(TidyStrings.Menu.quit, shortcut: "Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(Space.xs + 2)
        .frame(width: 290)
        .onAppear { model.metrics.start() }
        .onDisappear { model.metrics.stop() }
    }

    private func meter(_ title: String, _ value: String, _ fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).textStyle(.body, .muted)
                Spacer(minLength: Space.s)
                Text(value).textStyle(.body).monospacedDigit().lineLimit(1)
            }
            if let fraction {
                MeterBar(fraction: fraction, tint: Palette.onSurface.color).frame(height: 4).clipped()
            }
        }
    }
}

/// A row of the panel that looks and behaves like a menu item.
private struct MenuRow: View {
    let title: String
    let shortcut: String?
    let action: () -> Void

    init(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) { MenuRowLabel(title: title, shortcut: shortcut) }
            .buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowLabel: View {
    let title: String
    let shortcut: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: Space.m)
            if let shortcut { Text("⌘" + shortcut).opacity(0.6) }
        }
    }
}

/// The highlight of a menu: the accent fill under the pointer, white text on it.
private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        @Environment(\.accent) private var accent
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            let lit = isHovered && isEnabled
            configuration.label
                .textStyle(.body, lit ? .onAccent : .primary)
                .padding(.horizontal, Space.s + 2)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .background(lit ? accent.primary.color : .clear, in: RoundedRectangle(cornerRadius: 5))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
        }
    }
}
