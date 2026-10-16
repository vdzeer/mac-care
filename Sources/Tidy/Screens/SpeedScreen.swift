import CareCore
import CareUI
import SwiftUI

struct SpeedScreen: View {
    @Environment(\.accent) private var accent
    let model: SpeedModel
    let metrics: MetricsModel

    var body: some View {
        ScreenScaffold(title: TidyStrings.Nav.speed) {
            Text(TidyStrings.Speed.live).textStyle(.body, .muted)
        } content: {
            HStack(alignment: .top, spacing: Space.m) {
                Panel { autostart }.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: Space.m) {
                    HStack(spacing: Space.m) {
                        MetricTile(
                            title: TidyStrings.Speed.cpu, value: Self.percent(metrics.snapshot.cpu),
                            fraction: metrics.snapshot.cpu)
                        MetricTile(
                            title: TidyStrings.Speed.memory, value: ByteFormat.string(metrics.snapshot.memoryUsed),
                            fraction: metrics.snapshot.memoryFraction)
                    }
                    HStack(spacing: Space.m) {
                        Text(TidyStrings.Speed.pressure).textStyle(.body, .muted)
                        Spacer(minLength: 0)
                        StatusIcon(metrics.snapshot.pressure == .normal ? .ok : .attention, label: "")
                        Text(TidyStrings.Speed.pressureName(metrics.snapshot.pressure)).textStyle(.bodyStrong)
                    }
                    .padding(.horizontal, Space.l)
                    .frame(height: 48)
                    .background(Palette.surfaceRaised.color, in: RoundedRectangle(cornerRadius: Radius.l))
                    Panel { heavy }.frame(maxHeight: .infinity)
                }
                .frame(width: 332)
            }
        }
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    @ViewBuilder private var autostart: some View {
        VStack(spacing: Space.xs) {
            PanelHeader(
                TidyStrings.Speed.startsWithMac,
                note: model.phase == .ready ? TidyStrings.Speed.enabled(model.enabledCount, of: model.items.count) : nil
            )
            if model.phase != .ready {
                StatePanel(.loading, title: TidyStrings.Speed.loading)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.xs) {
                        ForEach(model.items) { item in
                            row(item)
                        }
                    }
                }
            }
            HStack(spacing: Space.m) {
                Text(TidyStrings.Speed.loginItems).textStyle(.caption, .muted).fixedSize(
                    horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                Button(TidyStrings.Speed.openLoginItems) { model.openLoginItemsSettings() }.buttonStyle(.careLinkInline)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
        }
    }

    private func row(_ item: AutostartItem) -> some View {
        HStack(spacing: Space.m) {
            IconTile(image: model.icon(for: item), name: item.name)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).textStyle(.bodyMedium).lineLimit(1)
                Text(model.problemID == item.id ? TidyStrings.Speed.failed : TidyStrings.Speed.kind(item.kind))
                    .textStyle(.caption, model.problemID == item.id ? .attention : .muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.canBeSwitchedHere {
                Text(item.isEnabled ? TidyStrings.Speed.on : TidyStrings.Speed.off).textStyle(.body, .muted)
                CareSwitch(isOn: item.isEnabled, label: item.name) { Task { await model.toggle(item) } }
                    .disabled(model.busyID != nil)
            } else {
                Button(TidyStrings.Speed.inSettings) { model.openLoginItemsSettings() }.buttonStyle(.careLink)
            }
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.xs)
        .frame(minHeight: 56)
        .opacity(item.isEnabled ? 1 : 0.6)
    }

    private var heavy: some View {
        VStack(spacing: Space.xs) {
            PanelHeader(TidyStrings.Speed.heaviest, note: TidyStrings.Speed.heaviestColumns)
            ForEach(metrics.heavy) { process in
                HStack(spacing: Space.m) {
                    Text(process.name).textStyle(.bodyMedium).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Int(process.cpu.rounded()))%").textStyle(.body).monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                    Text(ByteFormat.string(process.memory)).textStyle(.body, .muted).monospacedDigit()
                        .frame(width: 68, alignment: .trailing)
                }
                .padding(.horizontal, Space.m)
                .frame(height: 44)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A small card with one live number and a meter under it.
struct MetricTile: View {
    @Environment(\.accent) private var accent
    let title: String
    let value: String
    let fraction: Double?
    var note: String?
    var isRaised = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title).textStyle(.body, .muted)
            Text(value).textStyle(isRaised ? .title : .display).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            if let fraction {
                MeterBar(fraction: fraction, tint: accent.primary.color)
            }
            if let note {
                Text(note).textStyle(.caption, .muted)
            }
        }
        .padding(isRaised ? Space.m : Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isRaised ? Palette.surfaceRaised.color : Palette.surface.color, in: RoundedRectangle(cornerRadius: Radius.l)
        )
        .overlay(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(isRaised ? .clear : Palette.border.color))
    }
}
