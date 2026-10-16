import CareCore
import CareUI
import SwiftUI

/// Ward → Settings…: live protection, and what Ward needs to work fully.
struct SettingsView: View {
    let model: AppModel
    let updates: Updates
    @State private var hasAccess = FullDiskAccess.isGranted()

    var body: some View {
        Form {
            Section {
                Toggle(
                    WardStrings.Settings.live,
                    isOn: Binding(get: { model.live.isOn }, set: { on in Task { await model.live.setOn(on) } })
                )
                .disabled(model.live.isStarting)
                Text(WardStrings.Settings.liveNote).textStyle(.caption, .muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                requirement(
                    ok: hasAccess, title: WardStrings.Settings.fullDiskAccess,
                    note: WardStrings.Settings.fullDiskAccessNote
                ) {
                    Button(WardStrings.Settings.openPrivacy) { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                }
                requirement(
                    ok: model.engine.isInstalled, title: WardStrings.Settings.engine,
                    note: model.engine.isInstalled
                        ? WardStrings.Settings.engineInstalled : WardStrings.Settings.engineMissing
                ) { EmptyView() }
            }
            UpdatesSection(updates: updates, words: WardStrings.Settings.updates)
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear {
            hasAccess = FullDiskAccess.isGranted()
            model.engine.refresh()
        }
    }

    private func requirement(
        ok: Bool, title: String, note: String, @ViewBuilder action: () -> some View
    ) -> some View {
        HStack(spacing: Space.m) {
            StatusIcon(ok ? .ok : .attention, label: title)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.body)
                Text(note).textStyle(.caption, .muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.m)
            action()
        }
    }
}
