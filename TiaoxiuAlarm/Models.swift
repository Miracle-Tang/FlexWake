import SwiftUI
import Combine

struct HolidayRule: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let kind: DayKind
    let note: String
}

enum DayKind: String {
    case officialHoliday = "法定放假"
    case makeupWorkday = "调休补班"
    case normalWorkday = "常规工作日"
    case normalWeekend = "常规双休日"

    var tint: Color {
        switch self {
        case .officialHoliday: return Color(red: 255/255, green: 90/255, blue: 95/255)     // 柔和珊瑚红
        case .makeupWorkday: return Color(red: 0/255, green: 168/255, blue: 204/255)       // 高雅湖蓝色
        case .normalWorkday: return Color(red: 76/255, green: 185/255, blue: 143/255)      // 翠绿色
        case .normalWeekend: return Color(red: 142/255, green: 147/255, blue: 160/255)     // 烟灰色
        }
    }
}

enum CustomDateKind: String, CaseIterable, Identifiable, Codable {
    case holiday = "自定义放假"
    case workday = "自定义补班"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .holiday: return Color(red: 255/255, green: 90/255, blue: 95/255)
        case .workday: return Color(red: 0/255, green: 168/255, blue: 204/255)
        }
    }

    var symbolName: String {
        switch self {
        case .holiday: return "calendar.badge.minus"
        case .workday: return "calendar.badge.plus"
        }
    }
}

struct CustomDateItem: Identifiable, Hashable, Codable {
    var id = UUID()
    var date: Date
    var kind: CustomDateKind
}

struct AlarmModel: Identifiable, Hashable, Codable {
    enum RepeatMode: String, CaseIterable, Identifiable, Codable {
        case fiveDaysTiaoxiu = "5天 + 智能调休"
        case fiveHalfDaysTiaoxiu = "5.5天 + 智能调休"
        case sixDaysTiaoxiu = "6天 + 智能调休"
        case everyday = "每天"
        var id: String { rawValue }
    }

    var id = UUID()
    var hour: Int
    var minute: Int
    var isEnabled: Bool
    var repeatMode: RepeatMode
    var title: String = "起床闹钟"
    var snoozeEnabled: Bool = true
    var snoozeDuration: Int = 9
    var soundName: String = "晨光"
    var vibrationEnabled: Bool = true

    var displayTime: String { String(format: "%02d:%02d", hour, minute) }

    enum CodingKeys: String, CodingKey {
        case id, hour, minute, isEnabled, repeatMode, title
        case snoozeEnabled, snoozeDuration, soundName, vibrationEnabled
    }

    init(id: UUID = UUID(), hour: Int, minute: Int, isEnabled: Bool, repeatMode: RepeatMode, title: String = "起床闹钟", snoozeEnabled: Bool = true, snoozeDuration: Int = 9, soundName: String = "晨光", vibrationEnabled: Bool = true) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.isEnabled = isEnabled
        self.repeatMode = repeatMode
        self.title = title
        self.snoozeEnabled = snoozeEnabled
        self.snoozeDuration = snoozeDuration
        self.soundName = soundName
        self.vibrationEnabled = vibrationEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        hour = try container.decode(Int.self, forKey: .hour)
        minute = try container.decode(Int.self, forKey: .minute)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        repeatMode = try container.decode(RepeatMode.self, forKey: .repeatMode)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "起床闹钟"
        snoozeEnabled = try container.decodeIfPresent(Bool.self, forKey: .snoozeEnabled) ?? true
        snoozeDuration = try container.decodeIfPresent(Int.self, forKey: .snoozeDuration) ?? 9
        soundName = try container.decodeIfPresent(String.self, forKey: .soundName) ?? "晨光"
        vibrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .vibrationEnabled) ?? true
    }

    func shouldRing(on date: Date, customDates: [CustomDateItem] = []) -> Bool {
        guard isEnabled else { return false }
        
        // 1. Check custom overrides
        let calendar = chinaCalendar()
        if let custom = customDates.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            return custom.kind == .workday
        }
        
        // 2. Check preset official holiday/makeup status
        let presetType = HolidayManager.shared.checkDayType(date: date, customDates: [])
        if presetType == .officialHoliday {
            return false // Skip official holiday
        }
        if presetType == .makeupWorkday {
            return true // Ring on makeup workday
        }
        
        // 3. Regular week-based schedule
        let weekday = calendar.component(.weekday, from: date)
        switch repeatMode {
        case .everyday:
            return true
        case .fiveDaysTiaoxiu:
            return weekday >= 2 && weekday <= 6 // Mon-Fri
        case .fiveHalfDaysTiaoxiu, .sixDaysTiaoxiu:
            return weekday != 1 // Mon-Sat
        }
    }

    func reason(on date: Date, customDates: [CustomDateItem] = []) -> String {
        guard isEnabled else { return "已关闭" }
        let dayType = HolidayManager.shared.checkDayType(date: date, customDates: customDates)
        let ring = shouldRing(on: date, customDates: customDates)
        switch (dayType, ring) {
        case (.officialHoliday, false): return "已自动跳过节假日"
        case (.makeupWorkday, true): return "调休补班，已唤醒"
        case (.normalWorkday, true): return "正常工作日，会响铃"
        case (.normalWeekend, false): return "常规周末，不响铃"
        case (.normalWeekend, true): return "工作日（含周六），会响铃"
        default: return ring ? "会响铃" : "不会响铃"
        }
    }
}
