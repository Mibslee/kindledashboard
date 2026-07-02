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
    let kindleRefreshInterval: Int
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
    private var kindleRefreshInterval = 20
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

    func setKindleRefreshInterval(_ seconds: Int) {
        lock.lock()
        kindleRefreshInterval = min(600, max(5, seconds))
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
            kindleRefreshInterval: kindleRefreshInterval,
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
        let weather = weatherLine(includeDetail: true)
        let battery = CommandRunner.shell("pmset -g batt | sed -n '2p' | awk -F';' '{gsub(/^[ \t]+|[ \t]+$/, \"\", $1); gsub(/^[ \t]+|[ \t]+$/, \"\", $2); print $1 \" | \" $2}'")
        let next = nextCalendarLine()
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "今日概览",
            subhead: longDate(),
            metrics: [
                Metric(label: "天气", value: weather.isEmpty ? "天气源暂不可用" : weather, emphasis: true),
                Metric(label: "日程", value: next, emphasis: false),
                Metric(label: "Mac", value: battery.isEmpty ? "电量不可用" : battery, emphasis: false),
                Metric(label: "下一步", value: "Mac 顶栏\n切换内容", emphasis: false)
            ],
            notes: ["信息牌已就绪 | 现在", "Mac 顶栏控制页面 | 可切换", "真全屏画面 | 待 Kindle 联调"],
            footer: footer(snapshot)
        )
    }

    private static func codex(_ snapshot: AppSnapshot) -> DashboardModel {
        let sessions = recentCodexSessions()
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "Codex 看板",
            subhead: timestamp(),
            metrics: [
                Metric(label: "当前目标", value: "Kindle 副屏", emphasis: true),
                Metric(label: "构建状态", value: kindleDockBuildStatus(), emphasis: false),
                Metric(label: "下一步", value: "连接 Kindle，测试真全屏画面", emphasis: false)
            ],
            notes: sessions,
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
                Metric(label: "用途", value: "边看步骤边操作", emphasis: true),
                Metric(label: "翻页", value: "顶栏菜单 /document/next", emphasis: false),
                Metric(label: "页码", value: "\(page + 1) / \(totalPages)", emphasis: false)
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
                Metric(label: "类型", value: hasImage ? "图片" : "未加载", emphasis: true),
                Metric(label: "来源", value: "Mac 顶栏", emphasis: false),
                Metric(label: "用途", value: "截图对照 / 图片预览", emphasis: false)
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
              return artist of current track & " - " & name of current track
            else
              return "音乐已暂停"
            end if
          else
            return "音乐未运行"
          end if
        end tell
        """)
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "音乐",
            subhead: timestamp(),
            metrics: [
                Metric(label: "正在播放", value: nowPlaying.isEmpty ? "不可用" : nowPlaying, emphasis: true),
                Metric(label: "控制", value: "播放/暂停、上一首、下一首", emphasis: false),
                Metric(label: "用途", value: "桌面音乐状态与轻控制", emphasis: false)
            ],
            notes: ["主控制 | 上一首 / 播放 / 下一首", "真全屏 | 显示播放状态", "浏览器模式 | 可点击控制"],
            footer: footer(snapshot)
        )
    }

    private static func weather(_ snapshot: AppSnapshot) -> DashboardModel {
        let simple = weatherLine(includeDetail: false)
        let detail = weatherLine(includeDetail: true)
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "天气",
            subhead: longDate(),
            metrics: [
                Metric(label: "室外", value: simple.isEmpty ? "天气源不可用" : simple, emphasis: true),
                Metric(label: "细节", value: detail.isEmpty ? "湿度和风力不可用" : detail, emphasis: false),
                Metric(label: "用途", value: "判断衣着、开窗、通勤", emphasis: false)
            ],
            notes: ["慢刷新 | 省电", "家庭传感器 | 后续接入", "空气质量 / 湿度 | 后续接入"],
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
                Metric(label: "待办", value: reminders.isEmpty ? "暂未授权提醒事项" : "\(listLines(reminders, fallback: "").count) 项提醒", emphasis: false),
                Metric(label: "用途", value: "避免漏掉下一项承诺", emphasis: false)
            ],
            notes: listLines(reminders, fallback: "提醒事项接入 | 需要 macOS 授权"),
            footer: footer(snapshot)
        )
    }

    private static func focus(_ snapshot: AppSnapshot) -> DashboardModel {
        let uptime = uptimeSummary()
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "专注",
            subhead: "专注状态牌",
            metrics: [
                Metric(label: "时间块", value: "50 分钟", emphasis: true),
                Metric(label: "意图", value: "一次只做一件事", emphasis: false),
                Metric(label: "Mac", value: uptime.isEmpty ? "就绪" : uptime, emphasis: false)
            ],
            notes: ["保持当前任务可见 | 当前", "绑定日历专注块 | 后续", "加入休息计时 | 后续", "联动屏保降噪 | 后续"],
            footer: footer(snapshot)
        )
    }

    private static func system(_ snapshot: AppSnapshot) -> DashboardModel {
        let rawCpu = firstMatch(CommandRunner.run("/usr/bin/top", ["-l", "1", "-n", "0"]), pattern: #"CPU usage: ([^\n]+)"#) ?? ""
        let cpu = cpuSummary(rawCpu)
        let memory = CommandRunner.shell("vm_stat | awk '/Pages free/ {free=$3} /Pages active/ {active=$3} /Pages wired down/ {wired=$4} END {gsub(/\\./,\"\",free); gsub(/\\./,\"\",active); gsub(/\\./,\"\",wired); printf \"空闲 %.1fGB | 活跃 %.1fGB | 常驻 %.1fGB\", free*4096/1024/1024/1024, active*4096/1024/1024/1024, wired*4096/1024/1024/1024}'")
        let disk = CommandRunner.shell("df -h / | awk 'NR==2 {print \"可用 \" $4 \" / 总 \" $2}'")
        let procs = CommandRunner.shell("ps -arcwwwxo %cpu,%mem,comm | sed -n '2,9p'")
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "系统",
            subhead: timestamp(),
            metrics: [
                Metric(label: "CPU", value: cpu, emphasis: true),
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
                Metric(label: "用途", value: "空闲时安静显示时间", emphasis: false)
            ],
            notes: ["安静显示 | 已启用", "每分钟刷新 | 低干扰"],
            footer: footer(snapshot)
        )
    }

    private static func nextCalendarLine() -> String {
        let value = CommandRunner.shell("command -v icalBuddy >/dev/null && icalBuddy -nc -nrd -ea -li 1 eventsToday 2>/dev/null | head -1 || true")
        return value.isEmpty ? "暂未接入日历" : value
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

    private static func cpuSummary(_ raw: String) -> String {
        guard !raw.isEmpty else { return "不可用" }
        let normalized = raw
            .replacingOccurrences(of: " user", with: " 用户")
            .replacingOccurrences(of: " sys", with: " 系统")
            .replacingOccurrences(of: " idle", with: " 空闲")
        return normalized
    }

    private static func uptimeSummary() -> String {
        let raw = CommandRunner.shell("uptime | sed 's/^ //; s/  */ /g'")
        guard !raw.isEmpty else { return "就绪" }
        let pieces = raw.components(separatedBy: ", load averages:")
        let load = pieces.count > 1 ? pieces[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let days = firstMatch(raw, pattern: #"up ([^,]+),"#) ?? ""
        if !days.isEmpty, !load.isEmpty {
            return "运行 \(days) | 负载 \(load)"
        }
        return raw
    }

    private static func recentCodexSessions() -> [String] {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/session_index.jsonl")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ["No recent session index found"]
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
        return sorted.isEmpty ? ["No recent session index found"] : Array(sorted)
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
        return rows.isEmpty ? ["No process pressure | OK"] : rows
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
        case .weather: return "传感计划"
        case .calendar, .home: return "今日"
        case .focus: return "专注计划"
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
        body += text("今天", x: x, y: y + 112, size: 142, weight: "700")
        body += text(model.subhead, x: x + 4, y: y + 170, size: 36, weight: "400")
        body += modeArt(cx: x + width - 82, cy: y + 86)

        if let primary = model.metrics.first {
            body += text(primary.label, x: x, y: y + 282, size: 30, weight: "700", family: "Menlo, Monaco, monospace")
            body += wrapped(primary.value, x: x, y: y + 348, width: width - 18, size: 58, maxLines: 2)
        }

        let adviceTop = y + 492
        body += rect(x: x, y: adviceTop, width: width, height: 138, stroke: 0, fill: "#000")
        body += text("现在该看什么", x: x + 30, y: adviceTop + 46, size: 26, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += text(homeAdvice, x: x + 30, y: adviceTop + 104, size: 44, weight: "700", fill: "#fff")

        body += metricStrip(x: x, y: y + 684, width: width, metrics: Array(model.metrics.dropFirst().prefix(3)))
        body += workList(x: x, y: y + 874, width: width, bottom: bottom, title: "今日", rows: model.notes)
        return body
    }

    private func codexContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("Codex", x: x, y: y + 98, size: 122, weight: "700")
        body += rightText("工作台", rightX: x + width, y: y + 88, size: 38, weight: "700", family: "Menlo, Monaco, monospace")
        body += text(model.subhead, x: x + 4, y: y + 154, size: 30, weight: "400", family: "Menlo, Monaco, monospace")

        let heroTop = y + 214
        body += rect(x: x, y: heroTop, width: width, height: 216, stroke: 0, fill: "#000")
        body += text("当前目标", x: x + 30, y: heroTop + 50, size: 28, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += wrapped(model.metrics.first?.value ?? "Kindle 副屏", x: x + 30, y: heroTop + 134, width: width - 60, size: 66, maxLines: 1, fill: "#fff")

        body += metricStrip(x: x, y: y + 478, width: width, metrics: Array(model.metrics.dropFirst().prefix(2)))
        body += workList(x: x, y: y + 690, width: width, bottom: bottom, title: "最近工作", rows: model.notes)
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
        body += wrapped(nowPlaying, x: x + 30, y: y + 364, width: width - 60, size: 66, maxLines: 1, fill: "#fff")

        body += musicButtonRow(x: x, y: y + 482, width: width)
        body += metricStrip(x: x, y: y + 664, width: width, metrics: Array(model.metrics.dropFirst().prefix(2)))
        body += workList(x: x, y: y + 882, width: width, bottom: bottom, title: "控制说明", rows: model.notes)
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
        body += wrapped(weatherAdvice, x: x + 30, y: heroTop + 136, width: width - 60, size: 64, maxLines: 1, fill: "#fff")

        body += metricStrip(x: x, y: y + 500, width: width, metrics: model.metrics)
        body += workList(x: x, y: y + 720, width: width, bottom: bottom, title: "接入计划", rows: model.notes)
        return body
    }

    private func calendarContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("日历", x: x, y: y + 104, size: 122, weight: "700")
        body += text(model.subhead, x: x + 4, y: y + 164, size: 34, weight: "400")
        body += modeArt(cx: x + width - 82, cy: y + 82)

        let next = model.metrics.first?.value ?? "暂未接入日历"
        let heroTop = y + 236
        body += rect(x: x, y: heroTop, width: width, height: 210, stroke: 0, fill: "#000")
        body += text("下一项", x: x + 30, y: heroTop + 52, size: 28, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += wrapped(next, x: x + 30, y: heroTop + 136, width: width - 60, size: 60, maxLines: 1, fill: "#fff")

        body += metricStrip(x: x, y: y + 500, width: width, metrics: Array(model.metrics.dropFirst().prefix(2)))
        body += workList(x: x, y: y + 720, width: width, bottom: bottom, title: "提醒事项", rows: model.notes)
        return body
    }

    private func focusContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += text("专注", x: x, y: y + 104, size: 122, weight: "700")
        body += text("只保留当前时间块", x: x + 4, y: y + 164, size: 34, weight: "400")
        body += modeArt(cx: x + width - 82, cy: y + 86)

        let heroTop = y + 236
        body += rect(x: x, y: heroTop, width: width, height: 230, stroke: 0, fill: "#000")
        body += text("当前时间块", x: x + 30, y: heroTop + 56, size: 28, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += text(model.metrics.first?.value ?? "50 分钟", x: x + 30, y: heroTop + 164, size: 92, weight: "700", fill: "#fff")

        body += metricStrip(x: x, y: y + 520, width: width, metrics: Array(model.metrics.dropFirst().prefix(2)))
        body += workList(x: x, y: y + 740, width: width, bottom: bottom, title: "专注计划", rows: model.notes)
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

        body += metricStrip(x: x, y: y + 500, width: width, metrics: Array(model.metrics.dropFirst().prefix(2)))
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
        if let weather = model.metrics.first?.value, weather.contains("湿度") {
            return "先看天气，再看日程"
        }
        return "看一眼就知道今天怎么安排"
    }

    private var weatherAdvice: String {
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
        if let currentWeather = model.metrics.first(where: { $0.label == "天气" || $0.label == "室外" })?.value,
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
        {"refreshSerial":\(snapshot.refreshSerial),"refreshInterval":\(snapshot.kindleRefreshInterval),"frontlightEnabled":\(snapshot.frontlightEnabled ? "true" : "false"),"frontlightLevel":\(snapshot.frontlightLevel),"batteryProtectionEnabled":\(snapshot.batteryProtectionEnabled ? "true" : "false"),"batteryLowerLimit":\(snapshot.batteryLowerLimit),"batteryUpperLimit":\(snapshot.batteryUpperLimit)}
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem!
    private var server: DashboardServer!

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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = makeStatusIcon()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "KindleDashboard"

        let menu = NSMenu()
        for mode in KindleMode.allCases {
            let item = NSMenuItem(title: mode.menuTitle, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("打开 Markdown 文档...", #selector(openMarkdownDocument)))
        menu.addItem(menuItem("文档上一页", #selector(previousDocumentPage)))
        menu.addItem(menuItem("文档下一页", #selector(nextDocumentPage)))
        menu.addItem(.separator())
        menu.addItem(menuItem("投射图片...", #selector(openProjectionImage)))
        menu.addItem(menuItem("投射当前截屏", #selector(projectScreenshot)))
        menu.addItem(.separator())
        let portrait = NSMenuItem(title: "竖屏布局", action: #selector(selectPortrait), keyEquivalent: "")
        portrait.target = self
        menu.addItem(portrait)
        let landscape = NSMenuItem(title: "横屏布局（保留）", action: #selector(selectLandscape), keyEquivalent: "")
        landscape.target = self
        menu.addItem(landscape)
        let cycle = NSMenuItem(title: "切换自动轮换", action: #selector(toggleCycle), keyEquivalent: "")
        cycle.target = self
        menu.addItem(cycle)

        menu.addItem(.separator())
        menu.addItem(menuItem("立即刷新 Kindle", #selector(refreshKindleNow)))
        menu.addItem(menuItem("Kindle 背光开/关", #selector(toggleFrontlight)))
        menu.addItem(menuItem("电池保护模式 45%-55%", #selector(toggleBatteryProtection)))
        let refreshRate = NSMenuItem(title: "刷新策略", action: nil, keyEquivalent: "")
        let refreshRateMenu = NSMenu()
        refreshRateMenu.addItem(infoMenuItem("轻刷新：每 1 分钟"))
        refreshRateMenu.addItem(infoMenuItem("全刷新：每 5 分钟"))
        refreshRateMenu.addItem(infoMenuItem("页面切换：立即轻刷新"))
        refreshRate.submenu = refreshRateMenu
        menu.addItem(refreshRate)

        menu.addItem(.separator())
        menu.addItem(menuItem("播放 / 暂停音乐", #selector(playPause)))
        menu.addItem(menuItem("下一首", #selector(nextTrack)))
        menu.addItem(menuItem("上一首", #selector(previousTrack)))

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()
        settingsMenu.addItem(menuItem("复制控制页地址", #selector(copyURL)))
        settingsMenu.addItem(menuItem("复制真全屏地址", #selector(copyFrameURL)))
        settingsMenu.addItem(menuItem("立即刷新 Kindle", #selector(refreshKindleNow)))
        settingsMenu.addItem(menuItem("Kindle 背光开/关", #selector(toggleFrontlight)))
        settingsMenu.addItem(menuItem("电池保护模式 45%-55%", #selector(toggleBatteryProtection)))
        let settingsRefreshRate = NSMenuItem(title: "刷新策略", action: nil, keyEquivalent: "")
        let settingsRefreshRateMenu = NSMenu()
        settingsRefreshRateMenu.addItem(infoMenuItem("轻刷新：每 1 分钟"))
        settingsRefreshRateMenu.addItem(infoMenuItem("全刷新：每 5 分钟"))
        settingsRefreshRateMenu.addItem(infoMenuItem("页面切换：立即轻刷新"))
        settingsRefreshRate.submenu = settingsRefreshRateMenu
        settingsMenu.addItem(settingsRefreshRate)
        settingsMenu.addItem(menuItem("切换自动轮换", #selector(toggleCycle)))
        settingsMenu.addItem(.separator())
        settingsMenu.addItem(menuItem("退出", #selector(quit)))
        settings.submenu = settingsMenu
        menu.addItem(settings)
        menu.addItem(menuItem("退出", #selector(quit)))
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func infoMenuItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func addRefreshRateItem(_ title: String, seconds: Int, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(selectRefreshRate(_:)), keyEquivalent: "")
        item.representedObject = seconds
        item.target = self
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

    @objc private func selectRefreshRate(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else {
            return
        }
        state.setKindleRefreshInterval(seconds)
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
