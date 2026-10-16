import CareCore
import CareUI
import SwiftUI

struct OverviewScreen: View {
    let model: AppModel

    /// How many attention rows the overview lists before "and more".
    private static let shownRows = 4

    var body: some View {
        ScreenScaffold(title: WardStrings.Nav.overview, scrolls: true) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: Space.l + Space.xs) {
                hero
                attention
                tiles
            }
        }
    }

    private var hero: some View {
        let count = model.attentionCount
        return HStack(alignment: .center, spacing: Space.l + Space.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(count > 0 ? Palette.attentionSurface.color : Palette.surfaceRaised.color)
                Image(systemName: count > 0 ? "exclamationmark.shield" : "checkmark.shield")
                    .textStyle(.lead, size: 28, count > 0 ? .attention : .success)
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(count > 0 ? WardStrings.Overview.attention(count) : WardStrings.Overview.allGood)
                    .textStyle(.display, size: 26)
                Text(lastScan).textStyle(.body, .muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Space.s) {
                Button(WardStrings.Overview.quickScan) { model.startQuickCheck() }
                    .buttonStyle(.carePrimary)
                Button(WardStrings.Overview.fullScan) {
                    model.section = .scan
                    model.shield.start(.full)
                }
                .buttonStyle(.careSecondary)
            }
            .disabled(model.shield.isBusy)
        }
        .padding(Space.xl)
        .background(Palette.surface.color, in: RoundedRectangle(cornerRadius: Radius.l + 2))
        .overlay(RoundedRectangle(cornerRadius: Radius.l + 2).strokeBorder(Palette.border.color))
    }

    private var lastScan: String {
        guard let date = model.shield.lastScanDate else { return WardStrings.Overview.neverScanned }
        let found = model.shield.lastScanFound
        return WardStrings.Overview.lastScan(
            AppLocale.relative(date),
            found == 0 ? WardStrings.Overview.nothingFound : WardStrings.Overview.found(found))
    }

    private struct Row: Identifiable {
        let id: String
        let title: String
        let note: String
        let action: String
        let target: WardSection
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if model.shield.findings.isEmpty == false {
            rows.append(
                Row(
                    id: "findings", title: WardStrings.Overview.findings(model.shield.findings.count),
                    note: WardStrings.Overview.findingsNote, action: WardStrings.Overview.review, target: .scan))
        }
        rows += model.mac.attention.map {
            Row(
                id: $0.id.rawValue, title: WardStrings.Mac.name($0), note: WardStrings.Mac.note($0),
                action: WardStrings.Overview.fix, target: .mac)
        }
        if model.autostart.newIDs.isEmpty == false {
            rows.append(
                Row(
                    id: "autostart", title: WardStrings.Overview.newAutostart(model.autostart.newIDs.count),
                    note: WardStrings.Overview.newAutostartNote, action: WardStrings.Overview.review,
                    target: .autostart))
        }
        return rows
    }

    @ViewBuilder private var attention: some View {
        let rows = rows
        if rows.isEmpty == false {
            VStack(alignment: .leading, spacing: Space.s) {
                SectionTitle(WardStrings.Overview.needsAttention)
                GroupedRows {
                    ForEach(rows.prefix(Self.shownRows)) { row in
                        HStack(spacing: Space.m) {
                            Circle().fill(Palette.attention.color).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title).textStyle(.bodyMedium)
                                Text(row.note).textStyle(.body, .muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button(row.action) {
                                if row.target == .mac,
                                    let check = model.mac.attention.first(where: {
                                        $0.id.rawValue == row.id
                                    }), check.settingsURL != nil
                                {
                                    model.mac.openSettings(for: check)
                                } else {
                                    model.section = row.target
                                }
                            }
                            .buttonStyle(.careBordered)
                        }
                        .padding(.horizontal, Space.m + 2)
                        .padding(.vertical, Space.m)
                    }
                }
                if rows.count > Self.shownRows {
                    Button(WardStrings.Overview.more(rows.count - Self.shownRows)) { model.section = .mac }
                        .buttonStyle(.careLinkInline)
                        .padding(.leading, Space.xs)
                }
            }
        }
    }

    private var tiles: some View {
        HStack(spacing: Space.l) {
            SummaryTile(
                title: WardStrings.Nav.live,
                value: model.live.isOn ? WardStrings.Overview.liveOn : WardStrings.Overview.liveOff,
                valueTone: model.live.isOn ? .success : .attention,
                note: model.live.isOn ? WardStrings.Overview.liveNote : WardStrings.Overview.liveOffNote
            ) { model.section = .live }
            SummaryTile(
                title: WardStrings.Nav.mac,
                value: WardStrings.Overview.macFine(model.mac.okCount, of: model.mac.checks.count),
                note: WardStrings.Overview.macNote
            ) { model.section = .mac }
            SummaryTile(
                title: WardStrings.Overview.quarantine,
                value: model.shield.entries.isEmpty
                    ? WardStrings.Overview.quarantineEmpty
                    : WardStrings.Overview.quarantined(model.shield.entries.count),
                note: WardStrings.Overview.quarantineNote
            ) {
                model.shield.tab = .quarantine
                model.section = .scan
            }
        }
    }
}
