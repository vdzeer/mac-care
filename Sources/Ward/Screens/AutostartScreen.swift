import AppKit
import CareCore
import CareUI
import SwiftUI

struct AutostartScreen: View {
    @Bindable var model: AutostartModel
    @State private var selectedID: String?

    var body: some View {
        ScreenScaffold(title: WardStrings.Nav.autostart) {
            SegmentedPicker(
                options: [
                    (AutostartModel.Filter.all, WardStrings.Autostart.all(model.items.count)),
                    (AutostartModel.Filter.new, WardStrings.Autostart.new(model.newIDs.count)),
                    (AutostartModel.Filter.unsigned, WardStrings.Autostart.unsigned(model.unsignedCount)),
                ], selection: $model.filter)
        } content: {
            HStack(alignment: .top, spacing: Space.m) {
                Panel { autostart }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Panel { network }.frame(width: 332).frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: What starts by itself

    @ViewBuilder private var autostart: some View {
        VStack(spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(WardStrings.Autostart.title).textStyle(.heading)
                Spacer(minLength: Space.m)
                if model.newIDs.isEmpty {
                    Text(WardStrings.Autostart.signer).textStyle(.body, .muted)
                } else {
                    Button(WardStrings.Autostart.markSeen) { model.markSeen() }.buttonStyle(.careLinkInline)
                }
            }
            .padding(.horizontal, Space.m)
            .frame(height: Metric.hit)

            if model.phase != .ready {
                StatePanel(.loading, title: WardStrings.Autostart.loading)
            } else if model.visible.isEmpty {
                StatePanel(.empty, title: WardStrings.Autostart.nothing)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.xs) {
                        ForEach(model.visible) { item in
                            row(item)
                        }
                    }
                }
                if let item = model.items.first(where: { $0.id == selectedID }) {
                    actions(for: item)
                }
            }
            HStack(spacing: Space.m) {
                Text(WardStrings.Autostart.loginItems).textStyle(.caption, .muted).fixedSize(
                    horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                Button(WardStrings.Autostart.openLoginItems) { model.openLoginItemsSettings() }.buttonStyle(
                    .careLinkInline)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
        }
    }

    private func row(_ item: AutostartItem) -> some View {
        let flagged = AutostartModel.lacksSignature(item)
        return Button {
            selectedID = selectedID == item.id ? nil : item.id
        } label: {
            HStack(spacing: Space.m) {
                IconTile(image: Self.icon(for: item), name: item.name)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.s) {
                        Text(item.name).textStyle(.bodyMedium).lineLimit(1)
                        if model.newIDs.contains(item.id) {
                            Badge(WardStrings.Autostart.newBadge, kind: .accent).scaleEffect(0.86)
                        }
                    }
                    Text(Self.detail(item)).textStyle(.caption, .muted).lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Badge(Self.signer(item), kind: flagged || item.isTargetMissing ? .attention : .neutral)
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: 60)
            .opacity(item.isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.careRow(selected: selectedID == item.id || flagged))
    }

    private func actions(for item: AutostartItem) -> some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.label).textStyle(.bodyStrong).lineLimit(1).truncationMode(.middle)
                Text((item.target ?? item.program ?? "").replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .textStyle(.caption, model.problemID == item.id ? .attention : .muted).lineLimit(1)
                    .truncationMode(.middle)
                if model.problemID == item.id {
                    Text(WardStrings.Autostart.failed).textStyle(.caption, .attention)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.canBeSwitchedHere {
                Button(item.isEnabled ? WardStrings.Autostart.disable : WardStrings.Autostart.enable) {
                    Task { await model.setEnabled(item.isEnabled == false, item) }
                }
                .buttonStyle(.careSecondary)
            } else {
                Button(WardStrings.Autostart.inSettings) { model.openLoginItemsSettings() }
                    .buttonStyle(.careSecondary)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(Palette.surfaceRaised.color, in: RoundedRectangle(cornerRadius: Radius.m))
    }

    static func signer(_ item: AutostartItem) -> String {
        if item.isTargetMissing { return WardStrings.Autostart.missing }
        return signer(item.signature)
    }

    static func signer(_ signature: SignatureInfo?) -> String {
        switch signature?.kind {
        case .apple: WardStrings.Autostart.apple
        case .developer(_, let name): name
        case .adHoc, .unsigned: WardStrings.Autostart.unsignedSigner
        case .broken: WardStrings.Autostart.brokenSigner
        case nil: WardStrings.Autostart.unknownSigner
        }
    }

    private static func detail(_ item: AutostartItem) -> String {
        var parts = [item.label, WardStrings.Autostart.kind(item.kind)]
        if let launcher = item.launcher { parts.append(WardStrings.Autostart.through(launcher)) }
        if item.isEnabled == false { parts.append(WardStrings.Autostart.off) }
        return parts.joined(separator: " · ")
    }

    private static func icon(for item: AutostartItem) -> NSImage? {
        guard let app = AutostartInventory.enclosingApp((item.target ?? "") + "/"),
            FileManager.default.fileExists(atPath: app)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: app)
    }

    // MARK: The network

    private var network: some View {
        VStack(spacing: Space.xs) {
            PanelHeader(WardStrings.Autostart.network, note: WardStrings.Autostart.networkColumns)
            ScrollView {
                LazyVStack(spacing: Space.xs) {
                    ForEach(model.network) { process in
                        let flagged = process.signature.map { $0.isTrusted == false } ?? false
                        HStack(spacing: Space.m) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(process.name).textStyle(.bodyMedium).lineLimit(1).truncationMode(.middle)
                                Text(
                                    ([Self.signer(process.signature)] + (flagged ? process.remotes.prefix(1) : []))
                                        .joined(separator: " · ")
                                )
                                .textStyle(.caption, flagged ? .attention : .muted).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(process.connections)).textStyle(.body).monospacedDigit()
                                .frame(width: 28, alignment: .trailing)
                            Text(ByteFormat.rate(process.rate)).textStyle(.body, .muted).monospacedDigit()
                                .frame(width: 76, alignment: .trailing)
                        }
                        .padding(.horizontal, Space.m)
                        .frame(minHeight: 52)
                        .background(
                            flagged ? Palette.surfaceRaised.color : .clear, in: RoundedRectangle(cornerRadius: Radius.m)
                        )
                    }
                }
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(WardStrings.Autostart.listening(model.listeningCount)).textStyle(.bodyStrong)
                Text(WardStrings.Autostart.networkNote).textStyle(.caption, .muted)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceRaised.color, in: RoundedRectangle(cornerRadius: Radius.m))
        }
    }
}
