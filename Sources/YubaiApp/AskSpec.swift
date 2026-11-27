import OSLog
import SwiftUI

/// 问余白 numbers with no design token.
enum AskSpec {
    // Sheet frame
    static let sheetTop: CGFloat = 62 // canvas Ask.dc.html: sheet top, status bar stays visible
    static let headerHeight: CGFloat = 44 // canvas Ask.dc.html: header row
    static let headerSide: CGFloat = 96 // canvas Ask.dc.html: header grid 96 / 1fr / 96
    static let headerInset: CGFloat = 8 // canvas Ask.dc.html: header padding and badge margin
    static let badgeHeight: CGFloat = 22 // canvas Ask.dc.html: AI 未连接 badge
    static let contentGap: CGFloat = 12 // canvas Ask.dc.html: message gap

    // Messages
    static let bubbleWidth: CGFloat = 260 // canvas Ask.dc.html: user bubble max width
    static let bubbleVertical: CGFloat = 10 // canvas Ask.dc.html: user bubble padding
    static let bubbleHorizontal: CGFloat = 14 // canvas Ask.dc.html: user bubble padding
    static let bubbleRadius: CGFloat = 18 // canvas Ask.dc.html: bubble and answer card radius
    static let bubbleTail: CGFloat = 6 // canvas Ask.dc.html: bubble bottom-right corner
    static let thumbRadius: CGFloat = 14 // canvas Ask.dc.html: thumbnail and offline inset row radius

    // Cards
    static let chevron: CGFloat = 14 // canvas Ask.dc.html: expander chevron
    static let followTop: CGFloat = 2 // canvas Ask.dc.html: follow-up block top padding
    static let gap10: CGFloat = 10 // canvas Ask.dc.html: chip row top, button gap, composer gap, batch row gap
    static let chipInset: CGFloat = 14 // canvas Ask.dc.html: chip padding
    static let chipRowTop: CGFloat = 5 // canvas Ask.dc.html: chips 10 below the question, less the 44 pt tap area around a 34 pt chip
    static let buttonsTop: CGFloat = 14 // canvas Ask.dc.html: remind button and action buttons top
    static let primaryShare: CGFloat = 1.6 // canvas Ask.dc.html: grid 1fr / 1.6fr
    static let factRow: CGFloat = 36 // canvas Ask.dc.html: fact row min height
    static let factKey: CGFloat = 72 // canvas Ask.dc.html: fact key column
    static let batchRow: CGFloat = 52 // canvas Ask.dc.html: batch row
    static let checkbox: CGFloat = 22 // canvas Ask.dc.html: batch checkbox
    static let checkboxRadius: CGFloat = 7 // canvas Ask.dc.html: batch checkbox
    static let check: CGFloat = 13 // canvas Ask.dc.html: check mark
    static let flagHeight: CGFloat = 18 // canvas Ask.dc.html: 可能重复 flag
    static let flagInset: CGFloat = 6 // canvas Ask.dc.html: flag padding and name gap
    static let barTop: CGFloat = 8 // canvas Ask.dc.html: offline budget bar
    static let rowsGap: CGFloat = 6 // canvas Ask.dc.html: offline rows and spent row
    static let insetAroundTap: CGFloat = 4 // canvas Ask.dc.html: inset row padding 10, less the tap area around the 32 pt button
    static let goHeight: CGFloat = 32 // canvas Ask.dc.html: 去设置 button

    // Composer
    static let composerHeight: CGFloat = 92 // canvas Ask.dc.html: composer incl. home indicator
    static let composerKeyboardGap: CGFloat = 8 // above the keyboard; the canvas has no keyboard board

    // canvas Ask.dc.html: user bubble, reason and answer text
    static let body = DS.TextStyle(size: 15, lineHeight: 22, weight: .regular, tracking: 0, family: .text, relativeTo: .body, monospacedDigit: false)
    // canvas Ask.dc.html: follow-up question
    static let question = DS.TextStyle(size: 15, lineHeight: 22, weight: .medium, tracking: 0, family: .text, relativeTo: .body, monospacedDigit: false)
    // canvas Ask.dc.html: chosen follow-up option
    static let chipSelected = DS.TextStyle(size: 14, lineHeight: 20, weight: .semibold, tracking: 0, family: .text, relativeTo: .callout, monospacedDigit: false)
    // canvas Ask.dc.html: verdict word
    static let verdict = DS.TextStyle(size: 22, lineHeight: 28, weight: .semibold, tracking: 0, family: .text, relativeTo: .title2, monospacedDigit: false)
    // canvas Ask.dc.html: approval title
    static let approvalTitle = DS.TextStyle(size: 17, lineHeight: 24, weight: .semibold, tracking: 0, family: .text, relativeTo: .headline, monospacedDigit: false)
    // canvas Ask.dc.html: from-value and fact values
    static let number14 = DS.TextStyle(size: 14, lineHeight: 20, weight: .regular, tracking: 0, family: .num, relativeTo: .callout, monospacedDigit: true)
    // canvas Ask.dc.html: offline purchase values
    static let number14Strong = DS.TextStyle(size: 14, lineHeight: 20, weight: .semibold, tracking: 0, family: .num, relativeTo: .callout, monospacedDigit: true)
    // canvas Ask.dc.html: batch amounts
    static let number15Strong = DS.TextStyle(size: 15, lineHeight: 20, weight: .semibold, tracking: 0, family: .num, relativeTo: .subheadline, monospacedDigit: true)
    // canvas Ask.dc.html: AI 未连接 badge and 可能重复 flag
    static let badge = DS.TextStyle(size: 11, lineHeight: 18, weight: .regular, tracking: 0, family: .text, relativeTo: .caption2, monospacedDigit: false)
}

enum AskRenderCounts {
    #if DEBUG
    private static let enabled = ProcessInfo.processInfo.arguments.contains("-YubaiLogAskRenderCounts")
    private static let logger = Logger(subsystem: "app.yubai.personal", category: "AskRenderCounts")
    @MainActor private static var counts: [String: Int] = [:]
    #endif

    @MainActor static func hit(_ body: String) {
        #if DEBUG
        guard enabled else { return }
        counts[body, default: 0] += 1
        logger.log("\(body, privacy: .public)=\(counts[body, default: 0], privacy: .public)")
        #endif
    }
}
