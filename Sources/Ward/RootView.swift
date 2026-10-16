import AppKit
import CareCore
import CareUI
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    static let entries: [NavEntry<WardSection>] = [
        NavEntry(id: .overview, title: WardStrings.Nav.overview, symbol: "square.grid.2x2"),
        NavEntry(id: .scan, title: WardStrings.Nav.scan, symbol: "magnifyingglass"),
        NavEntry(id: .live, title: WardStrings.Nav.live, symbol: "waveform.path.ecg"),
        NavEntry(id: .mac, title: WardStrings.Nav.mac, symbol: "lock"),
        NavEntry(id: .autostart, title: WardStrings.Nav.autostart, symbol: "arrow.triangle.2.circlepath"),
    ]

    var body: some View {
        AppShell(entries: Self.entries, selection: $model.section) {
            EngineCard(engine: model.engine)
        } content: {
            switch model.section {
            case .overview: OverviewScreen(model: model)
            case .scan: ScanScreen(model: model.shield)
            case .live: LiveScreen(model: model.live) { model.section = .scan }
            case .mac: MacScreen(model: model.mac)
            case .autostart:
                AutostartScreen(model: model.autostart)
                    .task { await model.autostart.load() }
                    .onAppear { model.autostart.startNetwork() }
                    .onDisappear { model.autostart.stopNetwork() }
            }
        }
        .sheet(isPresented: $model.showsPermissions) {
            PermissionsSheet(
                title: WardStrings.Permissions.title, message: WardStrings.Permissions.message,
                allowedLabel: WardStrings.Permissions.allowed, laterTitle: WardStrings.Permissions.later,
                doneTitle: WardStrings.Permissions.done, steps: Self.steps(model)
            ) { model.closePermissions() }
            .interactiveDismissDisabled()
        }
        .task { await model.askForPermissionsIfNeeded() }
    }

    static func steps(_ model: AppModel) -> [PermissionStep] {
        [
            PermissionStep(
                id: "fullDiskAccess", title: WardStrings.Permissions.fullDiskAccess,
                note: WardStrings.Permissions.fullDiskAccessNote, actionTitle: WardStrings.Permissions.openSettings,
                isAllowed: { FullDiskAccess.isGranted() },
                action: { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }),
            PermissionStep(
                id: "notifications", title: WardStrings.Permissions.notifications,
                note: WardStrings.Permissions.notificationsNote,
                actionTitle: WardStrings.Permissions.allowNotifications,
                isAllowed: { await AppModel.notificationsAllowed() }, action: { model.askForNotifications() }),
            PermissionStep(
                id: "engine", title: WardStrings.Permissions.engine, note: WardStrings.Permissions.engineNote,
                actionTitle: WardStrings.Permissions.copyCommand, doneLabel: WardStrings.Permissions.installed,
                isAllowed: {
                    model.engine.refresh()
                    return model.engine.isInstalled
                },
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(WardStrings.Permissions.installCommand, forType: .string)
                }),
        ]
    }
}

/// The state of the signature database at the foot of the sidebar.
struct EngineCard: View {
    let engine: EngineHost

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WardStrings.Engine.database).textStyle(.caption, .muted)
            Text(status).textStyle(.bodyStrong).fixedSize(horizontal: false, vertical: true)
            Text(WardStrings.Engine.engine).textStyle(.caption, .muted)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface.color, in: RoundedRectangle(cornerRadius: Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Palette.border.color))
    }

    private var status: String {
        guard engine.isInstalled else { return WardStrings.Engine.notInstalled }
        guard let date = engine.lastCheck else { return WardStrings.Engine.noDatabase }
        return WardStrings.Engine.updated(AppLocale.relative(date))
    }
}
