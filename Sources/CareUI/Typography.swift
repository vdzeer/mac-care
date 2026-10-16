import SwiftUI

/// The system typeface at the sizes of the approved mockup. 13 points is the macOS body size.
nonisolated public enum TextStyle: CaseIterable, Sendable {
    case hero, display, title, heading, lead, bodyStrong, bodyMedium, body, captionStrong, caption

    public var size: CGFloat {
        switch self {
        case .hero: 44
        case .display: 24
        case .title: 20
        case .lead: 15
        case .heading, .bodyStrong, .bodyMedium, .body: 13
        case .captionStrong, .caption: 12
        }
    }

    var weight: Font.Weight {
        switch self {
        case .hero, .display, .title, .heading, .bodyStrong, .captionStrong: .semibold
        case .bodyMedium: .medium
        case .lead, .body, .caption: .regular
        }
    }

    var tracking: CGFloat {
        self == .hero ? -0.5 : 0
    }
}

nonisolated public enum Tone: Sendable {
    /// `inverse` is text on a fill of the text colour itself, such as a chosen segment.
    case primary, muted, inverse, accent, onAccent, success, attention, danger, onDanger
}

private struct StyledText: ViewModifier {
    @Environment(\.accent) private var accent
    let style: TextStyle
    let tone: Tone
    let size: CGFloat?

    func body(content: Content) -> some View {
        content
            .font(.system(size: size ?? style.size, weight: style.weight))
            .tracking(size == nil ? style.tracking : 0)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch tone {
        case .primary: Palette.onSurface.color
        case .muted: Palette.onSurfaceMuted.color
        case .inverse: Palette.background.color
        case .accent: accent.text.color
        case .onAccent: accent.onPrimary.color
        case .success: Palette.success.color
        case .attention: Palette.attention.color
        case .danger: Palette.danger.color
        case .onDanger: Palette.onDangerSurface.color
        }
    }
}

extension View {
    /// The only way text gets a font and a colour.
    public func textStyle(_ style: TextStyle, _ tone: Tone = .primary) -> some View {
        modifier(StyledText(style: style, tone: tone, size: nil))
    }

    /// A step of the scale drawn at another size, for the few numbers that sit between two steps.
    public func textStyle(_ style: TextStyle, size: CGFloat, _ tone: Tone = .primary) -> some View {
        modifier(StyledText(style: style, tone: tone, size: size))
    }
}
