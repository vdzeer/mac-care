import AppKit
import CareCore
import CareUI
import SwiftUI

struct ScanScreen: View {
    @Bindable var model: ShieldModel

    var body: some View {
        ScreenScaffold(title: WardStrings.Nav.scan, scrolls: true) {
            SegmentedPicker(
                options: [
                    (ShieldModel.Tab.result, WardStrings.Scan.result),
                    (ShieldModel.Tab.quarantine, WardStrings.Scan.quarantine(model.entries.count)),
                ], selection: $model.tab)
        } content: {
            VStack(alignment: .leading, spacing: Space.l + Space.xs) {
                if model.hasFullDiskAccess == false {
                    NoticeRow(.attention, title: WardStrings.Scan.accessTitle, note: WardStrings.Scan.accessNote) {
                        Button(WardStrings.Scan.openSettings) { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                            .buttonStyle(.careLink)
                    }
                }
                modes
                Group {
                    if model.tab == .quarantine { quarantine } else { result }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private var modes: some View {
        HStack(spacing: Space.m) {
            ChoiceCard(
                title: WardStrings.Scan.quick, note: WardStrings.Scan.quickNote, hint: WardStrings.Scan.quickTime,
                isMarked: true
            ) { model.start(.quick) }
            ChoiceCard(
                title: WardStrings.Scan.full, note: WardStrings.Scan.fullNote, hint: WardStrings.Scan.fullTime
            ) { model.start(.full) }
            ChoiceCard(
                title: WardStrings.Scan.custom, note: WardStrings.Scan.customNote,
                hint: WardStrings.Scan.customTime, isDashed: true
            ) { pick() }
            .dropDestination(for: URL.self) { urls, _ in
                guard urls.isEmpty == false, model.isBusy == false else { return false }
                model.start(.custom(urls))
                return true
            }
        }
        .disabled(model.isBusy)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK, panel.urls.isEmpty == false { model.start(.custom(panel.urls)) }
    }

    // MARK: The result

    @ViewBuilder private var result: some View {
        switch model.phase {
        case .idle where model.result != nil || model.findings.isEmpty == false:
            findings
        case .preparing(let stage):
            StatePanel(
                .loading, title: stage == .updating ? WardStrings.Scan.updating : WardStrings.Scan.starting,
                message: stage == .updating ? WardStrings.Scan.updatingNote : nil)
        case .scanning:
            progress
        case .failed(let reason):
            if reason == "notInstalled" {
                StatePanel(.problem, title: WardStrings.Scan.noEngineTitle, message: WardStrings.Scan.noEngineNote)
            } else {
                StatePanel(
                    .problem, title: WardStrings.Scan.failed, message: reason,
                    actionTitle: WardStrings.Scan.retry
                ) { model.start(model.scope) }
            }
        case .idle:
            StatePanel(.empty, title: WardStrings.Scan.neverScanned, message: WardStrings.Scan.neverScannedNote)
                .frame(minHeight: 260)
        }
    }

    private var progress: some View {
        let progress = model.progress
        return Panel(padding: Space.l + Space.xs) {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    Text(WardStrings.Scan.checking).textStyle(.display)
                    Text(progress?.current ?? "").textStyle(.body, .muted).lineLimit(1).truncationMode(.middle)
                }
                MeterBar(fraction: progress?.fraction ?? 0, tint: Palette.onSurface.color)
                HStack {
                    Text(
                        WardStrings.Scan.progress(
                            progress?.unitsDone ?? 0, of: progress?.unitsTotal ?? 0, files: progress?.filesChecked ?? 0)
                    )
                    .textStyle(.body, .muted).monospacedDigit()
                    Spacer()
                    Button(WardStrings.Scan.stop) { model.stop() }.buttonStyle(.careSecondary)
                }
            }
        }
    }

    private var findings: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(model.findings.isEmpty ? WardStrings.Scan.clean : WardStrings.Scan.found(model.findings.count))
                    .textStyle(.heading)
                if let result = model.result {
                    Text(WardStrings.Scan.summary(WardStrings.Scan.scope(model.scope), files: result.filesChecked))
                        .textStyle(.body, .muted).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 0)
                if model.bulkFindings.isEmpty == false {
                    Button(WardStrings.Scan.allToQuarantine) { Task { await model.moveAllToQuarantine() } }
                        .buttonStyle(.careBordered)
                        .disabled(model.working.isEmpty == false)
                }
            }
            .padding(.horizontal, Space.xs)
            if model.findings.isEmpty == false {
                GroupedRows {
                    ForEach(model.findings) { finding in
                        row(finding)
                    }
                }
            }
            Text(footnote).textStyle(.body, .muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.xs)
                .padding(.top, Space.xs)
        }
    }

    private var footnote: String {
        guard let unreadable = model.result?.unreadable, unreadable > 0 else { return WardStrings.Scan.footnote }
        return WardStrings.Scan.unreadable(unreadable) + " " + WardStrings.Scan.footnote
    }

    private func row(_ finding: Finding) -> some View {
        let isMalicious = finding.severity == .malicious
        let folder = finding.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return HStack(spacing: Space.m) {
            Badge(
                isMalicious ? WardStrings.Scan.malicious : WardStrings.Scan.suspicious,
                kind: isMalicious ? .danger : .attention, symbol: isMalicious ? "xmark" : "exclamationmark"
            )
            .frame(width: 104, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.name).textStyle(.bodyMedium).lineLimit(1).truncationMode(.middle)
                Text("\(WardStrings.Scan.reason(finding.reason)) · \(folder)")
                    .textStyle(.caption, model.problems[finding.id] == nil ? .muted : .attention).lineLimit(2)
                if let problem = model.problems[finding.id] {
                    Text(WardStrings.Scan.problem(problem)).textStyle(.caption, .attention)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isMalicious {
                Button(WardStrings.Scan.showInFinder) { model.reveal(finding.url) }.buttonStyle(.careLink)
            } else {
                Button(WardStrings.Scan.keep) { model.keep(finding) }.buttonStyle(.careLink)
            }
            Group {
                if finding.autostart != nil {
                    Button(WardStrings.Scan.disable) { Task { await model.disable(finding) } }
                        .buttonStyle(.careBordered)
                } else {
                    Button(WardStrings.Scan.toQuarantine) { Task { await model.moveToQuarantine(finding) } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .disabled(model.working.contains(finding.id))
        }
        .padding(.horizontal, Space.m + 2)
        .padding(.vertical, Space.m)
    }

    // MARK: The quarantine

    @ViewBuilder private var quarantine: some View {
        if model.entries.isEmpty {
            StatePanel(
                .empty, title: WardStrings.Scan.quarantineEmpty, message: WardStrings.Scan.quarantineEmptyNote
            )
            .frame(minHeight: 260)
        } else {
            GroupedRows {
                ForEach(model.entries) { entry in
                    HStack(spacing: Space.l) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).textStyle(.bodyStrong).lineLimit(1).truncationMode(.middle)
                            Text(
                                WardStrings.Scan.cameFrom(
                                    entry.originalPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            )
                            .textStyle(.caption, .muted).lineLimit(1).truncationMode(.middle)
                            if let problem = model.problems[entry.id] {
                                Text(WardStrings.Scan.problem(problem)).textStyle(.caption, .attention)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ByteFormat.string(entry.bytes)).textStyle(.body, .muted).monospacedDigit()
                        Group {
                            Button(WardStrings.Scan.restore) { Task { await model.restore(entry) } }
                                .buttonStyle(.careLink)
                            Button(WardStrings.Scan.deleteForever) { Task { await model.delete(entry) } }
                                .buttonStyle(.careBordered)
                        }
                        .disabled(model.working.contains(entry.id))
                    }
                    .padding(.horizontal, Space.m + 2)
                    .padding(.vertical, Space.m)
                }
            }
        }
    }
}
