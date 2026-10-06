import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let identifiers = ["commute.segment", "commute.arrival"]
    override init() {
        super.init()
        center.delegate = self
    }
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    func denied() async -> Bool { await center.notificationSettings().authorizationStatus == .denied }
    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    func schedule(active: ActiveCommute?, enabled: Bool) async throws {
        cancel()
        guard enabled, let active else { return }
        if let timer = active.timer, timer.phase == .running {
            try await add(id: "commute.segment", date: timer.deadline,
                title: "这一段专注结束了", body: "打开应用确认进度，再开始下一段。")
        }
        try await add(id: "commute.arrival", date: active.cutoff,
            title: "该为到站做准备了", body: "保存进度，收好随身物品。本次计划已进入收尾。")
    }
    private func add(id: String, date: Date, title: String, body: String) async throws {
        guard date.timeIntervalSinceNow > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
