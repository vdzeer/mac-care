import AppKit
import Sparkle
import SwiftUI

/// Updates from GitHub Releases through Sparkle; the feed and the signing key are in each app's
/// Info.plist. Sparkle looks once a day and downloads a new version in the background. It goes in
/// at once, with the app started again, while the app sits in the menu bar with no window open and
/// nothing under way; otherwise once that is so, or when the app quits.
@Observable
public final class Updates: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var pending: (() -> Void)?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private let isBusy: () -> Bool

    /// `isBusy` is true while the app does something a restart would cut short.
    public init(isBusy: @escaping () -> Bool) {
        self.isBusy = isBusy
        super.init()
        // A build run straight from `swift build` has no Info.plist and so no feed: no updates.
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowsClosed(_:)), name: AppLife.allWindowsClosed, object: nil)
    }

    public var isAvailable: Bool { controller != nil }

    public var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.checksAutomatically) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    public var installsAutomatically: Bool {
        get {
            access(keyPath: \.installsAutomatically)
            return controller?.updater.automaticallyDownloadsUpdates ?? false
        }
        set {
            withMutation(keyPath: \.installsAutomatically) {
                controller?.updater.automaticallyDownloadsUpdates = newValue
            }
        }
    }

    public func checkNow() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    @objc private func windowsClosed(_ notification: Notification) {
        installIfIdle()
    }

    private func installIfIdle() {
        guard let install = pending else { return }
        guard !AppLife.hasOpenWindows, !isBusy() else {
            // Work in the menu bar ends without a window closing: look again later.
            if retry == nil {
                retry = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(600))
                    self?.retry = nil
                    self?.installIfIdle()
                }
            }
            return
        }
        pending = nil
        retry?.cancel()
        retry = nil
        install()
    }

    nonisolated public func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // Sparkle calls its delegate on the main thread.
        nonisolated(unsafe) let install = immediateInstallHandler
        MainActor.assumeIsolated {
            pending = install
            installIfIdle()
        }
        return true
    }
}

/// The words of the updates section, from the app's own Strings.swift.
public struct UpdateWords: Sendable {
    let checkAutomatically: String
    let installAutomatically: String
    let note: String
    let checkNow: String

    public init(checkAutomatically: String, installAutomatically: String, note: String, checkNow: String) {
        self.checkAutomatically = checkAutomatically
        self.installAutomatically = installAutomatically
        self.note = note
        self.checkNow = checkNow
    }
}

/// Settings → updates: the two Sparkle switches and a button to look now. Nothing in a build
/// without a feed.
public struct UpdatesSection: View {
    @Bindable var updates: Updates
    let words: UpdateWords

    public init(updates: Updates, words: UpdateWords) {
        self.updates = updates
        self.words = words
    }

    public var body: some View {
        if updates.isAvailable {
            Section {
                Toggle(words.checkAutomatically, isOn: $updates.checksAutomatically)
                Toggle(words.installAutomatically, isOn: $updates.installsAutomatically)
                    .disabled(!updates.checksAutomatically)
                HStack(spacing: Space.m) {
                    Text(words.note).textStyle(.caption, .muted).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.m)
                    Button(words.checkNow) { updates.checkNow() }
                }
            }
        }
    }
}
