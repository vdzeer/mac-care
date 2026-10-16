import Foundation
import Testing

@testable import CareUI

/// Every pairing of text and surface the apps use must reach WCAG AA for body text, in the
/// light and in the dark appearance.
@Suite struct ContrastTests {
    static var pairs: [(name: String, text: ColorToken, surface: ColorToken)] {
        var pairs: [(String, ColorToken, ColorToken)] = []
        let texts: [(String, ColorToken)] = [
            ("onSurface", Palette.onSurface), ("onSurfaceMuted", Palette.onSurfaceMuted), ("success", Palette.success),
            ("attention", Palette.attention), ("danger", Palette.danger), ("tidy.text", Accent.tidy.text),
            ("ward.text", Accent.ward.text),
        ]
        for (name, text) in texts {
            for (index, surface) in Palette.surfaces.enumerated() {
                pairs.append(("\(name) on surface level \(index)", text, surface))
            }
        }
        for (name, accent) in [("tidy", Accent.tidy), ("ward", Accent.ward)] {
            pairs.append(("\(name).onPrimary on primary", accent.onPrimary, accent.primary))
        }
        pairs.append(("attention on attentionSurface", Palette.attention, Palette.attentionSurface))
        pairs.append(("onDangerSurface on dangerSurface", Palette.onDangerSurface, Palette.dangerSurface))
        pairs.append(("background on onSurface", Palette.background, Palette.onSurface))
        return pairs
    }

    @Test(arguments: [false, true])
    func everyPairIsReadable(dark: Bool) {
        for pair in Self.pairs {
            let ratio = Self.contrast(pair.text.hex(dark: dark), pair.surface.hex(dark: dark))
            #expect(ratio >= 4.5, "\(pair.name), dark \(dark): \(ratio)")
        }
    }

    @Test func everyTextColourIsCheckedOnEverySurface() {
        #expect(Palette.textColors.count * Palette.surfaces.count <= Self.pairs.count)
    }

    @Test func theScaleStaysSmall() {
        #expect(Set(TextStyle.allCases.map(\.size)) == [12, 13, 15, 20, 24, 44])
    }

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (light, dark) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (light + 0.05) / (dark + 0.05)
    }

    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}
