import CareCore
import CareUI
import SwiftUI

struct JunkScreen: View {
    let model: JunkModel

    /// How many items of an opened group are listed before "and more".
    private static let listedItems = 40

    var body: some View {
        ScreenScaffold(title: TidyStrings.Nav.junk, scrolls: true) {
            Button(TidyStrings.Junk.journal) { model.isJournalShown = true }
                .buttonStyle(.careBordered)
                .help(TidyStrings.Junk.journalNote)
        } content: {
            HStack(alignment: .top, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    SectionTitle(TidyStrings.Junk.regenerates, note: TidyStrings.Junk.regeneratesNote)
                    GroupedRows {
                        ForEach(model.scan.groups(of: .regenerates)) { group in
                            groupRows(group)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: Space.s) {
                    SectionTitle(TidyStrings.Junk.review, note: TidyStrings.Junk.reviewNote)
                    GroupedRows {
                        ForEach(model.scan.groups(of: .review)) { group in
                            groupRows(group)
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(TidyStrings.Junk.neverOfferedTitle).textStyle(.bodyStrong)
                        Text(TidyStrings.Junk.neverOffered).textStyle(.body, .muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Palette.border.color))
                    .padding(.top, Space.s)
                }
                .frame(maxWidth: .infinity)
            }
        } footer: {
            Text(model.isMeasuring ? TidyStrings.Junk.measuring : TidyStrings.Junk.selected).textStyle(.body, .muted)
            Text(ByteFormat.string(model.headlineBytes)).textStyle(.bodyStrong).monospacedDigit()
            if model.isMeasuring { ProgressView().controlSize(.small) }
            Spacer(minLength: Space.m)
            Button(TidyStrings.Junk.clean) { model.isSheetShown = true }
                .buttonStyle(.carePrimary)
                .disabled(model.phase != .ready || model.plan.isEmpty)
        }
    }

    @ViewBuilder private func groupRows(_ group: JunkGroup) -> some View {
        let isOpen = model.expanded.contains(group.id)
        // A rule held back by an open app says so instead of showing a puzzling zero.
        let subtitle =
            group.items.isEmpty && group.skipped.isEmpty == false
            ? TidyStrings.Junk.closeToClean : TidyStrings.Junk.note(group.id)
        VStack(spacing: 0) {
            HStack(spacing: Space.xs) {
                Checkbox(state: model.checkState(of: group), label: TidyStrings.Junk.name(group.id)) {
                    model.selection.toggle(group)
                }
                .disabled(group.items.isEmpty)
                Button {
                    if isOpen { model.expanded.remove(group.id) } else { model.expanded.insert(group.id) }
                } label: {
                    HStack(spacing: Space.m) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(TidyStrings.Junk.name(group.id)).textStyle(.body).lineLimit(1)
                            Text(subtitle).textStyle(.caption, .muted).lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ByteFormat.string(group.bytes)).textStyle(.body).monospacedDigit()
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right").textStyle(.caption, .muted)
                            .frame(width: 12)
                    }
                    .padding(.vertical, Space.s)
                    .padding(.trailing, Space.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TidyStrings.Junk.expand(TidyStrings.Junk.name(group.id)))
            }
            .padding(.leading, Space.s)

            if isOpen {
                ForEach(group.items.prefix(Self.listedItems)) { item in
                    itemRow(item)
                }
                if group.items.count > Self.listedItems {
                    note(TidyStrings.Junk.more(group.items.count - Self.listedItems))
                }
                if group.items.isEmpty {
                    note(TidyStrings.Junk.empty)
                }
                if group.skipped.isEmpty == false {
                    note(TidyStrings.Junk.skipped(group.skipped.count))
                }
            }
        }
    }

    private func itemRow(_ item: JunkItem) -> some View {
        HStack(spacing: Space.xs) {
            Checkbox(state: model.selection.contains(item) ? .on : .off, label: item.name) {
                model.selection.toggle(item)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).textStyle(.body).lineLimit(1).truncationMode(.middle)
                if let detail = Self.detail(item) {
                    Text(detail).textStyle(.caption, item.isUnavailable ? .attention : .muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(ByteFormat.string(item.bytes)).textStyle(.body, .muted).monospacedDigit()
        }
        .padding(.leading, Space.xl + Space.s)
        .padding(.trailing, Space.xl + Space.xs)
        .frame(minHeight: Metric.hit)
    }

    /// The second line of an item: for simulators, which system and whether it still runs.
    private static func detail(_ item: JunkItem) -> String? {
        guard let runtime = item.runtime else { return nil }
        if item.rule == .simulatorRuntimes {
            guard let used = item.lastUsed else { return TidyStrings.Junk.neverUsed(runtime) }
            return TidyStrings.Junk.lastUsed(runtime, AppLocale.relative(used))
        }
        return item.isUnavailable ? TidyStrings.Junk.unavailable(runtime) : runtime
    }

    private func note(_ text: String) -> some View {
        Text(text).textStyle(.caption, .muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Space.xxl + Space.xxl)
            .padding(.vertical, Space.s)
    }
}
