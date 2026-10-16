import SwiftUI

public struct NavEntry<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    public let symbol: String

    public init(id: ID, title: String, symbol: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
    }
}

/// The window: a sidebar with the app's sections and a footer card, and the chosen screen beside
/// it. The title bar is hidden, so the window buttons sit at the top of the sidebar, as in the
/// mockup.
public struct AppShell<ID: Hashable, Footer: View, Content: View>: View {
    let entries: [NavEntry<ID>]
    @Binding var selection: ID
    let footer: Footer
    let content: Content

    public init(
        entries: [NavEntry<ID>], selection: Binding<ID>, @ViewBuilder footer: () -> Footer,
        @ViewBuilder content: () -> Content
    ) {
        self.entries = entries
        self._selection = selection
        self.footer = footer()
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entries) { entry in
                    SidebarRow(entry: entry, isCurrent: entry.id == selection) { selection = entry.id }
                }
                Spacer(minLength: Space.xl)
                footer
            }
            // Room for the window's close, minimise and zoom buttons.
            .padding(.top, 44)
            .padding(.horizontal, Space.s + 2)
            .padding(.bottom, Space.m)
            .frame(width: Metric.sidebarWidth)
            .frame(maxHeight: .infinity)
            .background(Palette.sidebar.color)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background.color)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct SidebarRow<ID: Hashable>: View {
    @Environment(\.accent) private var accent
    let entry: NavEntry<ID>
    let isCurrent: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Image(systemName: entry.symbol).frame(width: 18)
                Text(entry.title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .textStyle(isCurrent ? .bodyMedium : .body, isCurrent ? .onAccent : .primary)
            .padding(.horizontal, Space.s + 2)
            .frame(height: 30)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.s))
            .contentShape(RoundedRectangle(cornerRadius: Radius.s))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var background: Color {
        if isCurrent { return accent.primary.color }
        return isHovered ? Palette.surfaceRaised.color : .clear
    }
}

/// The frame every screen shares: a title bar with the screen's own controls on the right, a
/// hairline, the screen's content, and an optional bar along the bottom edge.
public struct ScreenScaffold<Trailing: View, Content: View, Footer: View>: View {
    let title: String
    let trailing: Trailing
    let content: Content
    let footer: Footer
    let scrolls: Bool

    public init(
        title: String, scrolls: Bool = false, @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.scrolls = scrolls
        self.trailing = trailing()
        self.content = content()
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                Text(title).textStyle(.heading, size: 15)
                Spacer(minLength: Space.m)
                trailing
            }
            .padding(.horizontal, Space.xl)
            .frame(height: 52)
            Divider()
            if scrolls {
                ScrollView { padded }
            } else {
                padded.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if Footer.self != EmptyView.self {
                Divider()
                HStack(spacing: Space.m) { footer }
                    .padding(.horizontal, Space.xxl)
                    .frame(height: 56)
                    .background(Palette.sidebar.color)
            }
        }
    }

    private var padded: some View {
        content
            .padding(.horizontal, Space.xxl)
            .padding(.vertical, Space.xl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension ScreenScaffold where Footer == EmptyView {
    public init(
        title: String, scrolls: Bool = false, @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, scrolls: scrolls, trailing: trailing, content: content) { EmptyView() }
    }
}

/// A card that groups rows, with hairlines between them, like a grouped list in System Settings.
public struct GroupedRows<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().padding(.leading, Space.m) }
                    row
                }
            }
        }
        .background(Palette.surface.color, in: RoundedRectangle(cornerRadius: Radius.l))
        .overlay(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Palette.border.color))
        .clipShape(RoundedRectangle(cornerRadius: Radius.l))
    }
}

/// A section heading above a grouped list, with an optional note on the right.
public struct SectionTitle: View {
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
            if let note { Text(note).textStyle(.body, .muted) }
        }
        .padding(.horizontal, Space.xs)
    }
}

/// A caption with one big figure under it, as on both overview screens.
public struct BigFigure: View {
    let caption: String
    let value: String
    let unit: String?

    public init(caption: String, value: String, unit: String? = nil) {
        self.caption = caption
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(caption).textStyle(.bodyMedium, .muted)
            Text(unit.map { value + "\u{00A0}" + $0 } ?? value)
                .textStyle(.hero).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A tile at the bottom of an overview: where it leads, one fact, one line about it.
public struct SummaryTile: View {
    let title: String
    let value: String
    let valueTone: Tone
    let note: String
    let action: () -> Void

    public init(
        title: String, value: String, valueTone: Tone = .primary, note: String, action: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.valueTone = valueTone
        self.note = note
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack {
                    Text(title).textStyle(.body, .muted)
                    Spacer()
                    Image(systemName: "chevron.right").textStyle(.caption, .muted)
                }
                Text(value).textStyle(.display, valueTone).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(note).textStyle(.body, .muted).lineLimit(2, reservesSpace: true)
            }
            .padding(Space.l + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface.color, in: RoundedRectangle(cornerRadius: Radius.l + 2))
            .overlay(RoundedRectangle(cornerRadius: Radius.l + 2).strokeBorder(Palette.border.color))
            .contentShape(RoundedRectangle(cornerRadius: Radius.l + 2))
        }
        .buttonStyle(.plain)
    }
}

/// Lays items out in a row and starts a new row when the next one does not fit.
public struct FlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    public init(spacing: CGFloat = Space.xl, lineSpacing: CGFloat = Space.s) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (
                    last.indices + [index], last.width + spacing + size.width, max(last.height, size.height)
                )
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
