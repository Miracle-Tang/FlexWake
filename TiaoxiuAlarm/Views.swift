import SwiftUI

struct ContentView: View {
    enum Tab: Hashable { case alarms, test, data }

    @StateObject private var customDateStore = CustomDateStore()
    @StateObject private var alarmStore = AlarmStore()
    @State private var selectedTab: Tab = .alarms
    @State private var selectedDate = Date()
    @State private var showingAddAlarm = false
    @State private var editingAlarm: AlarmModel?
    @State private var newHour = 6
    @State private var newMinute = 55
    @State private var newRepeatMode: AlarmModel.RepeatMode = .fiveHalfDaysTiaoxiu
    @State private var newTitle = "起床闹钟"
    @State private var newSnoozeEnabled = true
    @State private var newSnoozeDuration = 9
    @State private var newSoundName = "晨光"
    @State private var newVibrationEnabled = true
    @State private var customDate = Date()
    @State private var customDateKind: CustomDateKind = .holiday
    @State private var bannerMessage: String?
    @State private var notificationEnabled = false
    @State private var lastRefresh = Date()
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearanceMode") private var appearanceMode = 0

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        Group {
            if hasSeenWelcome { mainTabs } else { welcomeView }
        }
        .tint(AppBranding.accent)
        .preferredColorScheme(appearanceMode == 1 ? .light : (appearanceMode == 2 ? .dark : nil))
        .sheet(isPresented: $showingAddAlarm) { alarmEditorView() }
        .sheet(item: $editingAlarm) { alarm in alarmEditorView(existing: alarm) }
        .task {
            notificationEnabled = await NotificationManager.shared.requestAuthorization()
            refreshSchedules()
        }
        .safeAreaInset(edge: .top) {
            if let bannerMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(bannerMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
            }
        }
        .onChange(of: alarmStore.alarms) { _, _ in refreshSchedules() }
        .onChange(of: customDateStore.items) { _, _ in refreshSchedules() }
    }

    private var welcomeView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "alarm.waves.left.and.right.fill")
                .font(.system(size: 60))
                .foregroundStyle(AppBranding.accent)
            Text("FlexWake")
                .font(.largeTitle.bold())
            Text("你的智能调休闹钟")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("法定假期自动静音，补班日自动唤醒。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button { hasSeenWelcome = true } label: {
                Text("开始使用").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            Spacer()
        }
        .padding()
        .background(AppBranding.gradient(for: colorScheme).ignoresSafeArea())
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            alarmsPage.tabItem { Label("我的闹钟", systemImage: "alarm") }.tag(Tab.alarms)
            testPage.tabItem { Label("调休测试", systemImage: "calendar.badge.clock") }.tag(Tab.test)
            dataPage.tabItem { Label("数据中心", systemImage: "tray.full") }.tag(Tab.data)
        }
    }

    private func refreshSchedules() {
        lastRefresh = Date()
        NotificationManager.shared.refreshSchedules(from: alarmStore.alarms, customDates: customDateStore.items)
    }

    private func alarmEditorView(existing alarm: AlarmModel? = nil) -> some View {
        // Bindings 统一读写 newXxx State 变量，通过 onAppear 初始化已有闹钟的值
        let timeBinding = Binding<Date>(
            get: {
                var components = DateComponents()
                components.hour = newHour
                components.minute = newMinute
                return calendar.date(from: components) ?? Date()
            },
            set: { newDate in
                let comps = calendar.dateComponents([.hour, .minute], from: newDate)
                newHour = comps.hour ?? 0
                newMinute = comps.minute ?? 0
            }
        )

        return NavigationStack {
            Form {
                Section("闹钟名称") {
                    TextField("标题", text: $newTitle)
                }
                Section("设定时间") {
                    DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                Section("重复模式") {
                    Picker("", selection: $newRepeatMode) {
                        ForEach(AlarmModel.RepeatMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                Section(header: Text("铃声与提醒"), footer: Text("铃声选项仅作标记，实际推送使用系统默认铃声。振动跟随系统设置。")) {
                    Picker("铃声", selection: $newSoundName) {
                        ForEach(["晨光", "溪流", "鸟鸣", "经典", "微风"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    Toggle("振动", isOn: $newVibrationEnabled)
                    Toggle("稍后提醒", isOn: $newSnoozeEnabled)
                    if newSnoozeEnabled {
                        Stepper(value: $newSnoozeDuration, in: 1...30) {
                            Text("稍后提醒间隔：\(newSnoozeDuration) 分钟")
                        }
                    }
                }
            }
            .navigationTitle(alarm == nil ? "新增闹钟" : "编辑闹钟")
            .onAppear {
                // 编辑已有闹钟时，将其属性同步到 State 变量
                if let alarm {
                    newTitle = alarm.title
                    newHour = alarm.hour
                    newMinute = alarm.minute
                    newRepeatMode = alarm.repeatMode
                    newSnoozeEnabled = alarm.snoozeEnabled
                    newSnoozeDuration = alarm.snoozeDuration
                    newSoundName = alarm.soundName
                    newVibrationEnabled = alarm.vibrationEnabled
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismissEditor() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let newAlarm = AlarmModel(
                            id: alarm?.id ?? UUID(),
                            hour: newHour,
                            minute: newMinute,
                            isEnabled: alarm?.isEnabled ?? true,
                            repeatMode: newRepeatMode,
                            title: newTitle.isEmpty ? "未命名闹钟" : newTitle,
                            snoozeEnabled: newSnoozeEnabled,
                            snoozeDuration: newSnoozeDuration,
                            soundName: newSoundName,
                            vibrationEnabled: newVibrationEnabled
                        )
                        if let alarm, let idx = alarmStore.alarms.firstIndex(where: { $0.id == alarm.id }) {
                            alarmStore.alarms[idx] = newAlarm
                        } else {
                            alarmStore.add(newAlarm)
                        }
                        showBanner(alarm == nil ? "闹钟已添加" : "闹钟已更新")
                        dismissEditor()
                    }
                }
            }
        }
    }

    private func dismissEditor() { showingAddAlarm = false; editingAlarm = nil }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("FlexWake", systemImage: "alarm.fill").font(.title3.weight(.semibold))
                    Text("你的智能调休起床闹钟").font(.title2.bold())
                    Text("法定假期自动静音，补班日自动唤醒。").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sunrise.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                    .padding(14)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Circle())
            }
            
            HStack(spacing: 12) {
                metricPill(title: "闹钟", value: "\(alarmStore.alarms.count)", tint: .primary)
                metricPill(title: "启用", value: "\(alarmStore.alarms.filter { $0.isEnabled }.count)", tint: .green)
                metricPill(title: "自定义日期", value: "\(customDateStore.items.count)", tint: .blue)
            }
            
            // 7-day Timeline Preview
            sevenDayTimeline
            
            // Countdown message
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.checkmark.fill")
                    .foregroundColor(AppBranding.accent)
                    .font(.footnote)
                Text(nextRingMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, -4)
            
            HStack {
                Label(notificationEnabled ? "通知已授权" : "通知未授权", systemImage: notificationEnabled ? "bell.fill" : "bell.slash.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(notificationEnabled ? .green : .orange)
                Spacer()
                Button { showingAddAlarm = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加闹钟")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppBranding.accent)
            }
        }
        .padding()
        .background(AppBranding.cardGradient(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.top, 8)
    }

    private var sevenDayTimeline: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { dayOffset in
                let date = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
                let dayType = HolidayManager.shared.checkDayType(date: date, customDates: customDateStore.items)
                let weekdayLetter = dayOfWeekLetter(for: date)
                let isToday = calendar.isDateInToday(date)
                let isRinging = alarmStore.alarms.contains(where: { $0.shouldRing(on: date, customDates: customDateStore.items) })
                
                VStack(spacing: 4) {
                    Text(weekdayLetter)
                        .font(.caption2.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? AppBranding.accent : .secondary)
                    
                    ZStack {
                        Circle()
                            .fill(isRinging ? AppBranding.accent.opacity(isToday ? 0.2 : 0.08) : Color.primary.opacity(0.03))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: isRinging ? "bell.fill" : "bell.slash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isRinging ? AppBranding.accent : .secondary.opacity(0.5))
                    }
                    
                    ZStack {
                        if dayType == .officialHoliday {
                            Text("休")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 14, height: 14)
                                .background(DayKind.officialHoliday.tint)
                                .clipShape(Circle())
                        } else if dayType == .makeupWorkday {
                            Text("班")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 14, height: 14)
                                .background(DayKind.makeupWorkday.tint)
                                .clipShape(Circle())
                        } else {
                            Color.clear
                                .frame(width: 14, height: 14)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isToday ? Color.primary.opacity(0.04) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isToday ? AppBranding.accent.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
        }
        .padding(6)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var nextRingMessage: String {
        let enabledAlarms = alarmStore.alarms.filter { $0.isEnabled }
        guard !enabledAlarms.isEmpty else { return "所有闹钟均已关闭" }
        
        var soonestDate: Date? = nil
        for alarm in enabledAlarms {
            if let nextRing = HolidayManager.shared.nextRingDate(for: alarm, customDates: customDateStore.items) {
                if let currentSoonest = soonestDate {
                    if nextRing < currentSoonest {
                        soonestDate = nextRing
                    }
                } else {
                    soonestDate = nextRing
                }
            }
        }
        
        guard let targetDate = soonestDate else { return "未来 45 天内没有响铃排程" }
        
        let diff = targetDate.timeIntervalSince(Date())
        if diff <= 0 {
            return "闹钟即将响起"
        }
        
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        
        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "距离下次响铃还有 \(days) 天 \(remainingHours) 小时"
        } else if hours > 0 {
            return "距离下次响铃还有 \(hours) 小时 \(minutes) 分钟"
        } else {
            return "距离下次响铃还有 \(minutes) 分钟"
        }
    }

    private func dayOfWeekLetter(for date: Date) -> String {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
        case 1: return "日"
        case 2: return "一"
        case 3: return "二"
        case 4: return "三"
        case 5: return "四"
        case 6: return "五"
        case 7: return "六"
        default: return ""
        }
    }

    private var alarmsPage: some View {
        NavigationStack {
            List {
                Section {
                    heroCard
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                Section("已配置闹钟") {
                    if alarmStore.alarms.isEmpty { emptyAlarmsState } else {
                        ForEach($alarmStore.alarms) { $alarm in
                            alarmRow(alarm: $alarm)
                                .contentShape(Rectangle())
                                .onTapGesture { editingAlarm = alarm }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        if let idx = alarmStore.alarms.firstIndex(where: { $0.id == alarm.id }) {
                                            alarmStore.delete(at: IndexSet(integer: idx))
                                            showBanner("闹钟已删除")
                                        }
                                    } label: { Label("删除", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBranding.gradient(for: colorScheme).ignoresSafeArea())
            .navigationTitle("我的闹钟")
            .toolbar { Button { showingAddAlarm = true } label: { Image(systemName: "plus") } }
        }
    }

    private func alarmRow(alarm: Binding<AlarmModel>) -> some View {
        let today = Date()
        let shouldRing = alarm.wrappedValue.shouldRing(on: today, customDates: customDateStore.items)
        let nextRing = HolidayManager.shared.nextRingDate(for: alarm.wrappedValue, customDates: customDateStore.items)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(alarm.wrappedValue.title).font(.headline)
                    Text(alarm.wrappedValue.displayTime).font(.system(size: 32, weight: .bold, design: .rounded))
                    Text(alarm.wrappedValue.repeatMode.rawValue).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: alarm.isEnabled).labelsHidden()
            }
            
            HStack(spacing: 8) {
                if alarm.wrappedValue.isEnabled {
                    Label(shouldRing ? "今日会响铃" : "今日自动跳过", systemImage: shouldRing ? "bell.fill" : "bell.slash")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background((shouldRing ? Color.green : Color.secondary).opacity(0.12))
                        .foregroundStyle(shouldRing ? .green : .secondary)
                        .clipShape(Capsule())
                    Text(alarm.wrappedValue.reason(on: today, customDates: customDateStore.items)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("已关闭", systemImage: "bell.slash.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(Capsule())
                    Text("闹钟未启用，不会响铃").font(.caption).foregroundStyle(.secondary)
                }
            }
            
            if alarm.wrappedValue.isEnabled {
                HStack(spacing: 12) {
                    Label(alarm.wrappedValue.soundName, systemImage: "music.note")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if alarm.wrappedValue.snoozeEnabled {
                        Label("稍后提醒 (\(alarm.wrappedValue.snoozeDuration)分)", systemImage: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    if alarm.wrappedValue.vibrationEnabled {
                        Label("振动", systemImage: "waveform.path")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, -4)
            }
            
            if alarm.wrappedValue.isEnabled, let nextRing {
                Label("下次响铃：\(formattedDate(nextRing))", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .opacity(alarm.wrappedValue.isEnabled ? 1.0 : 0.6)
    }

    private var emptyAlarmsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "alarm").font(.largeTitle).foregroundStyle(.secondary)
            Text("还没有闹钟").font(.headline)
            Text("先添加一个 06:55 起床闹钟，再逐步补全你的工作日规则。").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("立即添加") { showingAddAlarm = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var testPage: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("验证某一天会不会响").font(.headline)
                        Text("用于快速检查节假日、补班和自定义规则是否生效。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    CustomCalendarView(selectedDate: $selectedDate, customDates: customDateStore.items)
                        .padding(.horizontal)
                    let dayType = HolidayManager.shared.checkDayType(date: selectedDate, customDates: customDateStore.items)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(formattedDate(selectedDate)).font(.headline)
                            Spacer()
                            Text(dayType.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(dayType.tint.opacity(0.12))
                                .foregroundStyle(dayType.tint)
                                .clipShape(Capsule())
                        }
                        Text(HolidayManager.shared.dayDescription(for: selectedDate, customDates: customDateStore.items))
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("闹钟判定").font(.headline).padding(.horizontal)
                        if alarmStore.alarms.isEmpty {
                            emptyAlarmResultState.padding(.horizontal)
                        } else {
                            ForEach(alarmStore.alarms) { alarm in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(alarm.title).font(.headline)
                                        Spacer()
                                        Text(alarm.shouldRing(on: selectedDate, customDates: customDateStore.items) ? "会响铃" : "不响铃")
                                            .fontWeight(.semibold)
                                            .foregroundStyle(alarm.shouldRing(on: selectedDate, customDates: customDateStore.items) ? .green : .red)
                                    }
                                    Text(alarm.reason(on: selectedDate, customDates: customDateStore.items))
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .background(AppBranding.gradient(for: colorScheme).ignoresSafeArea())
            .navigationTitle("调休测试")
        }
    }

    private var emptyAlarmResultState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark").font(.title2).foregroundStyle(.secondary)
            Text("没有可测试的闹钟").font(.subheadline.weight(.semibold))
            Text("先去“我的闹钟”添加一个闹钟，再回来验证。")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var dataPage: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("规则中心").font(.headline)
                        Text("内置官方节假日 + 你的自定义日期，最终决定当天是否响铃。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section("2026 内置放假与补班") {
                    ForEach(HolidayManager.shared.allPresetRules()) { rule in
                        ruleRow(date: rule.date, title: rule.note, tint: rule.kind.tint)
                    }
                }
                Section(header: Text("自定义日期"), footer: Text("自定义日期优先于内置规则，适合公司临时通知或个人特殊安排。")) {
                    DatePicker("日期", selection: $customDate, displayedComponents: .date)
                    Picker("类型", selection: $customDateKind) {
                        ForEach(CustomDateKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button {
                        let exists = customDateStore.items.contains { calendar.isDate($0.date, inSameDayAs: customDate) }
                        guard !exists else { return }
                        customDateStore.add(date: customDate, kind: customDateKind)
                        showBanner("已添加自定义日期")
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("添加自定义日期")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppBranding.accent)
                    .disabled(customDateStore.items.contains { calendar.isDate($0.date, inSameDayAs: customDate) })
                    if customDateStore.items.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.plus").font(.title2).foregroundStyle(.secondary)
                            Text("还没有自定义日期").font(.subheadline.weight(.semibold))
                            Text("可以把临时放假或补班直接加入规则库。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        ForEach(customDateStore.items) { item in
                            customDateRow(item)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        if let index = customDateStore.items.firstIndex(where: { $0.id == item.id }) {
                                            customDateStore.remove(at: IndexSet(integer: index))
                                            showBanner("已删除自定义日期")
                                        }
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                Section("外观设置") {
                    Picker("外观模式", selection: $appearanceMode) {
                        Text("跟随系统").tag(0)
                        Text("浅色模式").tag(1)
                        Text("深色模式").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                Section("系统通知权限") {
                    HStack {
                        Label(notificationEnabled ? "通知授权状态" : "未获得通知授权", systemImage: notificationEnabled ? "bell.badge.fill" : "bell.slash.fill")
                            .foregroundStyle(notificationEnabled ? .green : .orange)
                        Spacer()
                        Text(notificationEnabled ? "已开启" : "去设置")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("开启通知权限后，FlexWake 才能根据最新的调休规则为您精准安排晨间唤醒。我们尊重您的隐私，本应用绝对不会在后台收集或上传您的任何个人行为数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("响铃排程状态") {
                    Label("已更新于 \(formattedDate(lastRefresh))", systemImage: "arrow.clockwise")
                    Text("系统已根据内置的官方日历与您的自定义规则，为您预先编排了未来 45 天内的闹钟通知。每次您打开应用，都会自动在后台重新对排程进行对齐与更新。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBranding.gradient(for: colorScheme).ignoresSafeArea())
            .navigationTitle("数据中心")
        }
    }

    private func ruleRow(date: Date, title: String, tint: Color) -> some View {
        HStack {
            Label(formattedDate(date), systemImage: "calendar")
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.12))
                .foregroundStyle(tint)
                .clipShape(Capsule())
        }
    }

    private func customDateRow(_ item: CustomDateItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate(item.date)).font(.body.weight(.medium))
                Text(item.kind.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.kind == .holiday ? "不响铃" : "响铃")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(item.kind.tint.opacity(0.12))
                .foregroundStyle(item.kind.tint)
                .clipShape(Capsule())
        }
    }

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateStyle = .medium
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private func formattedDate(_ date: Date) -> String {
        Self.displayFormatter.string(from: date)
    }

    private func metricPill(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .clipShape(Capsule())
    }

    private func showBanner(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            bannerMessage = message
        }
        
        let currentMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if bannerMessage == currentMessage {
                withAnimation(.easeInOut(duration: 0.25)) {
                    bannerMessage = nil
                }
            }
        }
    }
}

struct CustomCalendarView: View {
    @Binding var selectedDate: Date
    var customDates: [CustomDateItem]
    
    @State private var currentMonthStart: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()
    
    @Environment(\.colorScheme) private var colorScheme
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 14) {
            // Month Header
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundColor(AppBranding.accent)
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Circle())
                }
                Spacer()
                Text(monthYearString(from: currentMonthStart))
                    .font(.headline.weight(.bold))
                Spacer()
                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundColor(AppBranding.accent)
                        .padding(8)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 4)
            
            // Weekday Headers
            HStack(spacing: 0) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
                    Text(day)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Days Grid
            let days = generateDaysForMonth(currentMonthStart)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(days, id: \.self) { date in
                    let isCurrentMonth = calendar.isDate(date, equalTo: currentMonthStart, toGranularity: .month)
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    let isToday = calendar.isDateInToday(date)
                    let dayKind = HolidayManager.shared.checkDayType(date: date, customDates: customDates)
                    
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(isSelected ? AppBranding.accent : (isToday ? AppBranding.accent.opacity(0.15) : Color.clear))
                                .frame(width: 32, height: 32)
                            
                            Text("\(calendar.component(.day, from: date))")
                                .font(.system(size: 15, weight: isSelected || isToday ? .bold : .regular))
                                .foregroundStyle(isSelected ? .white : (isCurrentMonth ? .primary : .secondary.opacity(0.35)))
                        }
                        
                        // Holiday/Workday badge
                        ZStack {
                            if dayKind == .officialHoliday {
                                Text("休")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 14, height: 14)
                                    .background(DayKind.officialHoliday.tint)
                                    .clipShape(Circle())
                            } else if dayKind == .makeupWorkday {
                                Text("班")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 14, height: 14)
                                    .background(DayKind.makeupWorkday.tint)
                                    .clipShape(Circle())
                            } else {
                                Color.clear
                                    .frame(width: 14, height: 14)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDate = date
                    }
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    
    private func changeMonth(by value: Int) {
        if let nextMonth = calendar.date(byAdding: .month, value: value, to: currentMonthStart) {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentMonthStart = nextMonth
            }
        }
    }
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年 M月"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
    
    private func generateDaysForMonth(_ monthStart: Date) -> [Date] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: monthStart),
              let firstDayOfWeek = calendar.dateComponents([.weekday], from: monthStart).weekday else {
            return []
        }
        
        var days: [Date] = []
        
        // Days from previous month
        let daysBefore = firstDayOfWeek - 1
        if daysBefore > 0 {
            for i in (1...daysBefore).reversed() {
                if let date = calendar.date(byAdding: .day, value: -i, to: monthStart) {
                    days.append(date)
                }
            }
        }
        
        // Days of current month
        for i in 0..<monthRange.count {
            if let date = calendar.date(byAdding: .day, value: i, to: monthStart) {
                days.append(date)
            }
        }
        
        // Days from next month to pad the grid to multiples of 7
        let totalCells = days.count
        let remainingCells = (7 - (totalCells % 7)) % 7
        if remainingCells > 0 {
            if let lastDay = days.last {
                for i in 1...remainingCells {
                    if let date = calendar.date(byAdding: .day, value: i, to: lastDay) {
                        days.append(date)
                    }
                }
            }
        }
        
        return days
    }
}
