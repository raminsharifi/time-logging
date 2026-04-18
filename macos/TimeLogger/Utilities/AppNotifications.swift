import Foundation

/// Shared notification names used to route keyboard-shortcut actions and
/// cross-view navigation without coupling the sender (menu commands) to the
/// receiver (active view). Keeping these in one place prevents the usual
/// string-key drift between an emitter and a subscriber.
extension Notification.Name {
    static let tlNewTimer = Notification.Name("tl.newTimer")
    static let tlToggleTimer = Notification.Name("tl.toggleTimer")
    static let tlPauseResume = Notification.Name("tl.pauseResume")
    static let tlStopTimer = Notification.Name("tl.stopTimer")
    static let tlNavigateTo = Notification.Name("tl.navigateTo")
}

/// Payload key for `.tlNavigateTo` — the value is a `SidebarItem.rawValue`.
enum NotificationKey {
    static let sidebarItem = "sidebarItem"
}
