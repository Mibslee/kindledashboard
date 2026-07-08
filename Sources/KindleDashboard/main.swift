import AppKit
import Foundation
import Network
import UniformTypeIdentifiers

enum KindleMode: String, CaseIterable, Identifiable {
    case home
    case codex
    case document
    case image
    case music
    case weather
    case calendar
    case focus
    case system
    case screensaver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .codex: return "Codex"
        case .document: return "文档"
        case .image: return "投射"
        case .music: return "音乐"
        case .weather: return "天气"
        case .calendar: return "日历"
        case .focus: return "专注"
        case .system: return "系统"
        case .screensaver: return "屏保"
        }
    }

    var menuTitle: String {
        switch self {
        case .home: return "首页总览"
        case .codex: return "Codex 看板"
        case .document: return "Markdown 文档"
        case .image: return "图片 / 截屏"
        case .music: return "音乐控制"
        case .weather: return "天气"
        case .calendar: return "日历"
        case .focus: return "专注"
        case .system: return "Mac 系统"
        case .screensaver: return "屏保"
        }
    }

    var menuSymbolName: String {
        switch self {
        case .home: return "house"
        case .codex: return "terminal"
        case .document: return "doc.text"
        case .image: return "camera"
        case .music: return "music.note"
        case .weather: return "sun.max"
        case .calendar: return "calendar"
        case .focus: return "scope"
        case .system: return "desktopcomputer"
        case .screensaver: return "moon"
        }
    }
}

enum KindleOrientation: String, CaseIterable {
    case portrait
    case landscapeClockwise

    var title: String {
        switch self {
        case .portrait: return "Portrait"
        case .landscapeClockwise: return "Landscape CW"
        }
    }

    var frameSize: (width: Int, height: Int) {
        switch self {
        case .portrait: return (1072, 1448)
        case .landscapeClockwise: return (1448, 1072)
        }
    }
}

struct AppSnapshot {
    let mode: KindleMode
    let orientation: KindleOrientation
    let cycleEnabled: Bool
    let cycleInterval: TimeInterval
    let refreshSerial: Int
    let lightRefreshInterval: Int
    let fullRefreshInterval: Int
    let frontlightEnabled: Bool
    let frontlightLevel: Int
    let batteryProtectionEnabled: Bool
    let batteryLowerLimit: Int
    let batteryUpperLimit: Int
    let kindleBatteryText: String
    let documentTitle: String
    let documentMarkdown: String
    let documentPage: Int
    let imageTitle: String
    let imageDataURI: String
    let imageMeta: String
}

final class AppState: @unchecked Sendable {
    private let lock = NSLock()
    private var mode: KindleMode = .home
    private var orientation: KindleOrientation = .portrait
    private var cycleEnabled = false
    private var cycleInterval: TimeInterval = 90
    private var refreshSerial = 1
    private var lightRefreshInterval = 60
    private var fullRefreshInterval = 300
    private var frontlightEnabled = false
    private var frontlightLevel = 10
    private var batteryProtectionEnabled = false
    private var batteryLowerLimit = 45
    private var batteryUpperLimit = 55
    private var kindleBatteryText = "Kindle --"
    private var lastCycle = Date()
    private var documentTitle = "操作步骤"
    private var documentPage = 0
    private var documentMarkdown = """
    # 操作步骤

    还没有加载 Markdown 文档。

    在 Mac 顶栏菜单选择「打开 Markdown 文档...」，或通过 HTTP POST 到 /document 推送内容。
    """
    private var imageTitle = "等待投射"
    private var imageDataURI = ""
    private var imageMeta = "从 Mac 顶栏选择图片或截屏"

    func setMode(_ newMode: KindleMode) {
        lock.lock()
        mode = newMode
        lastCycle = Date()
        bumpRefreshLocked()
        lock.unlock()
    }

    func setOrientation(_ newOrientation: KindleOrientation) {
        lock.lock()
        orientation = newOrientation
        bumpRefreshLocked()
        lock.unlock()
    }

    func setCycleEnabled(_ enabled: Bool) {
        lock.lock()
        cycleEnabled = enabled
        lastCycle = Date()
        bumpRefreshLocked()
        lock.unlock()
    }

    func requestRefresh() {
        lock.lock()
        bumpRefreshLocked()
        lock.unlock()
    }

    func setLightRefreshInterval(_ seconds: Int) {
        lock.lock()
        lightRefreshInterval = min(300, max(10, seconds))
        bumpRefreshLocked()
        lock.unlock()
    }

    func setFullRefreshInterval(_ seconds: Int) {
        lock.lock()
        fullRefreshInterval = min(1800, max(120, seconds))
        bumpRefreshLocked()
        lock.unlock()
    }

    func setFrontlightEnabled(_ enabled: Bool) {
        lock.lock()
        frontlightEnabled = enabled
        bumpRefreshLocked()
        lock.unlock()
    }

    func setFrontlightLevel(_ level: Int) {
        lock.lock()
        frontlightLevel = min(24, max(0, level))
        frontlightEnabled = frontlightLevel > 0
        bumpRefreshLocked()
        lock.unlock()
    }

    func setBatteryProtectionEnabled(_ enabled: Bool) {
        lock.lock()
        batteryProtectionEnabled = enabled
        bumpRefreshLocked()
        lock.unlock()
    }

    func updateKindleStatus(battery: String?, charging: String?) {
        let cleanBattery = (battery ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCharging = (charging ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nextText: String
        if cleanBattery.isEmpty {
            nextText = "Kindle --"
        } else if cleanCharging == "1" || cleanCharging.lowercased() == "true" {
            nextText = "Kindle \(cleanBattery)% 充电"
        } else {
            nextText = "Kindle \(cleanBattery)%"
        }

        lock.lock()
        if kindleBatteryText != nextText {
            kindleBatteryText = nextText
        }
        lock.unlock()
    }

    func setDocument(title: String, markdown: String) {
        lock.lock()
        documentTitle = title
        documentMarkdown = markdown
        documentPage = 0
        mode = .document
        lastCycle = Date()
        bumpRefreshLocked()
        lock.unlock()
    }

    func turnDocumentPage(_ delta: Int) {
        lock.lock()
        let nonEmptyLines = documentMarkdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        let maxPage = max(0, (max(1, nonEmptyLines) - 1) / 8)
        documentPage = min(maxPage, max(0, documentPage + delta))
        mode = .document
        lastCycle = Date()
        bumpRefreshLocked()
        lock.unlock()
    }

    func setProjectionImage(title: String, dataURI: String, meta: String) {
        lock.lock()
        imageTitle = title
        imageDataURI = dataURI
        imageMeta = meta
        mode = .image
        lastCycle = Date()
        bumpRefreshLocked()
        lock.unlock()
    }

    func snapshot() -> AppSnapshot {
        lock.lock()
        if cycleEnabled, Date().timeIntervalSince(lastCycle) >= cycleInterval {
            let visibleModes: [KindleMode] = [.home, .codex, .document, .image, .music, .weather, .calendar, .focus, .system]
            if let index = visibleModes.firstIndex(of: mode) {
                mode = visibleModes[(index + 1) % visibleModes.count]
            } else {
                mode = .home
            }
            lastCycle = Date()
            bumpRefreshLocked()
        }
        let result = AppSnapshot(
            mode: mode,
            orientation: orientation,
            cycleEnabled: cycleEnabled,
            cycleInterval: cycleInterval,
            refreshSerial: refreshSerial,
            lightRefreshInterval: lightRefreshInterval,
            fullRefreshInterval: fullRefreshInterval,
            frontlightEnabled: frontlightEnabled,
            frontlightLevel: frontlightLevel,
            batteryProtectionEnabled: batteryProtectionEnabled,
            batteryLowerLimit: batteryLowerLimit,
            batteryUpperLimit: batteryUpperLimit,
            kindleBatteryText: kindleBatteryText,
            documentTitle: documentTitle,
            documentMarkdown: documentMarkdown,
            documentPage: documentPage,
            imageTitle: imageTitle,
            imageDataURI: imageDataURI,
            imageMeta: imageMeta
        )
        lock.unlock()
        return result
    }

    private func bumpRefreshLocked() {
        refreshSerial += 1
        if refreshSerial == Int.max {
            refreshSerial = 1
        }
    }
}

final class CommandRunner {
    static func run(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            return ""
        }
    }

    static func shell(_ script: String) -> String {
        run("/bin/zsh", ["-lc", script])
    }

    static func appleScript(_ source: String) -> String {
        run("/usr/bin/osascript", ["-e", source])
    }
}

struct Metric {
    let label: String
    let value: String
    let emphasis: Bool
}

struct DashboardModel {
    let mode: KindleMode
    let orientation: KindleOrientation
    let generatedAt: Date
    let headline: String
    let subhead: String
    let metrics: [Metric]
    let notes: [String]
    let footer: String
    let footerRight: String

    let imageDataURI: String?
    let imageMeta: String?

    init(
        mode: KindleMode,
        orientation: KindleOrientation,
        generatedAt: Date,
        headline: String,
        subhead: String,
        metrics: [Metric],
        notes: [String],
        footer: String,
        footerRight: String = "",
        imageDataURI: String? = nil,
        imageMeta: String? = nil
    ) {
        self.mode = mode
        self.orientation = orientation
        self.generatedAt = generatedAt
        self.headline = headline
        self.subhead = subhead
        self.metrics = metrics
        self.notes = notes
        self.footer = footer
        self.footerRight = footerRight
        self.imageDataURI = imageDataURI
        self.imageMeta = imageMeta
    }

    func withFooterRight(_ value: String) -> DashboardModel {
        DashboardModel(
            mode: mode,
            orientation: orientation,
            generatedAt: generatedAt,
            headline: headline,
            subhead: subhead,
            metrics: metrics,
            notes: notes,
            footer: footer,
            footerRight: value,
            imageDataURI: imageDataURI,
            imageMeta: imageMeta
        )
    }
}

struct CodexActivity {
    let currentTask: String
    let limitStatus: CodexLimitStatus
    let recentWork: [String]
    let nextAction: String
}

struct CodexLimitStatus {
    let primaryLabel: String
    let primaryValue: String
    let weeklyValue: String
    let resetText: String
    let health: String
    let rows: [String]
}

struct WeatherSnapshot {
    let current: String
    let detail: String
    let advice: String
    let hourlyRows: [String]
}

struct DashboardData {
    static func make(snapshot: AppSnapshot) -> DashboardModel {
        let model: DashboardModel
        switch snapshot.mode {
        case .home:
            model = home(snapshot)
        case .codex:
            model = codex(snapshot)
        case .document:
            model = document(snapshot)
        case .image:
            model = image(snapshot)
        case .music:
            model = music(snapshot)
        case .weather:
            model = weather(snapshot)
        case .calendar:
            model = calendar(snapshot)
        case .focus:
            model = focus(snapshot)
        case .system:
            model = system(snapshot)
        case .screensaver:
            model = screensaver(snapshot)
        }
        return model.withFooterRight(snapshot.kindleBatteryText)
    }

    private static func home(_ snapshot: AppSnapshot) -> DashboardModel {
        let weather = weatherSnapshot()
        let battery = CommandRunner.shell("pmset -g batt | sed -n '2p' | awk -F';' '{gsub(/^[ \t]+|[ \t]+$/, \"\", $1); gsub(/^[ \t]+|[ \t]+$/, \"\", $2); print $1 \" | \" $2}'")
        let next = nextCalendarLine()
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "今日概览",
            subhead: longDate(),
            metrics: [
                Metric(label: "现在", value: weather.current, emphasis: true),
                Metric(label: "日程", value: next, emphasis: false),
                Metric(label: "Mac", value: battery.isEmpty ? "电量不可用" : battery, emphasis: false),
                Metric(label: "建议", value: weather.advice, emphasis: false)
            ],
            notes: ["天气建议 | \(weather.advice)", "下一日程 | \(next)", "刷新节奏 | 轻刷 1 分钟 / 全刷 5 分钟"],
            footer: footer(snapshot)
        )
    }

    private static func codex(_ snapshot: AppSnapshot) -> DashboardModel {
        let activity = codexActivity()
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "Codex 看板",
            subhead: timestamp(),
            metrics: [
                Metric(label: "当前任务", value: activity.currentTask, emphasis: true),
                Metric(label: activity.limitStatus.primaryLabel, value: activity.limitStatus.primaryValue, emphasis: false),
                Metric(label: "周额度", value: activity.limitStatus.weeklyValue, emphasis: false),
                Metric(label: "重置", value: activity.limitStatus.resetText, emphasis: false)
            ],
            notes: activity.limitStatus.rows + ["下一步 | \(activity.nextAction)"] + Array(activity.recentWork.prefix(5)),
            footer: footer(snapshot)
        )
    }

    private static func document(_ snapshot: AppSnapshot) -> DashboardModel {
        let rows = markdownRows(snapshot.documentMarkdown)
        let pageSize = 8
        let totalPages = max(1, Int(ceil(Double(rows.count) / Double(pageSize))))
        let page = min(max(0, snapshot.documentPage), totalPages - 1)
        let pageRows = Array(rows.dropFirst(page * pageSize).prefix(pageSize))
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: snapshot.documentTitle.isEmpty ? "文档" : snapshot.documentTitle,
            subhead: "第 \(page + 1)/\(totalPages) 页 · \(rows.count) 行",
            metrics: [
                Metric(label: "当前文档", value: snapshot.documentTitle.isEmpty ? "文档" : snapshot.documentTitle, emphasis: true),
                Metric(label: "页码", value: "\(page + 1) / \(totalPages)", emphasis: false),
                Metric(label: "剩余", value: "\(max(0, totalPages - page - 1)) 页", emphasis: false)
            ],
            notes: pageRows,
            footer: footer(snapshot)
        )
    }

    private static func image(_ snapshot: AppSnapshot) -> DashboardModel {
        let hasImage = !snapshot.imageDataURI.isEmpty
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: hasImage ? snapshot.imageTitle : "等待投射",
            subhead: "图片 / 截屏投射",
            metrics: [
                Metric(label: "当前内容", value: hasImage ? snapshot.imageTitle : "等待图片或截屏", emphasis: true),
                Metric(label: "图片信息", value: hasImage ? snapshot.imageMeta : "未加载", emphasis: false),
                Metric(label: "下一步", value: hasImage ? "看完后可继续投射" : "从 Mac 顶栏选择", emphasis: false)
            ],
            notes: hasImage ? ["当前图片 | \(snapshot.imageMeta)", "刷新 Kindle | 自动拉取新画面"] : ["打开图片... | 选择本地图片", "投射当前截屏 | 需要屏幕录制权限"],
            footer: footer(snapshot),
            imageDataURI: hasImage ? snapshot.imageDataURI : nil,
            imageMeta: snapshot.imageMeta
        )
    }

    private static func music(_ snapshot: AppSnapshot) -> DashboardModel {
        let nowPlaying = CommandRunner.appleScript("""
        tell application "Music"
          if it is running then
            if player state is playing then
              return "播放中|" & artist of current track & "|" & name of current track & "|" & album of current track
            else
              return "已暂停|" & artist of current track & "|" & name of current track & "|" & album of current track
            end if
          else
            return "未运行|||"
          end if
        end tell
        """)
        let musicParts = nowPlaying.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let musicState = musicParts.first ?? "未运行"
        let artist = musicParts.count > 1 ? musicParts[1] : ""
        let track = musicParts.count > 2 ? musicParts[2] : ""
        let album = musicParts.count > 3 ? musicParts[3] : ""
        let title = track.isEmpty ? "音乐未运行" : "\(artist.isEmpty ? "未知艺人" : artist) - \(track)"
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "音乐",
            subhead: timestamp(),
            metrics: [
                Metric(label: "正在播放", value: title, emphasis: true),
                Metric(label: "状态", value: musicState, emphasis: false),
                Metric(label: "专辑", value: album.isEmpty ? "--" : album, emphasis: false)
            ],
            notes: ["上一首 | Mac 顶栏 / Kindle 控制页", "播放暂停 | Mac 顶栏 / Kindle 控制页", "下一首 | Mac 顶栏 / Kindle 控制页"],
            footer: footer(snapshot)
        )
    }

    private static func weather(_ snapshot: AppSnapshot) -> DashboardModel {
        let weather = weatherSnapshot()
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "天气",
            subhead: "未来几小时 · \(clockTime()) 更新",
            metrics: [
                Metric(label: "现在", value: weather.current, emphasis: true),
                Metric(label: "细节", value: weather.detail, emphasis: false),
                Metric(label: "建议", value: weather.advice, emphasis: false)
            ],
            notes: weather.hourlyRows,
            footer: footer(snapshot)
        )
    }

    private static func calendar(_ snapshot: AppSnapshot) -> DashboardModel {
        let next = nextCalendarLine()
        let reminders = CommandRunner.shell("osascript -e 'tell application \"Reminders\" to if it is running then return name of reminders whose completed is false' 2>/dev/null | tr ',' '\\n' | sed -n '1,6p'")
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "日历",
            subhead: longDate(),
            metrics: [
                Metric(label: "下一项", value: next, emphasis: true),
                Metric(label: "待办", value: reminders.isEmpty ? "暂无提醒事项" : "\(listLines(reminders, fallback: "").count) 项提醒", emphasis: false),
                Metric(label: "建议", value: (next.contains("暂未") || next.contains("暂无")) ? "留给深度工作" : "提前 10 分钟准备", emphasis: false)
            ],
            notes: listLines(reminders, fallback: "今天没有提醒事项 | 可专注"),
            footer: footer(snapshot)
        )
    }

    private static func focus(_ snapshot: AppSnapshot) -> DashboardModel {
        let uptime = uptimeSummary()
        let currentTask = codexActivity().currentTask
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "专注",
            subhead: "专注状态牌",
            metrics: [
                Metric(label: "当前任务", value: currentTask, emphasis: true),
                Metric(label: "时间块", value: "50 分钟", emphasis: false),
                Metric(label: "Mac", value: uptime.isEmpty ? "就绪" : uptime, emphasis: false)
            ],
            notes: ["只做一件事 | 当前", "关闭额外页面 | 建议", "50 分钟后休息 | 建议"],
            footer: footer(snapshot)
        )
    }

    private static func system(_ snapshot: AppSnapshot) -> DashboardModel {
        let rawCpu = firstMatch(CommandRunner.run("/usr/bin/top", ["-l", "1", "-n", "0"]), pattern: #"CPU usage: ([^\n]+)"#) ?? ""
        let cpu = cpuSummary(rawCpu)
        let memory = CommandRunner.shell("vm_stat | awk '/Pages free/ {free=$3} /Pages active/ {active=$3} /Pages wired down/ {wired=$4} END {gsub(/\\./,\"\",free); gsub(/\\./,\"\",active); gsub(/\\./,\"\",wired); printf \"空闲 %.1fGB | 活跃 %.1fGB | 常驻 %.1fGB\", free*4096/1024/1024/1024, active*4096/1024/1024/1024, wired*4096/1024/1024/1024}'")
        let disk = CommandRunner.shell("df -h / | awk 'NR==2 {print \"可用 \" $4 \" / 总 \" $2}'")
        let procs = CommandRunner.shell("ps -arcwwwxo %cpu,%mem,comm | sed -n '2,9p'")
        let advice = systemAdvice(cpuSummary: cpu, memory: memory)
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "系统",
            subhead: timestamp(),
            metrics: [
                Metric(label: "状态", value: advice, emphasis: true),
                Metric(label: "CPU", value: cpu, emphasis: false),
                Metric(label: "内存", value: memory.isEmpty ? "不可用" : memory, emphasis: false),
                Metric(label: "磁盘", value: disk.isEmpty ? "不可用" : disk, emphasis: false)
            ],
            notes: processRows(procs).prefix(5).map { $0 },
            footer: footer(snapshot)
        )
    }

    private static func screensaver(_ snapshot: AppSnapshot) -> DashboardModel {
        DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: clockTime(),
            subhead: longDate(),
            metrics: [
                Metric(label: "离开", value: "Kindle Dock", emphasis: true),
                Metric(label: "唤醒", value: "用 Mac 顶栏切换模式", emphasis: false),
                Metric(label: "状态", value: "安静显示", emphasis: false)
            ],
            notes: ["安静显示 | 已启用", "每分钟刷新 | 低干扰"],
            footer: footer(snapshot)
        )
    }

    private static func nextCalendarLine() -> String {
        let value = CommandRunner.shell("command -v icalBuddy >/dev/null && icalBuddy -nc -nrd -ea -li 1 eventsToday 2>/dev/null | head -1 || true")
        return value.isEmpty ? "暂无日程" : value
    }

    private static func markdownRows(_ markdown: String) -> [String] {
        let rows = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { raw -> String in
                var line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return "" }
                if line.hasPrefix("#") {
                    line = line.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
                    return "■ \(line) | 标题"
                }
                if line.hasPrefix("- [ ]") {
                    return "□ \(line.dropFirst(5).trimmingCharacters(in: .whitespaces)) | 待做"
                }
                if line.hasPrefix("- [x]") || line.hasPrefix("- [X]") {
                    return "✓ \(line.dropFirst(5).trimmingCharacters(in: .whitespaces)) | 完成"
                }
                if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    return "• \(line.dropFirst(2).trimmingCharacters(in: .whitespaces)) | "
                }
                if line.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil {
                    return "\(line) | 步骤"
                }
                return "\(line) | "
            }
            .filter { !$0.isEmpty }
        return rows.isEmpty ? ["还没有加载 Markdown 文档 | "] : rows
    }

    private static func weatherLine(includeDetail: Bool) -> String {
        let raw = CommandRunner.shell("curl -m 3 -s 'https://wttr.in/?format=%t|%f|%h|%w' 2>/dev/null || true")
        let parts = raw
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count >= 4, !parts[0].isEmpty else {
            return ""
        }
        if includeDetail {
            return "室外 \(parts[0])，体感 \(parts[1])，湿度 \(parts[2])\n风 \(parts[3])"
        }
        return "室外 \(parts[0])，体感 \(parts[1])"
    }

    private static func weatherSnapshot() -> WeatherSnapshot {
        let raw = CommandRunner.shell("curl -m 4 -s 'https://wttr.in/?format=j1' 2>/dev/null || true")
        guard let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = (root["current_condition"] as? [[String: Any]])?.first else {
            let fallback = weatherLine(includeDetail: true)
            return WeatherSnapshot(
                current: fallback.isEmpty ? "天气源暂不可用" : fallback.replacingOccurrences(of: "\n", with: "，"),
                detail: fallback.isEmpty ? "等待下次刷新" : "来自 wttr.in",
                advice: fallback.isEmpty ? "天气源暂不可用" : "出门前看温度和风",
                hourlyRows: ["天气源暂不可用 | 稍后自动刷新"]
            )
        }

        let temp = intText(current["temp_C"]) ?? "--"
        let feels = intText(current["FeelsLikeC"]) ?? temp
        let humidity = intText(current["humidity"]) ?? "--"
        let wind = intText(current["windspeedKmph"]) ?? "--"
        let desc = weatherDescription(current) ?? "当前天气"
        let currentText = "\(desc) \(signedTemperature(temp))，体感 \(signedTemperature(feels))"
        let detailText = "湿度 \(humidity)%｜风 \(wind)km/h"

        let hourly = hourlyWeatherRows(root: root)
        let advice = weatherAdvice(
            temperature: Int(temp),
            feelsLike: Int(feels),
            humidity: Int(humidity),
            rows: hourly
        )
        return WeatherSnapshot(
            current: currentText,
            detail: detailText,
            advice: advice,
            hourlyRows: hourly.isEmpty ? ["未来几小时 | 暂无数据"] : hourly
        )
    }

    private static func hourlyWeatherRows(root: [String: Any]) -> [String] {
        guard let days = root["weather"] as? [[String: Any]] else { return [] }
        let nowHour = Calendar.current.component(.hour, from: Date())
        let threshold = nowHour * 100
        var rows: [String] = []

        for (dayIndex, day) in days.prefix(2).enumerated() {
            guard let hourly = day["hourly"] as? [[String: Any]] else { continue }
            for item in hourly {
                guard let timeValue = Int(intText(item["time"]) ?? "") else { continue }
                if dayIndex == 0, timeValue < threshold { continue }
                let hour = timeValue / 100
                let prefix = dayIndex == 0 ? String(format: "%02d:00", hour) : "明天 \(String(format: "%02d:00", hour))"
                let temp = intText(item["tempC"]) ?? "--"
                let rain = intText(item["chanceofrain"]) ?? "0"
                let desc = weatherDescription(item) ?? "天气"
                rows.append("\(prefix) \(desc) \(signedTemperature(temp)) | 降水 \(rain)%")
                if rows.count >= 5 { return rows }
            }
        }
        return rows
    }

    private static func weatherDescription(_ object: [String: Any]) -> String? {
        if let descriptions = object["weatherDesc"] as? [[String: Any]],
           let value = descriptions.first?["value"] as? String,
           !value.isEmpty {
            return localizedWeather(value)
        }
        return nil
    }

    private static func localizedWeather(_ value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("rain") || lower.contains("drizzle") { return "有雨" }
        if lower.contains("snow") { return "有雪" }
        if lower.contains("thunder") { return "雷雨" }
        if lower.contains("fog") || lower.contains("mist") { return "雾" }
        if lower.contains("cloud") || lower.contains("overcast") { return "多云" }
        if lower.contains("sun") || lower.contains("clear") { return "晴" }
        return value
    }

    private static func weatherAdvice(temperature: Int?, feelsLike: Int?, humidity: Int?, rows: [String]) -> String {
        let rowText = rows.joined(separator: " ")
        if rowText.range(of: #"降水 ([6-9]\d|100)%"#, options: .regularExpression) != nil {
            return "带伞，避开强降水"
        }
        if let feelsLike, feelsLike >= 34 {
            return "闷热，少外出多补水"
        }
        if let temperature, temperature <= 5 {
            return "偏冷，注意保暖"
        }
        if let humidity, humidity >= 80 {
            return "湿度高，少开窗"
        }
        return "天气稳定，可正常出行"
    }

    private static func signedTemperature(_ value: String) -> String {
        guard let number = Int(value) else { return "\(value)°C" }
        return number > 0 ? "+\(number)°C" : "\(number)°C"
    }

    private static func intText(_ value: Any?) -> String? {
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = value as? NSNumber {
            return "\(number.intValue)"
        }
        return nil
    }

    private static func cpuSummary(_ raw: String) -> String {
        guard !raw.isEmpty else { return "不可用" }
        if let idleText = firstMatch(raw, pattern: #"([\d\.]+)% idle"#),
           let idle = Double(idleText) {
            return "使用 \(Int(max(0, min(100, 100 - idle)).rounded()))%"
        }
        return raw
            .replacingOccurrences(of: " user", with: " 用户")
            .replacingOccurrences(of: " sys", with: " 系统")
            .replacingOccurrences(of: " idle", with: " 空闲")
    }

    private static func systemAdvice(cpuSummary: String, memory: String) -> String {
        if let cpu = firstMatch(cpuSummary, pattern: #"使用 (\d+)%"#).flatMap(Int.init), cpu >= 80 {
            return "CPU 压力高，先看进程"
        }
        if memory.contains("空闲 0.") {
            return "内存偏紧，少开大应用"
        }
        return "系统状态正常"
    }

    private static func uptimeSummary() -> String {
        let raw = CommandRunner.shell("uptime | sed 's/^ //; s/  */ /g'")
        guard !raw.isEmpty else { return "就绪" }
        let loadPieces = raw.components(separatedBy: "load averages:")
        if loadPieces.count > 1 {
            let load = loadPieces[1]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .prefix(1)
                .joined(separator: " / ")
            if !load.isEmpty {
                return "负载 \(load)"
            }
        }
        if let uptime = firstMatch(raw, pattern: #"up ([^,]+),"#), !uptime.isEmpty {
            return "运行 \(uptime)"
        }
        return "就绪"
    }

    private static func recentCodexSessions() -> [String] {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/session_index.jsonl")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ["暂无 Codex 会话记录"]
        }
        let sessions = content.split(separator: "\n").compactMap { line -> (name: String, updated: String, display: String)? in
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            let name = (object["thread_name"] as? String) ?? (object["name"] as? String) ?? "Untitled thread"
            let rawUpdated = object["updated_at"] as? String ?? ""
            let displayUpdated = rawUpdated.prefix(16).replacingOccurrences(of: "T", with: " ")
            let display = displayUpdated.isEmpty ? name : "\(name) | \(displayUpdated)"
            return (name, rawUpdated, display)
        }
        let sorted = sessions.sorted { $0.updated > $1.updated }.prefix(10).map(\.display)
        return sorted.isEmpty ? ["暂无 Codex 会话记录"] : Array(sorted)
    }

    private static func codexActivity() -> CodexActivity {
        let messages = recentCodexMessages(limit: 8)
        let limitStatus = codexLimitStatus()
        if let latest = messages.first {
            let rows = messages.map { message in
                let time = codexDisplayTime(message.timestamp)
                let title = clipped(message.text, limit: 30)
                return time.isEmpty ? title : "\(title) | \(time)"
            }
            return CodexActivity(
                currentTask: clipped(latest.text, limit: 46),
                limitStatus: limitStatus,
                recentWork: rows,
                nextAction: limitStatus.health
            )
        }

        let sessions = recentCodexSessions()
        return CodexActivity(
            currentTask: sessions.first.map { clipped($0.components(separatedBy: " | ").first ?? $0, limit: 46) } ?? "等待 Codex 任务",
            limitStatus: limitStatus,
            recentWork: sessions,
            nextAction: limitStatus.health
        )
    }

    private static func codexLimitStatus() -> CodexLimitStatus {
        if let live = codexRateLimitFromLogs() {
            return live
        }
        return codexLocalUsageStatus()
    }

    private static func codexRateLimitFromLogs() -> CodexLimitStatus? {
        let database = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/logs_2.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }
        let sql = """
        SELECT ts, feedback_log_body
        FROM logs
        WHERE (target = 'log' AND feedback_log_body LIKE 'Received message {"type":"codex.rate_limits"%')
           OR (target = 'codex_api::endpoint::responses_websocket' AND feedback_log_body LIKE '%websocket event: {"type":"codex.rate_limits"%')
        ORDER BY id DESC
        LIMIT 10;
        """
        guard let output = try? runSQLite(database: database, sql: sql), !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let timestamp = Int(line[..<tab]) ?? Int(Date().timeIntervalSince1970)
            let body = String(line[line.index(after: tab)...])
            guard let root = codexRateLimitJSON(from: body),
                  let status = codexLimitStatus(from: root, capturedAt: Date(timeIntervalSince1970: Double(timestamp))) else {
                continue
            }
            return status
        }
        return nil
    }

    private static func codexLimitStatus(from root: [String: Any], capturedAt: Date) -> CodexLimitStatus? {
        let codexLimit = dictionary(root["rateLimitsByLimitId"]).flatMap { limits in
            dictionary(limits["codex"])
        } ?? dictionary(root["rateLimits"])
        let legacyLimits = dictionary(root["rate_limits"])
        let primary = dictionary(codexLimit?["primary"]) ?? dictionary(legacyLimits?["primary"])
        let weekly = dictionary(codexLimit?["secondary"]) ?? dictionary(legacyLimits?["secondary"])

        let primaryRemaining = remainingPercent(primary)
        let weeklyRemaining = remainingPercent(weekly)
        guard primaryRemaining != nil || weeklyRemaining != nil else { return nil }

        let primaryReset = resetDate(primary)
        let weeklyReset = resetDate(weekly)
        let primaryText = primaryRemaining.map { "\($0)%" } ?? "--"
        let weeklyText = weeklyRemaining.map { "\($0)%" } ?? "--"
        let resetText = primaryReset.map(countdownText) ?? weeklyReset.map(countdownText) ?? "--"
        let health: String
        if let weeklyRemaining, weeklyRemaining <= 10 {
            health = "周额度紧张，减少长任务"
        } else if let primaryRemaining, primaryRemaining <= 15 {
            health = "5h 额度紧张，等重置"
        } else {
            health = "额度正常，可继续"
        }

        return CodexLimitStatus(
            primaryLabel: "5h 剩余",
            primaryValue: primaryText,
            weeklyValue: weeklyText,
            resetText: resetText,
            health: health,
            rows: [
                "限额状态 | \(health)",
                "5h 重置 | \(primaryReset.map(timestampText) ?? "--")",
                "周重置 | \(weeklyReset.map(timestampText) ?? "--")",
                "限额快照 | \(timestampText(capturedAt))"
            ]
        )
    }

    private static func codexLocalUsageStatus() -> CodexLimitStatus {
        let database = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/state_5.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else {
            return CodexLimitStatus(
                primaryLabel: "限额",
                primaryValue: "--",
                weeklyValue: "--",
                resetText: "--",
                health: "未找到本机 Codex 数据",
                rows: ["Codex 数据 | 未找到 ~/.codex/state_5.sqlite"]
            )
        }

        let recentStartMs = Int(Date().addingTimeInterval(-24 * 60 * 60).timeIntervalSince1970) * 1000
        let sql = """
        SELECT COUNT(*),
               COALESCE(SUM(tokens_used), 0),
               COALESCE(SUM(CASE WHEN updated_at_ms >= \(recentStartMs) THEN tokens_used ELSE 0 END), 0),
               COALESCE(SUM(CASE WHEN updated_at_ms >= \(recentStartMs) THEN 1 ELSE 0 END), 0)
        FROM threads;
        """
        let fields = (try? runSQLite(database: database, sql: sql))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t", omittingEmptySubsequences: false)
            .map(String.init) ?? []
        let threadCount = fields.indices.contains(0) ? (Int(fields[0]) ?? 0) : 0
        let totalTokens = fields.indices.contains(1) ? (Int(fields[1]) ?? 0) : 0
        let recentTokens = fields.indices.contains(2) ? (Int(fields[2]) ?? 0) : 0
        let recentThreads = fields.indices.contains(3) ? (Int(fields[3]) ?? 0) : 0

        return CodexLimitStatus(
            primaryLabel: "24h Tokens",
            primaryValue: compactNumber(recentTokens),
            weeklyValue: "--",
            resetText: "无快照",
            health: "未捕获服务端限额",
            rows: [
                "限额状态 | 未捕获服务端快照",
                "24h 活跃线程 | \(recentThreads)",
                "累计 Tokens | \(compactNumber(totalTokens))",
                "本机线程 | \(threadCount)"
            ]
        )
    }

    private static func codexRateLimitJSON(from body: String) -> [String: Any]? {
        if let root = jsonRoot(after: "Received message ", in: body) {
            return root
        }
        if let root = jsonRoot(after: "websocket event: ", in: body) {
            return root
        }
        return nil
    }

    private static func jsonRoot(after marker: String, in body: String) -> [String: Any]? {
        guard let markerRange = body.range(of: marker) else { return nil }
        let remainder = body[markerRange.upperBound...]
        guard let jsonStart = remainder.firstIndex(of: "{"),
              let jsonText = balancedJSONObjectText(from: remainder[jsonStart...]),
              let data = jsonText.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func balancedJSONObjectText(from text: Substring) -> String? {
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[...index])
                }
            }
        }
        return nil
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func remainingPercent(_ object: [String: Any]?) -> Int? {
        guard let object else { return nil }
        let used = number(object["usedPercent"]) ?? number(object["used_percent"])
        guard let used else { return nil }
        return Int(max(0, min(100, 100 - used)).rounded())
    }

    private static func resetDate(_ object: [String: Any]?) -> Date? {
        guard let object else { return nil }
        let reset = number(object["resetsAt"]) ?? number(object["reset_at"])
        return reset.map { Date(timeIntervalSince1970: $0) }
    }

    private static func runSQLite(database: URL, sql: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-separator", "\t", database.path, sql]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus == 0 {
            return output
        }
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw NSError(domain: "KindleDashboard.SQLite", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: error])
    }

    private static func compactNumber(_ value: Int) -> String {
        let number = Double(value)
        if number >= 1_000_000 {
            return "\(String(format: "%.1f", number / 1_000_000))M"
        }
        if number >= 1_000 {
            return "\(String(format: "%.1f", number / 1_000))K"
        }
        return "\(value)"
    }

    private static func countdownText(_ date: Date) -> String {
        let remaining = Int(date.timeIntervalSince(Date()))
        if remaining <= 0 {
            return "已重置"
        }
        if remaining < 24 * 60 * 60 {
            let hours = remaining / 3600
            let minutes = (remaining % 3600) / 60
            return hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
        }
        return timestampText(date)
    }

    private static func timestampText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func recentCodexMessages(limit: Int) -> [(text: String, timestamp: String)] {
        var messages: [(text: String, timestamp: String)] = []

        for file in codexSessionFiles().prefix(12) {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n") {
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["type"] as? String == "response_item",
                      let payload = object["payload"] as? [String: Any],
                      payload["type"] as? String == "message",
                      payload["role"] as? String == "user",
                      let content = payload["content"] as? [[String: Any]] else {
                    continue
                }

                let timestamp = object["timestamp"] as? String ?? ""
                for item in content {
                    guard item["type"] as? String == "input_text",
                          let raw = item["text"] as? String,
                          let clean = cleanedCodexUserText(raw) else {
                        continue
                    }
                    messages.append((clean, timestamp))
                }
            }
        }

        var seen = Set<String>()
        return Array(messages
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp { return lhs.text > rhs.text }
                return lhs.timestamp > rhs.timestamp
            }
            .filter { message in
                if seen.contains(message.text) { return false }
                seen.insert(message.text)
                return true
            }
            .prefix(limit))
    }

    private static func codexSessionFiles() -> [URL] {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            files.append((url, modified))
        }

        let sorted = files.sorted { $0.modified > $1.modified }.map(\.url)
        let indexedIDs = indexedCodexSessionIDs()
        guard !indexedIDs.isEmpty else { return sorted }

        let indexedFiles = sorted.filter { url in
            guard let id = codexSessionID(from: url) else { return false }
            return indexedIDs.contains(id)
        }
        return indexedFiles.isEmpty ? sorted : indexedFiles
    }

    private static func indexedCodexSessionIDs() -> Set<String> {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/session_index.jsonl")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let ids = content.split(separator: "\n").compactMap { line -> String? in
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object["id"] as? String
        }
        return Set(ids)
    }

    private static func codexSessionID(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        let pattern = #"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"#
        return firstMatch(name, pattern: pattern)
    }

    private static func cleanedCodexUserText(_ raw: String) -> String? {
        let trimmedRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRaw.range(of: #"^\[\d+\]\s+(assistant|tool|developer|system)\b"#, options: .regularExpression) != nil {
            return nil
        }
        let internalPrefixes = [
            "The following is the Codex agent history",
            "The Codex agent has requested",
            "Reviewed Codex session id:",
            "We need continue from summary",
            "Need continue from summary",
            "Planned action JSON:",
            "Assess the exact planned action",
            ">>> TRANSCRIPT",
            "<<< TRANSCRIPT",
            "Command completed:",
            "Command failed:"
        ]
        if internalPrefixes.contains(where: { trimmedRaw.hasPrefix($0) }) {
            return nil
        }
        if raw.contains("<environment_context>")
            || raw.contains("permissions instructions")
            || raw.contains("<app-context>")
            || raw.contains("<skills_instructions>") {
            return nil
        }
        if raw.contains("<image name=") || raw.contains("Files mentioned by the user") {
            return nil
        }

        let clean = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.hasPrefix("# Files mentioned")
                    && !trimmed.hasPrefix("## ")
                    && !trimmed.hasPrefix("<image")
                    && !trimmed.hasPrefix("</image")
            }
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard clean.count >= 2, clean.count <= 600 else { return nil }
        return clean
    }

    private static func codexDisplayTime(_ timestamp: String) -> String {
        guard !timestamp.isEmpty else { return "" }
        return String(timestamp.prefix(16).replacingOccurrences(of: "T", with: " "))
    }

    private static func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(0, limit - 1))) + "…"
    }

    private static func kindleDockBuildStatus() -> String {
        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let binary = cwd.appendingPathComponent(".build/debug/KindleDashboard")
        let source = cwd.appendingPathComponent("Sources/KindleDashboard/main.swift")
        guard let binaryDate = try? binary.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return "Needs build"
        }
        let sourceDate = (try? source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if sourceDate > binaryDate {
            return "Needs rebuild"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "Build OK \(formatter.string(from: binaryDate))"
    }

    static func localURL() -> String {
        "http://\(localIPAddress()):8787/"
    }

    private static func localIPAddress() -> String {
        let ip = CommandRunner.shell("ipconfig getifaddr en0 || ipconfig getifaddr en1 || ifconfig | awk '/inet / && $2 !~ /^127/ {print $2; exit}'")
        return ip.isEmpty ? "127.0.0.1" : ip
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    static func clockTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private static func longDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }

    private static func footer(_ snapshot: AppSnapshot) -> String {
        let cycle = snapshot.cycleEnabled ? "轮换开启" : "轮换关闭"
        return "竖屏 | \(cycle) | \(timestamp())"
    }

    private static func listLines(_ input: String, fallback: String) -> [String] {
        let lines = input
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? [fallback] : lines
    }

    private static func processRows(_ input: String) -> [String] {
        let rows = input.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count >= 3 else { return nil }
            let cpu = parts[0]
            let memory = parts[1]
            let command = parts.dropFirst(2).joined(separator: " ")
            return "\(command) | CPU \(cpu)% / MEM \(memory)%"
        }
        return rows.isEmpty ? ["暂无高压进程 | 正常"] : rows
    }

    private static func firstMatch(_ input: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let range = Range(match.range(at: 1), in: input) else {
            return nil
        }
        return String(input[range])
    }
}

struct HTMLRenderer {
    let model: DashboardModel
    let snapshot: AppSnapshot

    func html() -> String {
        let bodyClass = model.orientation == .landscapeClockwise ? "landscape" : "portrait"
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="refresh" content="\(refreshSeconds)">
          <title>\(escape(model.mode.title))</title>
          <style>
            html,body{margin:0;padding:0;background:#fff;color:#000;font-family:Georgia,"Times New Roman",serif;width:100%;height:100%;overflow:hidden}
            a{color:#000;text-decoration:none}
            .stage{box-sizing:border-box;background:#fff;color:#000}
            body.portrait .stage{width:100vw;height:100vh;padding:22px 24px;overflow:hidden}
            body.landscape .stage{width:100vh;height:100vw;padding:20px 24px;overflow:hidden;-webkit-transform-origin:0 0;transform-origin:0 0;-webkit-transform:rotate(-90deg) translateX(-100%);transform:rotate(-90deg) translateX(-100%)}
            .tabs{display:flex;gap:8px;margin-bottom:18px;border-bottom:4px solid #000;padding-bottom:10px}
            .tab{border:3px solid #000;padding:8px 10px;font-size:18px;font-weight:bold;line-height:1}
            .tab.active{background:#000;color:#fff}
            .top{display:grid;grid-template-columns:1.15fr .85fr;gap:18px;align-items:end;margin-bottom:20px}
            h1{font-size:76px;line-height:.9;margin:0;letter-spacing:0}
            .sub{font-size:25px;line-height:1.1;text-align:right}
            .grid{display:grid;grid-template-columns:1fr 1fr;gap:14px;align-items:stretch}
            .card{border:4px solid #000;padding:14px;min-height:154px;box-sizing:border-box;overflow:hidden}
            .card.emphasis{min-height:154px}
            h2{font-size:20px;text-transform:uppercase;margin:0 0 10px;letter-spacing:0}
            .value{font-size:29px;font-weight:bold;line-height:1.08;word-break:break-word;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
            .card.emphasis .value{font-size:36px}
            .notes{border-top:4px solid #000;margin-top:20px;padding-top:10px}
            .note{font-size:23px;line-height:1.18;border-bottom:2px solid #000;padding:8px 0;display:flex;gap:12px;justify-content:space-between;white-space:nowrap;overflow:hidden}
            .note-left{overflow:hidden;text-overflow:ellipsis}
            .note-right{font-weight:bold;text-align:right;white-space:nowrap}
            .actions{display:flex;gap:12px;margin-top:14px}
            .action{border:3px solid #000;padding:10px 12px;font-size:22px;font-weight:bold}
            .projection{border:4px solid #000;margin-top:18px;height:460px;display:flex;align-items:center;justify-content:center;overflow:hidden}
            .projection img{max-width:100%;max-height:100%;object-fit:contain}
            .footer{position:absolute;left:24px;right:24px;bottom:14px;border-top:3px solid #000;padding-top:8px;font-size:16px;display:flex;justify-content:space-between}
            body.portrait .top{grid-template-columns:1fr}
            body.portrait .sub{text-align:left}
            body.portrait h1{font-size:82px}
            body.portrait .grid{grid-template-columns:1fr}
            body.portrait .card{min-height:168px}
            body.portrait .card.emphasis{min-height:168px}
            body.portrait .tabs{flex-wrap:wrap}
            body.portrait .tab{font-size:17px}
            body.portrait .note{font-size:24px}
          </style>
        </head>
        <body class="\(bodyClass)">
          <main class="stage">
            \(tabs)
            <section class="top">
              <h1>\(escape(model.headline))</h1>
              <div class="sub">\(escape(model.subhead))</div>
            </section>
            <section class="grid">
              \(metricCards)
            </section>
            \(imagePreview)
            \(musicControls)
            <section class="notes">
              \(notes)
            </section>
            <footer class="footer"><span>\(escape(model.footer))</span><span><a href="/orientation/toggle">旋转</a> | <a href="/cycle/toggle">轮换</a></span></footer>
          </main>
        </body>
        </html>
        """
    }

    private var refreshSeconds: Int {
        switch model.mode {
        case .music: return 8
        case .weather: return 600
        case .screensaver: return 60
        default: return 20
        }
    }

    private var tabs: String {
        let items = KindleMode.allCases.map { mode in
            let active = mode == model.mode ? " active" : ""
            return "<a class=\"tab\(active)\" href=\"/mode/\(mode.rawValue)\">\(escape(mode.title))</a>"
        }.joined()
        return "<nav class=\"tabs\">\(items)</nav>"
    }

    private var metricCards: String {
        model.metrics.map { metric in
            let cls = metric.emphasis ? "card emphasis" : "card"
            return "<article class=\"\(cls)\"><h2>\(escape(metric.label))</h2><div class=\"value\">\(escape(metric.value))</div></article>"
        }.joined()
    }

    private var notes: String {
        model.notes.prefix(8).map { note in
            let parts = splitRow(note)
            return "<div class=\"note\"><span class=\"note-left\">\(escape(parts.left))</span><span class=\"note-right\">\(escape(parts.right))</span></div>"
        }.joined()
    }

    private func splitRow(_ value: String) -> (left: String, right: String) {
        let parts = value.components(separatedBy: " | ")
        guard parts.count >= 2 else { return (value, "") }
        return (parts.dropLast().joined(separator: " | "), parts.last ?? "")
    }

    private var musicControls: String {
        guard model.mode == .music else { return "" }
        return """
        <section class="actions">
          <a class="action" href="/control/previous">上一首</a>
          <a class="action" href="/control/playpause">播放 / 暂停</a>
          <a class="action" href="/control/next">下一首</a>
        </section>
        """
    }

    private var imagePreview: String {
        guard model.mode == .image, let dataURI = model.imageDataURI, !dataURI.isEmpty else {
            return ""
        }
        return "<section class=\"projection\"><img src=\"\(dataURI)\" alt=\"\(escape(model.headline))\"></section>"
    }
}

struct SVGRenderer {
    let model: DashboardModel

    func svg() -> String {
        let size = KindleOrientation.portrait.frameSize
        let w = size.width
        let h = size.height
        if model.mode == .home {
            return homeSVG(width: w, height: h)
        }
        let margin = 24
        let mainBottom = 1212
        let widgetTop = 1228
        let widgetHeight = 164
        let footerY = 1430
        let headerY = margin
        let headerHeight = 70
        var body = ""

        body += rect(x: margin, y: headerY, width: w - margin * 2, height: mainBottom - headerY, stroke: 5)
        body += rect(x: margin, y: headerY, width: w - margin * 2, height: headerHeight, stroke: 0, fill: "#000")
        body += centeredText(nativeTitle, centerX: w / 2, y: headerY + 47, size: 30, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += rightText("MAC", rightX: w - margin - 30, y: headerY + 47, size: 28, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")

        body += pageContent(x: margin + 32, y: headerY + headerHeight + 32, width: w - margin * 2 - 64, bottom: mainBottom - 32)
        body += widgetRail(x: margin, y: widgetTop, width: w - margin * 2, height: widgetHeight)
        body += line(x1: margin, y1: footerY - 36, x2: w - margin, y2: footerY - 36, stroke: 3)
        body += text("竖屏信息牌 | Mac 顶栏控制 | \(DashboardData.timestamp())", x: margin, y: footerY, size: 21, weight: "400", family: "Menlo, Monaco, monospace")
        body += rightText(model.footerRight, rightX: w - margin, y: footerY, size: 21, weight: "400", family: "Menlo, Monaco, monospace")

        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
          <rect x="0" y="0" width="\(w)" height="\(h)" fill="#fff"/>
          \(body)
        </svg>
        """
    }

    private func homeSVG(width w: Int, height h: Int) -> String {
        let margin = 68
        let widgetTop = 1248
        let widgetHeight = 160
        let footerY = 1430
        var body = ""
        body += pageContent(x: margin, y: 42, width: w - margin * 2, bottom: 1190)
        body += widgetRail(x: margin, y: widgetTop, width: w - margin * 2, height: widgetHeight)
        body += line(x1: margin, y1: footerY - 34, x2: w - margin, y2: footerY - 34, stroke: 2)
        body += text("Kindle Dashboard · \(DashboardData.timestamp())", x: margin, y: footerY, size: 21, weight: "400", family: "Menlo, Monaco, monospace")
        body += rightText(model.footerRight, rightX: w - margin, y: footerY, size: 21, weight: "400", family: "Menlo, Monaco, monospace")

        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
          <rect x="0" y="0" width="\(w)" height="\(h)" fill="#fff"/>
          \(body)
        </svg>
        """
    }

    private func rect(x: Int, y: Int, width: Int, height: Int, stroke: Int) -> String {
        rect(x: x, y: y, width: width, height: height, stroke: stroke, fill: "#fff")
    }

    private func rect(x: Int, y: Int, width: Int, height: Int, stroke: Int, fill: String) -> String {
        let strokePart = stroke > 0 ? " stroke=\"#000\" stroke-width=\"\(stroke)\"" : ""
        return "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(width)\" height=\"\(height)\" fill=\"\(fill)\"\(strokePart)/>"
    }

    private var nativeTitle: String {
        switch model.mode {
        case .home: return "首页"
        case .codex: return "CODEX"
        case .document: return "文档"
        case .image: return "投射"
        case .music: return "音乐"
        case .weather: return "天气"
        case .calendar: return "日历"
        case .focus: return "专注"
        case .system: return "系统"
        case .screensaver: return "屏保"
        }
    }

    private var sectionTitle: String {
        switch model.mode {
        case .codex: return "最近工作"
        case .document: return "文档内容"
        case .image: return "投射内容"
        case .music: return "控制"
        case .weather: return "未来几小时"
        case .calendar, .home: return "今日"
        case .focus: return "专注规则"
        case .system: return "资源压力"
        case .screensaver: return "空闲状态"
        }
    }

    private func line(x1: Int, y1: Int, x2: Int, y2: Int, stroke: Int) -> String {
        "<line x1=\"\(x1)\" y1=\"\(y1)\" x2=\"\(x2)\" y2=\"\(y2)\" stroke=\"#000\" stroke-width=\"\(stroke)\"/>"
    }

    private func text(_ value: String, x: Int, y: Int, size: Int, weight: String, fill: String = "#000", family: String = "Georgia, serif") -> String {
        "<text x=\"\(x)\" y=\"\(y)\" font-family=\"\(family)\" font-size=\"\(size)\" font-weight=\"\(weight)\" fill=\"\(fill)\">\(escape(value))</text>"
    }

    private func rightText(_ value: String, rightX: Int, y: Int, size: Int, weight: String, fill: String = "#000", family: String = "Georgia, serif") -> String {
        "<text x=\"\(rightX)\" y=\"\(y)\" text-anchor=\"end\" font-family=\"\(family)\" font-size=\"\(size)\" font-weight=\"\(weight)\" fill=\"\(fill)\">\(escape(value))</text>"
    }

    private func centeredText(_ value: String, centerX: Int, y: Int, size: Int, weight: String, fill: String = "#000", family: String = "Georgia, serif") -> String {
        "<text x=\"\(centerX)\" y=\"\(y)\" text-anchor=\"middle\" font-family=\"\(family)\" font-size=\"\(size)\" font-weight=\"\(weight)\" fill=\"\(fill)\">\(escape(value))</text>"
    }

    private func splitRow(_ value: String) -> (left: String, right: String) {
        let parts = value.components(separatedBy: " | ")
        guard parts.count >= 2 else { return (value, "") }
        return (parts.dropLast().joined(separator: " | "), parts.last ?? "")
    }

    private func pageContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        switch model.mode {
        case .home:
            return homeContent(x: x, y: y, width: width, bottom: bottom)
        case .codex:
            return codexContent(x: x, y: y, width: width, bottom: bottom)
        case .document:
            return documentContent(x: x, y: y, width: width, bottom: bottom)
        case .image:
            return imageContent(x: x, y: y, width: width, bottom: bottom)
        case .music:
            return musicContent(x: x, y: y, width: width, bottom: bottom)
        case .weather:
            return weatherContent(x: x, y: y, width: width, bottom: bottom)
        case .calendar:
            return calendarContent(x: x, y: y, width: width, bottom: bottom)
        case .focus:
            return focusContent(x: x, y: y, width: width, bottom: bottom)
        case .system:
            return systemContent(x: x, y: y, width: width, bottom: bottom)
        case .screensaver:
            return screensaverContent(x: x, y: y, width: width, bottom: bottom)
        }
    }

    private func homeContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("今天", x: x, y: y + 128, size: 154, weight: "700")
        body += text(model.subhead, x: x + 6, y: y + 194, size: 36, weight: "400")
        body += modeArt(cx: x + width - 78, cy: y + 108)

        if let primary = model.metrics.first {
            body += text(primary.label, x: x, y: y + 302, size: 30, weight: "700", family: "Menlo, Monaco, monospace")
            body += wrapped(primary.value, x: x, y: y + 368, width: width - 24, size: 54, maxLines: 2)
        }

        let adviceTop = y + 524
        body += rect(x: x, y: adviceTop, width: width, height: 132, stroke: 0, fill: "#111")
        body += text("接下来看什么", x: x + 30, y: adviceTop + 46, size: 25, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += text(homeAdvice, x: x + 30, y: adviceTop + 102, size: 42, weight: "700", fill: "#fff")

        body += metricStrip(x: x, y: y + 720, width: width, metrics: Array(model.metrics.dropFirst().prefix(3)))
        body += workList(x: x, y: y + 938, width: width, bottom: bottom, title: "今日", rows: model.notes)
        return body
    }

    private func codexContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("Codex", x: x, y: y + 98, size: 122, weight: "700")
        body += rightText("工作台", rightX: x + width, y: y + 88, size: 38, weight: "700", family: "Menlo, Monaco, monospace")
        body += text(model.subhead, x: x + 4, y: y + 154, size: 30, weight: "400", family: "Menlo, Monaco, monospace")

        let heroTop = y + 214
        body += rect(x: x, y: heroTop, width: width, height: 216, stroke: 0, fill: "#000")
        body += text(model.metrics.first?.label ?? "当前任务", x: x + 30, y: heroTop + 50, size: 28, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += wrapped(model.metrics.first?.value ?? "等待 Codex 任务", x: x + 30, y: heroTop + 120, width: width - 60, size: 54, maxLines: 2, fill: "#fff")

        body += metricStrip(x: x, y: y + 478, width: width, metrics: Array(model.metrics.dropFirst().prefix(3)))
        body += workList(x: x, y: y + 690, width: width, bottom: bottom, title: "限额与最近任务", rows: model.notes)
        return body
    }

    private func documentContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("文档", x: x, y: y + 96, size: 118, weight: "700")
        body += text(model.subhead, x: x + 4, y: y + 154, size: 34, weight: "400")
        body += documentIcon(cx: x + width - 82, cy: y + 84)

        let titleTop = y + 202
        body += rect(x: x, y: titleTop, width: width, height: 142, stroke: 0, fill: "#000")
        body += text("当前对照", x: x + 30, y: titleTop + 48, size: 27, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += wrapped(model.headline, x: x + 30, y: titleTop + 108, width: width - 60, size: 50, maxLines: 1, fill: "#fff")

        body += documentList(x: x, y: y + 404, width: width, bottom: bottom - 46, rows: model.notes)
        body += text("翻页：Mac 顶栏「文档上一页 / 下一页」", x: x, y: bottom - 8, size: 23, weight: "400", family: "Menlo, Monaco, monospace")
        return body
    }

    private func imageContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("投射", x: x, y: y + 96, size: 118, weight: "700")
        body += text(model.subhead, x: x + 4, y: y + 154, size: 34, weight: "400")
        body += imageIcon(cx: x + width - 86, cy: y + 84)

        let heroTop = y + 202
        body += rect(x: x, y: heroTop, width: width, height: 132, stroke: 0, fill: "#000")
        body += text("当前内容", x: x + 30, y: heroTop + 48, size: 27, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += wrapped(model.headline, x: x + 30, y: heroTop + 102, width: width - 60, size: 46, maxLines: 1, fill: "#fff")

        let imageTop = y + 376
        let imageBottom = bottom - 74
        let imageHeight = max(220, imageBottom - imageTop)
        body += rect(x: x, y: imageTop, width: width, height: imageHeight, stroke: 5)
        if let dataURI = model.imageDataURI, !dataURI.isEmpty {
            body += "<image x=\"\(x + 18)\" y=\"\(imageTop + 18)\" width=\"\(width - 36)\" height=\"\(imageHeight - 36)\" preserveAspectRatio=\"xMidYMid meet\" href=\"\(dataURI)\"/>"
        } else {
            body += centeredText("从 Mac 顶栏投射图片或截屏", centerX: x + width / 2, y: imageTop + imageHeight / 2 - 20, size: 36, weight: "700")
            body += centeredText("支持 PNG / JPG / HEIC 等常见图片", centerX: x + width / 2, y: imageTop + imageHeight / 2 + 36, size: 26, weight: "400")
        }
        body += text(model.imageMeta ?? "等待图片", x: x, y: bottom - 22, size: 24, weight: "400", family: "Menlo, Monaco, monospace")
        return body
    }

    private func musicContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("音乐", x: x, y: y + 100, size: 120, weight: "700")
        body += text("桌面播放控制", x: x + 4, y: y + 158, size: 34, weight: "400")
        body += modeArt(cx: x + width - 86, cy: y + 86)

        let nowPlaying = model.metrics.first?.value ?? "音乐未运行"
        body += rect(x: x, y: y + 232, width: width, height: 202, stroke: 0, fill: "#000")
        body += text("正在播放", x: x + 30, y: y + 284, size: 28, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += wrapped(nowPlaying, x: x + 30, y: y + 350, width: width - 60, size: 54, maxLines: 2, fill: "#fff")

        body += musicButtonRow(x: x, y: y + 482, width: width)
        body += metricStrip(x: x, y: y + 664, width: width, metrics: Array(model.metrics.dropFirst().prefix(2)))
        body += workList(x: x, y: y + 882, width: width, bottom: bottom, title: "控制与状态", rows: model.notes)
        return body
    }

    private func weatherContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("天气", x: x, y: y + 104, size: 122, weight: "700")
        body += text(model.subhead, x: x + 4, y: y + 164, size: 34, weight: "400")
        body += modeArt(cx: x + width - 82, cy: y + 86)

        let heroTop = y + 236
        body += rect(x: x, y: heroTop, width: width, height: 210, stroke: 0, fill: "#000")
        body += text("出门前判断", x: x + 30, y: heroTop + 52, size: 28, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += wrapped(weatherAdvice, x: x + 30, y: heroTop + 126, width: width - 60, size: 54, maxLines: 2, fill: "#fff")

        body += metricStrip(x: x, y: y + 500, width: width, metrics: model.metrics)
        body += workList(x: x, y: y + 720, width: width, bottom: bottom, title: "未来几小时", rows: model.notes)
        return body
    }

    private func calendarContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("日历", x: x, y: y + 104, size: 122, weight: "700")
        body += text(model.subhead, x: x + 4, y: y + 164, size: 34, weight: "400")
        body += modeArt(cx: x + width - 82, cy: y + 82)

        let next = model.metrics.first?.value ?? "暂无日程"
        let heroTop = y + 236
        body += rect(x: x, y: heroTop, width: width, height: 210, stroke: 0, fill: "#000")
        body += text("下一项", x: x + 30, y: heroTop + 52, size: 28, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += wrapped(next, x: x + 30, y: heroTop + 136, width: width - 60, size: 60, maxLines: 1, fill: "#fff")

        body += metricStrip(x: x, y: y + 500, width: width, metrics: Array(model.metrics.dropFirst().prefix(2)))
        body += workList(x: x, y: y + 720, width: width, bottom: bottom, title: "今日提醒", rows: model.notes)
        return body
    }

    private func focusContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("专注", x: x, y: y + 104, size: 122, weight: "700")
        body += text("只保留当前时间块", x: x + 4, y: y + 164, size: 34, weight: "400")
        body += modeArt(cx: x + width - 82, cy: y + 86)

        let heroTop = y + 236
        body += rect(x: x, y: heroTop, width: width, height: 230, stroke: 0, fill: "#000")
        body += text("当前任务", x: x + 30, y: heroTop + 56, size: 28, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += wrapped(model.metrics.first?.value ?? "等待任务", x: x + 30, y: heroTop + 132, width: width - 60, size: 54, maxLines: 2, fill: "#fff")

        body += metricStrip(x: x, y: y + 520, width: width, metrics: Array(model.metrics.dropFirst().prefix(2)))
        body += workList(x: x, y: y + 740, width: width, bottom: bottom, title: "专注规则", rows: model.notes)
        return body
    }

    private func systemContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("系统", x: x, y: y + 104, size: 122, weight: "700")
        body += text(model.subhead, x: x + 4, y: y + 164, size: 30, weight: "400", family: "Menlo, Monaco, monospace")
        body += modeArt(cx: x + width - 82, cy: y + 86)

        let heroTop = y + 236
        body += rect(x: x, y: heroTop, width: width, height: 212, stroke: 0, fill: "#000")
        body += text("资源压力", x: x + 30, y: heroTop + 52, size: 28, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += wrapped(model.metrics.first?.value ?? "不可用", x: x + 30, y: heroTop + 122, width: width - 60, size: 48, maxLines: 2, fill: "#fff")

        body += metricStrip(x: x, y: y + 500, width: width, metrics: Array(model.metrics.dropFirst().prefix(3)))
        body += workList(x: x, y: y + 720, width: width, bottom: bottom, title: "高占用进程", rows: model.notes)
        return body
    }

    private func screensaverContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += centeredText(model.headline, centerX: x + width / 2, y: y + 344, size: 190, weight: "700", family: "Georgia, serif")
        body += centeredText(model.subhead, centerX: x + width / 2, y: y + 416, size: 38, weight: "400")
        body += line(x1: x + 110, y1: y + 508, x2: x + width - 110, y2: y + 508, stroke: 5)
        body += centeredText("离开时保持安静显示", centerX: x + width / 2, y: y + 586, size: 44, weight: "700")
        body += centeredText("回到 Mac 顶栏即可切换内容", centerX: x + width / 2, y: y + 650, size: 34, weight: "400")
        body += workList(x: x, y: y + 808, width: width, bottom: bottom, title: "状态", rows: model.notes)
        return body
    }

    private var homeAdvice: String {
        let values = model.metrics.map(\.value).joined(separator: " ")
        if values.contains("无日程") || values.contains("暂无日程") {
            return "先看天气，再推进项目"
        }
        if values.contains("湿度") {
            return "先看天气，再看日程"
        }
        return "看一眼就知道今天怎么安排"
    }

    private var weatherAdvice: String {
        if let advice = model.metrics.first(where: { $0.label == "建议" })?.value,
           !advice.isEmpty {
            return advice
        }
        let value = model.metrics.map(\.value).joined(separator: " ")
        if value.contains("湿度") {
            return "湿度偏高，少开窗"
        }
        if value.contains("--") || value.contains("不可用") {
            return "天气源暂不可用"
        }
        return "出门前看温度和风"
    }

    private func metricStrip(x: Int, y: Int, width: Int, metrics: [Metric]) -> String {
        guard !metrics.isEmpty else { return "" }
        let gap = 18
        let count = min(3, metrics.count)
        let cardWidth = (width - gap * (count - 1)) / count
        return metrics.prefix(count).enumerated().map { index, metric in
            let cx = x + index * (cardWidth + gap)
            return """
            <rect x="\(cx)" y="\(y)" width="\(cardWidth)" height="172" fill="#fff" stroke="#000" stroke-width="4"/>
            \(text(metric.label, x: cx + 24, y: y + 50, size: 26, weight: "700", family: "Menlo, Monaco, monospace"))
            \(wrapped(metric.value, x: cx + 24, y: y + 108, width: cardWidth - 48, size: 33, maxLines: 2))
            """
        }.joined()
    }

    private func workList(x: Int, y: Int, width: Int, bottom: Int, title: String, rows: [String]) -> String {
        var body = ""
        body += line(x1: x, y1: y, x2: x + width, y2: y, stroke: 4)
        body += text(title, x: x, y: y + 48, size: 31, weight: "700", family: "Menlo, Monaco, monospace")
        let rowHeight = 70
        let firstBaseline = y + 110
        var rowY = firstBaseline
        while rowY < bottom - 10 {
            body += line(x1: x, y1: rowY - 34, x2: x + width, y2: rowY - 34, stroke: 2)
            rowY += rowHeight
        }
        let capacity = max(1, (bottom - y - 88) / rowHeight)
        for (index, note) in rows.prefix(capacity).enumerated() {
            let row = splitRow(note)
            let baseline = firstBaseline + index * rowHeight
            body += wrapped(row.left, x: x, y: baseline, width: width - 276, size: 34, maxLines: 1)
            body += rightText(row.right, rightX: x + width, y: baseline, size: 28, weight: "700", family: "Menlo, Monaco, monospace")
        }
        return body
    }

    private func documentList(x: Int, y: Int, width: Int, bottom: Int, rows: [String]) -> String {
        var body = ""
        body += line(x1: x, y1: y, x2: x + width, y2: y, stroke: 4)
        body += text("文档内容", x: x, y: y + 48, size: 31, weight: "700", family: "Menlo, Monaco, monospace")
        let firstBaseline = y + 110
        let rowHeight = 66
        let capacity = max(1, (bottom - y - 78) / rowHeight)

        var lineY = firstBaseline - 36
        while lineY < bottom - 10 {
            body += line(x1: x, y1: lineY, x2: x + width, y2: lineY, stroke: 2)
            lineY += rowHeight
        }

        for (index, note) in rows.prefix(capacity).enumerated() {
            let row = splitRow(note)
            let baseline = firstBaseline + index * rowHeight
            if row.right == "标题" {
                body += wrapped(row.left, x: x, y: baseline, width: width - 110, size: 35, maxLines: 1)
            } else {
                body += wrapped(row.left, x: x, y: baseline, width: width - 172, size: 32, maxLines: 1)
                body += rightText(row.right, rightX: x + width, y: baseline, size: 24, weight: "700", family: "Menlo, Monaco, monospace")
            }
        }
        return body
    }

    private func musicButtonRow(x: Int, y: Int, width: Int) -> String {
        let gap = 22
        let buttonWidth = (width - gap * 2) / 3
        let labels = [("上一首", "PREV", false), ("播放/暂停", "PLAY", true), ("下一首", "NEXT", false)]
        return labels.enumerated().map { index, item in
            let bx = x + index * (buttonWidth + gap)
            let fill = item.2 ? "#000" : "#fff"
            let ink = item.2 ? "#fff" : "#000"
            return """
            <rect x="\(bx)" y="\(y)" width="\(buttonWidth)" height="128" fill="\(fill)" stroke="#000" stroke-width="5"/>
            <text x="\(bx + buttonWidth / 2)" y="\(y + 50)" text-anchor="middle" font-family="Menlo, Monaco, monospace" font-size="23" font-weight="700" fill="\(ink)">\(item.1)</text>
            <text x="\(bx + buttonWidth / 2)" y="\(y + 96)" text-anchor="middle" font-family="Georgia, serif" font-size="35" font-weight="700" fill="\(ink)">\(item.0)</text>
            """
        }.joined()
    }

    private var titleSize: Int {
        switch model.mode {
        case .screensaver, .home: return 112
        case .music: return 86
        default: return 94
        }
    }

    private func modeArt(cx: Int, cy: Int) -> String {
        switch model.mode {
        case .weather, .home:
            return """
            <circle cx="\(cx)" cy="\(cy)" r="34" fill="#fff" stroke="#000" stroke-width="6"/>
            <line x1="\(cx)" y1="\(cy - 62)" x2="\(cx)" y2="\(cy - 48)" stroke="#000" stroke-width="5"/>
            <line x1="\(cx - 62)" y1="\(cy)" x2="\(cx - 48)" y2="\(cy)" stroke="#000" stroke-width="5"/>
            <line x1="\(cx + 48)" y1="\(cy)" x2="\(cx + 62)" y2="\(cy)" stroke="#000" stroke-width="5"/>
            <path d="M \(cx - 26) \(cy + 50) C \(cx + 4) \(cy + 24), \(cx + 54) \(cy + 30), \(cx + 70) \(cy + 52)" fill="none" stroke="#000" stroke-width="6"/>
            """
        case .music:
            return """
            <circle cx="\(cx - 26)" cy="\(cy + 34)" r="20" fill="#fff" stroke="#000" stroke-width="6"/>
            <circle cx="\(cx + 36)" cy="\(cy + 18)" r="20" fill="#fff" stroke="#000" stroke-width="6"/>
            <line x1="\(cx - 6)" y1="\(cy + 31)" x2="\(cx - 6)" y2="\(cy - 48)" stroke="#000" stroke-width="7"/>
            <line x1="\(cx + 56)" y1="\(cy + 15)" x2="\(cx + 56)" y2="\(cy - 64)" stroke="#000" stroke-width="7"/>
            <line x1="\(cx - 6)" y1="\(cy - 48)" x2="\(cx + 56)" y2="\(cy - 64)" stroke="#000" stroke-width="7"/>
            """
        case .focus:
            return """
            <circle cx="\(cx)" cy="\(cy)" r="58" fill="#fff" stroke="#000" stroke-width="7"/>
            <circle cx="\(cx)" cy="\(cy)" r="28" fill="#fff" stroke="#000" stroke-width="6"/>
            <line x1="\(cx)" y1="\(cy - 72)" x2="\(cx)" y2="\(cy + 72)" stroke="#000" stroke-width="5"/>
            <line x1="\(cx - 72)" y1="\(cy)" x2="\(cx + 72)" y2="\(cy)" stroke="#000" stroke-width="5"/>
            """
        case .calendar:
            return """
            <rect x="\(cx - 54)" y="\(cy - 46)" width="108" height="92" fill="#fff" stroke="#000" stroke-width="7"/>
            <line x1="\(cx - 54)" y1="\(cy - 18)" x2="\(cx + 54)" y2="\(cy - 18)" stroke="#000" stroke-width="6"/>
            <line x1="\(cx - 20)" y1="\(cy + 12)" x2="\(cx + 26)" y2="\(cy + 12)" stroke="#000" stroke-width="6"/>
            """
        case .system:
            return """
            <rect x="\(cx - 58)" y="\(cy - 50)" width="116" height="100" fill="#fff" stroke="#000" stroke-width="7"/>
            <polyline points="\(cx - 42),\(cy + 20) \(cx - 18),\(cy - 10) \(cx + 2),\(cy + 6) \(cx + 28),\(cy - 28) \(cx + 44),\(cy - 2)" fill="none" stroke="#000" stroke-width="6"/>
            """
        default:
            return ""
        }
    }

    private func imageIcon(cx: Int, cy: Int) -> String {
        """
        <rect x="\(cx - 58)" y="\(cy - 48)" width="116" height="96" fill="#fff" stroke="#000" stroke-width="7"/>
        <circle cx="\(cx + 26)" cy="\(cy - 18)" r="13" fill="#fff" stroke="#000" stroke-width="5"/>
        <path d="M \(cx - 42) \(cy + 30) L \(cx - 8) \(cy - 4) L \(cx + 14) \(cy + 18) L \(cx + 40) \(cy - 10) L \(cx + 52) \(cy + 30) Z" fill="none" stroke="#000" stroke-width="6"/>
        """
    }

    private func documentIcon(cx: Int, cy: Int) -> String {
        """
        <path d="M \(cx - 50) \(cy - 58) H \(cx + 28) L \(cx + 58) \(cy - 28) V \(cy + 58) H \(cx - 50) Z" fill="#fff" stroke="#000" stroke-width="7"/>
        <path d="M \(cx + 28) \(cy - 58) V \(cy - 28) H \(cx + 58)" fill="none" stroke="#000" stroke-width="7"/>
        <line x1="\(cx - 26)" y1="\(cy - 18)" x2="\(cx + 26)" y2="\(cy - 18)" stroke="#000" stroke-width="6"/>
        <line x1="\(cx - 26)" y1="\(cy + 10)" x2="\(cx + 34)" y2="\(cy + 10)" stroke="#000" stroke-width="6"/>
        <line x1="\(cx - 26)" y1="\(cy + 38)" x2="\(cx + 12)" y2="\(cy + 38)" stroke="#000" stroke-width="6"/>
        """
    }

    private func widgetRail(x: Int, y: Int, width: Int, height: Int) -> String {
        let gap = 16
        let itemWidth = (width - gap * 3) / 4
        let widgets = bottomWidgets()
        return widgets.enumerated().map { index, widget in
            let ix = x + index * (itemWidth + gap)
            let active = widget.title == activeWidgetTitle
            let fill = active ? "#000" : "#fff"
            let ink = active ? "#fff" : "#000"
            let stroke = active ? 0 : 4
            return """
            <rect x="\(ix)" y="\(y)" width="\(itemWidth)" height="\(height)" fill="\(fill)" stroke="#000" stroke-width="\(stroke)"/>
            \(widget.icon(ix + 24, y + 30, ink))
            <text x="\(ix + 82)" y="\(y + 58)" font-family="Menlo, Monaco, monospace" font-size="25" font-weight="700" fill="\(ink)">\(escape(widget.title))</text>
            <text x="\(ix + 26)" y="\(y + 126)" font-family="Georgia, serif" font-size="34" font-weight="700" fill="\(ink)">\(escape(widget.value))</text>
            """
        }.joined()
    }

    private struct BottomWidget {
        let title: String
        let value: String
        let icon: (Int, Int, String) -> String
    }

    private var activeWidgetTitle: String {
        switch model.mode {
        case .home: return "时间"
        case .weather: return "天气"
        case .music: return "音乐"
        case .calendar: return "日历"
        case .screensaver: return "时间"
        default: return ""
        }
    }

    private func bottomWidgets() -> [BottomWidget] {
        [
            BottomWidget(title: "天气", value: shortWeather(), icon: sunIcon),
            BottomWidget(title: "时间", value: DashboardData.clockTime(), icon: clockIcon),
            BottomWidget(title: "音乐", value: shortMusic(), icon: musicIcon),
            BottomWidget(title: "日历", value: shortCalendar(), icon: calendarIcon)
        ]
    }

    private func shortWeather() -> String {
        if let currentWeather = model.metrics.first(where: { $0.label == "天气" || $0.label == "室外" || $0.label == "现在" })?.value,
           let temp = firstTemperature(in: currentWeather) {
            return temp
        }
        let value = CommandRunner.shell("curl -m 2 -s 'https://wttr.in/?format=%t' 2>/dev/null || true")
        return value.isEmpty ? "--" : value
    }

    private func firstTemperature(in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"[+-]\d+°C"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value) else {
            return nil
        }
        return String(value[range])
    }

    private func shortMusic() -> String {
        let value = CommandRunner.appleScript("""
        tell application "Music"
          if it is running then
            if player state is playing then
              return name of current track
            else
              return "暂停"
            end if
          else
            return "未播放"
          end if
        end tell
        """)
        return value.isEmpty ? "未播放" : String(value.prefix(8))
    }

    private func shortCalendar() -> String {
        let value = CommandRunner.shell("command -v icalBuddy >/dev/null && icalBuddy -nc -nrd -ea -li 1 eventsToday 2>/dev/null | head -1 || true")
        return value.isEmpty ? "无日程" : String(value.prefix(8))
    }

    private func sunIcon(x: Int, y: Int, ink: String) -> String {
        "<circle cx=\"\(x + 20)\" cy=\"\(y + 20)\" r=\"18\" fill=\"none\" stroke=\"\(ink)\" stroke-width=\"4\"/>"
    }

    private func clockIcon(x: Int, y: Int, ink: String) -> String {
        "<circle cx=\"\(x + 20)\" cy=\"\(y + 20)\" r=\"20\" fill=\"none\" stroke=\"\(ink)\" stroke-width=\"4\"/><line x1=\"\(x + 20)\" y1=\"\(y + 20)\" x2=\"\(x + 20)\" y2=\"\(y + 8)\" stroke=\"\(ink)\" stroke-width=\"3\"/><line x1=\"\(x + 20)\" y1=\"\(y + 20)\" x2=\"\(x + 31)\" y2=\"\(y + 20)\" stroke=\"\(ink)\" stroke-width=\"3\"/>"
    }

    private func musicIcon(x: Int, y: Int, ink: String) -> String {
        "<circle cx=\"\(x + 14)\" cy=\"\(y + 34)\" r=\"10\" fill=\"none\" stroke=\"\(ink)\" stroke-width=\"4\"/><line x1=\"\(x + 24)\" y1=\"\(y + 32)\" x2=\"\(x + 24)\" y2=\"\(y + 4)\" stroke=\"\(ink)\" stroke-width=\"5\"/>"
    }

    private func calendarIcon(x: Int, y: Int, ink: String) -> String {
        "<rect x=\"\(x)\" y=\"\(y + 4)\" width=\"42\" height=\"36\" fill=\"none\" stroke=\"\(ink)\" stroke-width=\"4\"/><line x1=\"\(x)\" y1=\"\(y + 16)\" x2=\"\(x + 42)\" y2=\"\(y + 16)\" stroke=\"\(ink)\" stroke-width=\"3\"/>"
    }

    private func wrapped(_ value: String, x: Int, y: Int, width: Int, size: Int, maxLines: Int) -> String {
        wrapped(value, x: x, y: y, width: width, size: size, maxLines: maxLines, fill: "#000")
    }

    private func wrapped(_ value: String, x: Int, y: Int, width: Int, size: Int, maxLines: Int, fill: String) -> String {
        let charWidth = containsWideGlyphs(value) ? Double(size) * 0.92 : Double(size) * 0.55
        let maxChars = max(6, width / max(12, Int(charWidth)))
        var lines: [String] = []
        for segment in value.components(separatedBy: "\n") {
            guard lines.count < maxLines else { break }
            lines.append(contentsOf: wrap(segment, maxChars: maxChars, maxLines: maxLines - lines.count))
        }
        return lines.enumerated().map { index, line in
            text(line, x: x, y: y + index * Int(Double(size) * 1.18), size: size, weight: "700", fill: fill)
        }.joined()
    }

    private func wrap(_ value: String, maxChars: Int, maxLines: Int) -> [String] {
        var result: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty, result.count < maxLines {
                result.append(current)
                current = ""
            }
        }

        for token in value.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
            if token.count > maxChars {
                flush()
                var remaining = token
                while !remaining.isEmpty, result.count < maxLines {
                    result.append(String(remaining.prefix(maxChars)))
                    remaining = String(remaining.dropFirst(maxChars))
                }
                continue
            }
            let next = current.isEmpty ? token : "\(current) \(token)"
            if next.count > maxChars {
                flush()
                current = token
            } else {
                current = next
            }
            if result.count == maxLines { break }
        }
        flush()

        if result.isEmpty {
            result = [String(value.prefix(maxChars))]
        }
        if value.count > result.joined(separator: " ").count, !result.isEmpty {
            result[result.count - 1] = String(result[result.count - 1].prefix(max(1, maxChars - 3))) + "..."
        }
        return Array(result.prefix(maxLines))
    }

    private func containsWideGlyphs(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value)) ||
            (0x3000...0x303F).contains(Int(scalar.value)) ||
            (0xFF00...0xFFEF).contains(Int(scalar.value))
        }
    }
}

final class DashboardServer: @unchecked Sendable {
    private let state: AppState
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "kindle.dashboard.server")

    init(state: AppState) {
        self.state = state
    }

    func start(port: UInt16 = 8787) throws {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var requestData = accumulated
            if let data {
                requestData.append(data)
            }
            if error == nil, !isComplete, !self.hasCompleteRequest(requestData) {
                self.receiveRequest(on: connection, accumulated: requestData)
                return
            }

            let request = String(data: requestData, encoding: .utf8) ?? ""
            let response = self.response(for: request)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func hasCompleteRequest(_ data: Data) -> Bool {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter) else {
            return false
        }
        let headerData = data[..<headerRange.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else {
            return true
        }
        let contentLength = header
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { line -> Int? in
                let rawValue = line.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                return Int(value)
            } ?? 0
        return data.count - headerRange.upperBound >= contentLength
    }

    private func response(for request: String) -> Data {
        let method = request.split(separator: " ").first.map(String.init) ?? "GET"
        let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let cleanPath = path.split(separator: "?").first.map(String.init) ?? path

        if cleanPath == "/document", method.uppercased() == "POST" {
            let title = queryValue("title", in: path) ?? "Markdown 文档"
            let markdown = requestBody(from: request)
            state.setDocument(title: title, markdown: markdown.isEmpty ? "# 空文档\n\n没有收到 Markdown 内容。" : markdown)
            return http(body: "OK\n", status: "200 OK", contentType: "text/plain; charset=utf-8")
        }
        if cleanPath == "/document/next" {
            state.turnDocumentPage(1)
            return redirect()
        }
        if cleanPath == "/document/previous" || cleanPath == "/document/prev" {
            state.turnDocumentPage(-1)
            return redirect()
        }
        if cleanPath == "/refresh" {
            state.requestRefresh()
            return http(body: "OK\n", status: "200 OK", contentType: "text/plain; charset=utf-8")
        }
        if cleanPath == "/kindle/status" {
            state.updateKindleStatus(
                battery: queryValue("battery", in: path),
                charging: queryValue("charging", in: path)
            )
            return http(body: "OK\n", status: "200 OK", contentType: "text/plain; charset=utf-8")
        }

        if let rawMode = queryValue("mode", in: path),
           let mode = KindleMode(rawValue: rawMode) {
            state.setMode(mode)
        }

        if cleanPath.hasPrefix("/mode/") {
            let raw = cleanPath.replacingOccurrences(of: "/mode/", with: "")
            if let mode = KindleMode(rawValue: raw) {
                state.setMode(mode)
            }
            return redirect()
        }
        if cleanPath == "/orientation/toggle" {
            let next: KindleOrientation = state.snapshot().orientation == .portrait ? .landscapeClockwise : .portrait
            state.setOrientation(next)
            return redirect()
        }
        if cleanPath == "/orientation/portrait" {
            state.setOrientation(.portrait)
            return redirect()
        }
        if cleanPath == "/orientation/landscape" {
            state.setOrientation(.landscapeClockwise)
            return redirect()
        }
        if cleanPath == "/cycle/toggle" {
            state.setCycleEnabled(!state.snapshot().cycleEnabled)
            return redirect()
        }
        if cleanPath == "/cycle/on" {
            state.setCycleEnabled(true)
            return redirect()
        }
        if cleanPath == "/cycle/off" {
            state.setCycleEnabled(false)
            return redirect()
        }
        if cleanPath.hasPrefix("/control/playpause") {
            _ = CommandRunner.appleScript(#"tell application "Music" to playpause"#)
            state.setMode(.music)
            return redirect()
        }
        if cleanPath.hasPrefix("/control/next") {
            _ = CommandRunner.appleScript(#"tell application "Music" to next track"#)
            state.setMode(.music)
            return redirect()
        }
        if cleanPath.hasPrefix("/control/previous") {
            _ = CommandRunner.appleScript(#"tell application "Music" to previous track"#)
            state.setMode(.music)
            return redirect()
        }

        let snapshot = state.snapshot()
        if cleanPath == "/control.json" {
            return http(body: controlJSON(snapshot), status: "200 OK", contentType: "application/json; charset=utf-8")
        }
        let model = DashboardData.make(snapshot: snapshot)

        if cleanPath == "/frame.svg" || cleanPath == "/native.svg" {
            return http(body: SVGRenderer(model: model).svg(), status: "200 OK", contentType: "image/svg+xml; charset=utf-8")
        }
        if cleanPath == "/frame.png" || cleanPath == "/native.png" {
            let svg = SVGRenderer(model: model).svg()
            if let data = pngData(fromSVG: svg) {
                return http(data: data, status: "200 OK", contentType: "image/png")
            }
            return http(body: "PNG render failed\n", status: "500 Internal Server Error", contentType: "text/plain; charset=utf-8")
        }
        if cleanPath == "/kindle-client.sh" {
            return http(body: kindleClientScript(), status: "200 OK", contentType: "text/plain; charset=utf-8")
        }
        let body = HTMLRenderer(model: model, snapshot: snapshot).html()
        return http(body: body, status: "200 OK", contentType: "text/html; charset=utf-8")
    }

    private func controlJSON(_ snapshot: AppSnapshot) -> String {
        """
        {"refreshSerial":\(snapshot.refreshSerial),"refreshInterval":\(snapshot.lightRefreshInterval),"lightRefreshInterval":\(snapshot.lightRefreshInterval),"fullRefreshInterval":\(snapshot.fullRefreshInterval),"frontlightEnabled":\(snapshot.frontlightEnabled ? "true" : "false"),"frontlightLevel":\(snapshot.frontlightLevel),"batteryProtectionEnabled":\(snapshot.batteryProtectionEnabled ? "true" : "false"),"batteryLowerLimit":\(snapshot.batteryLowerLimit),"batteryUpperLimit":\(snapshot.batteryUpperLimit)}
        """
    }

    private func requestBody(from request: String) -> String {
        if let range = request.range(of: "\r\n\r\n") {
            return String(request[range.upperBound...])
        }
        if let range = request.range(of: "\n\n") {
            return String(request[range.upperBound...])
        }
        return ""
    }

    private func queryValue(_ name: String, in path: String) -> String? {
        guard let query = path.split(separator: "?", maxSplits: 1).dropFirst().first else {
            return nil
        }
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.first == name else { continue }
            let value = parts.count > 1 ? parts[1] : ""
            return value.removingPercentEncoding ?? value
        }
        return nil
    }

    private func redirect() -> Data {
        let response = "HTTP/1.1 303 See Other\r\nLocation: /\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        return Data(response.utf8)
    }

    private func http(body: String, status: String, contentType: String) -> Data {
        let bodyData = Data(body.utf8)
        return http(data: bodyData, status: status, contentType: contentType)
    }

    private func http(data bodyData: Data, status: String, contentType: String) -> Data {
        var header = ""
        header += "HTTP/1.1 \(status)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(bodyData.count)\r\n"
        header += "Cache-Control: no-store\r\n"
        header += "Connection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(bodyData)
        return data
    }

    private func pngData(fromSVG svg: String) -> Data? {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
        let svgURL = directory.appendingPathComponent("kindledashboard-\(id).svg")
        let pngURL = directory.appendingPathComponent("kindledashboard-\(id).png")
        defer {
            try? FileManager.default.removeItem(at: svgURL)
            try? FileManager.default.removeItem(at: pngURL)
        }
        do {
            try svg.write(to: svgURL, atomically: true, encoding: .utf8)
        } catch {
            return nil
        }
        _ = CommandRunner.run("/usr/bin/sips", ["-s", "format", "png", svgURL.path, "--out", pngURL.path])
        return try? Data(contentsOf: pngURL)
    }

    private func kindleClientScript() -> String {
        """
        #!/bin/sh
        # Prototype Kindle-side pull client. Install through KUAL after FBInk is available.
        SERVER="${1:-\(DashboardData.localURL())}"
        OUT="/mnt/us/extensions/kindle_dock/current.png"
        mkdir -p /mnt/us/extensions/kindle_dock
        lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null || true
        while :; do
          wget -q -O "$OUT" "$SERVER/frame.png" || curl -fsSL "$SERVER/frame.png" -o "$OUT"
          if command -v fbink >/dev/null 2>&1; then
            fbink -c -f -a -g "file=$OUT" 2>/dev/null || true
          fi
          sleep 30
        done
        """
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem!
    private var server: DashboardServer!
    private var settingsMenuItem: NSMenuItem?
    private var modeMenuItems: [NSMenuItem] = []
    private var portraitMenuItem: NSMenuItem?
    private var landscapeMenuItem: NSMenuItem?
    private var lightRefreshMenuItems: [NSMenuItem] = []
    private var fullRefreshMenuItems: [NSMenuItem] = []
    private var cycleMenuItems: [NSMenuItem] = []
    private var frontlightMenuItems: [NSMenuItem] = []
    private var batteryProtectionMenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        server = DashboardServer(state: state)
        do {
            try server.start()
        } catch {
            showAlert("Failed to start Kindle server on port 8787: \(error)")
        }
        setupMenu()
    }

    private func setupMenu() {
        settingsMenuItem = nil
        modeMenuItems.removeAll()
        portraitMenuItem = nil
        landscapeMenuItem = nil
        lightRefreshMenuItems.removeAll()
        fullRefreshMenuItems.removeAll()
        cycleMenuItems.removeAll()
        frontlightMenuItems.removeAll()
        batteryProtectionMenuItems.removeAll()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = makeStatusIcon()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "KindleDashboard"

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(infoMenuItem("Kindle Dashboard"))
        menu.addItem(infoMenuItem("已连接 · 本机服务"))
        menu.addItem(.separator())
        for mode in KindleMode.allCases {
            let item = menuItem(mode.menuTitle, #selector(selectMode(_:)), symbol: mode.menuSymbolName)
            item.representedObject = mode.rawValue
            modeMenuItems.append(item)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("打开 Markdown 文档...", #selector(openMarkdownDocument), symbol: "doc.text"))
        menu.addItem(menuItem("文档上一页", #selector(previousDocumentPage), symbol: "chevron.left"))
        menu.addItem(menuItem("文档下一页", #selector(nextDocumentPage), symbol: "chevron.right"))
        menu.addItem(.separator())
        menu.addItem(menuItem("投射图片...", #selector(openProjectionImage), symbol: "photo"))
        menu.addItem(menuItem("投射当前截屏", #selector(projectScreenshot), symbol: "camera.viewfinder"))

        menu.addItem(.separator())
        menu.addItem(menuItem("立即刷新 Kindle", #selector(refreshKindleNow), symbol: "arrow.clockwise"))

        menu.addItem(.separator())
        menu.addItem(menuItem("播放 / 暂停音乐", #selector(playPause), symbol: "playpause"))
        menu.addItem(menuItem("下一首", #selector(nextTrack), symbol: "forward.end"))
        menu.addItem(menuItem("上一首", #selector(previousTrack), symbol: "backward.end"))

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        settings.image = symbolImage("gearshape")
        settingsMenuItem = settings
        let settingsMenu = NSMenu()
        settingsMenu.addItem(statefulMenuItem("Kindle 背光", #selector(toggleFrontlight), symbol: "sun.max", storeIn: &frontlightMenuItems))
        settingsMenu.addItem(statefulMenuItem("电池保护", #selector(toggleBatteryProtection), symbol: "battery.100", storeIn: &batteryProtectionMenuItems))
        let settingsCycle = menuItem("自动轮换", #selector(toggleCycle), symbol: "arrow.triangle.2.circlepath")
        cycleMenuItems.append(settingsCycle)
        settingsMenu.addItem(settingsCycle)
        settingsMenu.addItem(.separator())
        let portrait = menuItem("竖屏布局", #selector(selectPortrait), symbol: "rectangle.portrait")
        portraitMenuItem = portrait
        settingsMenu.addItem(portrait)
        let landscape = menuItem("横屏布局", #selector(selectLandscape), symbol: "rectangle")
        landscapeMenuItem = landscape
        settingsMenu.addItem(landscape)
        settingsMenu.addItem(.separator())
        let settingsRefreshRate = NSMenuItem(title: "刷新策略", action: nil, keyEquivalent: "")
        settingsRefreshRate.image = symbolImage("timer")
        let settingsRefreshRateMenu = NSMenu()
        let lightRefresh = NSMenuItem(title: "轻刷新", action: nil, keyEquivalent: "")
        lightRefresh.image = symbolImage("arrow.clockwise")
        let lightRefreshMenu = NSMenu()
        addRefreshRateItem("10 秒", seconds: 10, action: #selector(selectLightRefreshRate(_:)), to: lightRefreshMenu, storeIn: &lightRefreshMenuItems)
        addRefreshRateItem("30 秒", seconds: 30, action: #selector(selectLightRefreshRate(_:)), to: lightRefreshMenu, storeIn: &lightRefreshMenuItems)
        addRefreshRateItem("1 分钟", seconds: 60, action: #selector(selectLightRefreshRate(_:)), to: lightRefreshMenu, storeIn: &lightRefreshMenuItems)
        addRefreshRateItem("3 分钟", seconds: 180, action: #selector(selectLightRefreshRate(_:)), to: lightRefreshMenu, storeIn: &lightRefreshMenuItems)
        addRefreshRateItem("5 分钟", seconds: 300, action: #selector(selectLightRefreshRate(_:)), to: lightRefreshMenu, storeIn: &lightRefreshMenuItems)
        lightRefresh.submenu = lightRefreshMenu
        settingsRefreshRateMenu.addItem(lightRefresh)

        let fullRefresh = NSMenuItem(title: "完全刷新", action: nil, keyEquivalent: "")
        fullRefresh.image = symbolImage("arrow.triangle.2.circlepath")
        let fullRefreshMenu = NSMenu()
        addRefreshRateItem("2 分钟", seconds: 120, action: #selector(selectFullRefreshRate(_:)), to: fullRefreshMenu, storeIn: &fullRefreshMenuItems)
        addRefreshRateItem("5 分钟", seconds: 300, action: #selector(selectFullRefreshRate(_:)), to: fullRefreshMenu, storeIn: &fullRefreshMenuItems)
        addRefreshRateItem("10 分钟", seconds: 600, action: #selector(selectFullRefreshRate(_:)), to: fullRefreshMenu, storeIn: &fullRefreshMenuItems)
        addRefreshRateItem("15 分钟", seconds: 900, action: #selector(selectFullRefreshRate(_:)), to: fullRefreshMenu, storeIn: &fullRefreshMenuItems)
        addRefreshRateItem("30 分钟", seconds: 1800, action: #selector(selectFullRefreshRate(_:)), to: fullRefreshMenu, storeIn: &fullRefreshMenuItems)
        fullRefresh.submenu = fullRefreshMenu
        settingsRefreshRateMenu.addItem(fullRefresh)
        settingsRefreshRateMenu.addItem(infoMenuItem("页面切换：立即轻刷新"))
        settingsRefreshRate.submenu = settingsRefreshRateMenu
        settingsMenu.addItem(settingsRefreshRate)
        settingsMenu.addItem(.separator())
        settingsMenu.addItem(menuItem("复制控制页地址", #selector(copyURL), symbol: "link"))
        settingsMenu.addItem(menuItem("复制真全屏地址", #selector(copyFrameURL), symbol: "rectangle.on.rectangle"))
        settings.submenu = settingsMenu
        menu.addItem(settings)
        menu.addItem(menuItem("退出 Kindle Dashboard", #selector(quit), symbol: "power"))
        statusItem.menu = menu
        updateControlMenuState()
    }

    private func menuItem(_ title: String, _ action: Selector, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: menuTitle(title), action: action, keyEquivalent: "")
        item.target = self
        if let symbol {
            item.image = symbolImage(symbol)
        }
        return item
    }

    private func statefulMenuItem(_ title: String, _ action: Selector, symbol: String, storeIn storage: inout [NSMenuItem]) -> NSMenuItem {
        let item = menuItem(title, action, symbol: symbol)
        storage.append(item)
        return item
    }

    private func infoMenuItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        return image
    }

    private func menuTitle(_ title: String, status: String = "") -> String {
        guard !status.isEmpty else { return title }
        let targetWidth = 18
        let padding = max(2, targetWidth - displayWidth(title))
        return title + String(repeating: " ", count: padding) + status
    }

    private func displayWidth(_ value: String) -> Int {
        value.unicodeScalars.reduce(0) { result, scalar in
            let code = Int(scalar.value)
            let isWide = (0x4E00...0x9FFF).contains(code) ||
                (0x3000...0x303F).contains(code) ||
                (0xFF00...0xFFEF).contains(code)
            return result + (isWide ? 2 : 1)
        }
    }

    private func addRefreshRateItem(_ title: String, seconds: Int, action: Selector, to menu: NSMenu, storeIn storage: inout [NSMenuItem]) {
        let item = NSMenuItem(title: menuTitle(title), action: action, keyEquivalent: "")
        item.representedObject = seconds
        item.target = self
        storage.append(item)
        menu.addItem(item)
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = KindleMode(rawValue: raw) else {
            return
        }
        state.setMode(mode)
        updateTitle()
    }

    @objc private func selectPortrait() {
        state.setOrientation(.portrait)
        updateTitle()
    }

    @objc private func selectLandscape() {
        state.setOrientation(.landscapeClockwise)
        updateTitle()
    }

    @objc private func toggleCycle() {
        let enabled = !state.snapshot().cycleEnabled
        state.setCycleEnabled(enabled)
        updateTitle()
    }

    @objc private func refreshKindleNow() {
        state.requestRefresh()
        updateTitle()
    }

    @objc private func toggleFrontlight() {
        let snapshot = state.snapshot()
        state.setFrontlightEnabled(!snapshot.frontlightEnabled)
        updateTitle()
    }

    @objc private func toggleBatteryProtection() {
        let snapshot = state.snapshot()
        state.setBatteryProtectionEnabled(!snapshot.batteryProtectionEnabled)
        updateTitle()
    }

    @objc private func selectLightRefreshRate(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else {
            return
        }
        state.setLightRefreshInterval(seconds)
        updateTitle()
    }

    @objc private func selectFullRefreshRate(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else {
            return
        }
        state.setFullRefreshInterval(seconds)
        updateTitle()
    }

    @objc private func playPause() {
        _ = CommandRunner.appleScript(#"tell application "Music" to playpause"#)
        state.setMode(.music)
        updateTitle()
    }

    @objc private func nextTrack() {
        _ = CommandRunner.appleScript(#"tell application "Music" to next track"#)
        state.setMode(.music)
        updateTitle()
    }

    @objc private func previousTrack() {
        _ = CommandRunner.appleScript(#"tell application "Music" to previous track"#)
        state.setMode(.music)
        updateTitle()
    }

    @objc private func openMarkdownDocument() {
        let panel = NSOpenPanel()
        panel.title = "选择 Markdown 文档"
        panel.prompt = "显示到 Kindle"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            .plainText
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let title = url.deletingPathExtension().lastPathComponent
            state.setDocument(title: title, markdown: content)
            updateTitle()
        } catch {
            showAlert("无法读取文档：\(error.localizedDescription)")
        }
    }

    @objc private func previousDocumentPage() {
        state.turnDocumentPage(-1)
        updateTitle()
    }

    @objc private func nextDocumentPage() {
        state.turnDocumentPage(1)
        updateTitle()
    }

    @objc private func openProjectionImage() {
        let panel = NSOpenPanel()
        panel.title = "选择要投射的图片"
        panel.prompt = "显示到 Kindle"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        projectImageFile(url)
    }

    @objc private func projectScreenshot() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kindledashboard-screenshot-\(Int(Date().timeIntervalSince1970)).png")
        _ = CommandRunner.run("/usr/sbin/screencapture", ["-x", url.path])
        guard FileManager.default.fileExists(atPath: url.path) else {
            showAlert("无法截屏。请检查 macOS 屏幕录制权限。")
            return
        }
        projectImageFile(url, title: "屏幕截图")
    }

    @objc private func copyURL() {
        copy(DashboardData.localURL())
    }

    @objc private func copyFrameURL() {
        copy("\(DashboardData.localURL())frame.svg")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateTitle() {
        let snapshot = state.snapshot()
        statusItem.button?.toolTip = "KindleDashboard: \(snapshot.mode.title)"
        updateControlMenuState(snapshot)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateControlMenuState()
    }

    private func updateControlMenuState(_ existingSnapshot: AppSnapshot? = nil) {
        let snapshot = existingSnapshot ?? state.snapshot()
        settingsMenuItem?.title = menuTitle("设置", status: snapshot.cycleEnabled ? "轮换开" : "轮换关")

        for item in modeMenuItems {
            guard let raw = item.representedObject as? String,
                  let mode = KindleMode(rawValue: raw) else {
                continue
            }
            item.title = menuTitle(mode.menuTitle, status: mode == snapshot.mode ? "当前" : "")
            item.state = mode == snapshot.mode ? .on : .off
        }

        portraitMenuItem?.title = menuTitle("竖屏布局", status: snapshot.orientation == .portrait ? "生效" : "")
        portraitMenuItem?.state = snapshot.orientation == .portrait ? .on : .off
        landscapeMenuItem?.title = menuTitle("横屏布局", status: snapshot.orientation == .landscapeClockwise ? "生效" : "保留")
        landscapeMenuItem?.state = snapshot.orientation == .landscapeClockwise ? .on : .off

        for item in lightRefreshMenuItems {
            guard let seconds = item.representedObject as? Int else { continue }
            item.title = menuTitle(refreshLabel(seconds), status: seconds == snapshot.lightRefreshInterval ? "当前" : "")
            item.state = seconds == snapshot.lightRefreshInterval ? .on : .off
        }

        for item in fullRefreshMenuItems {
            guard let seconds = item.representedObject as? Int else { continue }
            item.title = menuTitle(refreshLabel(seconds), status: seconds == snapshot.fullRefreshInterval ? "当前" : "")
            item.state = seconds == snapshot.fullRefreshInterval ? .on : .off
        }

        for item in cycleMenuItems {
            item.title = menuTitle("自动轮换", status: snapshot.cycleEnabled ? "开" : "关")
            item.state = snapshot.cycleEnabled ? .on : .off
        }

        for item in frontlightMenuItems {
            if snapshot.frontlightEnabled {
                item.title = menuTitle("Kindle 背光", status: "开 \(snapshot.frontlightLevel)")
                item.state = .on
            } else {
                item.title = menuTitle("Kindle 背光", status: "关")
                item.state = .off
            }
        }

        for item in batteryProtectionMenuItems {
            if snapshot.batteryProtectionEnabled {
                item.title = menuTitle("电池保护", status: "开 \(snapshot.batteryLowerLimit)-\(snapshot.batteryUpperLimit)%")
                item.state = .on
            } else {
                item.title = menuTitle("电池保护", status: "关")
                item.state = .off
            }
        }
    }

    private func refreshLabel(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) 秒"
        }
        return "\(seconds / 60) 分钟"
    }

    private func projectImageFile(_ url: URL, title overrideTitle: String? = nil) {
        guard let image = NSImage(contentsOf: url) else {
            showAlert("无法读取图片。")
            return
        }
        guard let pngData = pngDataForKindle(from: image) else {
            showAlert("无法转换图片。")
            return
        }
        let title = overrideTitle ?? url.deletingPathExtension().lastPathComponent
        let size = image.size
        let byteCount = ByteCountFormatter.string(fromByteCount: Int64(pngData.count), countStyle: .file)
        let meta = "\(Int(size.width))×\(Int(size.height)) · \(byteCount)"
        let dataURI = "data:image/png;base64,\(pngData.base64EncodedString())"
        state.setProjectionImage(title: title, dataURI: dataURI, meta: meta)
        updateTitle()
    }

    private func pngDataForKindle(from image: NSImage) -> Data? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }
        let maxDimension: CGFloat = 1400
        let scale = min(1, maxDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = NSSize(width: max(1, sourceSize.width * scale), height: max(1, sourceSize.height * scale))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width.rounded()),
            pixelsHigh: Int(targetSize.height.rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        bitmap.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: targetSize).fill()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [.compressionFactor: 0.8])
    }

    private func makeStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 18))
        image.lockFocus()
        NSColor.labelColor.setStroke()
        NSColor.labelColor.setFill()

        let device = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 14, height: 15), xRadius: 1.8, yRadius: 1.8)
        device.lineWidth = 2
        device.stroke()

        let topLine = NSBezierPath()
        topLine.move(to: NSPoint(x: 4, y: 12.5))
        topLine.line(to: NSPoint(x: 13, y: 12.5))
        topLine.lineWidth = 1.5
        topLine.stroke()

        NSBezierPath(rect: NSRect(x: 4, y: 5, width: 3.5, height: 4)).fill()
        NSBezierPath(rect: NSRect(x: 9.5, y: 5, width: 3.5, height: 4)).fill()
        NSBezierPath(ovalIn: NSRect(x: 18, y: 4, width: 4.5, height: 4.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: 18, y: 10.5, width: 4.5, height: 4.5)).fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "KindleDashboard"
        alert.informativeText = message
        alert.runModal()
    }
}

private func escape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

if CommandLine.arguments.contains("--dump-home-svg") {
    let state = AppState()
    let model = DashboardData.make(snapshot: state.snapshot())
    print(SVGRenderer(model: model).svg())
    exit(0)
}

if CommandLine.arguments.contains("--dump-codex-svg") {
    let state = AppState()
    state.setMode(.codex)
    let model = DashboardData.make(snapshot: state.snapshot())
    print(SVGRenderer(model: model).svg())
    exit(0)
}

if let dumpIndex = CommandLine.arguments.firstIndex(of: "--dump-mode"),
   CommandLine.arguments.indices.contains(dumpIndex + 1),
   let mode = KindleMode(rawValue: CommandLine.arguments[dumpIndex + 1]) {
    let state = AppState()
    state.setMode(mode)
    let model = DashboardData.make(snapshot: state.snapshot())
    print(SVGRenderer(model: model).svg())
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
