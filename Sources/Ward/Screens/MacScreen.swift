import CareCore
import CareUI
import SwiftUI

struct MacScreen: View {
    @Environment(\.accent) private var accent
    let model: MacModel

    var body: some View {
        ScreenScaffold(title: WardStrings.Nav.mac) {
            Button(WardStrings.Mac.recheck) { Task { await model.refresh() } }
                .buttonStyle(.careSecondary)
                .disabled(model.isLoading)
        } content: {
            if model.checks.isEmpty {
                StatePanel(.loading, title: WardStrings.Mac.loading)
            } else {
                HStack(alignment: .top, spacing: Space.m) {
                    Panel(padding: Space.l + Space.xs) { summary }.frame(width: 240).frame(maxHeight: .infinity)
                    Panel { list }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(WardStrings.Mac.fine).textStyle(.lead, .muted)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(model.okCount)).textStyle(.hero).monospacedDigit()
                    Text(WardStrings.Mac.outOf(model.checks.count)).textStyle(.title, .muted)
                }
            }
            Spacer(minLength: 0)
            // One block per check: the ones that need attention stand taller, so colour is not the only cue.
            HStack(alignment: .bottom, spacing: Space.xs) {
                ForEach(model.checks) { check in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(check.state == .attention ? Palette.attention.color : accent.primary.color)
                        .opacity(check.state == .unknown ? 0.35 : 1)
                        .frame(height: check.state == .attention ? 28 : 12)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(WardStrings.Mac.summary(ok: model.okCount, attention: model.attention.count))
            Text(WardStrings.Mac.readOnly).textStyle(.body, .muted)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Space.xs) {
                ForEach(model.checks) { check in
                    let needsAttention = check.state == .attention
                    NoticeRow(
                        needsAttention ? .attention : .ok, title: WardStrings.Mac.name(check),
                        note: WardStrings.Mac.note(check), isRaised: needsAttention
                    ) {
                        if needsAttention, check.settingsURL != nil {
                            Button(WardStrings.Mac.openSettings) { model.openSettings(for: check) }
                                .buttonStyle(.careLink)
                        }
                    }
                    .opacity(check.state == .unknown ? 0.6 : 1)
                }
            }
        }
    }
}
