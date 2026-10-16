import CareCore
import CareUI
import SwiftUI

struct AppsScreen: View {
    @Bindable var model: AppsModel

    var body: some View {
        ScreenScaffold(title: TidyStrings.Nav.apps) {
            SegmentedPicker(
                options: [
                    (AppsModel.Mode.installed, TidyStrings.Apps.installed(model.footprints.count)),
                    (AppsModel.Mode.orphans, TidyStrings.Apps.orphans(model.orphans?.count ?? 0)),
                ], selection: $model.mode)
        } content: {
            if model.phase != .ready {
                StatePanel(.loading, title: TidyStrings.Apps.measuring)
            } else {
                HStack(alignment: .top, spacing: Space.m) {
                    Panel { list }.frame(width: 308).frame(maxHeight: .infinity)
                    Panel(padding: Space.l + Space.xs) { detail }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: The list on the left

    @ViewBuilder private var list: some View {
        VStack(spacing: Space.xs) {
            if model.mode == .installed {
                SearchField(text: $model.search, prompt: TidyStrings.Apps.search)
            }
            HStack {
                Text(model.mode == .installed ? TidyStrings.Apps.columnApp : TidyStrings.Apps.columnOrphan)
                Spacer()
                Text(model.mode == .installed ? TidyStrings.Apps.columnSize : "")
            }
            .textStyle(.caption, .muted)
            .padding(.horizontal, Space.m)
            .padding(.top, Space.s)

            ScrollView {
                LazyVStack(spacing: Space.xs) {
                    if model.mode == .installed {
                        ForEach(model.visibleFootprints, id: \.app.id) { footprint in
                            row(
                                id: footprint.app.id, name: footprint.app.name, bytes: footprint.bytes,
                                icon: model.icon(for: footprint.app))
                        }
                    } else if let orphans = model.orphans {
                        ForEach(orphans) { group in
                            row(id: group.id, name: group.bundleID, bytes: group.bytes, icon: nil)
                        }
                    }
                }
            }
            .overlay {
                if model.mode == .installed, model.visibleFootprints.isEmpty {
                    StatePanel(.empty, title: TidyStrings.Apps.nothingFound)
                } else if model.mode == .orphans, model.orphans == nil {
                    StatePanel(.loading, title: TidyStrings.Apps.lookingForOrphans)
                } else if model.mode == .orphans, model.orphans?.isEmpty == true {
                    StatePanel(.empty, title: TidyStrings.Apps.noOrphans, message: TidyStrings.Apps.noOrphansNote)
                }
            }
        }
    }

    private func row(id: String, name: String, bytes: Int64, icon: NSImage?) -> some View {
        Button {
            model.select(id)
        } label: {
            HStack(spacing: Space.m) {
                IconTile(image: icon, name: name)
                Text(name).textStyle(.bodyMedium).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(ByteFormat.string(bytes)).textStyle(.body, .muted).monospacedDigit()
            }
            .padding(.horizontal, Space.m)
            .frame(height: 52)
        }
        .buttonStyle(.careRow(selected: model.selectedID == id))
    }

    // MARK: The selection on the right

    @ViewBuilder private var detail: some View {
        if model.mode == .installed, let footprint = model.selectedFootprint {
            let app = footprint.app
            selection(
                title: app.name, icon: model.icon(for: app), subtitle: lastOpened(app), parts: footprint.parts,
                note: model.isRunning(app) ? TidyStrings.Apps.running : app.isApple ? TidyStrings.Apps.appleNote : nil,
                isBlocked: model.isRunning(app))
        } else if model.mode == .orphans, let group = model.selectedOrphan {
            selection(
                title: group.bundleID, icon: nil, subtitle: TidyStrings.Apps.orphanNote, parts: group.parts, note: nil,
                isBlocked: false)
        } else if let report = model.lastReport {
            VStack(spacing: Space.m) {
                StatusIcon(report.problems.isEmpty ? .ok : .attention, label: "")
                Text(TidyStrings.Apps.moved(ByteFormat.string(report.freedBytes))).textStyle(.heading)
                if report.appStayed {
                    Text(TidyStrings.Apps.appStayed).textStyle(.body, .attention)
                        .multilineTextAlignment(.center).frame(maxWidth: 360)
                } else if report.problems.isEmpty == false {
                    Text(TidyStrings.Apps.failed(report.problems.count)).textStyle(.body, .attention)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            StatePanel(.empty, title: TidyStrings.Apps.pick, message: TidyStrings.Apps.pickNote)
        }
    }

    private func lastOpened(_ app: InstalledApp) -> String {
        guard let date = app.lastUsed else { return TidyStrings.Apps.neverOpened }
        return TidyStrings.Apps.lastOpened(AppLocale.relative(date))
    }

    private func selection(
        title: String, icon: NSImage?, subtitle: String, parts: [AppPart], note: String?, isBlocked: Bool
    ) -> some View {
        let ticked = parts.filter { model.unticked.contains($0.id) == false }
        return VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.l) {
                IconTile(image: icon, name: title, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).textStyle(.title).lineLimit(1).truncationMode(.middle)
                    Text(subtitle).textStyle(.body, .muted).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(ByteFormat.string(ticked.reduce(0) { $0 + $1.bytes })).textStyle(.display).monospacedDigit()
                    Text(TidyStrings.Apps.places(ticked.count)).textStyle(.caption, .muted)
                }
            }
            Rectangle().fill(Palette.border.color).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(parts) { part in
                        HStack(spacing: Space.m) {
                            Checkbox(
                                state: model.unticked.contains(part.id) ? .off : .on, label: part.url.lastPathComponent
                            ) {
                                if model.unticked.remove(part.id) == nil { model.unticked.insert(part.id) }
                            }
                            Button {
                                model.reveal(part.url)
                            } label: {
                                HStack(spacing: Space.m) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(TidyStrings.Apps.part(part.kind)).textStyle(.bodyMedium)
                                        Text(part.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                            .textStyle(.caption, .muted).lineLimit(1).truncationMode(.middle)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(ByteFormat.string(part.bytes)).textStyle(.bodyStrong).monospacedDigit()
                                }
                                .padding(.horizontal, Space.s)
                                .frame(minHeight: 52)
                            }
                            .buttonStyle(.careRow)
                            .help(TidyStrings.Apps.showInFinder)
                        }
                    }
                }
            }
            HStack(spacing: Space.l) {
                Text(note ?? TidyStrings.Apps.toTrashNote)
                    .textStyle(.body, note == nil ? .muted : .attention)
                    .frame(maxWidth: 320, alignment: .leading)
                Spacer(minLength: 0)
                Button(TidyStrings.Apps.toTrash) { Task { await model.removeSelection() } }
                    .buttonStyle(.carePrimary)
                    .disabled(isBlocked || ticked.isEmpty || model.isWorking)
            }
        }
    }
}
