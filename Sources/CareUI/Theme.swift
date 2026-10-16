import AppKit
import SwiftUI

/// A colour with one value for the light appearance and one for the dark, named for the job it
/// does. Windows follow the system appearance.
nonisolated public struct ColorToken: Sendable, Equatable {
    public let light: UInt32
    public let dark: UInt32

    public init(_ light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    /// The same value in both appearances.
    public init(_ both: UInt32) {
        self.init(both, dark: both)
    }

    public func hex(dark isDark: Bool) -> UInt32 { isDark ? dark : light }

    public var nsColor: NSColor {
        let light = light
        let dark = dark
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return Self.srgb(isDark ? dark : light)
        }
    }

    public var color: Color { Color(nsColor: nsColor) }

    static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The values come from the approved mockup and sit close to the system's own colours.
nonisolated public enum Palette {
    /// The content side of the window.
    public static let background = ColorToken(0xFFFFFF, dark: 0x1E1E20)
    /// The sidebar and bars along the window's edge.
    public static let sidebar = ColorToken(0xF0F0F2, dark: 0x29292C)
    /// Cards and grouped lists.
    public static let surface = ColorToken(0xF7F7F9, dark: 0x262628)
    /// A hovered row, a quiet note.
    public static let surfaceRaised = ColorToken(0xEDEDF0, dark: 0x303033)
    public static let border = ColorToken(0xE2E2E6, dark: 0x3A3A3D)
    public static let borderStrong = ColorToken(0xC7C7CC, dark: 0x55555A)
    public static let onSurface = ColorToken(0x1D1D1F, dark: 0xF5F5F7)
    public static let onSurfaceMuted = ColorToken(0x6B6B70, dark: 0xA1A1A6)
    public static let success = ColorToken(0x187A42, dark: 0x4CC27A)
    public static let attention = ColorToken(0x9A4600, dark: 0xFFA94D)
    public static let danger = ColorToken(0xB42318, dark: 0xFF8A80)
    public static let attentionSurface = ColorToken(0xFCEBDD, dark: 0x3A2A18)
    public static let dangerSurface = ColorToken(0xFDE7E5, dark: 0x3A1E1C)
    public static let onDangerSurface = ColorToken(0xB42318, dark: 0xFF8A80)
    /// Every text colour and every surface it may sit on, for the contrast test.
    public static let textColors = [onSurface, onSurfaceMuted, success, attention, danger]
    public static let surfaces = [background, sidebar, surface, surfaceRaised]
}

/// The colour that tells the apps apart: a fill for the main button and the chosen row, and a
/// text colour for links on the window background.
nonisolated public struct Accent: Sendable, Equatable {
    public let primary: ColorToken
    public let text: ColorToken
    public let onPrimary: ColorToken

    public static let tidy = Accent(
        primary: ColorToken(0x187A42), text: ColorToken(0x187A42, dark: 0x4CC27A), onPrimary: ColorToken(0xFFFFFF))
    public static let ward = Accent(
        primary: ColorToken(0x4F4DD0), text: ColorToken(0x4F4DD0, dark: 0x9A98FF), onPrimary: ColorToken(0xFFFFFF))
}

extension EnvironmentValues {
    @Entry public var accent: Accent = .tidy
}

nonisolated public enum Space {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 28
}

nonisolated public enum Radius {
    public static let s: CGFloat = 6
    public static let m: CGFloat = 8
    public static let l: CGFloat = 10
}

nonisolated public enum Metric {
    /// The height of a list row or a control a whole row hangs on.
    public static let hit: CGFloat = 32
    public static let sidebarWidth: CGFloat = 220
    public static let windowWidth: CGFloat = 1100
    public static let windowHeight: CGFloat = 720
}
