import OSLog
import SwiftUI

/// Settings, account and first-open numbers with no design token.
enum SettingsSpec {
    // Shared
    static let row: CGFloat = 52 // canvas Settings.dc.html: settings rows, SettingsMore.dc.html: account edit rows
    static let groupGap: CGFloat = 22 // canvas Settings.dc.html: gap between cards and above the version
    static let cardInset: CGFloat = 14 // canvas Settings.dc.html: card leading inset, weekend row, key field
    static let chevron: CGFloat = 14 // canvas Settings.dc.html: row chevron
    static let previewBar: CGFloat = 10 // canvas Settings.dc.html: cycle preview, SettingsMore.dc.html: split bar, Onboard.dc.html: progress
    static let barRadius: CGFloat = 5 // canvas SettingsMore.dc.html: split bar outer radius
    static let labelsTop: CGFloat = 6 // canvas SettingsMore.dc.html: split labels, Onboard.dc.html: progress labels
    static let headerTop: CGFloat = 6 // canvas Settings.dc.html: recurring header and category segmented control
    static let cardTop: CGFloat = 14 // canvas Settings.dc.html: calendar and list cards

    // 周期起始日
    static let dayGap: CGFloat = 6 // canvas Settings.dc.html: day grid gap
    static let dayCell: CGFloat = 40 // canvas Settings.dc.html: day cell
    static let onboardDayCell: CGFloat = 42 // canvas Onboard.dc.html: step 1 day cell
    static let lastDaySpan = 3 // canvas Settings.dc.html: 每月最后一天 spans three columns
    static let previewTop: CGFloat = 18 // canvas Settings.dc.html: preview bar top
    static let previewGap: CGFloat = 3 // canvas Settings.dc.html: gap between the two halves
    static let markerWidth: CGFloat = 2 // canvas Settings.dc.html: today marker
    static let markerHeight: CGFloat = 18 // canvas Settings.dc.html: today marker
    static let labelGap: CGFloat = 8 // canvas Settings.dc.html: preview labels top

    // 固定订阅
    static let monthHeader: CGFloat = 36 // canvas Settings.dc.html: calendar month header and arrow buttons
    static let calendarInset: CGFloat = 10 // canvas Settings.dc.html: calendar card padding
    static let weekdayRow: CGFloat = 20 // canvas Settings.dc.html: weekday row
    static let calendarCell: CGFloat = 44 // canvas Settings.dc.html: day cells
    static let calendarRowGap: CGFloat = 2 // canvas Settings.dc.html: row gap
    static let calendarArrow: CGFloat = 16 // canvas Settings.dc.html: month arrows
    static let markTop: CGFloat = 4 // canvas Settings.dc.html: date top inset
    static let markGap: CGFloat = 3 // canvas Settings.dc.html: date to marks
    static let markOverlap: CGFloat = 6 // canvas Settings.dc.html: second mark offset
    static let subRow: CGFloat = 56 // canvas Settings.dc.html: subscription rows, SettingsMore.dc.html: currency rows
    static let rowTile: CGFloat = 32 // canvas Settings.dc.html: list brand tile, SettingsMore.dc.html: name field tile
    static let pickTile: CGFloat = 56 // canvas SettingsMore.dc.html: icon picker tile
    static let tileRadius: CGFloat = 0.25 // canvas SettingsMore.dc.html: brand tile radius / size
    static let glyphShare: CGFloat = 0.56 // canvas SettingsMore.dc.html: glyph / tile
    static let monogramShare: CGFloat = 0.44 // canvas Settings.dc.html: 14 pt monogram on a 32 pt tile
    static let monogramMinimum: CGFloat = 10 // canvas Settings.dc.html: monogram on an 18 pt mark
    static let darkBrandLuminance = 0.08 // canvas SettingsMore.dc.html: near-black brands get a separator ring
    static let lightBrandLuminance = 0.7 // SPEC §3.1: light brands use an ink glyph

    // 分类
    static let segmentWidth: CGFloat = 200 // canvas Settings.dc.html: 支出 / 收入
    static let categoryChevron: CGFloat = 16 // canvas Settings.dc.html: category chevron
    static let chevronColumn: CGFloat = 20 // canvas Settings.dc.html: chevron column
    static let addIcon: CGFloat = 13 // canvas Settings.dc.html: 添加小类 plus
    static let openGap: CGFloat = 8 // canvas Settings.dc.html: below the open card

    // 余白的 AI
    static let aiCard: CGFloat = 64 // canvas Settings.dc.html: 云端 AI card
    static let shareTop: CGFloat = 10 // canvas Settings.dc.html: 云端能看到 caption
    static let shareChip: CGFloat = 40 // canvas Settings.dc.html: share chips
    static let shareColumns = 4 // canvas Settings.dc.html: four chips
    static let shareMark: CGFloat = 13 // canvas Settings.dc.html: chip check and cross
    static let disabledOpacity = 0.4 // SPEC §5: chips while cloud AI is off
    static let toneWidth: CGFloat = 120 // canvas Settings.dc.html: 温和 / 直接 segmented control
    static let toneHeight: CGFloat = 30 // canvas Settings.dc.html: 温和 / 直接 segmented control
    static let toneInset: CGFloat = 2 // canvas Settings.dc.html: compact segmented inset
    static let keyButtonsTop: CGFloat = 16 // canvas Settings.dc.html: 粘贴 / 保存 row
    static let pasteShare: CGFloat = 1.0 / 3.0 // canvas Settings.dc.html: 1fr / 2fr buttons
    static let linkIcon: CGFloat = 12 // canvas Settings.dc.html: 去 DeepSeek 申请 arrow
    static let keyPrefix = 3 // SPEC §5: shown key start
    static let keySuffix = 4 // SPEC §5: shown key end
    static let keyBullets = 16 // canvas Settings.dc.html: masked key bullets

    // Amount sheets
    static let amountVertical: CGFloat = 14 // canvas SettingsMore.dc.html: amount box padding
    static let nameFieldInset: CGFloat = 10 // canvas SettingsMore.dc.html: subscription name field
    static let chipsTop: CGFloat = 12 // canvas SettingsMore.dc.html: chips and split bar top
    static let tenPercent: Int64 = 10 // canvas SettingsMore.dc.html: 10 % chip
    static let twentyPercent: Int64 = 20 // canvas SettingsMore.dc.html: 20 % chip

    // 币种
    static let symbolColumn: CGFloat = 32 // canvas SettingsMore.dc.html: currency symbol column
    static let codeColumn: CGFloat = 44 // canvas SettingsMore.dc.html: currency code column
    static let check: CGFloat = 20 // canvas SettingsMore.dc.html: base currency check

    // 添加账户 / 编辑账户
    static let typeTile: CGFloat = 64 // canvas SettingsMore.dc.html: type grid tile
    static let typeIcon: CGFloat = 22 // canvas SettingsMore.dc.html: type icon
    static let typeColumns = 3 // canvas SettingsMore.dc.html: type grid
    static let nameField: CGFloat = 48 // canvas SettingsMore.dc.html: account name field
    static let balanceBox: CGFloat = 64 // canvas SettingsMore.dc.html: balance box
    static let balanceTop: CGFloat = 10 // canvas SettingsMore.dc.html: balance box top and padding

    // 首次打开
    static let progressGap: CGFloat = 6 // canvas Onboard.dc.html: progress segments
    static let progressHeight: CGFloat = 4 // canvas Onboard.dc.html: progress segments
    static let progressTrailing: CGFloat = 56 // canvas Onboard.dc.html: progress right margin
    static let titleSide: CGFloat = 24 // canvas Onboard.dc.html: title padding
    static let buttonBottom: CGFloat = 44 // canvas Onboard.dc.html: primary button above the bottom edge
    static let incomeBox: CGFloat = 62 // canvas Onboard.dc.html: 每月到手 box
    static let savingBorder: CGFloat = 2 // canvas Onboard.dc.html: focused 先攒 box
    static let caretHeight: CGFloat = 22 // canvas Onboard.dc.html: amount caret
    static let floorRow: CGFloat = 48 // canvas Onboard.dc.html: 底线存款 row
    static let accountTile: CGFloat = 96 // canvas Onboard.dc.html: account tiles
    static let accountGap: CGFloat = 10 // canvas Onboard.dc.html: account grid gap
    static let badge: CGFloat = 22 // canvas Onboard.dc.html: check badge
    static let badgeIcon: CGFloat = 12 // canvas Onboard.dc.html: check badge glyph
    static let dash: [CGFloat] = [5, 4] // canvas Onboard.dc.html: dashed 其他账户 border
    static let onboardColumns = 2 // canvas Onboard.dc.html: account grid

    // canvas Settings.dc.html: 固定订阅 monthly total
    static let total = DS.TextStyle(size: 30, lineHeight: 36, weight: .semibold, tracking: -0.5, family: .num, relativeTo: .largeTitle, monospacedDigit: true)
    // canvas SettingsMore.dc.html: amount sheets
    static let amount = DS.TextStyle(size: 28, lineHeight: 34, weight: .semibold, tracking: -0.5, family: .num, relativeTo: .title, monospacedDigit: true)
    // canvas Settings.dc.html: +N marks
    static let more = DS.TextStyle(size: 10, lineHeight: 12, weight: .semibold, tracking: 0, family: .num, relativeTo: .caption2, monospacedDigit: true)
    // canvas Settings.dc.html: DeepSeek key field
    static let key = DS.TextStyle(size: 16, lineHeight: 22, weight: .regular, tracking: 1, family: .num, relativeTo: .body, monospacedDigit: true)
    // canvas SettingsMore.dc.html: HK$ symbol
    static let smallSymbol = DS.TextStyle(size: 11, lineHeight: 14, weight: .semibold, tracking: 0, family: .num, relativeTo: .caption2, monospacedDigit: true)
    // canvas SettingsMore.dc.html: icon picker monogram
    static let pickMonogram = DS.TextStyle(size: 22, lineHeight: 26, weight: .semibold, tracking: 0, family: .text, relativeTo: .title2, monospacedDigit: false)
    // canvas Onboard.dc.html: step titles
    static let onboardTitle = DS.TextStyle(size: 28, lineHeight: 36, weight: .semibold, tracking: -0.3, family: .text, relativeTo: .largeTitle, monospacedDigit: false)
    // canvas Onboard.dc.html: account tile name
    static let tileName = DS.TextStyle(size: 15, lineHeight: 20, weight: .medium, tracking: 0, family: .text, relativeTo: .subheadline, monospacedDigit: false)
}

@MainActor enum SettingsRenderCounts {
    #if DEBUG
    private static let enabled = ProcessInfo.processInfo.arguments.contains("-YubaiLogSettingsRenderCounts")
    private static let logger = Logger(subsystem: "app.yubai.personal", category: "SettingsRenderCounts")
    private static var counts: [String: Int] = [:]
    #endif

    static func hit(_ part: String) {
        #if DEBUG
        guard enabled else { return }
        counts[part, default: 0] += 1
        logger.notice("\(part, privacy: .public)=\(counts[part, default: 0], privacy: .public)")
        #endif
    }
}
