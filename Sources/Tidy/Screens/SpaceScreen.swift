import AppKit
import CareCore
import CareUI
import SwiftUI

struct SpaceScreen: View {
    @Environment(\.accent) private var accent
    @Bindable var model: SpaceModel
    /// The junk measurement tells how much of each system place can be removed.
    let junk: JunkModel
    let openJunk: () -> Void

    /// How many boxes the map draws before the rest become "other".
    private static let shownBoxes = 11

    var body: some View {
        ScreenScaffold(title: TidyStrings.Nav.space) {
            SegmentedPicker(
                options: [
                    (SpaceModel.Tab.map, TidyStrings.Space.map), (SpaceModel.Tab.large, TidyStrings.Space.large),
                    (SpaceModel.Tab.duplicates, TidyStrings.Space.duplicates),
                    (SpaceModel.Tab.system, TidyStrings.System.tab),
                ], selection: $model.tab)
        } content: {
            VStack(spacing: Space.m) {
                if model.hasFullDiskAccess == false {
                    NoticeRow(.attention, title: TidyStrings.Space.accessTitle, note: TidyStrings.Space.accessNote) {
                        Button(TidyStrings.Space.openSettings) { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                            .buttonStyle(.careLink)
                    }
                }
                switch model.tab {
                case .map: map
                case .large: files
                case .duplicates: copies
                case .system: system
                }
            }
        }
    }

    // MARK: The map

    private var map: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Panel(padding: Space.l) {
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(spacing: Space.m) {
                        if model.trail.isEmpty == false {
                            Button(TidyStrings.Space.back) { Task { await model.back() } }.buttonStyle(.careSecondary)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                            Text(model.isAtHome ? TidyStrings.Space.home : model.folder.lastPathComponent)
                                .textStyle(.heading).lineLimit(1).truncationMode(.middle)
                            Text(ByteFormat.string(model.folderBytes)).textStyle(.body, .muted).monospacedDigit()
                        }
                        Spacer(minLength: 0)
                        Button(TidyStrings.Space.pickFolder) { Task { await model.pickFolder() } }
                            .buttonStyle(.careSecondary)
                    }
                    if model.isLoadingMap {
                        StatePanel(.loading, title: TidyStrings.Space.measuring)
                    } else if model.nodes.isEmpty {
                        StatePanel(.empty, title: TidyStrings.Space.empty)
                    } else {
                        GeometryReader { proxy in
                            boxes(in: proxy.size)
                        }
                        Text(TidyStrings.Space.hint).textStyle(.caption, .muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Panel {
                VStack(spacing: Space.xs) {
                    PanelHeader(TidyStrings.Space.biggestHere)
                    ScrollView {
                        LazyVStack(spacing: Space.xs) {
                            ForEach(model.nodes.prefix(40)) { node in
                                Button {
                                    Task { await model.open(node) }
                                } label: {
                                    HStack(spacing: Space.m) {
                                        Image(systemName: node.isFolder ? "folder" : "doc").textStyle(.body, .muted)
                                            .frame(width: 20)
                                        Text(node.name).textStyle(.bodyMedium).lineLimit(1).truncationMode(.middle)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(ByteFormat.string(node.bytes)).textStyle(.body, .muted).monospacedDigit()
                                    }
                                    .padding(.horizontal, Space.m)
                                    .frame(height: Metric.hit)
                                }
                                .buttonStyle(.careRow)
                            }
                        }
                    }
                }
            }
            .frame(width: 288)
            .frame(maxHeight: .infinity)
        }
    }

    private func boxes(in size: CGSize) -> some View {
        let shown = Array(model.nodes.prefix(Self.shownBoxes))
        let rest = model.nodes.dropFirst(Self.shownBoxes).reduce(Int64(0)) { $0 + $1.bytes }
        let weights = shown.map { Double($0.bytes) } + (rest > 0 ? [Double(rest)] : [])
        let rects = Treemap.layout(weights, in: CGRect(origin: .zero, size: size))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(rects.enumerated()), id: \.offset) { index, rect in
                let node = index < shown.count ? shown[index] : nil
                Button {
                    if let node { Task { await model.open(node) } }
                } label: {
                    box(
                        name: node?.name ?? TidyStrings.Space.other, bytes: node?.bytes ?? rest, rank: index,
                        size: rect.size)
                }
                .buttonStyle(.plain)
                .disabled(node == nil)
                .frame(width: max(rect.width - 4, 0), height: max(rect.height - 4, 0))
                .offset(x: rect.minX + 2, y: rect.minY + 2)
            }
        }
    }

    private func box(name: String, bytes: Int64, rank: Int, size: CGSize) -> some View {
        // The biggest box carries the accent; the others step down in lightness.
        let fills = [accent.primary.color, Palette.borderStrong.color, Palette.border.color]
        let fill = rank < fills.count ? fills[rank] : Palette.surfaceRaised.color
        let hasRoom = size.width > 76 && size.height > 44
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Radius.m).fill(fill)
            if hasRoom {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ByteFormat.string(bytes)).textStyle(.bodyStrong, rank == 0 ? .onAccent : .primary)
                        .monospacedDigit()
                    Text(name).textStyle(.caption, rank == 0 ? .onAccent : .muted).lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(10)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.m))
        .help(name)
    }

    // MARK: System data

    private struct SystemRow: Identifiable {
        let id: String
        let title: String
        let note: String
        let bytes: Int64
        let cleanable: Int64
        let url: URL?
        let isManaged: Bool
    }

    private func systemRows(_ places: [SystemDataPlace], in group: SystemDataPlace.Group) -> [SystemRow] {
        var rows: [SystemRow] = []
        // Simulator systems live in a part of the disk only the system can read, so their sizes come from Xcode.
        if group == .developer, let runtimes = junk.scan.groups.first(where: { $0.id == .simulatorRuntimes }),
            runtimes.items.isEmpty == false
        {
            rows.append(
                SystemRow(
                    id: "runtimes", title: TidyStrings.System.runtimes,
                    note: TidyStrings.System.runtimesNote(runtimes.items.count), bytes: runtimes.bytes,
                    cleanable: runtimes.bytes, url: nil, isManaged: false))
        }
        rows += places.filter { $0.group == group }.map { place in
            let path = place.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            return SystemRow(
                id: place.id, title: TidyStrings.System.title(place),
                note: "\(path) · \(TidyStrings.System.note(place.known))", bytes: place.bytes,
                cleanable: SystemDataScanner.cleanable(in: place, junk.scan), url: place.url,
                isManaged: place.isManaged)
        }
        return rows.sorted { $0.bytes > $1.bytes }
    }

    @ViewBuilder private var system: some View {
        Panel {
            if let places = model.systemPlaces {
                let groups = SystemDataPlace.Group.allCases.map { ($0, systemRows(places, in: $0)) }
                let total = groups.flatMap(\.1).reduce(Int64(0)) { $0 + $1.bytes }
                let cleanable = groups.flatMap(\.1).reduce(Int64(0)) { $0 + $1.cleanable }
                VStack(spacing: Space.xs) {
                    HStack(spacing: Space.m) {
                        Text(TidyStrings.System.summary(ByteFormat.string(total), ByteFormat.string(cleanable)))
                            .textStyle(.bodyStrong).monospacedDigit()
                        Spacer(minLength: 0)
                        Button(TidyStrings.System.recount) { model.scanSystem() }.buttonStyle(.careSecondary)
                    }
                    .padding(.horizontal, Space.m)
                    ScrollView {
                        LazyVStack(spacing: Space.xs) {
                            ForEach(groups, id: \.0) { group, rows in
                                if rows.isEmpty == false {
                                    Text(TidyStrings.System.group(group)).textStyle(.caption, .muted)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, Space.m)
                                        .padding(.top, Space.m)
                                    ForEach(rows) { row in
                                        systemRow(row)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                StatePanel(.loading, title: TidyStrings.System.measuring, message: TidyStrings.System.measuringNote)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func systemRow(_ row: SystemRow) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title).textStyle(.bodyMedium).lineLimit(1).truncationMode(.middle)
                Text(row.note).textStyle(.caption, .muted).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.cleanable > 0 {
                Text(TidyStrings.System.cleanable(ByteFormat.string(row.cleanable))).textStyle(.caption, .accent)
                    .monospacedDigit().lineLimit(1)
            }
            Text(ByteFormat.string(row.bytes)).textStyle(.bodyStrong).monospacedDigit()
                .frame(width: 84, alignment: .trailing)
            Group {
                if row.cleanable > 0 {
                    Button(TidyStrings.System.toJunk, action: openJunk).buttonStyle(.careLink)
                } else if let url = row.url, row.isManaged == false {
                    Button(TidyStrings.System.showInFinder) { model.reveal(url) }.buttonStyle(.careLink)
                }
            }
            .frame(width: 168, alignment: .trailing)
        }
        .padding(.leading, Space.m)
        .frame(minHeight: 52)
        .opacity(row.isManaged ? 0.65 : 1)
    }

    // MARK: Big files and copies

    @ViewBuilder private var files: some View {
        Panel {
            if let large = model.largeFiles {
                if large.isEmpty {
                    StatePanel(.empty, title: TidyStrings.Space.noLarge, message: TidyStrings.Space.noLargeNote)
                } else {
                    VStack(spacing: Space.xs) {
                        ScrollView {
                            LazyVStack(spacing: Space.xs) {
                                ForEach(large) { file in
                                    fileRow(
                                        url: file.url, bytes: file.bytes,
                                        note: TidyStrings.Space.opened(
                                            AppLocale.relative(file.lastOpened)))
                                }
                            }
                        }
                        actionBar
                    }
                }
            } else {
                StatePanel(.loading, title: TidyStrings.Space.lookingForLarge, message: TidyStrings.Space.scope)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var copies: some View {
        Panel {
            if let groups = model.duplicates {
                if groups.isEmpty {
                    StatePanel(
                        .empty, title: TidyStrings.Space.noDuplicates, message: TidyStrings.Space.noDuplicatesNote)
                } else {
                    VStack(spacing: Space.xs) {
                        ScrollView {
                            LazyVStack(spacing: Space.xs) {
                                ForEach(groups.prefix(200)) { group in
                                    HStack(spacing: Space.m) {
                                        Text(group.files.first?.lastPathComponent ?? "").textStyle(.bodyStrong)
                                            .lineLimit(1).truncationMode(.middle)
                                        Text(TidyStrings.Space.copies(group.files.count)).textStyle(.body, .muted)
                                        Spacer(minLength: 0)
                                        Text(TidyStrings.Space.wasted(ByteFormat.string(group.wasted)))
                                            .textStyle(.body, .muted).monospacedDigit()
                                        Button(TidyStrings.Space.keepOne) { model.keepOne(of: group) }
                                            .buttonStyle(.careLinkInline)
                                    }
                                    .padding(.horizontal, Space.m)
                                    .frame(minHeight: Metric.hit)
                                    .background(
                                        Palette.surfaceRaised.color, in: RoundedRectangle(cornerRadius: Radius.m))
                                    ForEach(group.files, id: \.path) { url in
                                        fileRow(url: url, bytes: group.bytes, note: nil)
                                    }
                                }
                            }
                        }
                        actionBar
                    }
                }
            } else {
                StatePanel(
                    .loading, title: TidyStrings.Space.lookingForDuplicates,
                    message: TidyStrings.Space.lookingForDuplicatesNote + " " + TidyStrings.Space.scope)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileRow(url: URL, bytes: Int64, note: String?) -> some View {
        let folder = url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return HStack(spacing: Space.m) {
            Checkbox(state: model.ticked.contains(url.path) ? .on : .off, label: url.lastPathComponent) {
                model.toggle(url.path)
            }
            Button {
                model.reveal(url)
            } label: {
                HStack(spacing: Space.m) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(url.lastPathComponent).textStyle(.bodyMedium).lineLimit(1).truncationMode(.middle)
                        Text(note.map { "\(folder) · \($0)" } ?? folder).textStyle(.caption, .muted).lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(ByteFormat.string(bytes)).textStyle(.bodyStrong).monospacedDigit()
                }
                .padding(.horizontal, Space.s)
                .frame(minHeight: 52)
            }
            .buttonStyle(.careRow)
        }
        .padding(.leading, Space.s)
    }

    private var actionBar: some View {
        let count = model.ticked.count
        return HStack(spacing: Space.l) {
            if let report = model.lastReport, count == 0 {
                Text(
                    report.problems.isEmpty
                        ? TidyStrings.Space.moved(ByteFormat.string(report.freedBytes))
                        : TidyStrings.Space.failed(report.problems.count)
                )
                .textStyle(.body, report.problems.isEmpty ? .muted : .attention)
            } else {
                Text(
                    count == 0
                        ? TidyStrings.Space.nothingChosen
                        : TidyStrings.Space.chosen(count, ByteFormat.string(model.tickedBytes))
                )
                .textStyle(.body, .muted).monospacedDigit()
            }
            Spacer(minLength: 0)
            Button(TidyStrings.Space.toTrash) { Task { await model.trashTicked() } }
                .buttonStyle(.carePrimary)
                .disabled(count == 0 || model.isWorking)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .background(Palette.surfaceRaised.color, in: RoundedRectangle(cornerRadius: Radius.m))
    }
}
