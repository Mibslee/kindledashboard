import AppKit
import Foundation
import Network
import ServiceManagement
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
    struct Result {
        let output: String
        let error: String
        let status: Int32
    }

    static func run(_ launchPath: String, _ arguments: [String]) -> String {
        runResult(launchPath, arguments).output
    }

    static func runResult(_ launchPath: String, _ arguments: [String]) -> Result {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            return Result(
                output: String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                error: String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                status: process.terminationStatus
            )
        } catch {
            return Result(output: "", error: error.localizedDescription, status: -1)
        }
    }

    static func shell(_ script: String) -> String {
        run("/bin/zsh", ["-lc", script])
    }

    static func appleScript(_ source: String) -> String {
        run("/usr/bin/osascript", ["-e", source])
    }

    static func appleScriptResult(_ source: String) -> Result {
        runResult("/usr/bin/osascript", ["-e", source])
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
    let weatherCondition: WeatherCondition?
    let weatherHours: [HourlyWeather]

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
        imageMeta: String? = nil,
        weatherCondition: WeatherCondition? = nil,
        weatherHours: [HourlyWeather] = []
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
        self.weatherCondition = weatherCondition
        self.weatherHours = weatherHours
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
            imageMeta: imageMeta,
            weatherCondition: weatherCondition,
            weatherHours: weatherHours
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

private final class CodexRateLimitResponseBox: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var buffer = ""
    private var response: [String: Any]?

    func append(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        buffer += text
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            consume(line)
        }
        lock.unlock()
    }

    func result() -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return response
    }

    private func consume(_ line: String) {
        guard response == nil,
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["id"] as? NSNumber)?.intValue == 2,
              let result = object["result"] as? [String: Any] else {
            return
        }
        response = result
        semaphore.signal()
    }
}

enum WeatherCondition: String {
    case clear
    case partlyCloudy
    case cloudy
    case overcast
    case lightRain
    case moderateRain
    case heavyRain
    case thunder
    case snow
    case fog
    case wind
    case unknown

    var label: String {
        switch self {
        case .clear: return "晴"
        case .partlyCloudy: return "晴间多云"
        case .cloudy: return "多云"
        case .overcast: return "阴"
        case .lightRain: return "小雨"
        case .moderateRain: return "中雨"
        case .heavyRain: return "大雨"
        case .thunder: return "雷雨"
        case .snow: return "雪"
        case .fog: return "雾"
        case .wind: return "大风"
        case .unknown: return "天气"
        }
    }

    var isRain: Bool {
        switch self {
        case .lightRain, .moderateRain, .heavyRain, .thunder: return true
        default: return false
        }
    }
}

struct HourlyWeather {
    let time: String
    let condition: WeatherCondition
    let temperature: String
    let rainChance: Int
    let precipitationMM: Double

    var rowText: String {
        "\(time) \(condition.label) \(temperature) | 降水 \(rainChance)%"
    }
}

struct WeatherSnapshot {
    let current: String
    let detail: String
    let rainSummary: String
    let advice: String
    let condition: WeatherCondition
    let hourly: [HourlyWeather]
    let updatedAt: Date
    let isCached: Bool

    var hourlyRows: [String] {
        hourly.map(\.rowText)
    }
}

struct MacHealthSnapshot {
    let status: String
    let cpu: String
    let memory: String
    let thermal: String
    let disk: String
    let processRows: [String]
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

    static func preview(mode: KindleMode) -> DashboardModel {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 9, minute: 30)) ?? Date()
        let weatherHours = [
            HourlyWeather(time: "10:00", condition: .lightRain, temperature: "+27°C", rainChance: 48, precipitationMM: 0.8),
            HourlyWeather(time: "12:00", condition: .moderateRain, temperature: "+26°C", rainChance: 72, precipitationMM: 3.2),
            HourlyWeather(time: "15:00", condition: .heavyRain, temperature: "+25°C", rainChance: 88, precipitationMM: 8.6),
            HourlyWeather(time: "18:00", condition: .cloudy, temperature: "+26°C", rainChance: 25, precipitationMM: 0),
            HourlyWeather(time: "21:00", condition: .clear, temperature: "+24°C", rainChance: 8, precipitationMM: 0)
        ]
        let common = (
            orientation: KindleOrientation.portrait,
            generatedAt: date,
            footer: "公开预览数据",
            footerRight: "Kindle 76%"
        )

        switch mode {
        case .home:
            return DashboardModel(
                mode: mode, orientation: common.orientation, generatedAt: date,
                headline: "总览", subhead: "星期六, 7月 11",
                metrics: [
                    Metric(label: "天气", value: "小雨 +27°C，体感 +29°C", emphasis: true),
                    Metric(label: "天气细节", value: "湿度 78% · 风 12 km/h", emphasis: false),
                    Metric(label: "降雨", value: "15:00 大雨 · 88%", emphasis: false),
                    Metric(label: "出门建议", value: "午后强降雨，尽量提前出门", emphasis: false),
                    Metric(label: "Codex", value: "完善天气图标与总览信息层级", emphasis: true),
                    Metric(label: "5h", value: "78%", emphasis: false),
                    Metric(label: "周额度", value: "64%", emphasis: false),
                    Metric(label: "Mac", value: "系统状态正常", emphasis: true),
                    Metric(label: "CPU", value: "使用 24%", emphasis: false),
                    Metric(label: "内存", value: "使用 58%", emphasis: false),
                    Metric(label: "温控", value: "正常", emphasis: false)
                ],
                notes: [], footer: common.footer, footerRight: common.footerRight,
                weatherCondition: .lightRain, weatherHours: weatherHours
            )
        case .weather:
            return DashboardModel(
                mode: mode, orientation: common.orientation, generatedAt: date,
                headline: "天气", subhead: "未来几小时 · 09:30 更新",
                metrics: [
                    Metric(label: "现在", value: "小雨 +27°C，体感 +29°C", emphasis: true),
                    Metric(label: "细节", value: "湿度 78% · 风 12 km/h", emphasis: false),
                    Metric(label: "降雨", value: "15:00 大雨 · 88%", emphasis: false),
                    Metric(label: "建议", value: "午后强降雨，尽量提前出门", emphasis: false)
                ],
                notes: weatherHours.map(\.rowText), footer: common.footer, footerRight: common.footerRight,
                weatherCondition: .lightRain, weatherHours: weatherHours
            )
        case .codex:
            return DashboardModel(
                mode: mode, orientation: common.orientation, generatedAt: date,
                headline: "Codex 看板", subhead: "09:30",
                metrics: [
                    Metric(label: "当前任务", value: "完善天气图标与总览信息层级", emphasis: true),
                    Metric(label: "5h 剩余", value: "78%", emphasis: false),
                    Metric(label: "周额度", value: "64%", emphasis: false),
                    Metric(label: "重置", value: "3h18m", emphasis: false)
                ],
                notes: ["限额状态 | 额度正常，可继续", "5h 重置 | 今天 12:48", "周重置 | 周四 08:00", "下一步 | 完成真机检查"],
                footer: common.footer, footerRight: common.footerRight
            )
        case .music:
            return DashboardModel(
                mode: mode, orientation: common.orientation, generatedAt: date,
                headline: "音乐", subhead: "播放中",
                metrics: [
                    Metric(label: "正在播放", value: "陈绮贞 - 旅行的意义", emphasis: true),
                    Metric(label: "状态", value: "播放中", emphasis: false),
                    Metric(label: "专辑", value: "华丽的冒险", emphasis: false)
                ], notes: [], footer: common.footer, footerRight: common.footerRight
            )
        case .calendar:
            return DashboardModel(
                mode: mode, orientation: common.orientation, generatedAt: date,
                headline: "日历", subhead: "星期六, 7月 11",
                metrics: [Metric(label: "下一项", value: "10:30 产品评审", emphasis: true)],
                notes: ["确认发布清单 | 今天", "整理真机反馈 | 今天"],
                footer: common.footer, footerRight: common.footerRight
            )
        case .focus:
            return DashboardModel(
                mode: mode, orientation: common.orientation, generatedAt: date,
                headline: "专注", subhead: "只做一件事",
                metrics: [
                    Metric(label: "当前任务", value: "完善天气图标与总览信息层级", emphasis: true),
                    Metric(label: "建议专注", value: "50 分钟", emphasis: false)
                ], notes: [], footer: common.footer, footerRight: common.footerRight
            )
        case .system:
            return DashboardModel(
                mode: mode, orientation: common.orientation, generatedAt: date,
                headline: "系统", subhead: "Mac 健康",
                metrics: [
                    Metric(label: "状态", value: "系统状态正常", emphasis: true),
                    Metric(label: "CPU", value: "使用 24%", emphasis: false),
                    Metric(label: "内存", value: "使用 58%", emphasis: false),
                    Metric(label: "温控", value: "正常", emphasis: false)
                ],
                notes: ["系统盘 | 使用 42%", "WindowServer | CPU 8.2% / MEM 0.6%", "Music | CPU 2.1% / MEM 0.4%"],
                footer: common.footer, footerRight: common.footerRight
            )
        case .screensaver:
            return DashboardModel(
                mode: mode, orientation: common.orientation, generatedAt: date,
                headline: "09:30", subhead: "星期六, 7月 11",
                metrics: [], notes: [], footer: common.footer, footerRight: common.footerRight
            )
        case .document, .image:
            return DashboardModel(
                mode: mode, orientation: common.orientation, generatedAt: date,
                headline: mode == .document ? "操作步骤.md" : "等待投射",
                subhead: "公开预览", metrics: [], notes: ["选择内容 | Mac 顶栏"],
                footer: common.footer, footerRight: common.footerRight
            )
        }
    }

    private static func home(_ snapshot: AppSnapshot) -> DashboardModel {
        let weather = weatherSnapshot()
        let codex = codexActivity()
        let mac = macHealthSnapshot()
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "总览",
            subhead: longDate(),
            metrics: [
                Metric(label: "天气", value: weather.current, emphasis: true),
                Metric(label: "天气细节", value: weather.detail, emphasis: false),
                Metric(label: "降雨", value: weather.rainSummary, emphasis: false),
                Metric(label: "出门建议", value: weather.advice, emphasis: false),
                Metric(label: "Codex", value: codex.currentTask, emphasis: true),
                Metric(label: "5h", value: codex.limitStatus.primaryValue, emphasis: false),
                Metric(label: "周额度", value: codex.limitStatus.weeklyValue, emphasis: false),
                Metric(label: "Mac", value: mac.status, emphasis: true),
                Metric(label: "CPU", value: mac.cpu, emphasis: false),
                Metric(label: "内存", value: mac.memory, emphasis: false),
                Metric(label: "温控", value: mac.thermal, emphasis: false)
            ],
            notes: [],
            footer: footer(snapshot),
            weatherCondition: weather.condition,
            weatherHours: weather.hourly
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
        let cacheLabel = weather.isCached ? " · 缓存" : ""
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "天气",
            subhead: "未来几小时 · \(clockTime(weather.updatedAt)) 更新\(cacheLabel)",
            metrics: [
                Metric(label: "现在", value: weather.current, emphasis: true),
                Metric(label: "细节", value: weather.detail, emphasis: false),
                Metric(label: "降雨", value: weather.rainSummary, emphasis: false),
                Metric(label: "建议", value: weather.advice, emphasis: false)
            ],
            notes: weather.hourlyRows,
            footer: footer(snapshot),
            weatherCondition: weather.condition,
            weatherHours: weather.hourly
        )
    }

    private static func calendar(_ snapshot: AppSnapshot) -> DashboardModel {
        let next = nextCalendarLine()
        let reminders = reminderLines()
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "日历",
            subhead: longDate(),
            metrics: [
                Metric(label: "下一项", value: next, emphasis: true),
                Metric(label: "待办", value: reminders.isEmpty ? "暂无待办" : "\(reminders.count) 项待办", emphasis: false),
                Metric(label: "建议", value: (next.contains("暂未") || next.contains("暂无")) ? "留给深度工作" : "提前 10 分钟准备", emphasis: false)
            ],
            notes: reminders,
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
                Metric(label: "建议专注", value: "50 分钟", emphasis: false),
                Metric(label: "Mac", value: uptime.isEmpty ? "就绪" : uptime, emphasis: false)
            ],
            notes: ["只做一件事 | 当前", "关闭额外页面 | 建议", "50 分钟后休息 | 建议"],
            footer: footer(snapshot)
        )
    }

    private static func system(_ snapshot: AppSnapshot) -> DashboardModel {
        let mac = macHealthSnapshot()
        return DashboardModel(
            mode: snapshot.mode,
            orientation: snapshot.orientation,
            generatedAt: Date(),
            headline: "系统",
            subhead: timestamp(),
            metrics: [
                Metric(label: "状态", value: mac.status, emphasis: true),
                Metric(label: "CPU", value: mac.cpu, emphasis: false),
                Metric(label: "内存", value: mac.memory, emphasis: false),
                Metric(label: "温控", value: mac.thermal, emphasis: false)
            ],
            notes: ["系统盘 | \(mac.disk)"] + mac.processRows.prefix(4),
            footer: footer(snapshot)
        )
    }

    private static func macHealthSnapshot() -> MacHealthSnapshot {
        let rawCpu = firstMatch(CommandRunner.run("/usr/bin/top", ["-l", "1", "-n", "0"]), pattern: #"CPU usage: ([^\n]+)"#) ?? ""
        let cpu = cpuSummary(rawCpu)
        let memory = memoryUsageSummary()
        let thermal = thermalStateSummary()
        let disk = CommandRunner.shell("df -k / | awk 'NR==2 {print \"使用 \" $5}'")
        let procs = CommandRunner.shell("ps -arcwwwxo %cpu,%mem,comm | sed -n '2,9p'")
        return MacHealthSnapshot(
            status: systemAdvice(cpuSummary: cpu, memory: memory, thermal: thermal),
            cpu: cpu.isEmpty ? "不可用" : cpu,
            memory: memory.isEmpty ? "不可用" : memory,
            thermal: thermal,
            disk: disk.isEmpty ? "不可用" : disk,
            processRows: processRows(procs)
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
        let result = CommandRunner.appleScriptResult("""
        tell application "Calendar"
          set startOfDay to current date
          set time of startOfDay to 0
          set endOfDay to startOfDay + (24 * 60 * 60)
          set nextEvent to missing value
          repeat with calendarRef in calendars
            set matches to every event of calendarRef whose start date is greater than or equal to startOfDay and start date is less than endOfDay
            repeat with eventRef in matches
              if nextEvent is missing value or start date of eventRef is less than start date of nextEvent then
                set nextEvent to eventRef
              end if
            end repeat
          end repeat
          if nextEvent is missing value then return ""
          return summary of nextEvent
        end tell
        """)
        if result.status != 0 {
            return "日历未授权"
        }
        return result.output.isEmpty ? "暂无日程" : result.output
    }

    private static func reminderLines() -> [String] {
        let result = CommandRunner.appleScriptResult("""
        tell application "Reminders"
          set matches to reminders whose completed is false
          if (count of matches) is 0 then return ""
          set limitCount to count of matches
          if limitCount is greater than 6 then set limitCount to 6
          set output to ""
          repeat with itemRef in items 1 thru limitCount of matches
            set output to output & name of itemRef & linefeed
          end repeat
          return output
        end tell
        """)
        if result.status != 0 {
            return ["提醒事项未授权 | 未连接"]
        }
        return result.output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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

    private static func weatherSnapshot() -> WeatherSnapshot {
        let defaults = UserDefaults.standard
        let dataKey = "KindleDashboard.WeatherData"
        let dateKey = "KindleDashboard.WeatherDate"
        let now = Date()

        if let cachedData = defaults.data(forKey: dataKey),
           let capturedAt = defaults.object(forKey: dateKey) as? Date,
           now.timeIntervalSince(capturedAt) < 10 * 60,
           let cached = decodedWeatherSnapshot(data: cachedData, updatedAt: capturedAt, isCached: false) {
            return cached
        }

        if let liveData = fetchWeatherData(),
           let live = decodedWeatherSnapshot(data: liveData, updatedAt: now, isCached: false) {
            defaults.set(liveData, forKey: dataKey)
            defaults.set(now, forKey: dateKey)
            return live
        }

        if let cachedData = defaults.data(forKey: dataKey),
           let capturedAt = defaults.object(forKey: dateKey) as? Date,
           now.timeIntervalSince(capturedAt) < 6 * 60 * 60,
           let cached = decodedWeatherSnapshot(data: cachedData, updatedAt: capturedAt, isCached: true) {
            return cached
        }

        return WeatherSnapshot(
            current: "天气源暂不可用",
            detail: "等待下次刷新",
            rainSummary: "降雨待更新",
            advice: "天气稍后更新，按当前计划推进",
            condition: .unknown,
            hourly: [],
            updatedAt: now,
            isCached: false
        )
    }

    private static func fetchWeatherData() -> Data? {
        let url = "https://wttr.in/?format=j1"
        let commonArguments = [
            "--fail", "--silent", "--show-error",
            "--connect-timeout", "3", "--max-time", "7",
            "--retry", "1", "--retry-delay", "1"
        ]
        let attempts = [
            commonArguments + [url],
            ["--noproxy", "*"] + commonArguments + [url]
        ]

        for arguments in attempts {
            let result = CommandRunner.runResult("/usr/bin/curl", arguments)
            guard result.status == 0,
                  let data = result.output.data(using: .utf8),
                  !data.isEmpty else {
                continue
            }
            return data
        }
        return nil
    }

    private static func decodedWeatherSnapshot(data: Data, updatedAt: Date, isCached: Bool) -> WeatherSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = (root["current_condition"] as? [[String: Any]])?.first else {
            return nil
        }

        let temp = intText(current["temp_C"]) ?? "--"
        let feels = intText(current["FeelsLikeC"]) ?? temp
        let humidity = intText(current["humidity"]) ?? "--"
        let wind = intText(current["windspeedKmph"]) ?? "--"
        let condition = weatherCondition(current)
        let currentText = "\(condition.label) \(signedTemperature(temp))，体感 \(signedTemperature(feels))"
        let detailText = "湿度 \(humidity)% · 风 \(wind) km/h"

        let hourly = hourlyWeather(root: root)
        let rainSummary = rainOutlook(hourly)
        let advice = weatherAdvice(
            temperature: Int(temp),
            feelsLike: Int(feels),
            humidity: Int(humidity),
            currentCondition: condition,
            rows: hourly
        )
        return WeatherSnapshot(
            current: currentText,
            detail: detailText,
            rainSummary: rainSummary,
            advice: advice,
            condition: condition,
            hourly: hourly,
            updatedAt: updatedAt,
            isCached: isCached
        )
    }

    private static func hourlyWeather(root: [String: Any]) -> [HourlyWeather] {
        guard let days = root["weather"] as? [[String: Any]] else { return [] }
        let nowHour = Calendar.current.component(.hour, from: Date())
        let threshold = nowHour * 100
        var rows: [HourlyWeather] = []

        for (dayIndex, day) in days.prefix(2).enumerated() {
            guard let hourly = day["hourly"] as? [[String: Any]] else { continue }
            for item in hourly {
                guard let timeValue = Int(intText(item["time"]) ?? "") else { continue }
                if dayIndex == 0, timeValue < threshold { continue }
                let hour = timeValue / 100
                let prefix = dayIndex == 0 ? String(format: "%02d:00", hour) : "明天 \(String(format: "%02d:00", hour))"
                let temp = intText(item["tempC"]) ?? "--"
                let rain = Int(intText(item["chanceofrain"]) ?? "0") ?? 0
                let precipitation = number(item["precipMM"]) ?? 0
                rows.append(HourlyWeather(
                    time: prefix,
                    condition: weatherCondition(item),
                    temperature: signedTemperature(temp),
                    rainChance: rain,
                    precipitationMM: precipitation
                ))
                if rows.count >= 5 { return rows }
            }
        }
        return rows
    }

    private static func weatherDescription(_ object: [String: Any]) -> String {
        if let descriptions = object["weatherDesc"] as? [[String: Any]],
           let value = descriptions.first?["value"] as? String,
           !value.isEmpty {
            return value
        }
        return ""
    }

    private static func weatherCondition(_ object: [String: Any]) -> WeatherCondition {
        let description = weatherDescription(object).lowercased()
        let precipitation = number(object["precipMM"]) ?? 0

        if description.contains("thunder") { return .thunder }
        if description.contains("snow") || description.contains("sleet") || description.contains("blizzard") { return .snow }
        if description.contains("torrential") || description.contains("heavy rain") || precipitation >= 7.6 { return .heavyRain }
        if description.contains("moderate rain") || precipitation >= 2.5 { return .moderateRain }
        if description.contains("rain") || description.contains("drizzle") || precipitation > 0 { return .lightRain }
        if description.contains("fog") || description.contains("mist") || description.contains("haze") { return .fog }
        if description.contains("wind") || description.contains("gale") { return .wind }
        if description.contains("overcast") { return .overcast }
        if description.contains("partly") || description.contains("sunny interval") { return .partlyCloudy }
        if description.contains("cloud") { return .cloudy }
        if description.contains("sun") || description.contains("clear") { return .clear }
        return .unknown
    }

    private static func rainOutlook(_ rows: [HourlyWeather]) -> String {
        let rainy = rows.filter { $0.condition.isRain || $0.rainChance >= 40 }
        guard let strongest = rainy.max(by: { rainScore($0) < rainScore($1) }) else {
            return "未来几小时无明显降雨"
        }
        return "\(strongest.time) \(strongest.condition.label) · \(strongest.rainChance)%"
    }

    private static func rainScore(_ hour: HourlyWeather) -> Double {
        let intensity: Double
        switch hour.condition {
        case .thunder: intensity = 5
        case .heavyRain: intensity = 4
        case .moderateRain: intensity = 3
        case .lightRain: intensity = 2
        default: intensity = 1
        }
        return intensity * 100 + hour.precipitationMM * 10 + Double(hour.rainChance)
    }

    private static func weatherAdvice(
        temperature: Int?,
        feelsLike: Int?,
        humidity: Int?,
        currentCondition: WeatherCondition,
        rows: [HourlyWeather]
    ) -> String {
        let conditions = [currentCondition] + rows.map(\.condition)
        if conditions.contains(.thunder) || conditions.contains(.heavyRain) {
            return "强降雨，尽量推迟出门"
        }
        if conditions.contains(.moderateRain) {
            return "带伞，避开降雨时段"
        }
        if conditions.contains(.lightRain) {
            return "带折叠伞，注意湿滑"
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

    private static func memoryUsageSummary() -> String {
        let raw = CommandRunner.run("/usr/bin/memory_pressure", [])
        guard let freeText = firstMatch(raw, pattern: #"free percentage:\s*(\d+)%"#),
              let free = Int(freeText) else {
            return "不可用"
        }
        return "使用 \(max(0, min(100, 100 - free)))%"
    }

    private static func thermalStateSummary() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "正常"
        case .fair: return "偏热"
        case .serious: return "较热"
        case .critical: return "过热"
        @unknown default: return "未知"
        }
    }

    private static func systemAdvice(cpuSummary: String, memory: String, thermal: String) -> String {
        if thermal == "过热" || thermal == "较热" {
            return "温度压力较高，减少负载"
        }
        if let cpu = firstMatch(cpuSummary, pattern: #"使用 (\d+)%"#).flatMap(Int.init), cpu >= 80 {
            return "CPU 压力高，先看进程"
        }
        if let used = firstMatch(memory, pattern: #"使用 (\d+)%"#).flatMap(Int.init), used >= 85 {
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
        let database = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/state_5.sqlite")
        let sql = """
        SELECT title, updated_at
        FROM threads
        WHERE archived = 0 AND title <> ''
        ORDER BY recency_at_ms DESC
        LIMIT 10;
        """
        guard let output = try? runSQLite(database: database, sql: sql), !output.isEmpty else {
            return ["暂无 Codex 会话记录"]
        }
        return output.split(separator: "\n").compactMap { row in
            let fields = row.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let title = fields.first, !title.isEmpty else { return nil }
            let timestamp = fields.count > 1 ? fields[1] : ""
            return timestamp.isEmpty ? title : "\(title) | \(timestampText(Date(timeIntervalSince1970: Double(timestamp) ?? 0)))"
        }
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
        if let live = codexRateLimitFromAppServer() {
            return live
        }
        if let live = codexRateLimitFromLogs() {
            return live
        }
        return codexLocalUsageStatus()
    }

    private static func codexRateLimitFromAppServer() -> CodexLimitStatus? {
        let cacheKey = "KindleDashboard.CodexRateLimits"
        let cacheDateKey = "KindleDashboard.CodexRateLimitsDate"
        let defaults = UserDefaults.standard
        let now = Date()

        if let cachedData = defaults.data(forKey: cacheKey),
           let capturedAt = defaults.object(forKey: cacheDateKey) as? Date,
           now.timeIntervalSince(capturedAt) < 5 * 60,
           let root = try? JSONSerialization.jsonObject(with: cachedData) as? [String: Any],
           let status = codexLimitStatus(from: root, capturedAt: capturedAt) {
            return status
        }

        let paths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        guard let executable = paths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return cachedCodexRateLimit(defaults: defaults, dataKey: cacheKey, dateKey: cacheDateKey, maxAge: 15 * 60)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        let responseBox = CodexRateLimitResponseBox()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                responseBox.append(data)
            }
        }

        guard (try? process.run()) != nil else {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            return cachedCodexRateLimit(defaults: defaults, dataKey: cacheKey, dateKey: cacheDateKey, maxAge: 15 * 60)
        }

        let initialize: [String: Any] = [
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "KindleDashboard", "version": "1.0"],
                "capabilities": ["experimentalApi": true]
            ]
        ]
        let request: [String: Any] = ["id": 2, "method": "account/rateLimits/read", "params": NSNull()]
        for object in [initialize, request] {
            if var data = try? JSONSerialization.data(withJSONObject: object) {
                data.append(Data("\n".utf8))
                inputPipe.fileHandleForWriting.write(data)
            }
        }

        let waitResult = responseBox.semaphore.wait(timeout: .now() + 5)
        inputPipe.fileHandleForWriting.closeFile()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        if waitResult == .success,
           let root = responseBox.result(),
           let data = try? JSONSerialization.data(withJSONObject: root),
           let status = codexLimitStatus(from: root, capturedAt: now) {
            defaults.set(data, forKey: cacheKey)
            defaults.set(now, forKey: cacheDateKey)
            defaults.synchronize()
            return status
        }
        return cachedCodexRateLimit(defaults: defaults, dataKey: cacheKey, dateKey: cacheDateKey, maxAge: 15 * 60)
    }

    private static func cachedCodexRateLimit(
        defaults: UserDefaults,
        dataKey: String,
        dateKey: String,
        maxAge: TimeInterval
    ) -> CodexLimitStatus? {
        guard let data = defaults.data(forKey: dataKey),
              let capturedAt = defaults.object(forKey: dateKey) as? Date,
              Date().timeIntervalSince(capturedAt) < maxAge,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return codexLimitStatus(from: root, capturedAt: capturedAt)
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

        for file in codexSessionFiles().prefix(6) {
            guard let content = tailText(of: file, maxBytes: 2_000_000) else { continue }
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

        return files.sorted { $0.modified > $1.modified }.map(\.url)
    }

    private static func tailText(of url: URL, maxBytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > maxBytes ? size - maxBytes : 0
        try? handle.seek(toOffset: start)
        return String(data: handle.readDataToEndOfFile(), encoding: .utf8)
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
            ">>> APPROVAL REQUEST",
            "<<< APPROVAL REQUEST",
            "Command completed:",
            "Command failed:"
        ]
        if internalPrefixes.contains(where: { trimmedRaw.hasPrefix($0) }) {
            return nil
        }
        if trimmedRaw.hasPrefix("{")
            && trimmedRaw.contains("\"command\"")
            && (trimmedRaw.contains("\"sandbox_permissions\"") || trimmedRaw.contains("\"justification\"")) {
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

        var clean = raw
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
            .replacingOccurrences(of: #"^\[\d+\]\s+user:\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if clean.hasPrefix("["),
           let bracket = clean.firstIndex(of: "]") {
            let suffix = clean[clean.index(after: bracket)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.hasPrefix("user:") {
                clean = String(suffix.dropFirst("user:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

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

    static func clockTime(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
    private let uiFont = "-apple-system, BlinkMacSystemFont, 'PingFang SC', 'Helvetica Neue', Arial, sans-serif"
    private let monoFont = "'SF Mono', Menlo, Monaco, monospace"

    func svg() -> String {
        let size = KindleOrientation.portrait.frameSize
        let w = size.width
        let h = size.height
        let margin = 68
        let footerY = 1414
        var body = ""

        body += pageContent(x: margin, y: 42, width: w - margin * 2, bottom: footerY - 54)
        if model.mode != .screensaver {
            body += line(x1: margin, y1: footerY - 34, x2: w - margin, y2: footerY - 34, stroke: 2)
            body += text("更新 \(DashboardData.clockTime())", x: margin, y: footerY, size: 23, weight: "400", family: "Menlo, Monaco, monospace")
            if !model.footerRight.isEmpty && !model.footerRight.contains("--") {
                body += rightText(model.footerRight, rightX: w - margin, y: footerY, size: 23, weight: "400", family: "Menlo, Monaco, monospace")
            }
        }

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

    private func roundedRect(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        radius: Int,
        fill: String,
        stroke: String? = nil,
        strokeWidth: Int = 0
    ) -> String {
        let strokePart: String
        if let stroke, strokeWidth > 0 {
            strokePart = " stroke=\"\(stroke)\" stroke-width=\"\(strokeWidth)\""
        } else {
            strokePart = ""
        }
        return "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(width)\" height=\"\(height)\" rx=\"\(radius)\" fill=\"\(fill)\"\(strokePart)/>"
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
        let weather = weatherSummary(metricValue("天气", fallback: "天气待更新，--"))
        let task = metricValue("Codex", fallback: "等待当前任务")
        let fiveHour = metricValue("5h", fallback: "--")
        let weekly = metricValue("周额度", fallback: "--")

        body += text(model.subhead, x: x, y: y + 40, size: 28, weight: "600", fill: "#666", family: uiFont)
        body += text(DashboardData.clockTime(model.generatedAt), x: x - 4, y: y + 163, size: 118, weight: "700", family: uiFont)

        let weatherX = x + width - 262
        body += roundedRect(x: weatherX, y: y + 16, width: 262, height: 168, radius: 32, fill: "#f1f1f3")
        body += weatherIcon(condition: model.weatherCondition ?? .unknown, cx: weatherX + 70, cy: y + 92, size: 82)
        body += centeredText(weather.temperature, centerX: weatherX + 188, y: y + 94, size: 50, weight: "700", family: uiFont)
        body += centeredText("\(weather.condition) · \(humiditySummary())", centerX: weatherX + 188, y: y + 141, size: 23, weight: "600", fill: "#666", family: uiFont)

        body += roundedRect(x: x, y: y + 236, width: width, height: 154, radius: 30, fill: "#111")
        body += text(metricValue("降雨", fallback: "天气提醒"), x: x + 36, y: y + 284, size: 25, weight: "650", fill: "#fff", family: uiFont)
        body += wrapped(metricValue("出门建议", fallback: "天气稍后更新"), x: x + 36, y: y + 346, width: width - 72, size: 44, maxLines: 1, fill: "#fff", family: uiFont)

        body += text("正在处理", x: x, y: y + 458, size: 27, weight: "650", fill: "#666", family: uiFont)
        body += roundedRect(x: x, y: y + 486, width: width, height: 294, radius: 34, fill: "#f1f1f3")
        body += roundedRect(x: x + 32, y: y + 518, width: 126, height: 46, radius: 23, fill: "#111")
        body += "<circle cx=\"\(x + 57)\" cy=\"\(y + 541)\" r=\"6\" fill=\"#fff\"/>"
        body += text("Codex", x: x + 76, y: y + 550, size: 22, weight: "650", fill: "#fff", family: uiFont)
        body += wrapped(task, x: x + 32, y: y + 636, width: width - 64, size: 51, maxLines: 1, fill: "#111", family: uiFont)
        body += "<line x1=\"\(x + 32)\" y1=\"\(y + 689)\" x2=\"\(x + width - 32)\" y2=\"\(y + 689)\" stroke=\"#d0d0d0\" stroke-width=\"2\"/>"
        body += text("5 小时额度", x: x + 32, y: y + 735, size: 24, weight: "600", fill: "#666", family: uiFont)
        body += text(fiveHour, x: x + 208, y: y + 736, size: 29, weight: "700", family: uiFont)
        body += progressBar(x: x + 288, y: y + 717, width: 230, height: 18, value: fiveHour)
        body += text("周额度", x: x + 582, y: y + 735, size: 24, weight: "600", fill: "#666", family: uiFont)
        body += text(weekly, x: x + 720, y: y + 736, size: 29, weight: "700", family: uiFont)

        body += text("设备状态", x: x, y: y + 848, size: 27, weight: "650", fill: "#666", family: uiFont)
        body += roundedRect(x: x, y: y + 876, width: width, height: 292, radius: 34, fill: "#f7f7f8", stroke: "#dedee0", strokeWidth: 2)
        body += "<circle cx=\"\(x + 40)\" cy=\"\(y + 926)\" r=\"12\" fill=\"#111\"/>"
        body += text(metricValue("Mac", fallback: "Mac 状态不可用"), x: x + 68, y: y + 936, size: 34, weight: "680", family: uiFont)
        body += rightText("刚刚更新", rightX: x + width - 32, y: y + 936, size: 25, weight: "600", fill: "#666", family: uiFont)
        body += "<line x1=\"\(x + 32)\" y1=\"\(y + 976)\" x2=\"\(x + width - 32)\" y2=\"\(y + 976)\" stroke=\"#d0d0d0\" stroke-width=\"2\"/>"
        let deviceMetrics = [
            ("CPU", compactSystemValue(Metric(label: "CPU", value: metricValue("CPU", fallback: "--"), emphasis: false))),
            ("内存", compactSystemValue(Metric(label: "内存", value: metricValue("内存", fallback: "--"), emphasis: false))),
            ("温控", metricValue("温控", fallback: "--"))
        ]
        for (index, metric) in deviceMetrics.enumerated() {
            let columnX = x + 32 + index * 300
            body += text(metric.0, x: columnX, y: y + 1030, size: 23, weight: "600", fill: "#666", family: uiFont)
            body += text(metric.1.replacingOccurrences(of: "使用 ", with: ""), x: columnX, y: y + 1082, size: 42, weight: "700", family: uiFont)
        }
        return body
    }

    private func codexContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        let task = model.metrics.first?.value ?? "等待 Codex 任务"
        let fiveHour = metricValue("5h", fallback: "--")
        let weekly = metricValue("周额度", fallback: "--")
        let fiveReset = noteValue("5h 重置", fallback: metricValue("重置", fallback: "--"))
        let weeklyReset = noteValue("周重置", fallback: "--")
        let nextStep = noteValue("下一步", fallback: "等待下一步")
        let limitStatus = noteValue("限额状态", fallback: "状态可继续")

        body += text("当前工作", x: x, y: y + 36, size: 28, weight: "600", fill: "#666", family: uiFont)
        body += text("Codex", x: x - 4, y: y + 148, size: 96, weight: "720", family: uiFont)
        body += roundedRect(x: x + width - 176, y: y + 52, width: 176, height: 58, radius: 29, fill: "#f1f1f3")
        body += "<circle cx=\"\(x + width - 142)\" cy=\"\(y + 81)\" r=\"8\" fill=\"#111\"/>"
        body += text("处理中", x: x + width - 118, y: y + 91, size: 24, weight: "650", family: uiFont)

        body += roundedRect(x: x, y: y + 196, width: width, height: 330, radius: 36, fill: "#111")
        body += text("正在处理", x: x + 40, y: y + 254, size: 25, weight: "650", fill: "#bbb", family: uiFont)
        body += wrapped(task, x: x + 40, y: y + 344, width: width - 300, size: 55, maxLines: 2, fill: "#fff", family: uiFont)
        body += "<line x1=\"\(x + 40)\" y1=\"\(y + 460)\" x2=\"\(x + width - 40)\" y2=\"\(y + 460)\" stroke=\"#444\" stroke-width=\"2\"/>"
        body += text(limitStatus, x: x + 40, y: y + 500, size: 23, weight: "600", fill: "#bbb", family: uiFont)

        body += text("额度", x: x, y: y + 600, size: 27, weight: "650", fill: "#666", family: uiFont)
        body += roundedRect(x: x, y: y + 628, width: width, height: 262, radius: 34, fill: "#f5f5f6", stroke: "#dedee0", strokeWidth: 2)
        let half = width / 2
        body += "<line x1=\"\(x + half)\" y1=\"\(y + 664)\" x2=\"\(x + half)\" y2=\"\(y + 852)\" stroke=\"#d0d0d0\" stroke-width=\"2\"/>"
        body += text("5 小时", x: x + 36, y: y + 686, size: 24, weight: "600", fill: "#666", family: uiFont)
        body += text(fiveHour, x: x + 36, y: y + 756, size: 58, weight: "720", family: uiFont)
        body += progressBar(x: x + 196, y: y + 720, width: 258, height: 22, value: fiveHour)
        body += text("重置：\(fiveReset)", x: x + 36, y: y + 834, size: 23, weight: "500", fill: "#666", family: uiFont)
        body += text("本周", x: x + half + 42, y: y + 686, size: 24, weight: "600", fill: "#666", family: uiFont)
        body += text(weekly, x: x + half + 42, y: y + 756, size: 58, weight: "720", family: uiFont)
        body += progressBar(x: x + half + 202, y: y + 720, width: 238, height: 22, value: weekly)
        body += text("重置：\(weeklyReset)", x: x + half + 42, y: y + 834, size: 23, weight: "500", fill: "#666", family: uiFont)

        body += text("下一步", x: x, y: y + 960, size: 27, weight: "650", fill: "#666", family: uiFont)
        body += roundedRect(x: x, y: y + 988, width: width, height: 196, radius: 34, fill: "#f5f5f6", stroke: "#dedee0", strokeWidth: 2)
        body += "<circle cx=\"\(x + 52)\" cy=\"\(y + 1048)\" r=\"22\" fill=\"#111\"/>"
        body += "<path d=\"M \(x + 42) \(y + 1048) l 7 8 l 15 -18\" fill=\"none\" stroke=\"#fff\" stroke-width=\"5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
        body += wrapped(nextStep, x: x + 96, y: y + 1061, width: width - 136, size: 39, maxLines: 1, fill: "#111", family: uiFont)
        body += text("完成后再切换任务", x: x + 96, y: y + 1114, size: 26, weight: "550", fill: "#666", family: uiFont)
        return body
    }

    private func documentContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += pageHeading("文档", subtitle: model.subhead, x: x, y: y, width: width)
        body += wrapped(model.headline, x: x, y: y + 258, width: width - 110, size: 76, maxLines: 2)
        body += documentIcon(cx: x + width - 58, cy: y + 234)
        body += line(x1: x, y1: y + 382, x2: x + width, y2: y + 382, stroke: 4)
        var rows = model.notes
        if let first = rows.first {
            let firstText = splitRow(first).left.replacingOccurrences(of: "■ ", with: "")
            if firstText == model.headline {
                rows.removeFirst()
            }
        }
        body += readableDocument(x: x, y: y + 430, width: width, bottom: bottom, rows: rows)
        return body
    }

    private func imageContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += pageHeading("投射", subtitle: model.headline, x: x, y: y, width: width)
        body += imageIcon(cx: x + width - 62, cy: y + 72)

        let imageTop = y + 190
        let imageBottom = bottom - 46
        let imageHeight = max(220, imageBottom - imageTop)
        body += rect(x: x, y: imageTop, width: width, height: imageHeight, stroke: model.imageDataURI == nil ? 3 : 0)
        if let dataURI = model.imageDataURI, !dataURI.isEmpty {
            body += "<image x=\"\(x)\" y=\"\(imageTop)\" width=\"\(width)\" height=\"\(imageHeight)\" preserveAspectRatio=\"xMidYMid meet\" href=\"\(dataURI)\"/>"
        } else {
            body += centeredText("等待图片", centerX: x + width / 2, y: imageTop + imageHeight / 2 - 12, size: 76, weight: "700")
            body += centeredText("从 Mac 顶栏选择图片或截屏", centerX: x + width / 2, y: imageTop + imageHeight / 2 + 64, size: 36, weight: "400")
        }
        return body
    }

    private func musicContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += pageHeading("音乐", subtitle: metricValue("状态", fallback: "播放状态"), x: x, y: y, width: width)
        body += modeArt(cx: x + width - 76, cy: y + 78)

        let nowPlaying = model.metrics.first?.value ?? "音乐未运行"
        if nowPlaying.contains("未运行") || nowPlaying.contains("未播放") {
            body += emphasisBand(label: "播放状态", value: "等待音乐", x: x, y: y + 240, width: width, height: 190, valueSize: 68)
            body += simpleList(
                x: x,
                y: y + 520,
                width: width,
                bottom: min(bottom, y + 850),
                title: "从哪里控制",
                rows: ["开始播放 | Mac 顶栏", "切歌与暂停 | Mac 顶栏"],
                rowHeight: 108,
                valueSize: 44
            )
            return body
        }
        body += text("正在播放", x: x, y: y + 274, size: 30, weight: "700", family: "Menlo, Monaco, monospace")
        body += wrapped(nowPlaying, x: x, y: y + 382, width: width, size: 82, maxLines: 3)
        body += line(x1: x, y1: y + 650, x2: x + width, y2: y + 650, stroke: 4)
        body += text("专辑", x: x, y: y + 724, size: 28, weight: "700", family: "Menlo, Monaco, monospace")
        body += wrapped(metricValue("专辑", fallback: "--"), x: x, y: y + 808, width: width, size: 54, maxLines: 2)
        body += centeredText(metricValue("状态", fallback: "未播放"), centerX: x + width / 2, y: min(bottom - 100, y + 1110), size: 46, weight: "700")
        return body
    }

    private func weatherContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        let current = metricValue("现在", fallback: "天气源暂不可用")
        if current.contains("不可用") {
            body += centeredText("天气暂不可用", centerX: x + width / 2, y: y + 500, size: 82, weight: "700", family: uiFont)
            body += centeredText("稍后自动刷新", centerX: x + width / 2, y: y + 590, size: 38, weight: "400", family: uiFont)
            return body
        }
        let weather = weatherSummary(current)
        let updateLabel = model.subhead.replacingOccurrences(of: "未来几小时 · ", with: "")
        body += text("天气 · \(updateLabel)", x: x, y: y + 36, size: 28, weight: "600", fill: "#666", family: uiFont)
        body += text(weather.temperature, x: x - 4, y: y + 168, size: 132, weight: "700", family: uiFont)
        body += text(weather.condition, x: x, y: y + 244, size: 46, weight: "650", family: uiFont)
        body += text(metricValue("细节", fallback: ""), x: x, y: y + 292, size: 28, weight: "600", fill: "#666", family: uiFont)
        body += weatherIcon(condition: model.weatherCondition ?? .unknown, cx: x + width - 142, cy: y + 112, size: 176)

        let rain = metricValue("降雨", fallback: "降雨待更新")
        body += roundedRect(x: x, y: y + 344, width: width, height: 150, radius: 30, fill: "#111")
        body += text(rain, x: x + 36, y: y + 392, size: 24, weight: "650", fill: "#fff", family: uiFont)
        body += wrapped(weatherAdvice, x: x + 36, y: y + 452, width: width - 72, size: 43, maxLines: 1, fill: "#fff", family: uiFont)

        body += text("接下来", x: x, y: y + 572, size: 27, weight: "650", fill: "#666", family: uiFont)
        body += appleWeatherTimeline(x: x, y: y + 600, width: width, bottom: bottom)
        return body
    }

    private func calendarContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += pageHeading(monthTitle(model.generatedAt), subtitle: "\(calendarYear(model.generatedAt)) · \(lunarDateText(model.generatedAt))", x: x, y: y, width: width)
        body += modeArt(cx: x + width - 76, cy: y + 74)

        let next = model.metrics.first?.value ?? "暂无日程"
        body += monthCalendarGrid(date: model.generatedAt, x: x, y: y + 194, width: width)
        body += line(x1: x, y1: y + 770, x2: x + width, y2: y + 770, stroke: 3)
        body += text("下一项", x: x, y: y + 820, size: 27, weight: "700", family: "Menlo, Monaco, monospace")
        body += wrapped(next, x: x, y: y + 892, width: width, size: 52, maxLines: 1)
        if model.notes.isEmpty {
            body += line(x1: x, y1: y + 960, x2: x + width, y2: y + 960, stroke: 3)
            body += text("待办", x: x, y: y + 1010, size: 29, weight: "700", family: "Menlo, Monaco, monospace")
            body += rightText("暂无待办", rightX: x + width, y: y + 1010, size: 38, weight: "700")
            body += emphasisBand(label: "可用时间", value: "今天留白，适合安排深度工作", x: x, y: y + 1080, width: width, height: 170, valueSize: 48)
        } else {
            body += simpleList(x: x, y: y + 960, width: width, bottom: bottom, title: "待办", rows: Array(model.notes.prefix(3)), rowHeight: 96, valueSize: 42)
        }
        return body
    }

    private func focusContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += pageHeading("专注", subtitle: "只做一件事", x: x, y: y, width: width)
        body += modeArt(cx: x + width - 76, cy: y + 78)

        body += text("当前任务", x: x, y: y + 270, size: 30, weight: "700", family: "Menlo, Monaco, monospace")
        body += wrapped(model.metrics.first?.value ?? "等待任务", x: x, y: y + 382, width: width, size: 80, maxLines: 3)
        body += line(x1: x, y1: y + 690, x2: x + width, y2: y + 690, stroke: 4)
        body += text("建议专注块", x: x, y: y + 790, size: 29, weight: "700", family: "Menlo, Monaco, monospace")
        body += centeredText(metricValue("建议专注", fallback: "50 分钟"), centerX: x + width / 2, y: y + 930, size: 130, weight: "700")
        body += emphasisBand(label: "执行原则", value: "完成当前任务，再切换", x: x, y: y + 1030, width: width, height: 180, valueSize: 50)
        return body
    }

    private func systemContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += pageHeading("系统", subtitle: "Mac 健康", x: x, y: y, width: width)
        body += modeArt(cx: x + width - 76, cy: y + 78)

        body += emphasisBand(label: "状态", value: model.metrics.first?.value ?? "不可用", x: x, y: y + 205, width: width, height: 210, valueSize: 66, maxLines: 2)
        let systemMetrics = model.metrics.dropFirst().prefix(3).map { metric in
            Metric(label: metric.label, value: compactSystemValue(metric), emphasis: metric.emphasis)
        }
        body += summaryStrip(x: x, y: y + 485, width: width, metrics: systemMetrics, height: 240)
        body += simpleList(x: x, y: y + 805, width: width, bottom: bottom, title: "占用较高", rows: Array(model.notes.prefix(4)), rowHeight: 100, valueSize: 40)
        return body
    }

    private func screensaverContent(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = ""
        body += centeredText(model.headline, centerX: x + width / 2, y: y + 500, size: 242, weight: "700", family: "Georgia, serif")
        body += centeredText(model.subhead, centerX: x + width / 2, y: y + 594, size: 48, weight: "400")
        body += line(x1: x + 180, y1: y + 700, x2: x + width - 180, y2: y + 700, stroke: 4)
        if !model.footerRight.isEmpty && !model.footerRight.contains("--") {
            body += centeredText(model.footerRight, centerX: x + width / 2, y: y + 790, size: 34, weight: "400", family: "Menlo, Monaco, monospace")
        }
        return body
    }

    private func pageHeading(_ title: String, subtitle: String, x: Int, y: Int, width: Int) -> String {
        var body = ""
        body += text(title, x: x, y: y + 94, size: 88, weight: "700")
        if !subtitle.isEmpty {
            body += text(subtitle, x: x + 2, y: y + 148, size: 30, weight: "400", family: "Menlo, Monaco, monospace")
        }
        return body
    }

    private func metricValue(_ label: String, fallback: String) -> String {
        if let exact = model.metrics.first(where: { $0.label == label }) {
            return exact.value
        }
        return model.metrics.first(where: { $0.label.localizedCaseInsensitiveContains(label) })?.value ?? fallback
    }

    private func noteValue(_ label: String, fallback: String) -> String {
        for note in model.notes {
            let row = splitRow(note)
            if row.left == label, !row.right.isEmpty {
                return row.right
            }
        }
        return fallback
    }

    private func weatherSummary(_ value: String) -> (condition: String, temperature: String) {
        let parts = value
            .components(separatedBy: "，")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let primaryTokens = (parts.first ?? "")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let temperatureIndex = primaryTokens.firstIndex(where: { $0.contains("°") || $0.uppercased().contains("C") })
        let condition: String
        var temperature: String
        if let temperatureIndex {
            temperature = primaryTokens[temperatureIndex]
            let conditionTokens = primaryTokens.enumerated().compactMap { index, token in
                index == temperatureIndex ? nil : token
            }
            condition = conditionTokens.joined(separator: " ").isEmpty
                ? (model.weatherCondition?.label ?? "天气")
                : conditionTokens.joined(separator: " ")
        } else {
            condition = parts.first ?? model.weatherCondition?.label ?? "天气"
            temperature = parts.dropFirst().first ?? "--"
        }
        temperature = temperature
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "°C", with: "°")
            .replacingOccurrences(of: " C", with: "°")
        return (condition, temperature)
    }

    private func humiditySummary() -> String {
        let details = metricValue("天气细节", fallback: metricValue("细节", fallback: ""))
        if let humidity = details.components(separatedBy: "·").first(where: { $0.contains("湿度") }) {
            return humidity.replacingOccurrences(of: "湿度", with: "").trimmingCharacters(in: .whitespaces)
        }
        return "--"
    }

    private func percentageValue(_ value: String) -> Int {
        let digits = value.split(whereSeparator: { !$0.isNumber }).first
        return min(100, max(0, Int(digits ?? "0") ?? 0))
    }

    private func progressBar(x: Int, y: Int, width: Int, height: Int, value: String) -> String {
        let percentage = percentageValue(value)
        var body = roundedRect(x: x, y: y, width: width, height: height, radius: height / 2, fill: "#d2d2d5")
        if percentage > 0 {
            let fillWidth = max(height, width * percentage / 100)
            body += roundedRect(x: x, y: y, width: fillWidth, height: height, radius: height / 2, fill: "#111")
        }
        return body
    }

    private func semanticWeather(
        _ value: String,
        x: Int,
        y: Int,
        width: Int,
        primarySize: Int,
        secondarySize: Int
    ) -> String {
        let parts = value
            .components(separatedBy: "，")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else {
            return wrapped(value, x: x, y: y, width: width, size: primarySize, maxLines: 2)
        }
        var body = wrapped(parts[0], x: x, y: y, width: width, size: primarySize, maxLines: 1)
        body += wrapped(parts.dropFirst().joined(separator: "，"), x: x, y: y + primarySize + 20, width: width, size: secondarySize, maxLines: 1)
        return body
    }

    private func monthTitle(_ date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        return "\(month)月"
    }

    private func calendarYear(_ date: Date) -> String {
        "\(Calendar.current.component(.year, from: date))"
    }

    private func lunarDateText(_ date: Date) -> String {
        let lunar = Calendar(identifier: .chinese)
        let components = lunar.dateComponents([.month, .day], from: date)
        let months = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
        let days = [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
        ]
        let monthIndex = max(1, min(12, components.month ?? 1)) - 1
        let dayIndex = max(1, min(30, components.day ?? 1)) - 1
        return "农历\(months[monthIndex])\(days[dayIndex])"
    }

    private func monthCalendarGrid(date: Date, x: Int, y: Int, width: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let days = calendar.range(of: .day, in: .month, for: date) else {
            return ""
        }

        let columnWidth = width / 7
        let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
        var body = ""
        for (index, weekday) in weekdays.enumerated() {
            body += centeredText(weekday, centerX: x + columnWidth * index + columnWidth / 2, y: y + 42, size: 27, weight: "700", family: "Menlo, Monaco, monospace")
        }
        body += line(x1: x, y1: y + 66, x2: x + width, y2: y + 66, stroke: 2)

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let rowHeight = 78

        for day in days {
            let position = leadingDays + day - 1
            let column = position % 7
            let row = position / 7
            let centerX = x + column * columnWidth + columnWidth / 2
            let baseline = y + 126 + row * rowHeight
            let isToday = todayComponents.day == day
                && todayComponents.month == calendar.component(.month, from: interval.start)
                && todayComponents.year == calendar.component(.year, from: interval.start)
            if isToday {
                body += rect(x: centerX - 34, y: baseline - 48, width: 68, height: 62, stroke: 0, fill: "#111")
                body += centeredText("\(day)", centerX: centerX, y: baseline, size: 42, weight: "700", fill: "#fff")
            } else {
                body += centeredText("\(day)", centerX: centerX, y: baseline, size: 42, weight: "700")
            }
        }
        return body
    }

    private func compactSystemValue(_ metric: Metric) -> String {
        if metric.label == "内存" {
            return metric.value.components(separatedBy: " | ").first ?? metric.value
        }
        if metric.label == "磁盘" {
            return metric.value.components(separatedBy: " / ").first ?? metric.value
        }
        return metric.value
    }

    private func emphasisBand(
        label: String,
        value: String,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        valueSize: Int,
        maxLines: Int = 2
    ) -> String {
        var body = rect(x: x, y: y, width: width, height: height, stroke: 0, fill: "#111")
        body += text(label, x: x + 32, y: y + 48, size: 27, weight: "700", fill: "#fff", family: "Menlo, Monaco, monospace")
        body += wrapped(value, x: x + 32, y: y + 112, width: width - 64, size: valueSize, maxLines: maxLines, fill: "#fff")
        return body
    }

    private func summaryStrip(x: Int, y: Int, width: Int, metrics: [Metric], height: Int) -> String {
        let visible = Array(metrics.prefix(3))
        guard !visible.isEmpty else { return "" }
        let columnWidth = width / visible.count
        var body = line(x1: x, y1: y, x2: x + width, y2: y, stroke: 3)
        body += line(x1: x, y1: y + height, x2: x + width, y2: y + height, stroke: 3)

        for (index, metric) in visible.enumerated() {
            let columnX = x + index * columnWidth
            if index > 0 {
                body += line(x1: columnX, y1: y + 26, x2: columnX, y2: y + height - 26, stroke: 2)
            }
            body += text(metric.label, x: columnX + 24, y: y + 58, size: 27, weight: "700", family: "Menlo, Monaco, monospace")
            body += wrapped(metric.value, x: columnX + 24, y: y + 126, width: columnWidth - 48, size: 42, maxLines: 2)
        }
        return body
    }

    private func compactMetricStrip(x: Int, y: Int, width: Int, metrics: [Metric], height: Int) -> String {
        let visible = Array(metrics.prefix(3))
        guard !visible.isEmpty else { return "" }
        let columnWidth = width / visible.count
        var body = ""
        for (index, metric) in visible.enumerated() {
            let columnX = x + index * columnWidth
            if index > 0 {
                body += line(x1: columnX, y1: y + 18, x2: columnX, y2: y + height - 18, stroke: 2)
            }
            body += text(metric.label, x: columnX + 20, y: y + 54, size: 24, weight: "700", family: "Menlo, Monaco, monospace")
            body += wrapped(metric.value, x: columnX + 20, y: y + 118, width: columnWidth - 36, size: 36, maxLines: 1)
        }
        return body
    }

    private func weatherTimeline(x: Int, y: Int, width: Int, bottom: Int) -> String {
        var body = text("接下来", x: x, y: y + 42, size: 29, weight: "700", family: "Menlo, Monaco, monospace")
        body += line(x1: x, y1: y + 64, x2: x + width, y2: y + 64, stroke: 3)
        let hours = Array(model.weatherHours.prefix(5))
        guard !hours.isEmpty else {
            body += centeredText("未来几小时暂无数据", centerX: x + width / 2, y: y + 190, size: 46, weight: "700")
            return body
        }

        let rowHeight = min(112, max(94, (bottom - y - 70) / hours.count))
        for (index, hour) in hours.enumerated() {
            let rowTop = y + 64 + index * rowHeight
            let baseline = rowTop + Int(Double(rowHeight) * 0.68)
            if index > 0 {
                body += line(x1: x, y1: rowTop, x2: x + width, y2: rowTop, stroke: 1)
            }
            body += text(hour.time, x: x, y: baseline, size: 30, weight: "700", family: "Menlo, Monaco, monospace")
            body += weatherIcon(condition: hour.condition, cx: x + 250, cy: rowTop + rowHeight / 2, size: 62)
            body += text("\(hour.condition.label) \(hour.temperature)", x: x + 306, y: baseline, size: 39, weight: "700")
            let rainText = hour.rainChance == 0 && !hour.condition.isRain ? "无雨" : "降水 \(hour.rainChance)%"
            body += rightText(rainText, rightX: x + width, y: baseline, size: 31, weight: "700", family: "Menlo, Monaco, monospace")
        }
        return body
    }

    private func appleWeatherTimeline(x: Int, y: Int, width: Int, bottom: Int) -> String {
        let hours = Array(model.weatherHours.prefix(5))
        guard !hours.isEmpty else {
            return roundedRect(x: x, y: y, width: width, height: 240, radius: 34, fill: "#f6f6f7", stroke: "#dedee0", strokeWidth: 2)
                + centeredText("未来几小时暂无数据", centerX: x + width / 2, y: y + 140, size: 42, weight: "650", family: uiFont)
        }

        let cardHeight = min(628, max(500, bottom - y - 60))
        let rowHeight = cardHeight / hours.count
        var body = roundedRect(x: x, y: y, width: width, height: cardHeight, radius: 34, fill: "#f6f6f7", stroke: "#dedee0", strokeWidth: 2)
        for (index, hour) in hours.enumerated() {
            let rowTop = y + index * rowHeight
            let baseline = rowTop + Int(Double(rowHeight) * 0.67)
            if index > 0 {
                body += "<line x1=\"\(x + 32)\" y1=\"\(rowTop)\" x2=\"\(x + width - 32)\" y2=\"\(rowTop)\" stroke=\"#d0d0d0\" stroke-width=\"2\"/>"
            }
            body += text(hour.time, x: x + 34, y: baseline, size: 27, weight: "700", family: monoFont)
            body += weatherIcon(condition: hour.condition, cx: x + 220, cy: rowTop + rowHeight / 2, size: 70)
            body += text("\(hour.condition.label) \(compactTemperature(hour.temperature))", x: x + 286, y: baseline, size: 34, weight: "650", family: uiFont)
            body += rightText("\(hour.rainChance)%", rightX: x + width - 60, y: baseline - 12, size: 27, weight: "700", family: uiFont)
            body += progressBar(x: x + width - 240, y: baseline + 7, width: 182, height: 9, value: "\(hour.rainChance)%")
        }
        return body
    }

    private func compactTemperature(_ value: String) -> String {
        value
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "°C", with: "°")
            .replacingOccurrences(of: " C", with: "°")
    }

    private func simpleList(
        x: Int,
        y: Int,
        width: Int,
        bottom: Int,
        title: String,
        rows: [String],
        rowHeight: Int,
        valueSize: Int
    ) -> String {
        var body = ""
        body += text(title, x: x, y: y + 40, size: 29, weight: "700", family: "Menlo, Monaco, monospace")
        body += line(x1: x, y1: y + 62, x2: x + width, y2: y + 62, stroke: 3)
        let capacity = max(1, (bottom - y - 70) / rowHeight)

        for (index, note) in rows.prefix(capacity).enumerated() {
            let row = splitRow(note)
            let rowTop = y + 62 + index * rowHeight
            let baseline = rowTop + Int(Double(rowHeight) * 0.66)
            if index > 0 {
                body += line(x1: x, y1: rowTop, x2: x + width, y2: rowTop, stroke: 1)
            }
            let rightWidth = row.right.isEmpty ? 0 : min(300, max(150, row.right.count * 22))
            body += wrapped(row.left, x: x, y: baseline, width: width - rightWidth - 24, size: valueSize, maxLines: 1)
            if !row.right.isEmpty {
                body += rightText(row.right, rightX: x + width, y: baseline, size: max(28, valueSize - 8), weight: "700", family: "Menlo, Monaco, monospace")
            }
        }
        return body
    }

    private func readableDocument(x: Int, y: Int, width: Int, bottom: Int, rows: [String]) -> String {
        let rowHeight = 116
        let capacity = max(1, (bottom - y) / rowHeight)
        var body = ""

        for (index, note) in rows.prefix(capacity).enumerated() {
            let row = splitRow(note)
            let rowTop = y + index * rowHeight
            let isHeading = row.right == "标题"
            if index > 0 {
                body += line(x1: x, y1: rowTop, x2: x + width, y2: rowTop, stroke: 1)
            }
            body += wrapped(row.left, x: x, y: rowTop + 72, width: width, size: isHeading ? 52 : 44, maxLines: 1)
        }
        return body
    }

    private var homeAdvice: String {
        let values = model.metrics.map(\.value).joined(separator: " ")
        if values.contains("天气源暂不可用") {
            return "天气稍后更新，先推进项目"
        }
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

    private func modeArt(cx: Int, cy: Int) -> String {
        switch model.mode {
        case .weather, .home:
            return weatherIcon(condition: model.weatherCondition ?? .unknown, cx: cx, cy: cy, size: 126)
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

    private func weatherIcon(condition: WeatherCondition, cx: Int, cy: Int, size: Int) -> String {
        let scale = Double(size) / 148.0
        let stroke = max(2, Int((6 * scale).rounded()))
        func px(_ value: Double) -> Int { cx + Int((value * scale).rounded()) }
        func py(_ value: Double) -> Int { cy + Int((value * scale).rounded()) }
        func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, width: Int? = nil) -> String {
            "<line x1=\"\(px(x1))\" y1=\"\(py(y1))\" x2=\"\(px(x2))\" y2=\"\(py(y2))\" stroke=\"#000\" stroke-width=\"\(width ?? stroke)\" stroke-linecap=\"round\"/>"
        }
        func circle(_ x: Double, _ y: Double, _ radius: Double) -> String {
            "<circle cx=\"\(px(x))\" cy=\"\(py(y))\" r=\"\(max(2, Int((radius * scale).rounded())))\" fill=\"#fff\" stroke=\"#000\" stroke-width=\"\(stroke)\"/>"
        }
        func cloud(_ dx: Double = 0, _ dy: Double = 0) -> String {
            "<path d=\"M \(px(-50 + dx)) \(py(18 + dy)) C \(px(-50 + dx)) \(py(2 + dy)) \(px(-38 + dx)) \(py(-10 + dy)) \(px(-21 + dx)) \(py(-10 + dy)) C \(px(-13 + dx)) \(py(-34 + dy)) \(px(20 + dx)) \(py(-38 + dy)) \(px(34 + dx)) \(py(-15 + dy)) C \(px(54 + dx)) \(py(-15 + dy)) \(px(66 + dx)) \(py(0 + dy)) \(px(66 + dx)) \(py(18 + dy)) C \(px(66 + dx)) \(py(34 + dy)) \(px(53 + dx)) \(py(42 + dy)) \(px(34 + dx)) \(py(42 + dy)) H \(px(-28 + dx)) C \(px(-42 + dx)) \(py(42 + dy)) \(px(-50 + dx)) \(py(32 + dy)) \(px(-50 + dx)) \(py(18 + dy)) Z\" fill=\"#fff\" stroke=\"#000\" stroke-width=\"\(stroke)\" stroke-linejoin=\"round\"/>"
        }
        func sun(_ x: Double = 0, _ y: Double = 0, radius: Double = 23) -> String {
            var body = circle(x, y, radius)
            let inner = radius + 13
            let outer = radius + 23
            let diagonal = 0.707
            body += line(x, y - outer, x, y - inner) + line(x, y + inner, x, y + outer)
            body += line(x - outer, y, x - inner, y) + line(x + inner, y, x + outer, y)
            body += line(x - outer * diagonal, y - outer * diagonal, x - inner * diagonal, y - inner * diagonal)
            body += line(x + inner * diagonal, y + inner * diagonal, x + outer * diagonal, y + outer * diagonal)
            body += line(x + outer * diagonal, y - outer * diagonal, x + inner * diagonal, y - inner * diagonal)
            body += line(x - inner * diagonal, y + inner * diagonal, x - outer * diagonal, y + outer * diagonal)
            return body
        }
        func rain(_ positions: [Double], length: Double) -> String {
            positions.map { line($0, 52, $0 - length * 0.35, 52 + length, width: max(stroke, Int((7 * scale).rounded()))) }.joined()
        }

        let content: String
        switch condition {
        case .clear:
            content = sun()
        case .partlyCloudy:
            content = sun(-26, -25, radius: 18) + cloud(5, 8)
        case .cloudy:
            content = cloud()
        case .overcast:
            content = cloud(-12, -16) + cloud(8, 10)
        case .lightRain:
            content = cloud() + rain([-24, 22], length: 18)
        case .moderateRain:
            content = cloud() + rain([-32, 2, 36], length: 25)
        case .heavyRain:
            content = cloud() + rain([-46, -22, 2, 26, 50], length: 32)
        case .thunder:
            content = cloud() + "<polyline points=\"\(px(8)),\(py(45)) \(px(-8)),\(py(68)) \(px(8)),\(py(68)) \(px(-6)),\(py(92))\" fill=\"none\" stroke=\"#000\" stroke-width=\"\(max(stroke, Int((8 * scale).rounded())))\" stroke-linejoin=\"round\"/>" + rain([-32, 34], length: 18)
        case .snow:
            content = cloud() + line(-28, 54, -28, 76) + line(-39, 65, -17, 65) + line(25, 54, 25, 76) + line(14, 65, 36, 65)
        case .fog:
            content = cloud() + line(-48, 57, 50, 57) + line(-38, 76, 38, 76)
        case .wind:
            content = "<path d=\"M \(px(-56)) \(py(-22)) C \(px(-20)) \(py(-22)) \(px(-12)) \(py(-40)) \(px(8)) \(py(-40)) C \(px(27)) \(py(-40)) \(px(32)) \(py(-18)) \(px(18)) \(py(-10))\" fill=\"none\" stroke=\"#000\" stroke-width=\"\(stroke)\" stroke-linecap=\"round\"/><path d=\"M \(px(-58)) \(py(4)) H \(px(34)) C \(px(58)) \(py(4)) \(px(58)) \(py(34)) \(px(36)) \(py(34)) C \(px(25)) \(py(34)) \(px(19)) \(py(28)) \(px(18)) \(py(20))\" fill=\"none\" stroke=\"#000\" stroke-width=\"\(stroke)\" stroke-linecap=\"round\"/>" + line(-46, 30, -4, 30)
        case .unknown:
            content = cloud()
        }
        return content
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

    private func wrapped(_ value: String, x: Int, y: Int, width: Int, size: Int, maxLines: Int) -> String {
        wrapped(value, x: x, y: y, width: width, size: size, maxLines: maxLines, fill: "#000")
    }

    private func wrapped(_ value: String, x: Int, y: Int, width: Int, size: Int, maxLines: Int, fill: String, family: String = "Georgia, serif") -> String {
        let charWidth = containsWideGlyphs(value) ? Double(size) * 1.04 : Double(size) * 0.57
        let maxChars = max(6, width / max(12, Int(charWidth)))
        var lines: [String] = []
        for segment in value.components(separatedBy: "\n") {
            guard lines.count < maxLines else { break }
            lines.append(contentsOf: wrap(segment, maxChars: maxChars, maxLines: maxLines - lines.count))
        }
        return lines.enumerated().map { index, line in
            text(line, x: x, y: y + index * Int(Double(size) * 1.18), size: size, weight: "700", fill: fill, family: family)
        }.joined()
    }

    private func wrap(_ value: String, maxChars: Int, maxLines: Int) -> [String] {
        let breakCharacters: Set<Character> = ["，", "。", "；", "：", "、", "！", "？", ",", ".", ";", ":", "!", "?", "/", "｜", "|"]
        var remaining = Array(value.trimmingCharacters(in: .whitespacesAndNewlines))
        var result: [String] = []

        while !remaining.isEmpty, result.count < maxLines {
            let limit = min(maxChars, remaining.count)
            var cut = limit
            if remaining.count > maxChars {
                let earliestPreferredBreak = max(1, Int(Double(maxChars) * 0.55))
                for index in stride(from: limit - 1, through: earliestPreferredBreak - 1, by: -1) {
                    if breakCharacters.contains(remaining[index]) || remaining[index].isWhitespace {
                        cut = index + 1
                        break
                    }
                }
            }

            let line = String(remaining.prefix(cut)).trimmingCharacters(in: .whitespacesAndNewlines)
            remaining.removeFirst(cut)
            while remaining.first?.isWhitespace == true {
                remaining.removeFirst()
            }
            if !line.isEmpty {
                result.append(line)
            }
        }

        if !remaining.isEmpty, !result.isEmpty {
            result[result.count - 1] = String(result[result.count - 1].prefix(max(1, maxChars - 1))) + "…"
        }
        return result.isEmpty ? [String(value.prefix(maxChars))] : result
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
    private var launchAtLoginMenuItem: NSMenuItem?

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
        launchAtLoginMenuItem = nil

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
        let launchAtLogin = menuItem("登录时自动启动", #selector(toggleLaunchAtLogin), symbol: "power")
        launchAtLoginMenuItem = launchAtLogin
        settingsMenu.addItem(launchAtLogin)
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

    @objc private func toggleLaunchAtLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            showAlert("请先使用已安装的 KindleDashboard.app，再开启登录时自动启动。")
            return
        }

        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            updateControlMenuState()
        } catch {
            showAlert("无法修改登录项：\(error.localizedDescription)")
        }
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

        let launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginMenuItem?.title = menuTitle("登录时自动启动", status: launchAtLoginEnabled ? "开" : "关")
        launchAtLoginMenuItem?.state = launchAtLoginEnabled ? .on : .off
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

private func writeApplicationIcon(to path: String) -> Bool {
    let side = 1024
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return false
    }

    bitmap.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        return false
    }
    NSGraphicsContext.current = context

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()

    let shell = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 196, yRadius: 196)
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    shell.fill()

    let bevel = NSBezierPath(roundedRect: NSRect(x: 174, y: 108, width: 676, height: 808), xRadius: 92, yRadius: 92)
    NSColor(calibratedWhite: 0.02, alpha: 1).setFill()
    bevel.fill()

    let screenRect = NSRect(x: 224, y: 178, width: 576, height: 664)
    let screen = NSBezierPath(roundedRect: screenRect, xRadius: 30, yRadius: 30)
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    screen.fill()

    NSGraphicsContext.saveGraphicsState()
    screen.addClip()
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
    NSRect(x: 224, y: 670, width: 576, height: 172).fill()

    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 276, y: 752, width: 238, height: 28), xRadius: 14, yRadius: 14).fill()
    NSColor(calibratedRed: 0.43, green: 0.72, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 728, y: 746, width: 38, height: 38)).fill()

    NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 276, y: 558, width: 360, height: 44), xRadius: 12, yRadius: 12).fill()
    NSColor(calibratedWhite: 0.40, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 276, y: 500, width: 448, height: 24), xRadius: 12, yRadius: 12).fill()
    NSBezierPath(roundedRect: NSRect(x: 276, y: 454, width: 312, height: 24), xRadius: 12, yRadius: 12).fill()

    NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
    for x: CGFloat in [276, 436, 596] {
        NSBezierPath(roundedRect: NSRect(x: x, y: 268, width: 128, height: 118), xRadius: 14, yRadius: 14).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    NSColor(calibratedWhite: 0.44, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 492, y: 128, width: 40, height: 12)).fill()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 1]) else {
        return false
    }
    return (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
}

if CommandLine.arguments.contains("--dump-home-svg") {
    let state = AppState()
    let model = DashboardData.make(snapshot: state.snapshot())
    print(SVGRenderer(model: model).svg())
    exit(0)
}

if let iconIndex = CommandLine.arguments.firstIndex(of: "--write-app-icon"),
   CommandLine.arguments.indices.contains(iconIndex + 1) {
    exit(writeApplicationIcon(to: CommandLine.arguments[iconIndex + 1]) ? 0 : 1)
}

if CommandLine.arguments.contains("--dump-codex-svg") {
    let state = AppState()
    state.setMode(.codex)
    let model = DashboardData.make(snapshot: state.snapshot())
    print(SVGRenderer(model: model).svg())
    exit(0)
}

if let previewIndex = CommandLine.arguments.firstIndex(of: "--dump-preview"),
   CommandLine.arguments.indices.contains(previewIndex + 1),
   let mode = KindleMode(rawValue: CommandLine.arguments[previewIndex + 1]) {
    print(SVGRenderer(model: DashboardData.preview(mode: mode)).svg())
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
