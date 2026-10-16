import SwiftUI

/// The one main action of a screen: the system's prominent button in the app's accent colour.
public struct PrimaryButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) { configuration.label }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}

/// The second most important action: the system's bordered button, in neutral colours so only
/// the main action carries the accent. `large` matches the main button; the regular size suits
/// rows and title bars.
public struct SecondaryButtonStyle: PrimitiveButtonStyle {
    let isLarge: Bool

    public init(isLarge: Bool = true) {
        self.isLarge = isLarge
    }

    public func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) { configuration.label }
            .buttonStyle(.bordered)
            .controlSize(isLarge ? .large : .regular)
            .tint(Palette.onSurface.color)
    }
}

/// Accent-coloured text that acts as a button. `inline` drops the side padding so it lines up with text.
public struct LinkButtonStyle: ButtonStyle {
    let inline: Bool

    public init(inline: Bool = false) {
        self.inline = inline
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.bodyMedium, .accent)
            .padding(.horizontal, inline ? 0 : Space.s)
            .frame(minHeight: inline ? 0 : Metric.hit)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// A whole row that can be clicked; it lights up under the pointer.
public struct RowButtonStyle: ButtonStyle {
    let isSelected: Bool

    public init(isSelected: Bool = false) {
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration, isSelected: isSelected)
    }

    private struct RowBody: View {
        let configuration: Configuration
        let isSelected: Bool
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    (isSelected || isHovered || configuration.isPressed) ? Palette.surfaceRaised.color : .clear,
                    in: RoundedRectangle(cornerRadius: Radius.s)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.s))
                .onHover { isHovered = $0 }
        }
    }
}

extension PrimitiveButtonStyle where Self == PrimaryButtonStyle {
    public static var carePrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension PrimitiveButtonStyle where Self == SecondaryButtonStyle {
    public static var careSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    public static var careBordered: SecondaryButtonStyle { SecondaryButtonStyle(isLarge: false) }
}

extension ButtonStyle where Self == LinkButtonStyle {
    public static var careLink: LinkButtonStyle { LinkButtonStyle() }
    public static var careLinkInline: LinkButtonStyle { LinkButtonStyle(inline: true) }
}

extension ButtonStyle where Self == RowButtonStyle {
    public static var careRow: RowButtonStyle { RowButtonStyle() }
    public static func careRow(selected: Bool) -> RowButtonStyle { RowButtonStyle(isSelected: selected) }
}

public enum CheckState: Sendable, Equatable {
    case off, mixed, on
}

/// A tick box drawn like the system's, with a third state for a group where only some items are ticked.
public struct Checkbox: View {
    @Environment(\.accent) private var accent
    let state: CheckState
    let label: String
    let action: () -> Void

    public init(state: CheckState, label: String, action: @escaping () -> Void) {
        self.state = state
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(state == .off ? Palette.background.color : accent.primary.color)
                RoundedRectangle(cornerRadius: 3.5)
                    .strokeBorder(state == .off ? Palette.borderStrong.color : .clear, lineWidth: 1)
                if state != .off {
                    Image(systemName: state == .on ? "checkmark" : "minus")
                        .resizable().scaledToFit().fontWeight(.bold)
                        .foregroundStyle(accent.onPrimary.color)
                        .padding(3)
                }
            }
            .frame(width: 15, height: 15)
            .frame(width: 24, height: Metric.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(state == .on ? "1" : state == .mixed ? "mixed" : "0")
        .accessibilityAddTraits(.isToggle)
    }
}

/// The system's on/off switch.
public struct CareSwitch: View {
    let isOn: Bool
    let label: String
    let action: () -> Void

    public init(isOn: Bool, label: String, action: @escaping () -> Void) {
        self.isOn = isOn
        self.label = label
        self.action = action
    }

    public var body: some View {
        Toggle(label, isOn: Binding(get: { isOn }, set: { _ in action() }))
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel(label)
    }
}

/// Two or three choices: the system's segmented control.
public struct SegmentedPicker<ID: Hashable>: View {
    let options: [(id: ID, title: String)]
    @Binding var selection: ID

    public init(options: [(id: ID, title: String)], selection: Binding<ID>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.id) { option in
                Text(option.title).tag(option.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

/// A one-line search box.
public struct SearchField: View {
    @Binding var text: String
    let prompt: String

    public init(text: Binding<String>, prompt: String) {
        self._text = text
        self.prompt = prompt
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass").textStyle(.body, .muted)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .textStyle(.body)
        }
        .padding(.horizontal, Space.s + 2)
        .frame(height: 28)
        .background(Palette.background.color, in: RoundedRectangle(cornerRadius: Radius.s))
        .overlay(RoundedRectangle(cornerRadius: Radius.s).strokeBorder(Palette.border.color))
    }
}
