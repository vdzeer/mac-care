import AppKit
import CareCore
import Foundation
import Observation

/// What the Mac Security screen knows.
@Observable final class MacModel {
    private(set) var checks: [SecurityCheck] = []
    private(set) var isLoading = false
    private let runner: any CommandRunning
    private var isPreview = false

    init(runner: any CommandRunning) {
        self.runner = runner
    }

    func setPreview(_ checks: [SecurityCheck]) {
        self.checks = checks
        isPreview = true
    }

    var attention: [SecurityCheck] { checks.filter { $0.state == .attention } }
    var okCount: Int { checks.filter { $0.state == .ok }.count }

    func refresh() async {
        guard isLoading == false, isPreview == false else { return }
        isLoading = true
        checks = SecurityChecks.evaluate(await SecurityChecks.collect(runner: runner))
        isLoading = false
    }

    func openSettings(for check: SecurityCheck) {
        if let url = check.settingsURL { NSWorkspace.shared.open(url) }
    }
}
