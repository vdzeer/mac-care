import CareCore
import CareUI

/// Every word Tidy shows. Title case for buttons and menu items, sentence case for everything
/// else; the apostrophe is ’; no exclamation marks.
enum TidyStrings {
    static let appName = "Tidy"

    enum Nav {
        static let overview = "Overview"
        static let junk = "Junk"
        static let apps = "Apps"
        static let space = "Space"
        static let speed = "Speed"
    }

    enum Disk {
        static func free(_ free: String, of total: String) -> String { "\(free) free of \(total)" }
    }

    enum Overview {
        static let canRemove = "Can be removed"
        static let counting = "Counting what can be removed"
        static let clean = "Clean Up…"
        static let recount = "Count Again"
        static let countedJustNow = "Counted just now"
        static let explanation =
            "Caches and build leftovers. Apps make them again when they need them. Your files stay where they are."
        static let seeList = "Review List"
        static let nothingToRemove = "Nothing to remove"
        static func apps(_ count: Int) -> String { "\(count) installed" }
        static let appsNote = "Uninstall with every leftover"
        static func space(_ used: String) -> String { "\(used) used" }
        static let spaceNote = "Disk map, large files, duplicates"
        static func speed(_ count: Int) -> String { "\(count) at login" }
        static let speedNote = "Memory, CPU, what starts with your Mac"
    }

    enum Category {
        static func name(_ category: JunkCategory) -> String {
            switch category {
            case .xcode: "Xcode"
            case .build: "Build caches"
            case .apps: "App caches and logs"
            }
        }
    }

    enum Junk {
        static let selected = "Selected"
        static let clean = "Clean Up…"
        static let regenerates = "Regenerates"
        static let regeneratesNote = "Selected in advance"
        static let review = "Your call"
        static let reviewNote = "You decide"
        static let neverOfferedTitle = "Never offered"
        static let neverOffered =
            "Documents, photos, mail, keychains, git repositories and Docker data are in no list."
        static let journal = "Journal"
        static let journalNote = "What was removed, how much and when"
        static let open = "Open"
        static let measuring = "Counting"
        static let empty = "Nothing here"
        static let closeToClean = "Quit the app that uses it first"
        static func unavailable(_ runtime: String) -> String { "\(runtime) · unavailable" }
        static func skipped(_ count: Int) -> String { "Skipped because the app is open: \(count)" }
        static func more(_ count: Int) -> String { "And \(count) more" }
        static func lastUsed(_ build: String, _ when: String) -> String { "\(build) · used \(when)" }
        static func neverUsed(_ build: String) -> String { "\(build) · never used" }
        static func expand(_ name: String) -> String { "Show contents: \(name)" }

        static func name(_ rule: JunkRule.ID) -> String {
            switch rule {
            case .derivedData: "Xcode DerivedData"
            case .gradle: "Gradle"
            case .appCaches: "App caches"
            case .npm: "npm"
            case .deviceSupport: "iOS DeviceSupport"
            case .cocoaPods: "CocoaPods"
            case .yarn: "yarn"
            case .homebrew: "Homebrew"
            case .logs: "Logs"
            case .simulators: "iOS Simulators"
            case .simulatorRuntimes: "iOS Simulator runtimes"
            case .appDataCaches: "Caches in app data"
            case .wallpaperVideos: "Wallpaper videos"
            case .androidNDK: "Android NDK"
            case .androidImages: "Android system images"
            case .nuget: "NuGet"
            case .xcodeCaches: "Simulator caches"
            case .cliCaches: "Command-line tool caches"
            case .testBrowsers: "Test browsers"
            case .jetBrainsCaches: "JetBrains caches"
            case .trash: "Trash"
            case .androidDevices: "Android emulators"
            case .xcodeArchives: "Xcode archives"
            }
        }

        static func note(_ rule: JunkRule.ID) -> String {
            switch rule {
            case .derivedData: "Intermediate build files"
            case .gradle: "Android build dependencies"
            case .appCaches: "Temporary files apps make again"
            case .npm, .yarn: "Downloaded packages"
            case .deviceSupport: "Symbols for old iOS versions"
            case .cocoaPods: "Downloaded libraries"
            case .homebrew: "Old installers"
            case .logs: "App reports"
            case .simulators: "Devices with their data. Removed permanently"
            case .simulatorRuntimes: "iOS versions for Xcode. It downloads them again"
            case .appDataCaches: "Caches of editors and messengers"
            case .wallpaperVideos: "macOS downloads the ones you pick again"
            case .androidNDK: "Versions of the build tools"
            case .androidImages: "Systems for emulators"
            case .nuget: "Downloaded packages"
            case .xcodeCaches: "Xcode service files"
            case .cliCaches: "The ~/.cache folder. Tools download what they need again"
            case .testBrowsers: "For Playwright and Cypress. Their install command downloads them again"
            case .jetBrainsCaches: "IntelliJ, PyCharm, WebStorm and others rebuild them. Left alone while one is open"
            case .trash: "Emptied. Cannot be brought back"
            case .androidDevices: "Virtual devices. They go to the Trash"
            case .xcodeArchives: "Builds made for the App Store. They go to the Trash"
            }
        }
    }

    enum Confirm {
        static func title(_ size: String) -> String { "Clean up \(size)?" }
        static let regenerates = "Caches are removed at once. Apps make them again."
        static let review =
            "Under Your call, Android emulators and Xcode archives go to the Trash. The rest is removed permanently."
        static let cancel = "Cancel"
        static let confirm = "Clean Up"
    }

    enum Progress {
        static let cleaning = "Cleaning up"
        static func step(_ done: Int, of total: Int) -> String { "Done: \(done) of \(total)" }
    }

    enum Done {
        static let title = "Cleaned up"
        static func problems(_ count: Int) -> String { "Couldn’t remove: \(count)" }
        static let close = "OK"
        static func inTrash(_ size: String) -> String {
            "\(size) went to the Trash. The space comes back when the Trash is emptied."
        }
        static let emptyTrash = "Empty Trash"
        static let emptyTrashTitle = "Empty the Trash?"
        static let emptyTrashNote =
            "Everything in the Trash is removed permanently, not only what Tidy put there. This can’t be undone."
        static let trashOutOfSight =
            "Tidy can’t see inside the Trash. Give it Full Disk Access in System Settings, or empty the Trash in Finder."
    }

    enum JournalSheet {
        static let title = "Journal"
        static let empty = "No entries yet"
        static let emptyNote = "The first entry appears after a cleanup."
        static let close = "Close"
    }

    enum Apps {
        static func installed(_ count: Int) -> String { "Installed · \(count)" }
        static func orphans(_ count: Int) -> String { "Leftovers · \(count)" }
        static let search = "Search"
        static let columnApp = "App"
        static let columnSize = "With leftovers"
        static let columnOrphan = "Left by"
        static let measuring = "Measuring apps"
        static let lookingForOrphans = "Looking for leftovers of removed apps"
        static func lastOpened(_ when: String) -> String { "Last opened \(when)" }
        static let neverOpened = "Not known when it was last opened"
        static func places(_ count: Int) -> String { "Places: \(count)" }
        static let toTrash = "Move to Trash"
        static let toTrashNote = "Everything goes to the Trash. You can put it back from there."
        static let running = "The app is open. Quit it to remove it."
        static let appleNote = "This is an Apple app. Its data in the system stays where it is."
        static let pick = "Choose an app"
        static let pickNote = "Everything it left on the disk appears on the right."
        static let nothingFound = "Nothing found"
        static let noOrphans = "No leftovers"
        static let noOrphansNote = "Everything in Library belongs to installed apps."
        static let orphanNote =
            "A command-line tool may have left this folder too. Check the name before you remove it."
        static func moved(_ size: String) -> String { "Moved to the Trash: \(size)" }
        static func failed(_ count: Int) -> String { "Couldn’t move: \(count). Try in Finder." }
        static let appStayed =
            "The app couldn’t go to the Trash, so its data stayed too. Move the app to the Trash in Finder first."
        static let showInFinder = "Show in Finder"

        static func part(_ kind: LeftoverKind) -> String {
            switch kind {
            case .app: "App"
            case .data: "Data"
            case .caches: "Cache"
            case .logs: "Logs"
            case .preferences: "Preferences"
            case .savedState: "Saved window state"
            case .container: "App container"
            case .webData: "Web data"
            case .scripts: "Scripts"
            case .launchAgent: "Starts by itself"
            }
        }
    }

    enum Space {
        static let map = "Map"
        static let large = "Large Files"
        static let duplicates = "Duplicates"
        static let home = "Home folder"
        static let back = "Back"
        static let pickFolder = "Choose Folder…"
        static let hint = "Click a folder to go inside. A file opens in Finder."
        static let other = "Other"
        static let measuring = "Measuring what takes space"
        static let empty = "Nothing here"
        static let biggestHere = "Biggest here"
        static let lookingForLarge = "Looking for large files"
        static let noLarge = "No large files"
        static let noLargeNote = "None of your folders holds a file over 200 MB."
        static let lookingForDuplicates = "Comparing files"
        static let lookingForDuplicatesNote = "By size first, then by contents. This can take a few minutes."
        static let noDuplicates = "No duplicates"
        static let noDuplicatesNote = "No identical files over 1 MB were found."
        static let scope = "Your folders are checked. Library, hidden folders and the inside of apps are left out."
        static func opened(_ when: String) -> String { "opened \(when)" }
        static func copies(_ count: Int) -> String { "Copies: \(count)" }
        static func wasted(_ size: String) -> String { "extra: \(size)" }
        static let keepOne = "Keep One"
        static func chosen(_ count: Int, _ size: String) -> String { "Chosen: \(count) · \(size)" }
        static let nothingChosen = "Nothing chosen"
        static let toTrash = "Move to Trash"
        static func moved(_ size: String) -> String { "Moved to the Trash: \(size)" }
        static func failed(_ count: Int) -> String { "Couldn’t move: \(count)" }
        static let accessTitle = "No Full Disk Access"
        static let accessNote = "Without it some folders count as empty. You only grant it once."
        static let openSettings = "Open Settings"
    }

    enum System {
        static let tab = "System Data"
        static let measuring = "Measuring System Data"
        static let measuringNote = "These are the places macOS adds up into the System Data line."
        static let recount = "Count Again"
        static func summary(_ total: String, _ cleanable: String) -> String {
            "Found: \(total). Can be removed: \(cleanable)"
        }
        static func cleanable(_ size: String) -> String { "can remove \(size)" }
        static let toJunk = "Go to Junk"
        static let showInFinder = "Show in Finder"
        static let runtimes = "Simulator runtimes"
        static func runtimesNote(_ count: Int) -> String {
            "iOS versions downloaded for Xcode: \(count). Old ones can go"
        }

        static func group(_ group: SystemDataPlace.Group) -> String {
            switch group {
            case .developer: "Development"
            case .apps: "Apps"
            case .system: "System"
            }
        }

        static func title(_ place: SystemDataPlace) -> String {
            switch place.known {
            case .xcode: "Xcode"
            case .androidSDK: "Android SDK"
            case .gradle: "Gradle"
            case .npm: "npm"
            case .yarn: "yarn"
            case .nuget: "NuGet"
            case .androidHome: "Android emulators"
            case .cliCache: "Command-line tool caches"
            case .ollama: "Ollama"
            case .nodeVersions: "Node.js versions"
            case .cocoaPods: "CocoaPods"
            case .homebrew: "Homebrew"
            case .appCaches: "App caches"
            case .wallpapers: "Wallpapers and screen savers"
            case .docker: "Docker"
            case .trash: "Trash"
            case .swap: "Swap and sleep image"
            case .temporary: "Temporary files"
            case .systemLogs: "System logs"
            case .systemDatabases: "macOS service databases"
            case .systemCaches: "System caches"
            case .shared: "Shared folder"
            case .editor, .assistant, .toolData, .hiddenFolder, .appleData, .appData, .container: place.name
            }
        }

        static func note(_ known: SystemDataPlace.Known) -> String {
            switch known {
            case .xcode: "Builds, simulators, device symbols"
            case .androidSDK: "NDK, system images, build tools"
            case .gradle: "Android build dependencies and distributions"
            case .npm, .yarn: "Downloaded JavaScript packages"
            case .nuget: "Downloaded .NET packages"
            case .androidHome: "Virtual devices with their disks"
            case .cliCache: "The ~/.cache folder: caches and downloaded models"
            case .ollama: "Language models. Remove them with ollama rm"
            case .nodeVersions: "Installed with nvm"
            case .cocoaPods: "Index of iOS libraries"
            case .editor: "Extensions and data of a code editor"
            case .assistant: "Data of an AI assistant: settings, history, memory"
            case .toolData: "Data and settings of command-line tools"
            case .homebrew: "Apps installed with Homebrew"
            case .hiddenFolder: "Hidden folder of an app"
            case .appCaches: "Temporary files apps make again"
            case .wallpapers: "Downloaded videos for wallpapers and screen savers"
            case .docker: "Images and volumes. Clean them up in Docker itself"
            case .appleData: "macOS data. The system manages it"
            case .appData: "App data: settings, databases, downloads"
            case .container: "Data of a sandboxed app"
            case .trash: "Deleted files you can still bring back"
            case .swap: "macOS manages it. It shrinks after a restart"
            case .temporary: "Working files of all apps. macOS clears them itself"
            case .systemLogs: "macOS manages them"
            case .systemDatabases: "Indexes, diagnostics, system caches. macOS manages them"
            case .systemCaches: "macOS manages them"
            case .shared: "Every user of this Mac can see it"
            }
        }
    }

    enum Speed {
        static let live = "Updates every two seconds"
        static let startsWithMac = "Starts with your Mac"
        static let loginItems = "Apps that open when you log in are listed in System Settings."
        static let openLoginItems = "Open Login Items"
        static func enabled(_ on: Int, of total: Int) -> String { "On: \(on) of \(total)" }
        static let on = "On"
        static let off = "Off"
        static let inSettings = "In Settings"
        static let loading = "Collecting what starts with your Mac"
        static let cpu = "CPU"
        static let memory = "Memory"
        static let pressure = "Memory pressure"
        static let disk = "Disk"
        static let network = "Network"
        static let download = "Download"
        static let heaviest = "Heaviest now"
        static let heaviestColumns = "CPU · memory"
        static let failed = "Couldn’t change"
        static func of(_ used: String, _ total: String) -> String { "\(used) of \(total)" }
        static func free(_ size: String) -> String { "\(size) free" }
        static func traffic(_ down: String, _ up: String) -> String { "↓ \(down)  ↑ \(up)" }

        static func pressureName(_ pressure: MemoryPressure) -> String {
            switch pressure {
            case .normal: "Low"
            case .warning: "Raised"
            case .critical: "High"
            }
        }

        static func kind(_ kind: AutostartItem.Kind) -> String {
            switch kind {
            case .userAgent, .globalAgent: "Background service"
            case .daemon: "System service · needs an administrator password"
            case .loginItem: "Opens after you log in"
            case .appService: "Background service of an app"
            }
        }
    }

    enum Menu {
        static let updated = "Updated just now"
        static let canRemove = "can be removed safely"
        static let cleanUpNow = "Clean Up Now…"
        static let open = "Open Tidy"
        static let goTo = "Go To"
        static let settings = "Settings…"
        static let about = "About Tidy"
        static let quit = "Quit Tidy"
    }

    enum Commands {
        static let countAgain = "Count Again"
        static let checkForUpdates = "Check for Updates…"
    }

    enum Permissions {
        static let title = "Before you start"
        static let message =
            "Tidy works without this, but then it cannot see part of your disk and says so on the screens that need it."
        static let fullDiskAccess = "Full Disk Access"
        static let fullDiskAccessNote =
            "Lets Tidy see the Trash, Downloads, Desktop and the data of other apps. Turn on Tidy in the list that opens. If it is not there, click + and choose Tidy."
        static let openSettings = "Open System Settings"
        static let allowed = "Allowed"
        static let later = "Not Now"
        static let done = "Done"
    }

    enum Settings {
        static let openAtLogin = "Open at Login"
        static let openAtLoginNote = "Tidy starts in the menu bar when you log in."
        static let fullDiskAccess = "Full Disk Access"
        static let fullDiskAccessNote =
            "Without it Tidy cannot see the Trash, Downloads, Desktop and the data of other apps."
        static let openPrivacy = "Open Privacy Settings"
        static let updates = UpdateWords(
            checkAutomatically: "Check for Updates Automatically",
            installAutomatically: "Install Updates Automatically",
            note: "Tidy looks for a new version on GitHub once a day and installs it when it is not busy.",
            checkNow: "Check Now")
    }
}
