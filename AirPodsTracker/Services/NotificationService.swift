import Foundation
import UserNotifications
import Combine

@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()
    @Published private(set) var errorMessage: String?
    private let center = UNUserNotificationCenter.current()
    private let prefix = "airpodstracker.review."
    private var operation: Task<Void, Never>?

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            errorMessage = granted ? nil : "系统通知未开启；自动记录和手动补录仍可使用。"
            return granted
        } catch {
            errorMessage = "无法请求通知权限：\(error.localizedDescription)"
            return false
        }
    }

    func authorizationAllowed() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func scheduleReview(deviceID: UUID, start: Date) {
        enqueue { [self] in
            guard UserDefaults.standard.bool(forKey: "reviewRemindersEnabled") else { return }
            guard await authorizationAllowed() else {
                errorMessage = "系统通知未开启；本次未安排核对提醒。"
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "核对耳机连接记录"
            content.body = "这段记录可能缺少结束时间。打开 App 查看并核对；此提醒不能证明耳机仍在连接或佩戴。"
            content.sound = .default
            content.userInfo = ["deviceID": deviceID.uuidString]
            let fireDate = start.addingTimeInterval(12 * 60 * 60 + 60)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireDate.timeIntervalSinceNow), repeats: false)
            let request = UNNotificationRequest(identifier: identifier(deviceID), content: content, trigger: trigger)
            do {
                try await center.add(request)
                errorMessage = nil
            } catch {
                errorMessage = "未能安排核对提醒：\(error.localizedDescription)"
            }
        }
    }

    func cancelPending(deviceID: UUID) {
        enqueue { [self] in
            center.removePendingNotificationRequests(withIdentifiers: [identifier(deviceID)])
            center.removeDeliveredNotifications(withIdentifiers: [identifier(deviceID)])
        }
    }

    func cancelPending() {
        enqueue { [self] in
            let requests = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
    }

    func awaitPendingOperations() async {
        await operation?.value
    }

    private func identifier(_ deviceID: UUID) -> String { prefix + deviceID.uuidString }

    // Keep start/end requests ordered even when notification-center operations suspend.
    private func enqueue(_ action: @escaping @MainActor () async -> Void) {
        let previous = operation
        operation = Task { @MainActor in
            await previous?.value
            await action()
        }
    }
}
