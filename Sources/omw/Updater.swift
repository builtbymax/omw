import AppKit
import Sparkle

/// Sparkle auto-updates. Only active in builds whose Info.plist has a feed URL and an EdDSA public key,
/// so local dev builds never check for updates.
@MainActor
final class Updater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?

    /// Version of an update a scheduled check found, shown in the menu until the user acts on it.
    @Published private(set) var pendingVersion: String?
    /// The launcher's update banner stays hidden for this version once dismissed.
    @Published private var dismissedVersion = UserDefaults.standard.string(forKey: "dismissedUpdateVersion")

    /// Pending version the launcher should still remind about.
    var reminderVersion: String? { pendingVersion == dismissedVersion ? nil : pendingVersion }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func start() {
        // For trying the update banner without a real release: defaults write <bundle id> debugPendingUpdate 9.9.9
        pendingVersion = UserDefaults.standard.string(forKey: "debugPendingUpdate")
        let info = Bundle.main.infoDictionary ?? [:]
        guard let feed = info["SUFeedURL"] as? String, !feed.isEmpty,
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func checkForUpdates() {
        // Menu-bar apps are never frontmost on their own, so bring the update window forward.
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func dismissReminder() {
        dismissedVersion = pendingVersion
        UserDefaults.standard.set(pendingVersion, forKey: "dismissedUpdateVersion")
    }

    // MARK: SPUStandardUserDriverDelegate

    // Scheduled checks don't pop a window over the user's work, Sparkle shows a gentle reminder instead.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        guard !state.userInitiated else { return }
        let version = update.displayVersionString
        MainActor.assumeIsolated { pendingVersion = version }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { pendingVersion = nil }
    }
}
