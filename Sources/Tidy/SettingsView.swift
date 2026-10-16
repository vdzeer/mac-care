import CareCore
import CareUI
import SwiftUI

/// Tidy → Settings…: starting at login, and the one permission Tidy needs.
struct SettingsView: View {
    let updates: Updates
    @State private var openAtLogin = LoginItem.isOn
    @State private var hasAccess = FullDiskAccess.isGranted()

    var body: some View {
        Form {
            Section {
                Toggle(TidyStrings.Settings.openAtLogin, isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, wanted in
                        if !LoginItem.set(wanted) { openAtLogin = LoginItem.isOn }
                    }
                Text(TidyStrings.Settings.openAtLoginNote).textStyle(.caption, .muted)
            }
            Section {
                HStack(spacing: Space.m) {
                    StatusIcon(hasAccess ? .ok : .attention, label: TidyStrings.Settings.fullDiskAccess)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TidyStrings.Settings.fullDiskAccess).textStyle(.body)
                        Text(TidyStrings.Settings.fullDiskAccessNote).textStyle(.caption, .muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Space.m)
                    Button(TidyStrings.Settings.openPrivacy) { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                }
            }
            UpdatesSection(updates: updates, words: TidyStrings.Settings.updates)
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear { hasAccess = FullDiskAccess.isGranted() }
    }
}
