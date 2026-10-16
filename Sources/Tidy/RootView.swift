import AppKit
import CareCore
import CareUI
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    static let entries: [NavEntry<TidySection>] = [
        NavEntry(id: .overview, title: TidyStrings.Nav.overview, symbol: "square.grid.2x2"),
        NavEntry(id: .junk, title: TidyStrings.Nav.junk, symbol: "trash"),
        NavEntry(id: .apps, title: TidyStrings.Nav.apps, symbol: "app.badge"),
        NavEntry(id: .space, title: TidyStrings.Nav.space, symbol: "chart.pie"),
        NavEntry(id: .speed, title: TidyStrings.Nav.speed, symbol: "bolt"),
    ]

    var body: some View {
        @Bindable var junk = model.junk
        AppShell(entries: Self.entries, selection: $model.section) {
            DiskCard(volume: model.volume)
        } content: {
            switch model.section {
            case .overview: OverviewScreen(model: model)
            case .junk: JunkScreen(model: model.junk)
            case .apps: AppsScreen(model: model.apps).task { await model.apps.load() }
            case .space:
                SpaceScreen(model: model.space, junk: model.junk) { model.section = .junk }
                    .task { await model.space.loadMap() }
            case .speed:
                SpeedScreen(model: model.speed, metrics: model.metrics)
                    .task { await model.speed.load() }
                    .onAppear { model.metrics.start() }
                    .onDisappear { model.metrics.stop() }
            }
        }
        .sheet(isPresented: $junk.isSheetShown) {
            CleanSheet(model: model.junk).interactiveDismissDisabled(model.junk.phase == .cleaning)
        }
        .sheet(isPresented: $junk.isJournalShown) {
            JournalSheet(model: model.junk)
        }
        .sheet(isPresented: $model.showsPermissions) {
            PermissionsSheet(
                title: TidyStrings.Permissions.title, message: TidyStrings.Permissions.message,
                allowedLabel: TidyStrings.Permissions.allowed, laterTitle: TidyStrings.Permissions.later,
                doneTitle: TidyStrings.Permissions.done,
                steps: [
                    PermissionStep(
                        id: "fullDiskAccess", title: TidyStrings.Permissions.fullDiskAccess,
                        note: TidyStrings.Permissions.fullDiskAccessNote,
                        actionTitle: TidyStrings.Permissions.openSettings,
                        isAllowed: { FullDiskAccess.isGranted() },
                        action: { NSWorkspace.shared.open(FullDiskAccess.settingsURL) })
                ]
            ) { model.closePermissions() }
            .interactiveDismissDisabled()
        }
        .task { model.askForPermissionsIfNeeded() }
    }
}

/// The startup disk at the foot of the sidebar.
struct DiskCard: View {
    let volume: VolumeInfo?

    var body: some View {
        if let volume {
            VStack(alignment: .leading, spacing: Space.xs + 2) {
                Text(volume.name).textStyle(.caption, .muted)
                Text(TidyStrings.Disk.free(ByteFormat.string(volume.free), of: ByteFormat.string(volume.total)))
                    .textStyle(.bodyStrong).fixedSize(horizontal: false, vertical: true)
                MeterBar(fraction: volume.usedFraction, tint: Palette.onSurface.color)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface.color, in: RoundedRectangle(cornerRadius: Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Palette.border.color))
        }
    }
}
