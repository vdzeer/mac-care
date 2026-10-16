import CareCore
import CareUI

/// Every word Ward shows. Title case for buttons and menu items, sentence case for everything
/// else; the apostrophe is ’; no exclamation marks.
enum WardStrings {
    static let appName = "Ward"

    enum Nav {
        static let overview = "Overview"
        static let scan = "Scan"
        static let live = "Live Protection"
        static let mac = "Mac Security"
        static let autostart = "Autostart & Network"
    }

    enum Engine {
        static let database = "Signature database"
        static func updated(_ when: String) -> String { "Updated \(when)" }
        static let noDatabase = "Not downloaded yet"
        static let notInstalled = "Engine not installed"
        static let engine = "ClamAV"
    }

    enum Overview {
        static func attention(_ count: Int) -> String {
            count == 1 ? "1 thing needs attention" : "\(count) things need attention"
        }
        static let allGood = "Everything looks fine"
        static let needsAttention = "Needs attention"
        static let quickScan = "Quick Scan"
        static let fullScan = "Full Scan…"
        static func lastScan(_ when: String, _ outcome: String) -> String { "Last scan \(when), \(outcome)" }
        static let neverScanned = "No scans yet"
        static let nothingFound = "no threats found"
        static func found(_ count: Int) -> String { "found \(count)" }
        static func findings(_ count: Int) -> String { "Found in the last scan: \(count)" }
        static let findingsNote = "Look at each one and decide what to do with it"
        static func newAutostart(_ count: Int) -> String {
            count == 1 ? "1 new item starts with your Mac" : "\(count) new items start with your Mac"
        }
        static let newAutostartNote = "Added since you last looked"
        static let review = "Review"
        static let fix = "Open Settings"
        static let liveOn = "On"
        static let liveOff = "Off"
        static let liveNote = "Checks new files in Downloads, Applications, autostart and external disks"
        static let liveOffNote = "New files are not checked"
        static func macFine(_ ok: Int, of total: Int) -> String { "\(ok) of \(total) fine" }
        static let macNote = "Ward only reads settings. You change them in System Settings"
        static let quarantine = "Quarantine"
        static let quarantineEmpty = "Empty"
        static func quarantined(_ count: Int) -> String { count == 1 ? "1 file" : "\(count) files" }
        static let quarantineNote = "Ward never deletes anything by itself"
        static func more(_ count: Int) -> String { "And \(count) more" }
    }

    enum Scan {
        static let result = "Result"
        static func quarantine(_ count: Int) -> String { "Quarantine · \(count)" }
        static let quick = "Quick"
        static let quickNote = "Downloads and autostart"
        static let quickTime = "A few minutes"
        static let full = "Full"
        static let fullNote = "Home folder and all apps"
        static let fullTime = "Can take an hour"
        static let custom = "Custom"
        static let customNote = "Drop a folder or file here"
        static let customTime = "Or click to choose in Finder"
        static func found(_ count: Int) -> String { "Found: \(count)" }
        static let clean = "No threats found"
        static func summary(_ scope: String, files: Int) -> String {
            "\(scope) scan · \(ByteFormat.grouped(files)) files"
        }
        static func unreadable(_ count: Int) -> String { "Couldn’t read: \(count)." }
        static let allToQuarantine = "Quarantine All"
        static let toQuarantine = "Move to Quarantine"
        static let keep = "Keep"
        static let disable = "Turn Off"
        static let showInFinder = "Show in Finder"
        static let malicious = "Malicious"
        static let suspicious = "Suspicious"
        static let footnote =
            "Malicious means a match in the ClamAV signature database. Suspicious comes from Ward’s own checks and is often an app you built yourself. Ward never deletes anything: a file can come back from quarantine."
        static let neverScanned = "No scans yet"
        static let neverScannedNote = "Choose a kind of scan above. A quick scan takes a few minutes."
        static let updating = "Updating the signature database"
        static let updatingNote = "The first download is about 120 MB."
        static let starting = "Starting the engine"
        static let checking = "Checking"
        static func progress(_ done: Int, of total: Int, files: Int) -> String {
            "Folders: \(done) of \(total). Files: \(ByteFormat.grouped(files))"
        }
        static let stop = "Stop"
        static let noEngineTitle = "The ClamAV engine is not installed"
        static let noEngineNote = "Install it with brew install clamav, then open Ward again."
        static let failed = "The scan failed"
        static let retry = "Try Again"
        static let accessTitle = "No Full Disk Access"
        static let accessNote = "Without it Ward cannot see some folders. You only grant it once."
        static let openSettings = "Open Settings"
        static let quarantineEmpty = "Quarantine is empty"
        static let quarantineEmptyNote = "What you choose to isolate after a scan ends up here."
        static let restore = "Put Back"
        static let deleteForever = "Delete Permanently"
        static func cameFrom(_ path: String) -> String { "Was in \(path)" }
        static let placeTaken = "Another file now sits in the original place."
        static let moveFailed = "Couldn’t move it. Try in Finder."
        static let turnOffFailed = "Couldn’t turn it off."
        static let restoreFailed = "Couldn’t put it back."
        static let deleteFailed = "Couldn’t delete it."

        static func problem(_ problem: ShieldModel.Problem) -> String {
            switch problem {
            case .move: moveFailed
            case .turnOff: turnOffFailed
            case .taken: placeTaken
            case .restore: restoreFailed
            case .delete: deleteFailed
            }
        }

        static func scope(_ scope: ScanScope) -> String {
            switch scope {
            case .quick: quick
            case .full: full
            case .custom: custom
            }
        }

        static func reason(_ reason: Finding.Reason) -> String {
            switch reason {
            case .knownMalware(let signature): "Matches \(signature) in the signature database"
            case .unsignedAutostart: "Starts by itself and has no developer signature"
            case .hiddenAutostart: "Starts by itself from a hidden or temporary folder, with no signature"
            case .scriptAutostart: "Starts by itself and runs a script line that is not in any file"
            case .brokenSignature: "Changed after the developer signed it"
            case .unsignedApp: "App without a developer signature"
            case .notNotarizedApp: "Signed by a developer, but Apple did not check it for malware"
            }
        }
    }

    enum Live {
        static let on = "On"
        static let off = "Off"
        static let watched = "Watched places"
        static let howTitle = "How it works"
        static let how = "A new file is checked a few seconds after it appears. Ward does not stop apps from opening."
        static let events = "Recent events"
        static func checkedToday(_ count: Int) -> String { "Checked today: \(count)" }
        static let noEvents = "No events yet"
        static let noEventsNote = "As soon as a new file appears in one of the places, it shows up here."
        static let offTitle = "Live Protection is off"
        static let offNote = "Turn on the switch at the top and Ward watches for new files while your Mac is on."
        static let clean = "clean"
        static func signed(_ name: String) -> String { "clean, signed by \(name)" }
        static func signedNotNotarized(_ name: String) -> String { "clean, signed by \(name), not notarized" }
        static let notChecked = "not checked"
        static let notCheckedLabel = "Not checked"
        static let didNotStartTitle = "Live Protection didn’t start"
        static let didNotStartNote = "The ClamAV engine did not start. Check that it is installed, then try again."
        static let engineDownTitle = "The engine stopped answering"
        static let engineDownNote =
            "New files are not checked until it answers again. Ward tries to start it every few minutes."
        static let retry = "Try Again"
        static let review = "Review"
        static let startsAtLogin = "Ward starts with your Mac while protection is on."
        static let engineLoad = "The engine keeps its database in memory: about 1 GB."

        static func place(_ place: WatchedPlace) -> String {
            switch place {
            case .downloads: "Downloads"
            case .applications: "Applications"
            case .autostart: "Autostart"
            case .volumes: "External disks and disk images"
            case .desktop: "Desktop"
            }
        }

        static func placeNote(_ place: WatchedPlace) -> String {
            switch place {
            case .downloads: "~/Downloads"
            case .applications: "/Applications and ~/Applications"
            case .autostart: "LaunchAgents and LaunchDaemons"
            case .volumes: "/Volumes"
            case .desktop: "~/Desktop"
            }
        }
    }

    enum Notice {
        static let maliciousTitle = "Malicious file found"
        static let suspiciousTitle = "Suspicious file"
        static func body(_ name: String, _ place: String) -> String {
            "\(name) · \(place). Open Ward to decide."
        }
    }

    enum Mac {
        static let recheck = "Check Again"
        static let fine = "Fine"
        static func outOf(_ total: Int) -> String { "of \(total)" }
        static let readOnly = "Ward only reads settings. You change them in System Settings."
        static let openSettings = "Open Settings"
        static let unknown = "Couldn’t find out"
        static let loading = "Reading the Mac’s settings"
        static func summary(ok: Int, attention: Int) -> String { "Fine: \(ok). Need attention: \(attention)" }

        static func name(_ check: SecurityCheck) -> String {
            let needsAttention = check.state == .attention
            switch check.id {
            case .firewall: return needsAttention ? "Firewall is off" : "Firewall"
            case .securityUpdates:
                return needsAttention ? "Security fixes don’t install themselves" : "Security fixes"
            case .systemUpdates: return needsAttention ? "macOS updates don’t install themselves" : "macOS updates"
            case .fileVault: return needsAttention ? "The disk is not encrypted" : "FileVault disk encryption"
            case .gatekeeper: return needsAttention ? "Gatekeeper is off" : "Gatekeeper"
            case .systemIntegrity:
                return needsAttention ? "System Integrity Protection is off" : "System Integrity Protection"
            case .xprotect: return needsAttention ? "XProtect not found" : "XProtect"
            case .screenLock: return needsAttention ? "The screen asks for no password" : "Screen lock"
            case .autoLogin: return needsAttention ? "Logs in without a password" : "Automatic login"
            case .guestAccount: return needsAttention ? "The guest user is on" : "Guest user"
            case .remoteLogin: return needsAttention ? "Remote Login (SSH) is on" : "Remote Login (SSH)"
            case .screenSharing: return needsAttention ? "Screen Sharing is on" : "Screen Sharing"
            case .fileSharing: return needsAttention ? "File Sharing is on" : "File Sharing"
            }
        }

        static func note(_ check: SecurityCheck) -> String {
            if check.state == .unknown { return unknown }
            let needsAttention = check.state == .attention
            switch check.id {
            case .firewall:
                return needsAttention
                    ? "Apps from the network can connect to this Mac" : "Incoming connections are filtered"
            case .securityUpdates:
                return needsAttention
                    ? "Urgent fixes and the XProtect database wait until you install them" : "Install themselves"
            case .systemUpdates:
                return needsAttention ? "New macOS versions wait until you install them" : "Install themselves"
            case .fileVault:
                return needsAttention
                    ? "Whoever gets the disk can read the files without a password" : "The disk is encrypted"
            case .gatekeeper:
                return needsAttention ? "Any app opens, even an unchecked one" : "Only checked apps open"
            case .systemIntegrity:
                return needsAttention ? "System files can be changed. Turn it on from Recovery" : "On"
            case .xprotect:
                return needsAttention
                    ? "Apple’s built-in protection is missing" : "Database version \(check.detail ?? "")"
            case .screenLock:
                return needsAttention ? "After sleep the Mac opens without a password" : "Password right after sleep"
            case .autoLogin:
                return needsAttention ? "The Mac asks for nothing when it starts" : "Off"
            case .guestAccount:
                return needsAttention ? "Anyone can log in without a password" : "Off"
            case .remoteLogin:
                return needsAttention ? "Anyone on the network can connect with a password" : "Off"
            case .screenSharing:
                return needsAttention ? "The Mac’s screen can be watched from the network" : "Off"
            case .fileSharing:
                return needsAttention
                    ? "The Mac shows up on the network and its folders accept a login with a password" : "Off"
            }
        }
    }

    enum Autostart {
        static func all(_ count: Int) -> String { "All · \(count)" }
        static func new(_ count: Int) -> String { "New · \(count)" }
        static func unsigned(_ count: Int) -> String { "Unsigned · \(count)" }
        static let title = "Starts by itself"
        static let loginItems = "Apps that open when you log in are listed in System Settings."
        static let openLoginItems = "Open Login Items"
        static let signer = "Signed by"
        static let newBadge = "New"
        static let markSeen = "Mark as Seen"
        static let network = "Network now"
        static let networkColumns = "Connections · speed"
        static func listening(_ count: Int) -> String { "Waiting for incoming connections: \(count)" }
        static let networkNote = "Ward shows connections but does not block them."
        static let loading = "Collecting what starts with your Mac"
        static let nothing = "Nothing in this list"
        static let apple = "Apple"
        static let unsignedSigner = "Unsigned"
        static let brokenSigner = "Broken signature"
        static let unknownSigner = "Couldn’t check"
        static let missing = "App not found"
        static let disable = "Turn Off"
        static let enable = "Turn On"
        static let inSettings = "Change in Settings"
        static let off = "off"
        static let failed = "Couldn’t change"

        static func kind(_ kind: AutostartItem.Kind) -> String {
            switch kind {
            case .userAgent: "for you"
            case .globalAgent: "for all users"
            case .daemon: "system service"
            case .loginItem: "opens after you log in"
            case .appService: "background service of an app"
            }
        }

        static func through(_ launcher: String) -> String { "via \(launcher)" }
    }

    enum Menu {
        static let liveOn = "Live Protection is on"
        static let liveOff = "Live Protection is off"
        static let liveDown = "Live Protection can’t check files"
        static func lastScan(_ when: String, found: Int) -> String { "Last scan \(when) · found \(found)" }
        static let neverScanned = "No scans yet"
        static let live = "Live Protection"
        static let quickScan = "Quick Scan"
        static let open = "Open Ward"
        static let settings = "Settings…"
        static let about = "About Ward"
        static let quit = "Quit Ward"
    }

    enum Commands {
        static let quickScan = "Quick Scan"
        static let checkForUpdates = "Check for Updates…"
    }

    enum Permissions {
        static let title = "Before you start"
        static let message = "Ward works without these, but each one lets it see or tell you more."
        static let fullDiskAccess = "Full Disk Access"
        static let fullDiskAccessNote =
            "Lets Ward scan Downloads, Desktop, Mail and the data of other apps. Turn on Ward in the list that opens. If it is not there, click + and choose Ward."
        static let openSettings = "Open System Settings"
        static let notifications = "Notifications"
        static let notificationsNote = "Ward tells you when live protection finds something. macOS asks you once."
        static let allowNotifications = "Allow…"
        static let engine = "Scanning engine"
        static let engineNote =
            "Ward scans with ClamAV from Homebrew. Copy the command, run it in Terminal, and this row turns green."
        static let copyCommand = "Copy Command"
        static let installCommand = "brew install clamav"
        static let allowed = "Allowed"
        static let installed = "Installed"
        static let later = "Not Now"
        static let done = "Done"
    }

    enum Settings {
        static let live = "Live Protection"
        static let liveNote = "Checks new files as they appear. While it is on, Ward starts when you log in."
        static let fullDiskAccess = "Full Disk Access"
        static let fullDiskAccessNote =
            "Without it Ward cannot see the Trash, Downloads, Desktop and the data of other apps."
        static let openPrivacy = "Open Privacy Settings"
        static let engine = "Scanning engine"
        static let engineInstalled = "ClamAV from Homebrew is installed."
        static let engineMissing = "Install ClamAV with brew install clamav, then open Ward again."
        static let updates = UpdateWords(
            checkAutomatically: "Check for Updates Automatically",
            installAutomatically: "Install Updates Automatically",
            note: "Ward looks for a new version on GitHub once a day and installs it when it is not scanning.",
            checkNow: "Check Now")
    }

    enum Soon {
        static let title = "This section is still being built"
        static let message = "It arrives in one of the next builds."
    }
}
