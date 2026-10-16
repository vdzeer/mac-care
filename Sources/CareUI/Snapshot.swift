import AppKit
import SwiftUI

/// Draws a view into a PNG without showing a window. Used to check screens against the mockup,
/// in both appearances.
public enum SnapshotRenderer {
    public static func write<V: View>(_ view: V, size: CGSize, accent: Accent, dark: Bool, to url: URL) throws {
        let root =
            view
            .frame(width: size.width, height: size.height)
            .environment(\.accent, accent)
            .environment(\.colorScheme, dark ? .dark : .light)
            .tint(accent.primary.color)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = host.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // A few turns of the run loop let lists, images and text settle.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
