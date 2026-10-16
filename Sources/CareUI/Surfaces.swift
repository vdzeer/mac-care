import AppKit
import SwiftUI

/// A bordered card on the first surface level.
public struct Panel<Content: View>: View {
    let padding: CGFloat
    let content: Content

    public init(padding: CGFloat = Space.s, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(Palette.surface.color, in: RoundedRectangle(cornerRadius: Radius.l))
            .overlay(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Palette.border.color))
    }
}

/// A quieter card on the second surface level, for notes and small facts.
public struct RaisedPanel<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, Space.l + Space.xs)
            .padding(.vertical, Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceRaised.color, in: RoundedRectangle(cornerRadius: Radius.l))
    }
}

/// A panel heading with an optional note on the right.
public struct PanelHeader: View {
    let title: String
    let note: String?

    public init(_ title: String, note: String? = nil) {
        self.title = title
        self.note = note
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).textStyle(.heading)
            Spacer(minLength: Space.m)
            if let note {
                Text(note).textStyle(.body, .muted).monospacedDigit()
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.s)
        .padding(.bottom, Space.xs)
    }
}

/// A thin horizontal meter.
public struct MeterBar: View {
    let fraction: Double
    let tint: Color

    public init(fraction: Double, tint: Color) {
        self.fraction = fraction
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            Capsule().fill(Palette.border.color)
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// A bar split into parts, each as wide as its share.
public struct StackedBar: View {
    let parts: [(fraction: Double, color: Color)]

    public init(parts: [(fraction: Double, color: Color)]) {
        self.parts = parts
    }

    public var body: some View {
        GeometryReader { proxy in
            let gaps = CGFloat(max(parts.count - 1, 0)) * 3
            HStack(spacing: 3) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle().fill(part.color)
                        .frame(width: max((proxy.size.width - gaps) * part.fraction, 0))
                }
            }
        }
        .frame(height: 12)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

public enum BadgeKind: Sendable {
    case neutral, attention, danger, accent
}

public struct Badge: View {
    @Environment(\.accent) private var accent
    let text: String
    let kind: BadgeKind
    let symbol: String?

    public init(_ text: String, kind: BadgeKind = .neutral, symbol: String? = nil) {
        self.text = text
        self.kind = kind
        self.symbol = symbol
    }

    public var body: some View {
        HStack(spacing: Space.xs + 2) {
            if let symbol {
                Image(systemName: symbol).imageScale(.small).fontWeight(.bold)
            }
            Text(text)
        }
        .textStyle(.captionStrong, tone)
        .padding(.horizontal, Space.s)
        .frame(height: 22)
        .background(fill, in: Capsule())
    }

    private var tone: Tone {
        switch kind {
        case .neutral: .muted
        case .attention: .attention
        case .danger: .onDanger
        case .accent: .onAccent
        }
    }

    private var fill: Color {
        switch kind {
        case .neutral: Palette.surfaceRaised.color
        case .attention: Palette.attentionSurface.color
        case .danger: Palette.dangerSurface.color
        case .accent: accent.primary.color
        }
    }
}

public enum StatusKind: Sendable {
    case ok, attention, danger
}

/// A tick, a triangle or a cross: the shape differs as well as the colour.
public struct StatusIcon: View {
    let kind: StatusKind
    let label: String

    public init(_ kind: StatusKind, label: String) {
        self.kind = kind
        self.label = label
    }

    public var body: some View {
        Image(systemName: symbol)
            .resizable().scaledToFit().fontWeight(.semibold)
            .foregroundStyle(color)
            .frame(width: 18, height: 18)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch kind {
        case .ok: "checkmark"
        case .attention: "exclamationmark.triangle"
        case .danger: "xmark.octagon"
        }
    }

    private var color: Color {
        switch kind {
        case .ok: Palette.success.color
        case .attention: Palette.attention.color
        case .danger: Palette.danger.color
        }
    }
}

/// A small rounded tile with an app's own icon, or its first letter when there is none.
public struct IconTile: View {
    let image: NSImage?
    let name: String
    let size: CGFloat

    public init(image: NSImage?, name: String, size: CGFloat = 32) {
        self.image = image
        self.name = name
        self.size = size
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.28).fill(Palette.border.color)
                    .overlay {
                        Text(String(name.prefix(1)).uppercased()).textStyle(.title, size: size * 0.42)
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// What a screen shows when it has nothing, is busy, or failed. Every empty state names the next step.
public struct StatePanel: View {
    public enum Kind: Sendable { case empty, loading, problem }

    let kind: Kind
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    public init(
        _ kind: Kind, title: String, message: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Space.m) {
            switch kind {
            case .loading: ProgressView().controlSize(.regular)
            case .problem: StatusIcon(.attention, label: title)
            case .empty: EmptyView()
            }
            Text(title).textStyle(.heading)
            if let message {
                Text(message).textStyle(.body, .muted).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.careSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A row that states a fact with a status mark, and offers something to do about it on the right.
public struct NoticeRow<Trailing: View>: View {
    let kind: StatusKind
    let title: String
    let note: String?
    let isRaised: Bool
    let trailing: Trailing

    public init(
        _ kind: StatusKind, title: String, note: String? = nil, isRaised: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.kind = kind
        self.title = title
        self.note = note
        self.isRaised = isRaised
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Space.m) {
            StatusIcon(kind, label: "")
            VStack(alignment: .leading, spacing: 0) {
                Text(title).textStyle(kind == .ok ? .bodyMedium : .bodyStrong).lineLimit(1)
                if let note {
                    Text(note).textStyle(.caption, .muted).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.xs)
        .padding(.vertical, Space.s)
        .frame(minHeight: isRaised ? 52 : 40)
        .background(isRaised ? Palette.surface.color : .clear, in: RoundedRectangle(cornerRadius: Radius.l))
        .overlay {
            if isRaised { RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Palette.border.color) }
        }
    }
}

/// A card that is itself a button: a title, what it covers, and a small note. `isMarked` outlines the usual choice.
public struct ChoiceCard: View {
    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let note: String
    let hint: String
    let isMarked: Bool
    let isDashed: Bool
    let action: () -> Void

    public init(
        title: String, note: String, hint: String, isMarked: Bool = false, isDashed: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.note = note
        self.hint = hint
        self.isMarked = isMarked
        self.isDashed = isDashed
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).textStyle(.heading)
                Text(note).textStyle(.body, .muted).lineLimit(1)
                Text(hint).textStyle(.caption, .muted).lineLimit(1)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isDashed ? .clear : Palette.surface.color, in: RoundedRectangle(cornerRadius: Radius.l))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.l)
                    .strokeBorder(
                        isMarked ? accent.primary.color : isDashed ? Palette.borderStrong.color : Palette.border.color,
                        style: StrokeStyle(lineWidth: isMarked ? 2 : 1, dash: isDashed ? [5, 4] : []))
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.l))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}
