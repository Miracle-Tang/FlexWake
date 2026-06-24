import Foundation
import SwiftUI
import Combine
import UserNotifications

struct HolidayManager {
    static let shared = HolidayManager()

    private let calendar: Calendar
    private let holidayDates: Set<String>
    private let makeupDates: Set<String>

    init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        self.calendar = cal

        self.holidayDates = Set([
            "2026-01-01", "2026-01-02", "2026-01-03",
            "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19", "2026-02-20", "2026-02-21", "2026-02-22",
            "2026-04-03", "2026-04-04", "2026-04-05",
            "2026-05-01", "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05",
            "2026-06-19", "2026-06-20", "2026-06-21",
            "2026-09-27", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07"
        ])
        self.makeupDates = Set([
            "2026-02-08", "2026-02-15",
            "2026-04-06",
            "2026-05-09",
            "2026-06-14",
            "2026-09-26",
            "2026-10-10"
        ])
    }

    func checkDayType(date: Date, customDates: [CustomDateItem] = []) -> DayKind {
        let key = formatKey(date)
        if let custom = customDates.first(where: { formatKey($0.date) == key }) {
            return custom.kind == .holiday ? .officialHoliday : .makeupWorkday
        }
        if holidayDates.contains(key) { return .officialHoliday }
        if makeupDates.contains(key) { return .makeupWorkday }
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? .normalWeekend : .normalWorkday
    }

    func nextRingDate(for alarm: AlarmModel, customDates: [CustomDateItem] = []) -> Date? {
        guard alarm.isEnabled else { return nil }
        let calendar = configuredCalendar()
        let now = Date()
        for dayOffset in 0..<45 {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            guard alarm.shouldRing(on: candidateDay, customDates: customDates) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            components.hour = alarm.hour
            components.minute = alarm.minute
            guard let candidate = calendar.date(from: components), candidate >= now else { continue }
            return candidate
        }
        return nil
    }

    func dayDescription(for date: Date, customDates: [CustomDateItem] = []) -> String {
        switch checkDayType(date: date, customDates: customDates) {
        case .officialHoliday: return "法定放假，不响铃"
        case .makeupWorkday: return "调休补班，正常响铃"
        case .normalWorkday: return "常规工作日，正常响铃"
        case .normalWeekend: return "常规周末，不响铃"
        }
    }

    func allPresetRules() -> [HolidayRule] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let holidays = holidayDates.compactMap { formatter.date(from: $0) }.map { HolidayRule(date: $0, kind: .officialHoliday, note: "法定放假") }
        let makeup = makeupDates.compactMap { formatter.date(from: $0) }.map { HolidayRule(date: $0, kind: .makeupWorkday, note: "调休补班") }
        return (holidays + makeup).sorted { $0.date < $1.date }
    }

    private func configuredCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }

    private func formatKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

final class CustomDateStore: ObservableObject {
    @Published var items: [CustomDateItem] { didSet { save() } }

    private let storageKey = "custom_dates_store_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? decoder.decode([CustomDateItem].self, from: data) {
            self.items = decoded
        } else { self.items = [] }
    }

    func add(date: Date, kind: CustomDateKind) {
        let normalized = Calendar.current.startOfDay(for: date)
        guard !items.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: normalized) }) else { return }
        items.append(CustomDateItem(date: normalized, kind: kind))
        items.sort { $0.date < $1.date }
    }

    func remove(at offsets: IndexSet) { items.remove(atOffsets: offsets) }

    private func save() {
        if let data = try? encoder.encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

final class AlarmStore: ObservableObject {
    @Published var alarms: [AlarmModel] { didSet { save() } }

    private let storageKey = "alarm_store_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? decoder.decode([AlarmModel].self, from: data) {
            self.alarms = decoded
        } else {
            self.alarms = [AlarmModel(hour: 6, minute: 55, isEnabled: true, repeatMode: .fiveHalfDaysTiaoxiu, title: "起床闹钟")]
        }
    }

    func add(_ alarm: AlarmModel) {
        alarms.append(alarm)
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    func delete(at offsets: IndexSet) { alarms.remove(atOffsets: offsets) }

    private func save() {
        if let data = try? encoder.encode(alarms) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

final class NotificationManager {
    static let shared = NotificationManager()

    func requestAuthorization() async -> Bool {
        do { return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) }
        catch { return false }
    }

    func refreshSchedules(from alarms: [AlarmModel], customDates: [CustomDateItem]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        alarms.filter { $0.isEnabled }.forEach { scheduleSmartNotifications(for: $0, customDates: customDates) }
    }

    private func scheduleSmartNotifications(for alarm: AlarmModel, customDates: [CustomDateItem]) {
        let calendar = configuredCalendar()
        let now = Date()
        for dayOffset in 0..<45 {
            guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            guard alarm.shouldRing(on: targetDate, customDates: customDates) else { continue }
            var components = calendar.dateComponents([.year, .month, .day], from: targetDate)
            components.hour = alarm.hour
            components.minute = alarm.minute
            guard let fireDate = calendar.date(from: components), fireDate >= now else { continue }
            let content = UNMutableNotificationContent()
            content.title = alarm.title
            content.body = HolidayManager.shared.dayDescription(for: targetDate, customDates: customDates)
            content.sound = .default
            let identifier = "\(alarm.id.uuidString)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func configuredCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }
}
