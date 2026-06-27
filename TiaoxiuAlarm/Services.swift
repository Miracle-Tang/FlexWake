import Foundation
import SwiftUI
import Combine
import UserNotifications

// MARK: - 共享工具

/// 统一配置的中国时区日历，避免各处重复创建
func chinaCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    return cal
}

// MARK: - HolidayManager

struct HolidayManager {
    static let shared = HolidayManager()

    private let calendar: Calendar
    private let holidayDates: Set<String>
    private let makeupDates: Set<String>

    /// 缓存的 DateFormatter，避免在循环中反复创建
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

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
        // 周日(1)和周六(7)均为周末
        return (weekday == 1 || weekday == 7) ? .normalWeekend : .normalWorkday
    }

    func nextRingDate(for alarm: AlarmModel, customDates: [CustomDateItem] = []) -> Date? {
        guard alarm.isEnabled else { return nil }
        let cal = chinaCalendar()
        let now = Date()
        for dayOffset in 0..<45 {
            guard let candidateDay = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            guard alarm.shouldRing(on: candidateDay, customDates: customDates) else { continue }
            var components = cal.dateComponents([.year, .month, .day], from: candidateDay)
            components.hour = alarm.hour
            components.minute = alarm.minute
            guard let candidate = cal.date(from: components), candidate >= now else { continue }
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
        let holidays = holidayDates.compactMap { Self.keyFormatter.date(from: $0) }.map { HolidayRule(date: $0, kind: .officialHoliday, note: "法定放假") }
        let makeup = makeupDates.compactMap { Self.keyFormatter.date(from: $0) }.map { HolidayRule(date: $0, kind: .makeupWorkday, note: "调休补班") }
        return (holidays + makeup).sorted { $0.date < $1.date }
    }

    private func formatKey(_ date: Date) -> String {
        Self.keyFormatter.string(from: date)
    }
}

// MARK: - CustomDateStore

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

// MARK: - AlarmStore

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

// MARK: - NotificationManager

final class NotificationManager {
    static let shared = NotificationManager()

    /// iOS 单个 App 最多 64 条待触发本地通知，预留 4 条余量
    private static let maxPendingNotifications = 60

    func requestAuthorization() async -> Bool {
        do { return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) }
        catch { return false }
    }

    func refreshSchedules(from alarms: [AlarmModel], customDates: [CustomDateItem]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        // 收集全部待排通知，按触发时间排序后截取前 N 条，防止超出 iOS 64 条上限
        var allItems: [(fireDate: Date, request: UNNotificationRequest)] = []
        for alarm in alarms where alarm.isEnabled {
            allItems.append(contentsOf: buildNotificationItems(for: alarm, customDates: customDates))
        }
        allItems.sort { $0.fireDate < $1.fireDate }

        for item in allItems.prefix(Self.maxPendingNotifications) {
            center.add(item.request) { error in
                if let error {
                    print("[FlexWake] 通知排程失败: \(error.localizedDescription)")
                }
            }
        }
    }

    private func buildNotificationItems(for alarm: AlarmModel, customDates: [CustomDateItem]) -> [(fireDate: Date, request: UNNotificationRequest)] {
        let calendar = chinaCalendar()
        let now = Date()
        var items: [(fireDate: Date, request: UNNotificationRequest)] = []

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
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            items.append((fireDate: fireDate, request: request))
        }
        return items
    }
}
