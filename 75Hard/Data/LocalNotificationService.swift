import Foundation
import UserNotifications

actor LocalNotificationService: NotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async throws -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge, .provisional]
        return try await center.requestAuthorization(options: options)
    }

    func scheduleNotifications(for attempt: ChallengeAttempt, program: ProgramDefinition, preferences: UserNotificationPreferences) async throws {
        await cancelNotifications(for: attempt.id)

        let calendar = Calendar.current
        let startDate = try attempt.startedOn.date(in: calendar)

        for dayOffset in 0..<program.durationDays {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { continue }

            for schedule in preferences.schedules where schedule.isEnabled {
                var triggerDate = calendar.date(bySettingHour: schedule.time.hour ?? 0, minute: schedule.time.minute ?? 0, second: 0, of: dayDate)!
                triggerDate = calendar.date(byAdding: .day, value: -(schedule.daysBeforeEnd ?? 0), to: triggerDate) ?? triggerDate

                guard triggerDate > Date() else { continue }
                if let quietStart = preferences.quietHoursStart, let quietEnd = preferences.quietHoursEnd {
                    let hour = calendar.component(.hour, from: triggerDate)
                    let startHour = quietStart.hour ?? 22
                    let endHour = quietEnd.hour ?? 7
                    if (startHour > endHour && (hour >= startHour || hour < endHour)) || (hour >= startHour && hour < endHour) {
                        continue
                    }
                }

                let content = UNMutableNotificationContent()
                content.title = notificationTitle(for: schedule.notificationType)
                content.body = notificationBody(for: schedule.notificationType, day: dayOffset + 1)
                content.sound = .default
                content.categoryIdentifier = "DAILY_REMINDER"
                content.userInfo = ["attemptID": attempt.id.uuidString, "type": schedule.notificationType.rawValue, "day": dayOffset + 1]

                let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate), repeats: false)
                let request = UNNotificationRequest(identifier: "\(attempt.id.uuidString)-\(schedule.notificationType.rawValue)-\(dayOffset)", content: content, trigger: trigger)

                try await center.add(request)
            }
        }
    }

    func cancelNotifications(for attemptID: UUID) async {
        let requests = await center.pendingNotificationRequests()
        let toRemove = requests.filter { $0.identifier.contains(attemptID.uuidString) }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    func cancelAllNotifications() async {
        center.removeAllPendingNotificationRequests()
    }

    func getPendingNotifications() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    private func notificationTitle(for type: NotificationType) -> String {
        switch type {
        case .workout1: return "Workout #1 Time!"
        case .workout2: return "Workout #2 Time!"
        case .hydration: return "Stay Hydrated"
        case .reading: return "Reading Time"
        case .diet: return "Diet Check"
        case .progressPhoto: return "Progress Photo"
        case .dailyComplete: return "Complete Your Day"
        case .streakMilestone: return "Streak Milestone!"
        case .challengeEnding: return "Challenge Ending Soon"
        }
    }

    private func notificationBody(for type: NotificationType, day: Int) -> String {
        switch type {
        case .workout1: return "Day \(day): Time for your first 45-minute workout"
        case .workout2: return "Day \(day): Time for your second 45-minute outdoor workout"
        case .hydration: return "Day \(day): Drink water to hit your gallon goal"
        case .reading: return "Day \(day): Read 10 pages of your book"
        case .diet: return "Day \(day): Stick to your diet plan"
        case .progressPhoto: return "Day \(day): Take your daily progress photo"
        case .dailyComplete: return "Day \(day): Review and complete your daily requirements"
        case .streakMilestone: return "Amazing! You've hit a streak milestone"
        case .challengeEnding: return "Only \(75 - day) days left in your challenge!"
        }
    }
}