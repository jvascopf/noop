import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Foreground presentation delegate for the app's local notifications (wind-down nudge, smart-alarm
/// backup, battery/illness alerts).
///
/// Without a `UNUserNotificationCenterDelegate`, iOS/macOS suppress a notification's banner while the
/// app is in the FOREGROUND (the default). A user testing a reminder with the app open would see
/// nothing and conclude notifications are broken. Returning banner + sound + list here makes them
/// visible whether the app is open or not — matching what the user expects from a reminder.
///
/// Cross-platform (iOS + macOS). Register once at launch:
/// `UNUserNotificationCenter.current().delegate = NotificationPresenter.shared`.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationPresenter()

    private override init() { super.init() }

    /// K5: wired by the app root (`StrandApp` on macOS, `StrandiOSApp` on iOS) at launch to route a
    /// tapped scheduled morning-brief notification to the Coach screen via `NavRouter.openCoach()`. nil
    /// is a safe no-op (the tap is simply not routed) rather than a crash if this ever fires before the
    /// root has wired it.
    var onCoachBriefTapped: (() -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // The silent "strap not synced" reminder stays silent with NOOP open: into the list, no banner.
        if notification.request.identifier == SyncReminderPolicy.identifier {
            completionHandler([.list])
            return
        }
        completionHandler([.banner, .sound, .list])
    }

    /// Handle a tap on a delivered notification. Only the scheduled morning-brief category (K5) routes
    /// anywhere; every other notification (wind-down, smart-alarm, battery/illness) just opens the app
    /// to wherever it was, matching the pre-K5 behaviour.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.categoryIdentifier == CoachBriefScheduler.notificationCategoryId {
            onCoachBriefTapped?()
        }
        completionHandler()
    }

    /// Deep-link to the OS notification settings so a user who denied can flip it back on — the
    /// system permission dialog only appears once, so Settings is the only recovery path. Shared by
    /// every "Notifications are off" recovery alert (SmartAlarmView's wind-down nudge, Automations'
    /// battery alerts) so the platform-specific URL lives in exactly one place.
    static func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
