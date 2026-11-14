#if DEBUG && targetEnvironment(simulator)
import Foundation
import Observation
import YubaiCore
#if os(iOS)
import UIKit
import SwiftUI
#endif

#if os(iOS)
/// Read-only native geometry for scripted walks. No device/Release code or
/// visible controls: safe areas, transition completion and remaining scroll
/// travel must be observed rather than guessed from a full-screen AX frame.
struct UITestWindowMetrics: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.read() }
    final class Probe: UIView {
        private var link: CADisplayLink?
        private final class Tick: NSObject {
            weak var probe: Probe?
            init(_ probe: Probe) { self.probe = probe }
            @objc func read() { probe?.read() }
        }
        init() {
            super.init(frame: .zero)
            backgroundColor = .clear; isUserInteractionEnabled = false
            accessibilityIdentifier = "uiTestWindowMetrics"
            updateAccessibility()
            NotificationCenter.default.addObserver(self, selector: #selector(updateAccessibility),
                name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError() }
        deinit { link?.invalidate() }
        @objc private func updateAccessibility() {
            // Script metadata is queryable by XCTest, never a VoiceOver stop.
            isAccessibilityElement = !UIAccessibility.isVoiceOverRunning
        }
        override func didMoveToWindow() {
            super.didMoveToWindow(); link?.invalidate(); link = nil
            if window != nil {
                let timer = CADisplayLink(target: Tick(self), selector: #selector(Tick.read))
                timer.preferredFramesPerSecond = 10
                timer.add(to: .main, forMode: .common); link = timer; read()
            }
        }
        func read() {
            guard let window else { return }
            func rect(_ value: CGRect) -> [CGFloat] { [value.minX, value.minY, value.width, value.height] }
            func transitioning(_ controller: UIViewController) -> Bool {
                controller.transitionCoordinator != nil || controller.isBeingPresented || controller.isBeingDismissed ||
                    controller.children.contains(where: transitioning) || controller.presentedViewController.map(transitioning) == true
            }
            var scrolls: [[String: Any]] = []
            var focused = ""
            func collect(_ view: UIView) {
                guard !view.isHidden, view.alpha > 0 else { return }
                if view.isFirstResponder { focused = view.accessibilityIdentifier ?? "" }
                if let scroll = view as? UIScrollView, scroll.bounds.width > 0, scroll.isScrollEnabled {
                    let frame = scroll.convert(scroll.bounds, to: nil)
                    let scale = frame.height / max(1, scroll.bounds.height)
                    let minimum = -scroll.adjustedContentInset.top
                    let maximum = max(minimum, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
                    scrolls.append(["identifier": scroll.accessibilityIdentifier ?? "", "frame": rect(frame),
                                    "remainingDown": max(0, maximum - scroll.contentOffset.y) * scale,
                                    "remainingUp": max(0, scroll.contentOffset.y - minimum) * scale])
                }
                for child in view.subviews { collect(child) }
            }
            collect(window)
            let safe = window.convert(window.safeAreaLayoutGuide.layoutFrame, to: nil)
            let value: [String: Any] = ["safeArea": rect(safe), "transitioning": window.rootViewController.map(transitioning) ?? false,
                                      "focused": focused, "scrolls": scrolls]
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8), accessibilityValue != json { accessibilityValue = json }
        }
    }
}
#endif

@MainActor @Observable final class UITestRequestLog {
    static let shared = UITestRequestLog()
    var count = 0
    var organizationRequests = 0
    var completedOrganizationIDs: Set<String> = []
    var resentCompletedCount = 0
}

/// No fixture path or scripted response is available in device / Release builds.
/// A UUID-isolated test ledger AND an explicit script flag are both required.
enum UITestSupport {
    /// Opt in only with a valid, isolated UI script; replies remain offline.
    static var allowsBackground: Bool {
        script != nil && ProcessInfo.processInfo.environment["YUBAI_UI_ALLOW_BACKGROUND"] == "1"
    }
    /// Select the same slow, cloud-enabled fixture for BG and foreground fallback checks.
    /// Explicit organization scenarios keep their existing data and timing.
    static var usesBackgroundFixture: Bool {
        script == "salary" && organizationScenario == nil &&
            ProcessInfo.processInfo.environment["YUBAI_UI_BACKGROUND_FIXTURE"] == "1"
    }
    static var organizationScenario: String? {
        guard script == "salary" || script == "v46-sort", let value = ProcessInfo.processInfo.environment["YUBAI_UI_ORGANIZATION_SCENARIO"],
              ["stop-second", "fail-second", "by-party", "by-party-many", "by-party-long", "questions-complete", "questions-stop", "questions-fail"].contains(value) else { return nil }
        return value
    }
    static var isByPartyScenario: Bool { organizationScenario?.hasPrefix("by-party") == true }
    @MainActor static func importRequestState(in ledger: Ledger) -> String {
        let log = UITestRequestLog.shared
        let requests = "requests=\(log.count)"
        guard script != nil, organizationScenario != nil || ProcessInfo.processInfo.environment["YUBAI_UI_TEST_IMPORT_STATE"] == "1" else { return requests }
        var state = requests + ";entries=\(ledger.activeEntries.count);classified=\(ledger.activeEntries.filter { !Classification.isPending($0) }.count);resent=\(log.resentCompletedCount)"
        if organizationScenario?.hasPrefix("questions-") == true {
            state += ";questions=\(ledger.imports.flatMap { $0.organization?.questions ?? [] }.count)"
            #if os(iOS)
            state += ";idle=\(UIApplication.shared.isIdleTimerDisabled ? 1 : 0)"
            #endif
        }
        return state
    }
    static var keepsUndoReceipt: Bool {
        script != nil && ProcessInfo.processInfo.environment["YUBAI_UI_TEST_KEEP_UNDO"] == "1"
    }
    static let screenshotScripts: Set<String> = [
        "judge-ask", "judge-wait", "judge-buy", "judge-skip", "wishlist-cool",
        "letter-saving", "profile-revisit", "subcategory", "salary"
    ]
    /// Scripted replies alone do not imply that a key is configured.
    /// UI tests can explicitly simulate either state without changing Keychain.
    /// The manual background fixture defaults to a configured fake key.
    static var configuredKeyOverride: Bool? {
        guard script != nil else { return nil }
        switch ProcessInfo.processInfo.environment["YUBAI_UI_TEST_CONFIGURED_KEY"] {
        case "1": return true
        case "0": return false
        default: return usesBackgroundFixture ? true : nil
        }
    }
    /// Round 45 fixtures. Numbers follow the design boards; dates follow the simulator clock.
    static let v45Scripts: Set<String> = [
        "v45-home", "v45-over", "v45-bill", "v45-payday", "v45-late", "v45-newcycle", "v45-gap", "v45-new",
        "v45-share", "v45-bill-match", "v45-entry-history", "v45-ask",
        "v45-category", "v45-payback", "v45-split"
    ]
    static var script: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--test-ledger"), args.indices.contains(i + 1),
              UUID(uuidString: args[i + 1]) != nil,
              let name = ProcessInfo.processInfo.environment["YUBAI_UI_TEST_SCRIPT"],
              (butler47Scripts.contains(name) || savings47Scripts.contains(name) || home47Scripts.contains(name) || galleryScripts.contains(name) || billGalleryScripts.contains(name) || v46Scripts.contains(name) || screenshotScripts.contains(name) || ["round40", "empty", "import", "restrain", "ask", "profile", "memory", "manual", "entries", "bills", "bills-overdue", "bills-auto", "bills-estimated", "bills-clarity", "bills-multiple", "wish-bought", "overview-xl", "butler-deck"].contains(name) || v45Scripts.contains(name) || secondBatchScripts.contains(name)) else { return nil }
        return name
    }
    static var statementURL: URL? {
        guard ["import", "v45-import-merge"].contains(script ?? ""), let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--test-ledger") else { return nil }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YubaiUITests/" + ProcessInfo.processInfo.arguments[i + 1])
            .appendingPathComponent("合成账单.csv")
    }
    @MainActor static func prepare(_ repository: LedgerRepository) throws {
        guard let script else { return }
        func save(_ fixture: Ledger, reason: String) throws {
            var fixture = fixture
            if ProcessInfo.processInfo.environment["YUBAI_GALLERY_HIDE_AMOUNTS"] == "1" { fixture.preferences.hideAmounts = true }
            if let appearance = galleryAppearance { fixture.preferences.appearance = appearance }
            try repository.save(fixture, reason: reason)
        }
        if let url = statementURL, let encoded = ProcessInfo.processInfo.environment["YUBAI_UI_STATEMENT"],
           let data = Data(base64Encoded: encoded), data.count < 1_000_000 {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        if script == "empty", galleryAppearance != nil, !FileManager.default.fileExists(atPath: repository.file.path) {
            try save(Ledger(), reason: "合成截图夹具")
            return
        }
        guard !FileManager.default.fileExists(atPath: repository.file.path), script != "empty" else { return }
        let now = Dates.now
        if savings47Scripts.contains(script) {
            let value = try savings47Ledger(script, now: now)
            resetGalleryDeviceState(for: value.id)
            try save(value, reason: "合成存取夹具")
            return
        }
        if butler47Scripts.contains(script) {
            let value = try butler47Ledger(script, now: now)
            resetGalleryDeviceState(for: value.id)
            try save(value, reason: "合成管家夹具")
            return
        }
        if home47Scripts.contains(script) {
            let value = try home47Ledger(script, now: now)
            resetGalleryDeviceState(for: value.id)
            try save(value, reason: "合成主页夹具")
            return
        }
        if billGalleryScripts.contains(script) {
            let value = try billGalleryLedger(script, now: now)
            resetGalleryDeviceState(for: value.id)
            try save(value, reason: "合成账单夹具")
            return
        }
        if v46Scripts.contains(script) {
            let value = try v46Ledger(script, now: now)
            resetGalleryDeviceState(for: value.id)
            try save(value, reason: "合成截图夹具")
            return
        }
        if galleryScripts.contains(script) {
            let ledger = try galleryLedger(script, now: now)
            resetGalleryDeviceState(for: ledger.id)
            try save(ledger, reason: "合成截图夹具")
            if script == "gallery" { try repository.preserveRecovery(ledger, reason: "合成截图历史") }
            return
        }
        if secondBatchScripts.contains(script) {
            try prepareSecondBatch(repository, script: script, now: now)
            return
        }
        if script == "salary" {
            try save(organizationScenario == nil && !usesBackgroundFixture ? salaryLedger(now: now) : organizationLedger(now: now), reason: "合成工资夹具")
            return
        }
        if screenshotScripts.contains(script) {
            try save(screenshotLedger(script, now: now), reason: "合成截图夹具")
            return
        }
        if v45Scripts.contains(script) {
            try save(v45Ledger(script, now: now), reason: "合成测试夹具")
            return
        }
        var ledger = Ledger()
        ledger.preferences.onboardingComplete = true; ledger.preferences.cloudAIEnabled = script != "manual" && script != "entries" && !script.hasPrefix("bills")
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        ledger.mutedTopics = ["letter"] // Keep scripted flows independent of the weekday.
        let account = Account(name: "合成银行卡", balance: 100_000, at: now)
        ledger.accounts = [account]
        if script.hasPrefix("v42") {
            ledger.preferences.cloudAIEnabled = false
            ledger.accounts[0].anchorBalance = script == "v42-over" ? 2_158_000 : 2_834_000
            ledger.accounts[0].anchorDate = Dates.addDays(-1, to: Dates.day(now))
            ledger.fixedSavings = 2_000_000; ledger.savingRule = .fixed(200_000)
            if script == "v42-share" {
                ledger.savingRule = .share(20)
                ledger.entries = [Entry(date: now, amount: 840_000, nature: .income, accountID: account.id, title: "兼职", category: "兼职")]
            }
            let cycle = Finance.cycle(in: ledger, now: now)
            let previous = Finance.cycle(in: ledger, now: cycle.start.addingTimeInterval(-1))
            ledger.savingHistory = [CycleSaving(cycleStart: previous.start, cycleEnd: previous.end, income: 800_000, target: 200_000, saved: 200_000)]
        }
        if script == "round40" {
            ledger.preferences.cloudAIEnabled = false
            ledger.entries = (0..<3).map { Entry(date: Dates.addMonths(-$0, to: now), amount: 350_000, accountID: account.id, title: "合成跨月房租", category: "居住") }
            var deleted = Entry(date: now, amount: 3200, accountID: account.id, title: "合成放回测试", category: "餐饮")
            deleted.deletedAt = now; ledger.entries.append(deleted)
        } else if script == "overview-xl" {
            ledger.entries = [Entry(date: now, amount: 3200, accountID: account.id, title: "合成测试的午饭和日用品以及下周旅行准备", category: "日用")]
        } else if script == "ask" || script == "restrain" {
            ledger.entries = [Entry(date: now, amount: 3200, accountID: account.id, title: "合成咖啡", category: "餐饮")]
        } else if script == "import" {
            ledger.entries = [Entry(date: now.addingTimeInterval(-60), amount: 1600, accountID: account.id, title: "原有午饭", category: "餐饮")]
        } else if script == "entries" {
            ledger.entries = (0..<50).map { Entry(date: now.addingTimeInterval(Double(-$0 * 60)), amount: 3200, accountID: account.id, title: "合成账目 \($0)", category: "餐饮") }
        }
        if script == "butler-deck" {
            ledger.preferences.cloudAIEnabled = false
            ledger.entries = (0..<2).map { Entry(date: now, amount: 3200, accountID: account.id, title: "合成观察 \($0)", category: "餐饮") }
            var top = ButlerCard(kind: .offCharacter, title: "合成的两笔观察", body: "合成记录", evidence: ledger.entries.map(\.id), action: .openEvidence, dedupeKey: "off:" + ledger.entries.map { $0.id.uuidString }.joined(separator: ":"))
            top.priority = 0; top.createdAt = now
            var next = ButlerCard(kind: .recurring, title: "下一条合成提醒", body: "合成记录", action: .openEvidence, dedupeKey: "test:next")
            next.priority = 1; next.createdAt = now
            ledger.cards = [top, next]
        }
        if script == "restrain" {
            ledger.profile.restrain = [ProfileArea(title: "咖啡", match: AreaMatch(keywords: ["咖啡"]), softLimit: SoftLimit(perMonthAmount: 3000))]
        }
        if script == "wish-bought" {
            let entry = Entry(date: now, amount: 3200, accountID: account.id, title: "合成水壶", category: "日用")
            ledger.entries = [entry]
            var wish = WishItem(title: "合成水壶", amount: entry.amount)
            wish.status = .bought; wish.boughtEntryID = entry.id; wish.followUpAt = Dates.addMonths(1, to: now)
            ledger.wishlist = [wish]
        }
        if script.hasPrefix("bills") {
            var rent = Plan(title: "房租", amount: 30_000, dueDate: Dates.day(now))
            rent.accountID = account.id
            var salary = Plan(title: "工资", amount: 50_000, dueDate: Dates.day(now), frequency: .monthly, inflow: true, category: "工资", nature: .income)
            salary.accountID = account.id; ledger.plans = [rent, salary]
            if script == "bills-overdue" {
                var old = Plan(title: "上月账单", amount: 1000, dueDate: Dates.addMonths(-1, to: Dates.day(now)))
                old.accountID = account.id
                var phone = Plan(title: "话费", amount: 6800, dueDate: Dates.day(now))
                phone.accountID = account.id; ledger.plans += [old, phone]
            }
            if script == "bills-auto" {
                ledger.plans[0].autoPay = true; ledger.plans[0].autoPaySince = Dates.day(now)
                ledger.plans[1].dueDate = Dates.addDays(1, to: Dates.day(now))
            }
            if script == "bills-estimated" {
                var power = Plan(title: "电费", amount: 12_000, dueDate: Dates.day(now))
                power.accountID = account.id; power.estimated = true; ledger.plans = [power]
            }
            if script == "bills-clarity" {
                let month = Dates.calendar.dateInterval(of: .month, for: now)!
                ledger.plans[0].dueDate = month.start
                ledger.plans[1].dueDate = max(month.start, Dates.addDays(-6, to: Dates.day(now)))
                var phone = Plan(title: "话费", amount: 5800, dueDate: Dates.day(month.end.addingTimeInterval(-1)))
                phone.accountID = account.id
                var video = Plan(title: "视频会员", amount: 2500, dueDate: month.start)
                video.accountID = account.id; video.autoPay = true
                ledger.plans += [phone, video]
                var entry = Entry(date: now, amount: video.amount, accountID: account.id, title: video.title)
                entry.planID = video.id; entry.occurrence = video.dueDate; entry.source = "自动扣款"; entry.recordedAt = now
                ledger.entries = [entry]
            }
            if script == "bills-multiple" {
                var plan = Plan(title: "每周订阅", amount: 1000, dueDate: Dates.addDays(-35, to: Dates.day(now)), frequency: .weekly)
                plan.accountID = account.id; plan.installments = 7; ledger.plans = [plan]
            }
        }
        if !script.hasPrefix("bills") { seedKnownHomeBudget(&ledger, now: now) }
        try save(ledger, reason: "合成测试夹具")
    }
    /// 现在页各状态。手上的钱、每月存、固定存款和账单照画板：还能花 = 手上 − 存下的钱 5,000 − 每月存 2,000 − 固定账单还要付。
    static func v45Ledger(_ script: String, now: Date) throws -> Ledger {
        if ["v45-category", "v45-payback", "v45-split"].contains(script) { return try v45SecondBatchLedger(script, now: now) }
        if ["v45-share", "v45-bill-match", "v45-entry-history", "v45-ask"].contains(script) {
            var ledger = try v45Ledger(script == "v45-bill-match" ? "v45-bill" : "v45-home", now: now)
            let accountID = ledger.accounts[0].id
            switch script {
            case "v45-share":
                ledger.cycleAnchor = .calendarMonth; ledger.savingRule = .share(20)
                ledger.entries.append(Entry(date: now, amount: 840_000, nature: .income, accountID: accountID,
                                            title: "合成兼职", category: "兼职"))
                seedClosedV45Cycle(&ledger, now: now)
            case "v45-bill-match":
                // Loaded data predates autoLink: paying the bill must offer this
                // existing record instead of recording the same expense twice.
                ledger.entries.append(Entry(date: now, amount: 15_800, accountID: accountID,
                                            title: "话费和宽带", category: "居住"))
            case "v45-entry-history":
                // The latest choice is the exception; two of the last three
                // still suggest 餐饮. The two manual expenses also form a repeat.
                for offset in 1...3 {
                    let date = Dates.addDays(-offset, to: now)
                    var entry = Entry(date: date, amount: 1800, accountID: accountID,
                                      title: "合成咖啡", category: offset == 1 ? "购物" : "餐饮")
                    entry.purpose = "合成咖啡"; entry.recordedAt = date; entry.userEdited = true
                    ledger.entries.append(entry)
                }
            default:
                ledger.preferences.cloudAIEnabled = true
                ledger.entries.append(Entry(date: now, amount: 3200, accountID: accountID,
                                            title: "合成咖啡", category: "餐饮"))
            }
            try ledger.validate()
            return ledger
        }
        var ledger = Ledger()
        ledger.preferences.onboardingComplete = true; ledger.preferences.cloudAIEnabled = false
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now); ledger.lastSubcategoryBatchDay = Dates.text(now)
        ledger.mutedTopics = ["letter"]
        let today = Dates.day(now)
        func day(_ offset: Int) -> Date { Dates.addDays(offset, to: today) }
        var account = Account(name: script == "v45-new" ? "微信零钱" : "合成银行卡", kind: .bank, balance: 0, at: day(-12))
        let accountID = account.id
        var spending: [Entry] = []
        func spend(_ cents: Int64, _ title: String, _ category: String, on date: Date) {
            spending.append(Entry(date: date, amount: cents, accountID: accountID, title: title, category: category))
        }
        func earlier(_ minutes: Double) -> Date { max(today, now.addingTimeInterval(-60 * minutes)) }
        var hand: Int64 = 1_217_400
        var paydayOffset = 20
        var bills: [(title: String, amount: Int64, due: Int, estimated: Bool)] = [
            ("房租", 327_000, 12, false), ("话费和宽带", 16_000, 5, false), ("电费", 18_000, 7, true)
        ]
        switch script {
        case "v45-home":
            for offset in 1...8 { spend(10_000, "日常", "餐饮", on: day(-offset).addingTimeInterval(12 * 3600)) }
            spend(2800, "午饭", "餐饮", on: earlier(30)); spend(800, "地铁", "交通", on: earlier(20))
        case "v45-over":
            hand = 1_029_000; paydayOffset = 5
            bills = [("房租", 327_000, 2, false), ("话费和宽带", 16_000, 3, false), ("电费", 18_000, 4, true)]
            for offset in 1...10 { spend(27_200, "日常", "餐饮", on: day(-offset).addingTimeInterval(12 * 3600)) }
        case "v45-bill":
            hand = 1_200_000; paydayOffset = 15
            bills = [("房租", 327_000, 10, false), ("话费和宽带", 16_000, 0, false), ("电费", 18_000, 1, true)]
            for offset in 1...8 { spend(14_000, "日常", "餐饮", on: day(-offset).addingTimeInterval(12 * 3600)) }
            spend(3200, "午饭", "餐饮", on: day(-1).addingTimeInterval(13 * 3600)); spend(800, "地铁", "交通", on: day(-1).addingTimeInterval(14 * 3600))
        case "v45-payday", "v45-late":
            hand = 721_200; paydayOffset = script == "v45-late" ? -3 : 0; bills = []
            spend(4600, "晚饭", "餐饮", on: day(-1).addingTimeInterval(19 * 3600)); spend(800, "地铁", "交通", on: day(-1).addingTimeInterval(20 * 3600))
        case "v45-newcycle":
            hand = 1_522_200; paydayOffset = 0; bills = []
            for offset in 5...12 { spend(22_350, "日常", "餐饮", on: day(-offset).addingTimeInterval(12 * 3600)) }
        case "v45-gap":
            hand = 1_201_400
            for offset in 4...11 { spend(10_000, "日常", "餐饮", on: day(-offset).addingTimeInterval(12 * 3600)) }
        default: // v45-new
            hand = 800_000; bills = []
        }
        account.anchorBalance = hand + spending.reduce(0) { $0 + $1.amount }
        ledger.accounts = [account]
        ledger.entries = spending
        if script == "v45-gap" {
            var wallet = Account(name: "微信零钱", kind: .cash, balance: 30_000, at: day(-12)); wallet.reconciled = true
            ledger.accounts.append(wallet)
        }
        if script == "v45-new" { return ledger }
        ledger.fixedSavings = 500_000; ledger.savingRule = .fixed(200_000)
        var salary = Plan(title: "工资", amount: 801_000, dueDate: day(paydayOffset), frequency: .monthly, inflow: true, category: "工资奖金", nature: .income)
        salary.accountID = accountID
        ledger.plans = [salary]
        for bill in bills {
            var plan = Plan(title: bill.title, amount: bill.amount, dueDate: day(bill.due), frequency: .monthly, category: "居住")
            plan.accountID = accountID; plan.estimated = bill.estimated
            ledger.plans.append(plan)
        }
        if script == "v45-bill", let power = ledger.plans.first(where: { $0.title == "电费" }) {
            var paid = Entry(date: Dates.addMonths(-1, to: day(1)).addingTimeInterval(12 * 3600), amount: 18_000, accountID: accountID, title: "电费", category: "居住")
            paid.planID = power.id; paid.occurrence = Dates.addMonths(-1, to: day(1))
            ledger.entries.append(paid)
        }
        if ["v45-payday", "v45-late", "v45-newcycle"].contains(script) {
            // 发薪日改成「确认到账才开新周期」：从这一期起要点「到了」。
            ledger.paydayConfirmSince = day(paydayOffset)
        }
        if script == "v45-newcycle", let planID = ledger.plans.first?.id {
            var receipt = Entry(date: max(today, earlier(10)), amount: 801_000, nature: .income, accountID: accountID, title: "工资", category: "工资奖金")
            receipt.planID = planID; receipt.occurrence = today
            ledger.entries.append(receipt)
            ledger.accounts[0].anchorBalance -= receipt.amount
        }
        // The board's 5,000 already includes older savings. Startup maintenance
        // must not merge a synthetic previous cycle into it a second time.
        seedClosedV45Cycle(&ledger, now: now, unspent: script == "v45-newcycle" ? 21_200 : 0)
        try ledger.validate()
        return ledger
    }
    private static func v45SecondBatchLedger(_ script: String, now: Date) throws -> Ledger {
        var ledger = try v45Ledger(script == "v45-split" ? "v45-gap" : "v45-home", now: now)
        let account = ledger.accounts[0]
        switch script {
        case "v45-category":
            ledger.cycleAnchor = .calendarMonth; ledger.entries = []
            let start = Finance.cycle(in: ledger, now: now).start
            let lunch = Entry(date: start, amount: 2800, accountID: account.id, title: "合成午饭", category: "餐饮")
            var refund = Entry(date: now, amount: 500, nature: .refund, accountID: account.id, title: "合成退款", category: "餐饮")
            refund.relatedEntryID = lunch.id
            ledger.entries = [lunch, Entry(date: now, amount: 3200, accountID: account.id, title: "合成午饭", category: "餐饮"), refund,
                              Entry(date: now, amount: 100, accountID: account.id, title: "合成餐饮备注", category: "购物")]
            for (offset, amount) in [62_400, 70_200, 58_800].enumerated() {
                ledger.entries.append(Entry(date: Dates.addMonths(-offset - 1, to: start), amount: Int64(amount), accountID: account.id, title: "合成午饭", category: "餐饮"))
            }
            seedClosedV45Cycle(&ledger, now: now)
        case "v45-payback":
            var purchase = Entry(date: now, amount: 120_000, accountID: account.id, title: "大衣", category: "购物", fromReserve: true)
            purchase.recordedAt = now
            ledger.entries.append(purchase)
        default:
            let actual = Finance.balance(account, in: ledger, at: now) - 41_200
            try Reconciliation.apply(&ledger, actual: [account.id: actual], now: now)
        }
        try ledger.validate()
        return ledger
    }
    private static func seedClosedV45Cycle(_ ledger: inout Ledger, now: Date, unspent: Int64 = 0) {
        let cycle = Finance.cycle(in: ledger, now: now)
        let previous = Finance.cycle(in: ledger, now: cycle.start.addingTimeInterval(-1))
        ledger.savingHistory = [CycleSaving(cycleStart: previous.start, cycleEnd: min(previous.end, Dates.addDays(-1, to: cycle.start)),
                                           income: 801_000, target: 200_000, saved: 200_000,
                                           unspent: unspent, leftoverChoice: unspent == 0 ? .keep : nil)]
    }

    static func salaryLedger(now: Date) -> Ledger {
        var ledger = Ledger()
        ledger.preferences.onboardingComplete = true
        ledger.preferences.cloudAIEnabled = false
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        ledger.lastSubcategoryBatchDay = Dates.text(now)
        ledger.mutedTopics = ["letter"]
        let account = Account(name: "合成工资卡", balance: 200_000, at: now)
        ledger.accounts = [account]
        // Keep 未结清 reachable after dismissing the salary candidate too.
        var pendingBill = Plan(title: "合成未结清账单", amount: 99, dueDate: Dates.day(now))
        pendingBill.accountID = account.id; ledger.plans = [pendingBill]
        let month = Dates.calendar.dateInterval(of: .month, for: now)!.start
        let latestMonth = Dates.calendar.component(.day, from: now) >= 10 ? month : Dates.addMonths(-1, to: month)
        var batch = ImportBatch(filename: "合成工资流水.csv", importedCount: 6, duplicateCount: 0, skippedCount: 0)
        batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: ledger.updatedAt)
        ledger.imports = [batch]
        for offset in -2...0 {
            var entry = Entry(date: Dates.addDays(9, to: Dates.addMonths(offset, to: latestMonth)), amount: 800_000,
                              nature: .income, accountID: account.id, title: "合成公司", category: "工资奖金")
            entry.batchID = batch.id; entry.source = "文件"
            ledger.entries.append(entry)
        }
        for day in 1...90 {
            var entry = Entry(date: Dates.addDays(-day, to: Dates.day(now)), amount: 5_000, accountID: account.id,
                              title: "合成日常支出", category: day <= 3 ? Classification.pendingCategory : "餐饮")
            if day <= 3 { entry.batchID = batch.id; entry.source = "文件" }
            ledger.entries.append(entry)
        }
        return ledger
    }
    /// Three chunks by default; the manual background fixture uses five slow chunks.
    /// No salary candidate or automatic cloud work.
    static func organizationLedger(now: Date) -> Ledger {
        var ledger = salaryLedger(now: now)
        ledger.preferences.cloudAIEnabled = true
        if ["by-party-many", "by-party-long"].contains(organizationScenario ?? "") {
            // 64 groups / 75 entries: the first 61 groups cover exactly 72 entries.
            // The long variant supplies 64 rows in one group and a second live group.
            let many = organizationScenario == "by-party-many"
            ledger.entries = []
            var batch = ImportBatch(filename: "合成长列表.csv", importedCount: many ? 75 : 65, duplicateCount: 0, skippedCount: 0)
            batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: ledger.updatedAt)
            ledger.imports = [batch]
            for index in 0..<(many ? 64 : 2) {
                let count = many ? (index < 11 ? 2 : 1) : (index == 0 ? 64 : 1)
                for row in 0..<count {
                    let party = String(format: "合成对方%02d", index)
                    var entry = Entry(date: now.addingTimeInterval(-Double(index * 100 + row)), amount: 100,
                                      nature: .unknownOut, accountID: ledger.accounts[0].id, title: party + " · 合成明细\(row)")
                    entry.batchID = batch.id; entry.source = "文件"
                    ledger.entries.append(entry)
                }
            }
            if !many {
                // Force the quick card's controls to extend below an iPhone viewport.
                ledger.categories += (0..<24).map { YubaiCore.Category(String(format: "合成分类%02d", $0)) }
            }
            ButlerCards.refresh(&ledger, now: now)
            return ledger
        }
        if organizationScenario == "by-party" {
            var batch = ImportBatch(filename: "合成剩余流水.csv", importedCount: 10, duplicateCount: 0, skippedCount: 0)
            batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: ledger.updatedAt)
            ledger.imports = [batch]
            ledger.entries = (0..<10).map { index in
                let title = index == 0 ? "合成个人 · 来款" : (index <= 6 ? "合成对方甲 · 明细" : "合成对方乙 · 明细")
                var entry = Entry(date: Dates.addDays(-index - 5, to: now), amount: index == 0 ? 99 : 100,
                                  nature: index == 0 ? .unknownIn : .unknownOut, accountID: ledger.accounts[0].id, title: title)
                entry.batchID = batch.id; entry.source = "文件"
                return entry
            }
            // More than five unrelated reminders exercise fallback ordering.
            for index in 0..<6 {
                ledger.entries.append(Entry(date: Dates.addDays(-10, to: now), amount: 200,
                                            nature: .unknownIn, accountID: ledger.accounts[0].id, title: "合成旧来款\(index)", category: "其他收入"))
            }
            ButlerCards.refresh(&ledger, now: now)
            return ledger
        }
        // A known plan makes these rows association candidates; retain the
        // 30/30/10 (or 5×30) checkpoints asserted by the stop/fail UI tests.
        var plan = Plan(title: "合成关联候选", amount: 100, dueDate: Dates.addMonths(12, to: now), frequency: .monthly)
        plan.accountID = ledger.accounts[0].id; ledger.plans.append(plan)
        let count = usesBackgroundFixture ? 150 : 70
        var batch = ImportBatch(filename: "合成大量流水.csv", importedCount: count, duplicateCount: 0, skippedCount: 0)
        batch.needsOrganization = true; batch.undo = ImportUndo(updatedAt: ledger.updatedAt)
        ledger.imports = [batch]
        ledger.entries = (1...count).map { day in
            var entry = Entry(date: Dates.addDays(-day, to: Dates.day(now)), amount: 100,
                              accountID: ledger.accounts[0].id, title: "合成日常支出\(day)", category: Classification.pendingCategory)
            entry.batchID = batch.id; entry.source = "文件"
            return entry
        }
        return ledger
    }
    /// Fresh, synthetic data only. Dates follow the simulator clock.
    static func screenshotLedger(_ script: String, now: Date) throws -> Ledger {
        var ledger = Ledger()
        ledger.preferences.onboardingComplete = true
        ledger.preferences.cloudAIEnabled = script.hasPrefix("judge-") || script == "profile-revisit"
        ledger.lastReflectionWeek = ButlerCards.isoWeek(now)
        ledger.lastSubcategoryBatchDay = Dates.text(now)
        let account = Account(name: "合成银行卡", balance: script == "judge-skip" ? 302_900 : 1_217_900, at: now)
        ledger.accounts = [account]
        switch script {
        case "judge-ask", "judge-wait", "judge-buy":
            ledger.profile.generous = [ProfileArea(title: "运动装备", match: AreaMatch(subcategories: ["购物/运动户外"]), note: "运动装备愿意多花", confirmedAt: now)]
            ledger.memories = [MemoryNote(text: "打算开始徒步，还没去过几次，现在的跑鞋可以先走几次", kind: .plan, source: .chat, createdAt: Dates.addDays(-7, to: now))]
            if script == "judge-buy" {
                ledger.memories = [MemoryNote(text: "想长期徒步，旧跑鞋你也说磨脚了", kind: .plan, source: .chat, createdAt: Dates.addMonths(-1, to: now))]
            }
        case "judge-skip":
            // ¥3,029 less ¥1,750 rent leaves ¥1,279 against a ¥1,899 purchase.
            let month = Dates.calendar.dateInterval(of: .month, for: now)!
            var rent = Plan(title: "房租", amount: 175_000, dueDate: month.end.addingTimeInterval(-1), category: "居住")
            rent.accountID = account.id; ledger.plans = [rent]
        case "wishlist-cool":
            ledger.wishlist = cooldownWishes(now: now)
            let purchaseDate = Dates.addDays(-31, to: now)
            let entry = Entry(date: purchaseDate, amount: 59_900, accountID: account.id, title: "合成机械键盘", category: "购物")
            ledger.entries = [entry]
            var bought = WishItem(title: entry.title, amount: entry.amount, purpose: "每天写东西用")
            bought.createdAt = Dates.addDays(-35, to: now); bought.status = .bought
            bought.boughtEntryID = entry.id; bought.followUpAt = Dates.addDays(30, to: purchaseDate)
            ledger.wishlist.append(bought)
        case "letter-saving":
            // Keep letter unmuted, and create the first letter of this month via Core.
            let weekStart = ButlerCards.calendar.dateInterval(of: .weekOfYear, for: now)!.start
            ledger.wishlist = [droppedWish(title: "合成投影仪", amount: 129_900, at: now.addingTimeInterval(-1)),
                               droppedWish(title: "合成咖啡机", amount: 248_000, at: weekStart.addingTimeInterval(-60))]
            ledger.plans = [("视频会员", Int64(2500)), ("网盘", 1200), ("健身 App", 3000)].enumerated().map { index, item in
                let (title, amount) = item
                let month = Dates.calendar.dateInterval(of: .month, for: now)!.start
                let dueDate = Dates.addDays([3, 12, 24][index] - 1, to: month)
                var plan = Plan(title: title, amount: amount, dueDate: dueDate, frequency: .monthly, category: "娱乐旅行")
                plan.id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
                plan.accountID = account.id
                return plan
            }
            if let candidate = WeeklyLetter.candidate(ledger, now: now) { ledger.cards = [candidate.card(now: now)] }
        case "profile-revisit":
            ledger.profile.restrain = [
                ProfileArea(title: "外卖", match: AreaMatch(subcategories: ["餐饮/外卖"]), note: "外卖每周最多 3 次", softLimit: SoftLimit(perWeekCount: 3), confirmedAt: now),
                ProfileArea(title: "数码电器", match: AreaMatch(subcategories: ["购物/数码电器"]), note: "数码电器每月 800", softLimit: SoftLimit(perMonthAmount: 80_000), confirmedAt: now)
            ]
            ledger.profile.generous = ["书", "运动装备", "朋友吃饭"].map { ProfileArea(title: $0, confirmedAt: now) }
            ledger.profile.principles = ["日常用得上才买", "先试再买"]
            ledger.memories = [MemoryNote(text: "合成：最近经常加班", kind: .life, source: .chat, createdAt: Dates.addDays(-5, to: now)),
                               MemoryNote(text: "合成：打算长期徒步", kind: .plan, source: .chat, createdAt: Dates.addDays(-10, to: now)),
                               MemoryNote(text: "合成：喜欢和朋友一起吃饭", kind: .value, source: .chat, createdAt: Dates.addDays(-15, to: now))]
            ledger.entries = (0..<3).map { index in
                classifiedEntry(title: "合成外卖 \(index + 1)", amount: 3200, category: "餐饮", subcategory: "外卖", accountID: account.id, date: now)
            }
            ledger.entries.append(classifiedEntry(title: "合成数码配件", amount: 42_000, category: "购物", subcategory: "数码电器", accountID: account.id, date: now))
        case "subcategory":
            ledger.entries = [
                classifiedEntry(title: "徒步鞋 · 京东", amount: 89_900, category: "购物", subcategory: "运动户外", accountID: account.id, date: now.addingTimeInterval(-1)),
                classifiedEntry(title: "合成充电器", amount: 12_900, category: "购物", subcategory: "数码电器", accountID: account.id, date: now.addingTimeInterval(-60)),
                classifiedEntry(title: "合成收纳盒", amount: 5900, category: "购物", subcategory: "家居家电", accountID: account.id, date: now.addingTimeInterval(-120)),
                Entry(date: now.addingTimeInterval(-180), amount: 19_900, accountID: account.id, title: "合成购物", category: "购物"),
                Entry(date: now.addingTimeInterval(-240), amount: 8900, accountID: account.id, title: "合成日用品", category: "购物")
            ]
            // Existing wishlist purchase link reaches record details without changing navigation.
            if let shoes = ledger.entries.first {
                var wish = WishItem(title: shoes.title, amount: shoes.amount)
                wish.createdAt = shoes.date; wish.status = .bought; wish.boughtEntryID = shoes.id
                ledger.wishlist = [wish]
            }
        default: throw YubaiError.invalid("未知合成截图脚本。")
        }
        try ledger.validate()
        return ledger
    }
    private static func classifiedEntry(title: String, amount: Int64, category: String, subcategory: String, accountID: UUID, date: Date) -> Entry {
        var entry = Entry(date: date, amount: amount, accountID: accountID, title: title, category: category)
        entry.subcategory = subcategory; entry.subcategoryUserEdited = false
        return entry
    }
    private static func droppedWish(title: String, amount: Int64, at date: Date) -> WishItem {
        var wish = WishItem(title: title, amount: amount)
        wish.createdAt = Dates.addDays(-7, to: date); wish.status = .dropped; wish.droppedAt = date
        return wish
    }
    private static func cooldownWishes(now: Date) -> [WishItem] {
        var headphones = WishItem(title: "降噪耳机", amount: 189_900, purpose: "通勤地铁太吵")
        headphones.createdAt = Dates.addDays(-7, to: now); headphones.coolUntil = now.addingTimeInterval(-1)
        var shoes = WishItem(title: "徒步鞋", amount: 89_900)
        shoes.createdAt = Dates.addDays(-1, to: now); shoes.coolUntil = Dates.addDays(2, to: now)
        var coffee = WishItem(title: "咖啡机", amount: 248_000)
        coffee.createdAt = Dates.addDays(-12, to: now)
        return [headphones, shoes, coffee, droppedWish(title: "合成投影仪", amount: 129_900, at: now.addingTimeInterval(-1))]
    }

}

struct UITestTransport: ChatTransport {
    let script: String
    func send(_ request: ChatRequest) async throws -> ChatMessage {
        await MainActor.run { UITestRequestLog.shared.count += 1 }
        if let reply = try UITestSupport.butler47Reply(request, script: script) { return reply }
        if let reply = try UITestSupport.addEntryReceiptReply(request, script: script) { return reply }
        if let reply = try UITestSupport.secondBatchReceiptReply(request, script: script) { return reply }
        if let reply = try UITestSupport.galleryReply(request, script: script) { return reply }
        if ["导入整理", "导入整理·按对方"].contains(request.purpose), UITestSupport.usesBackgroundFixture {
            try await Task.sleep(for: .seconds(8))
        }
        if ["salary", "import"].contains(script), request.purpose == "导入整理·按对方" {
            let payload = try JSONValue.parse(request.messages.last?.content ?? "")
            let groups = payload["groups"]?.arrayValue ?? []
            let keys = Set(groups.compactMap { group -> String? in
                guard let party = group["party"]?.stringValue else { return nil }
                return "group:" + party + (group["inflow"] == .bool(true) ? ":in" : ":out")
            })
            await MainActor.run {
                let log = UITestRequestLog.shared
                log.organizationRequests += 1
                log.resentCompletedCount += keys.intersection(log.completedOrganizationIDs).count
                log.completedOrganizationIDs.formUnion(keys)
            }
            // Leave outgoing records on the real fallback card for grouping tests.
            if UITestSupport.isByPartyScenario {
                let results: [JSONValue] = groups.compactMap { group in
                    guard group["inflow"] == .bool(true), let id = group["id"] else { return nil }
                    return .object(["group": id, "category": .string("其他收入"), "nature": .string("income"),
                                    "purpose": .string("来自合成个人"), "confident": .bool(true)])
                }
                return ChatMessage(role: .assistant, content: try JSONValue.object(["groups": .array(results)]).jsonText())
            }
            var results: [JSONValue] = []
            for group in groups {
                guard let id = group["id"] else { continue }
                let income = group["inflow"] == .bool(true)
                if script == "import", income {
                    // Uncertain incoming groups stay on the local fallback.
                    results.append(.object(["group": id, "skip": .bool(true)]))
                } else {
                    results.append(.object(["group": id, "category": .string(income ? "工资奖金" : "餐饮"),
                        "nature": .string(income ? "income" : "expense"), "confident": .bool(true)]))
                }
            }
            return ChatMessage(role: .assistant, content: try JSONValue.object(["groups": .array(results)]).jsonText())
        }
        if script == "salary", request.purpose == "导入整理" {
            let payload = try JSONValue.parse(request.messages.last?.content ?? "")
            let batchRows = payload["batch"]?.arrayValue ?? []
            let ids = Set(batchRows.compactMap { $0["id"]?.stringValue })
            // rN names are request-local; provenance facts identify retry rows.
            let stableKeys = Set(batchRows.map { row in
                ["account", "date", "title", "amount"].map { (try? row[$0]?.jsonText()) ?? "" }.joined(separator: "|")
            })
            let scenario = UITestSupport.organizationScenario
            if UITestSupport.isByPartyScenario {
                let rows: [JSONValue] = (payload["batch"]?.arrayValue ?? []).compactMap { row in
                    guard row["inflow"] == .bool(true), let id = row["id"] else { return nil }
                    return .object(["entry": id, "category": .string("其他收入"), "nature": .string("income"),
                        "purpose": .string("来自合成个人"), "confident": .bool(true)])
                }
                return ChatMessage(role: .assistant, content: try JSONValue.object(["rows": .array(rows)]).jsonText())
            }
            let number = await MainActor.run {
                let log = UITestRequestLog.shared
                log.organizationRequests += 1
                log.resentCompletedCount += stableKeys.intersection(log.completedOrganizationIDs).count
                return log.organizationRequests
            }
            if scenario?.hasPrefix("questions-") == true, number >= 2 {
                if scenario == "questions-stop" || (scenario == "questions-fail" && number > 2) {
                    while true { try await Task.sleep(for: .seconds(1)) }
                }
                try await Task.sleep(for: .seconds(number <= 3 ? 7 : 1)) // Observe saved classifications while the next chunk is running.
                if scenario == "questions-fail" {
                    throw DeepSeekError.http(503)
                }
            }
            if scenario == "stop-second", number >= 2 {
                // Stay in a cancellable request until the UI presses Stop.
                while true { try await Task.sleep(for: .seconds(1)) }
            }
            if scenario == "fail-second", number == 2 {
                try await Task.sleep(for: .seconds(1))
                throw DeepSeekError.http(503)
            }
            if scenario == "fail-second", number == 3 {
                while true { try await Task.sleep(for: .seconds(1)) }
            }
            if scenario == "fail-second", number >= 4 {
                // Complete retry's first two chunks, then expose saved progress.
                try await Task.sleep(for: .seconds(number <= 5 ? 1 : 5))
            }
            let rows: [JSONValue] = (payload["batch"]?.arrayValue ?? []).compactMap { row in
                guard let id = row["id"]?.stringValue else { return nil }
                let income = row["inflow"] == .bool(true)
                return .object(["entry": .string(id), "category": .string(income ? "工资奖金" : "餐饮"),
                                "nature": .string(income ? "income" : "expense"), "confident": .bool(true)])
            }
            var questions: [JSONValue] = []
            // Deliberate legacy replies: questions must not suppress confident rows.
            let returnsLegacyQuestion = (scenario?.hasPrefix("questions-") == true && number == 1) ||
                (UITestSupport.usesBackgroundFixture && number == 2)
            if returnsLegacyQuestion, let id = ids.sorted().first {
                let options: [JSONValue] = [("日常支出", "expense"), ("还款", "repayment")].map { title, nature in
                    .object(["title": .string(title), "items": .array([
                        .object(["kind": .string("set_nature"), "entry": .string(id), "nature": .string(nature)])
                    ])])
                }
                questions = [.object(["text": .string("这笔支出是什么用途？"), "entry_ids": .array([.string(id)]), "options": .array(options)])]
            }
            await MainActor.run { UITestRequestLog.shared.completedOrganizationIDs.formUnion(stableKeys) }
            return ChatMessage(role: .assistant, content: try JSONValue.object(["rows": .array(rows), "items": .array([]),
                "series": .array([]), "questions": .array(questions)]).jsonText())
        }
        if script.hasPrefix("judge-") || script == "v45-principles" { return try purchaseReply(request) }
        if script == "profile-revisit", request.purpose == "消费观对话" {
            let reply = profileReply(request)
            if reply.toolCalls == nil, request.messages.contains(where: { $0.role == .assistant && $0.toolCalls == nil }),
               let delay = Double(ProcessInfo.processInfo.environment["YUBAI_UI_PROFILE_REPLY_DELAY"] ?? ""), delay > 0 {
                try await Task.sleep(for: .seconds(min(delay, 5)))
            }
            return reply
        }
        if script == "memory" {
            if request.messages.last?.role == .tool { return ChatMessage(role: .assistant, content: "记下了这个计划。") }
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "remember-plan", name: "remember",
                arguments: #"{"text":"年底前想换电脑","kind":"plan"}"#)])
        }
        if request.purpose == "管家卡片与来信" || request.purpose == "导入短评" {
            return ChatMessage(role: .assistant, content: #"{"cards":[]}"#) // Use the real local templates.
        }
        if script == "import", request.purpose == "导入整理" {
            let payload = try JSONValue.parse(request.messages.last?.content ?? "")
            let batch = payload["batch"]?.arrayValue ?? []
            let id = batch.first(where: { $0["inflow"] == .bool(true) })?["id"]?.stringValue
            let rows: [JSONValue] = batch.compactMap { row in
                guard let key = row["id"]?.stringValue, key != id else { return nil }
                return .object(["entry": .string(key), "category": .string("餐饮"), "nature": .string("expense"), "confident": .bool(true)])
            }
            // Deliberate legacy question for an omitted row: only a local fallback may appear.
            var questions: [JSONValue] = []
            if let id {
                questions = [.object(["text": .string("这笔来款是什么用途？"), "entry_ids": .array([.string(id)]), "options": .array([
                .object(["title": .string("日常收入"), "items": .array([
                    .object(["kind": .string("set_nature"), "entry": .string(id), "nature": .string("income")]),
                    .object(["kind": .string("set_category"), "entry": .string(id), "category": .string("其他收入")])])]),
                .object(["title": .string("先留没写用途"), "items": .array([
                    .object(["kind": .string("set_purpose"), "entry": .string(id), "text": .string("待核对来款")])])])])])]
            }
            let result = JSONValue.object(["rows": .array(rows), "items": .array([]), "series": .array([]), "questions": .array(questions)])
            return ChatMessage(role: .assistant, content: try result.jsonText())
        }
        if script == "ask" || script == "v45-ask" {
            if request.messages.last?.role != .tool {
                return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "coffee-total", name: "summarize",
                    arguments: #"{"nature":"spending","keyword":"咖啡","group_by":"category"}"#)])
            }
            // The agent has executed the real read tool. Quote its amount, never a fabricated answer.
            let result = try JSONValue.parse(request.messages.last?.content ?? "")
            guard let amount = result["spending"]?["text"]?.stringValue else { throw YubaiError.invalid("合成问答缺少汇总。") }
            return ChatMessage(role: .assistant, content: "咖啡共花了 " + amount + "。")
        }
        throw YubaiError.invalid("这条 UI 测试没有配置此请求；不会访问网络。")
    }
    private func purchaseReply(_ request: ChatRequest) throws -> ChatMessage {
        // Route background wording through the existing local-template path.
        guard request.purpose != "管家卡片与来信" else { return ChatMessage(role: .assistant, content: #"{"cards":[]}"#) }
        let lastUserIndex = request.messages.lastIndex { $0.role == .user } ?? request.messages.startIndex
        let turn = request.messages.suffix(from: lastUserIndex)
        let judged = turn.contains { $0.role == .tool && $0.toolCallID == "judge-purchase" }
        let submitted = turn.contains { $0.role == .tool && $0.toolCallID == "purchase-verdict" }
        if let last = turn.last, last.role == .tool, let content = last.content,
           let error = try JSONValue.parse(content)["error"] {
            throw YubaiError.invalid("合成购买工具失败：" + (error["message"]?.stringValue ?? content))
        }
        if submitted { return ChatMessage(role: .assistant, content: "已给出结论。") }
        if !judged {
            let skip: Bool = script == "judge-skip"
            var fields: [String: JSONValue] = ["title": .string(skip ? "降噪耳机" : "徒步鞋"),
                "amount": .string(script == "v45-principles" ? "2480" : (skip ? "1899" : "899")), "category": .string("购物"),
                "subcategory": .string(skip ? "数码电器" : "运动户外")]
            if skip {
                let rentDate = Dates.calendar.dateInterval(of: .month, for: Dates.now)!.end
                fields["date"] = .string(Dates.text(rentDate))
            }
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "judge-purchase", name: "judge_purchase", arguments: try JSONValue.object(fields).jsonText())])
        }
        let direct = request.messages.last { $0.role == .user }?.content?.contains("直接给结论") == true
        if script == "judge-ask", !direct, request.messages.filter({ $0.role == .user }).count == 1 {
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "purchase-questions", name: "ask_purchase_questions", arguments:
                #"{"questions":[{"text":"最近三个月徒步过几次？","options":["还没怎么去","一两次","每月都去"]},{"text":"现在的鞋里，有能先穿着走的吗？","options":["有双跑鞋","没有合适的"]},{"text":"先穿现有的走三次，还会觉得非换不可吗？","options":["会，旧鞋磨脚","说不好"]}]}"#)])
        }
        let verdict: String
        let reason: String
        switch script {
        case "judge-buy": verdict = "buy"; reason = "旧跑鞋你也说磨脚了。"
        case "judge-skip":
            verdict = "skip"
            let result = try JSONValue.parse(turn.last { $0.toolCallID == "judge-purchase" }?.content ?? "")
            let due = result["affordability"]?["upcoming_payments"]?.arrayValue?.first?["date"]?.stringValue.flatMap(Dates.parse)
            let month = due.map { Dates.calendar.component(.month, from: $0) } ?? 11
            reason = "买了以后到 \(month)月1日交房租前还差 620 元。"
        default: verdict = "wait"; reason = "你最近三个月还没去徒步，现在的跑鞋可以先走几次。"
        }
        let judgment = try JSONValue.parse(turn.last { $0.toolCallID == "judge-purchase" }?.content ?? "")
        let memories: JSONValue? = judgment["memories"]
        let ids: [String] = ["plan", "value", "life"].flatMap { kind in
            (memories?[kind]?.arrayValue ?? []).compactMap { $0["id"]?.stringValue }
        }
        let args: JSONValue = .object(["verdict": .string(verdict), "reason": .string(reason),
            "need": .string(verdict == "buy" ? "need" : "want"), "memory_ids": .array(ids.map(JSONValue.string))])
        return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "purchase-verdict", name: "submit_verdict", arguments: try args.jsonText())])
    }
    private func profileReply(_ request: ChatRequest) -> ChatMessage {
        let lastUserIndex = request.messages.lastIndex { $0.role == .user } ?? request.messages.startIndex
        let turn = request.messages.suffix(from: lastUserIndex)
        if !turn.contains(where: { $0.role == .tool && $0.toolCallID == "revisit-profile" }) {
            return ChatMessage(role: .assistant, toolCalls: [ChatToolCall(id: "revisit-profile", name: "get_profile")])
        }
        if request.messages.contains(where: { $0.role == .assistant && $0.toolCalls == nil }) {
            return ChatMessage(role: .assistant, content: "外卖这周已经 3 次了，加班的日子想怎么安排？")
        }
        return ChatMessage(role: .assistant, content: "你现在写着想克制外卖和数码，愿意在书、运动装备和朋友吃饭上多花。想改哪里？")
    }

}
#endif
