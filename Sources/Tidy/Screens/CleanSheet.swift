import CareCore
import CareUI
import SwiftUI

/// One sheet for the whole cleanup: the question, the progress, the result.
struct CleanSheet: View {
    let model: JunkModel
    @State private var isEmptyTrashAsked = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            switch model.phase {
            case .cleaning: progress
            case .finished: result
            default: question
            }
        }
        .padding(Space.xl)
        .frame(width: 460)
        .background(Palette.surface.color)
    }

    @ViewBuilder private var question: some View {
        let plan = model.plan
        let groups = model.scan.groups.filter { JunkMath.selectedBytes(in: $0, model.selection) > 0 }
        Text(TidyStrings.Confirm.title(ByteFormat.string(plan.bytes))).textStyle(.title)
        VStack(spacing: 0) {
            ForEach(groups) { group in
                HStack {
                    Text(TidyStrings.Junk.name(group.id)).textStyle(.body)
                    Spacer()
                    Text(ByteFormat.string(JunkMath.selectedBytes(in: group, model.selection)))
                        .textStyle(.body, .muted).monospacedDigit()
                }
                .frame(height: 28)
            }
        }
        Text(TidyStrings.Confirm.regenerates).textStyle(.body, .muted)
        if groups.contains(where: { $0.rule.cleanupClass == .review }) {
            Text(TidyStrings.Confirm.review).textStyle(.body, .attention)
        }
        HStack(spacing: Space.m) {
            Spacer()
            Button(TidyStrings.Confirm.cancel) { model.isSheetShown = false }
                .buttonStyle(.careSecondary)
                .keyboardShortcut(.cancelAction)
            Button(TidyStrings.Confirm.confirm) { Task { await model.clean() } }
                .buttonStyle(.carePrimary)
        }
    }

    @ViewBuilder private var progress: some View {
        Text(TidyStrings.Progress.cleaning).textStyle(.title)
        MeterBar(
            fraction: model.stepsTotal > 0 ? Double(model.stepsDone) / Double(model.stepsTotal) : 0,
            tint: Palette.onSurface.color)
        Text(TidyStrings.Progress.step(model.stepsDone, of: model.stepsTotal)).textStyle(.body, .muted)
            .monospacedDigit()
    }

    @ViewBuilder private var result: some View {
        let report = model.report
        let trashReport = model.trashReport
        let problems = (report?.problems ?? []) + (trashReport?.problems ?? [])
        let trashed = report?.trashedBytes ?? 0
        Text(TidyStrings.Done.title).textStyle(.lead, .muted)
        Text(ByteFormat.string((report?.deletedBytes ?? 0) + (trashReport?.deletedBytes ?? 0)))
            .textStyle(.display)
        if trashed > 0, trashReport == nil {
            Text(TidyStrings.Done.inTrash(ByteFormat.string(trashed))).textStyle(.body, .muted)
        }
        if model.trashOutOfSight {
            Text(TidyStrings.Done.trashOutOfSight).textStyle(.body, .attention)
        }
        if problems.isEmpty == false {
            Text(TidyStrings.Done.problems(problems.count)).textStyle(.body, .attention)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(problems.prefix(20), id: \.request.id) { outcome in
                        Text(outcome.request.name).textStyle(.caption, .muted).lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
        HStack(spacing: Space.m) {
            Spacer()
            if trashed > 0, trashReport == nil {
                Button(TidyStrings.Done.emptyTrash) { isEmptyTrashAsked = true }
                    .buttonStyle(.careSecondary)
            }
            Button(TidyStrings.Done.close) { Task { await model.acknowledge() } }
                .buttonStyle(.carePrimary)
                .keyboardShortcut(.defaultAction)
        }
        .confirmationDialog(TidyStrings.Done.emptyTrashTitle, isPresented: $isEmptyTrashAsked) {
            Button(TidyStrings.Done.emptyTrash, role: .destructive) { Task { await model.emptyTrash() } }
            Button(TidyStrings.Confirm.cancel, role: .cancel) {}
        } message: {
            Text(TidyStrings.Done.emptyTrashNote)
        }
    }
}

struct JournalSheet: View {
    let model: JunkModel

    var body: some View {
        let entries = model.journal.entries().reversed().prefix(200)
        VStack(alignment: .leading, spacing: Space.l) {
            Text(TidyStrings.JournalSheet.title).textStyle(.title)
            if entries.isEmpty {
                StatePanel(
                    .empty, title: TidyStrings.JournalSheet.empty, message: TidyStrings.JournalSheet.emptyNote)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries)) { entry in
                            HStack(spacing: Space.m) {
                                Text(AppLocale.dateAndTime(entry.date))
                                    .textStyle(.caption, .muted).monospacedDigit()
                                    .frame(width: 120, alignment: .leading)
                                Text(entry.name).textStyle(.body).lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(ByteFormat.string(entry.bytes)).textStyle(.body, .muted).monospacedDigit()
                            }
                            .frame(height: 32)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button(TidyStrings.JournalSheet.close) { model.isJournalShown = false }
                    .buttonStyle(.careSecondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 560, height: 480)
        .background(Palette.surface.color)
    }
}
