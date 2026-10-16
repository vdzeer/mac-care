import CareCore
import CareUI
import SwiftUI

struct OverviewScreen: View {
    @Environment(\.accent) private var accent
    let model: AppModel

    private var junk: JunkModel { model.junk }

    var body: some View {
        ScreenScaffold(title: TidyStrings.Nav.overview, scrolls: true) {
            Button {
                Task { await junk.measure() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.careBordered)
            .help(TidyStrings.Overview.recount)
            .accessibilityLabel(TidyStrings.Overview.recount)
            .disabled(junk.isMeasuring || junk.phase == .cleaning)
        } content: {
            VStack(alignment: .leading, spacing: Space.l + Space.xs) {
                hero
                tiles
            }
        }
    }

    private var hero: some View {
        let parts = ByteFormat.parts(junk.headlineBytes)
        let segments = JunkMath.segments(junk.scan, junk.selection)
        let total = max(segments.reduce(0) { $0 + $1.bytes }, 1)
        return HStack(alignment: .center, spacing: Space.xxl + 4) {
            VStack(alignment: .leading, spacing: Space.s) {
                BigFigure(
                    caption: junk.isMeasuring ? TidyStrings.Overview.counting : TidyStrings.Overview.canRemove,
                    value: parts.value, unit: parts.unit)
                Text(TidyStrings.Overview.explanation).textStyle(.body, .muted)
                    .frame(maxWidth: 440, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s) {
                    Button(TidyStrings.Overview.clean) { junk.isSheetShown = true }
                        .buttonStyle(.carePrimary)
                        .disabled(junk.phase != .ready || junk.plan.isEmpty)
                    Button(TidyStrings.Overview.seeList) { model.section = .junk }
                        .buttonStyle(.careSecondary)
                }
                .padding(.top, Space.s)
                if junk.isMeasuring {
                    ProgressView().controlSize(.small)
                } else if junk.phase == .ready {
                    Text(TidyStrings.Overview.countedJustNow).textStyle(.caption, .muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: Space.m + 2) {
                ForEach(segments, id: \.category) { segment in
                    VStack(alignment: .leading, spacing: Space.xs + 2) {
                        HStack {
                            Text(TidyStrings.Category.name(segment.category)).textStyle(.body)
                            Spacer(minLength: Space.m)
                            Text(ByteFormat.string(segment.bytes)).textStyle(.body, .muted).monospacedDigit()
                        }
                        MeterBar(fraction: Double(segment.bytes) / Double(total), tint: accent.primary.color)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Space.xl)
        .background(Palette.surface.color, in: RoundedRectangle(cornerRadius: Radius.l + 2))
        .overlay(RoundedRectangle(cornerRadius: Radius.l + 2).strokeBorder(Palette.border.color))
    }

    private var tiles: some View {
        HStack(spacing: Space.l) {
            SummaryTile(
                title: TidyStrings.Nav.apps, value: TidyStrings.Overview.apps(model.appCount),
                note: TidyStrings.Overview.appsNote
            ) { model.section = .apps }
            SummaryTile(
                title: TidyStrings.Nav.space,
                value: TidyStrings.Overview.space(ByteFormat.string(model.volume?.used ?? 0)),
                note: TidyStrings.Overview.spaceNote
            ) { model.section = .space }
            SummaryTile(
                title: TidyStrings.Nav.speed, value: TidyStrings.Overview.speed(model.autostartCount),
                note: TidyStrings.Overview.speedNote
            ) { model.section = .speed }
        }
    }
}
