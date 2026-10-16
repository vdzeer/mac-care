import SwiftUI

/// One thing an app asks the user to allow: how to tell whether it is allowed, and what the
/// button next to it does.
public struct PermissionStep: Identifiable {
    public let id: String
    public let title: String
    public let note: String
    public let actionTitle: String
    /// What the row says once it is done; the sheet's "allowed" label when nil.
    public let doneLabel: String?
    public let isAllowed: @MainActor () async -> Bool
    public let action: @MainActor () -> Void

    public init(
        id: String, title: String, note: String, actionTitle: String, doneLabel: String? = nil,
        isAllowed: @escaping @MainActor () async -> Bool, action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.actionTitle = actionTitle
        self.doneLabel = doneLabel
        self.isAllowed = isAllowed
        self.action = action
    }
}

/// The app's own window for what it needs from macOS. There is no system prompt for Full Disk
/// Access, so the app explains it, opens the right page of System Settings, and notices by
/// itself when access has been turned on. Every system dialog that follows names the app.
public struct PermissionsSheet: View {
    let title: String
    let message: String
    let allowedLabel: String
    let laterTitle: String
    let doneTitle: String
    let steps: [PermissionStep]
    let onClose: () -> Void
    @State private var allowed: Set<String> = []

    public init(
        title: String, message: String, allowedLabel: String, laterTitle: String, doneTitle: String,
        steps: [PermissionStep], onClose: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.allowedLabel = allowedLabel
        self.laterTitle = laterTitle
        self.doneTitle = doneTitle
        self.steps = steps
        self.onClose = onClose
    }

    private var isComplete: Bool { steps.allSatisfy { allowed.contains($0.id) } }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.l + Space.xs) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).textStyle(.title)
                Text(message).textStyle(.body, .muted).fixedSize(horizontal: false, vertical: true)
            }
            GroupedRows {
                ForEach(steps) { step in
                    let isAllowed = allowed.contains(step.id)
                    HStack(alignment: .center, spacing: Space.m) {
                        StatusIcon(isAllowed ? .ok : .attention, label: step.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).textStyle(.bodyMedium)
                            Text(step.note).textStyle(.caption, .muted).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if isAllowed {
                            Text(step.doneLabel ?? allowedLabel).textStyle(.bodyMedium, .success)
                        } else {
                            Button(step.actionTitle) { step.action() }.buttonStyle(.careBordered)
                        }
                    }
                    .padding(.horizontal, Space.m + 2)
                    .padding(.vertical, Space.m)
                }
            }
            HStack {
                Spacer()
                if isComplete {
                    Button(doneTitle, action: onClose).buttonStyle(.carePrimary).keyboardShortcut(.defaultAction)
                } else {
                    Button(laterTitle, action: onClose).buttonStyle(.careSecondary).keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 540)
        // System Settings changes nothing in the app directly, so the sheet looks again every second
        // and a half while it is open.
        .task {
            while !Task.isCancelled {
                var now: Set<String> = []
                for step in steps where await step.isAllowed() { now.insert(step.id) }
                allowed = now
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}
