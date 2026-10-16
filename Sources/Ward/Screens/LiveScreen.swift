import CareCore
import CareUI
import SwiftUI

struct LiveScreen: View {
    let model: LiveModel
    let review: () -> Void

    var body: some View {
        ScreenScaffold(title: WardStrings.Nav.live) {
            HStack(spacing: Space.s) {
                if model.isStarting {
                    ProgressView().controlSize(.small)
                }
                Text(model.isOn ? WardStrings.Live.on : WardStrings.Live.off).textStyle(.bodyStrong)
                CareSwitch(isOn: model.isOn, label: WardStrings.Nav.live) {
                    Task { await model.setOn(model.isOn == false) }
                }
                .disabled(model.isStarting)
            }
        } content: {
            VStack(spacing: Space.m) {
                if model.hasProblem {
                    NoticeRow(
                        .attention,
                        title: model.isOn ? WardStrings.Live.engineDownTitle : WardStrings.Live.didNotStartTitle,
                        note: model.isOn ? WardStrings.Live.engineDownNote : WardStrings.Live.didNotStartNote
                    ) {
                        Button(WardStrings.Live.retry) { Task { await model.retry() } }
                            .buttonStyle(.careLink)
                            .disabled(model.isStarting)
                    }
                }
                panels
            }
        }
    }

    private var panels: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(spacing: Space.m) {
                Panel {
                    VStack(spacing: Space.xs) {
                        PanelHeader(WardStrings.Live.watched)
                        ForEach(WatchedPlace.allCases, id: \.self) { place in
                            HStack(spacing: Space.m) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(WardStrings.Live.place(place)).textStyle(.bodyMedium)
                                    Text(WardStrings.Live.placeNote(place)).textStyle(.caption, .muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                CareSwitch(
                                    isOn: model.isOn && model.places.contains(place),
                                    label: WardStrings.Live.place(place)
                                ) { model.toggle(place) }
                                .disabled(model.isOn == false)
                            }
                            .padding(.leading, Space.m)
                            .frame(minHeight: 56)
                        }
                    }
                }
                RaisedPanel {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(WardStrings.Live.howTitle).textStyle(.bodyStrong)
                        Text(WardStrings.Live.how).textStyle(.body, .muted)
                        Text(WardStrings.Live.engineLoad + " " + WardStrings.Live.startsAtLogin)
                            .textStyle(.caption, .muted)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(width: 364)

            Panel { events }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var events: some View {
        VStack(spacing: Space.xs) {
            PanelHeader(WardStrings.Live.events, note: WardStrings.Live.checkedToday(model.checkedToday))
            if model.isOn == false {
                StatePanel(.empty, title: WardStrings.Live.offTitle, message: WardStrings.Live.offNote)
            } else if model.events.isEmpty {
                StatePanel(.empty, title: WardStrings.Live.noEvents, message: WardStrings.Live.noEventsNote)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.xs) {
                        ForEach(model.events) { event in
                            row(event)
                        }
                    }
                }
            }
        }
    }

    private func row(_ event: LiveEvent) -> some View {
        HStack(spacing: Space.m) {
            Text(AppLocale.time(event.date)).textStyle(.body, .muted).monospacedDigit()
                .frame(width: 48, alignment: .leading)
            switch event.verdict {
            case .clean:
                StatusIcon(.ok, label: WardStrings.Live.clean)
                texts(event, detail: Self.cleanDetail(event), strong: false)
            case .notChecked:
                StatusIcon(.attention, label: WardStrings.Live.notCheckedLabel)
                texts(event, detail: WardStrings.Live.notChecked, strong: true)
            case .flagged(let finding):
                StatusIcon(finding.severity == .malicious ? .danger : .attention, label: WardStrings.Scan.suspicious)
                texts(event, detail: WardStrings.Scan.reason(finding.reason), strong: true)
                Button(WardStrings.Live.review, action: review).buttonStyle(.careLink)
            }
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.xs)
        .frame(minHeight: 60)
        .background(
            event.verdict == .clean ? .clear : Palette.surfaceRaised.color, in: RoundedRectangle(cornerRadius: Radius.m)
        )
    }

    static func cleanDetail(_ event: LiveEvent) -> String {
        guard let signer = event.signer else { return WardStrings.Live.clean }
        return event.notarized == false ? WardStrings.Live.signedNotNotarized(signer) : WardStrings.Live.signed(signer)
    }

    private func texts(_ event: LiveEvent, detail: String, strong: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(event.url.lastPathComponent).textStyle(strong ? .bodyStrong : .bodyMedium).lineLimit(1)
                .truncationMode(.middle)
            Text("\(WardStrings.Live.place(event.place)) · \(detail)").textStyle(.caption, .muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
