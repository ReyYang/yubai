import SwiftUI
import YubaiCore

enum YubaiTheme {
    static let deepJade = Color(red: 0.12, green: 0.40, blue: 0.34)
    #if os(macOS)
    static let jade = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.46, green: 0.78, blue: 0.65, alpha: 1) : NSColor(red: 0.12, green: 0.40, blue: 0.34, alpha: 1)
    })
    #else
    static let jade = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.46, green: 0.78, blue: 0.65, alpha: 1) : UIColor(red: 0.12, green: 0.40, blue: 0.34, alpha: 1)
    })
    #endif
    static let mint = Color(red: 0.72, green: 0.88, blue: 0.79)
    static let amber = Color(red: 0.68, green: 0.40, blue: 0.10)
    static let ink = Color(red: 0.12, green: 0.19, blue: 0.17)
    static let palette: [Color] = [jade, .blue, .orange, .purple, .teal, .pink, .indigo, .brown, .gray]
    #if os(macOS)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    #else
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    #endif
}
struct BrandMark: View {
    var body: some View { HStack(spacing: 11) { ZStack { RoundedRectangle(cornerRadius: 13).fill(YubaiTheme.deepJade).frame(width: 43, height: 43); Image(systemName: "circle.lefthalf.filled").font(.system(size: 25, weight: .light)).foregroundStyle(.white) }; VStack(alignment: .leading, spacing: 1) { Text("余白").font(.system(size: 23, weight: .semibold, design: .serif)); Text("Y U B A I").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary) } } }
}
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.headline).padding(.horizontal, 22).padding(.vertical, 14).frame(minHeight: 46).foregroundStyle(.white).background(YubaiTheme.deepJade.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 14)) }
}
struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { content.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(YubaiTheme.card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(.primary.opacity(0.035), lineWidth: 1)) }
}
struct Page<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 22) { content }.padding(.horizontal, 22).padding(.vertical, 24).frame(maxWidth: 1080).frame(maxWidth: .infinity) }.scrollDismissesKeyboard(.interactively).background(YubaiTheme.canvas) }
}
struct SectionHeading: View {
    var title: String; var subtitle: String? = nil
    var body: some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.title3.weight(.semibold)); if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) } } }
}
struct AmountLabel: View {
    let cents: Int64; var large = false; var hide = false
    var body: some View { Text(hide ? "••••••" : Money.text(cents)).font(large ? .system(size: 38, weight: .medium, design: .rounded) : .system(.body, design: .rounded).weight(.semibold)).monospacedDigit().minimumScaleFactor(0.55).lineLimit(1).accessibilityLabel(hide ? "金额已隐藏" : Money.text(cents)) }
}
struct EmptyState: View {
    var icon: String; var title: String; var message: String; var action: String? = nil; var onAction: (() -> Void)?
    init(_ icon: String, _ title: String, _ message: String, action: String? = nil, onAction: (() -> Void)? = nil) { self.icon = icon; self.title = title; self.message = message; self.action = action; self.onAction = onAction }
    var body: some View { VStack(spacing: 16) { Image(systemName: icon).font(.system(size: 36, weight: .light)).foregroundStyle(YubaiTheme.jade).frame(width: 76, height: 76).background(YubaiTheme.jade.opacity(0.08), in: RoundedRectangle(cornerRadius: 24)); Text(title).font(.title3.weight(.semibold)); Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 410); if let action, let onAction { Button(action, action: onAction).buttonStyle(PrimaryButtonStyle()) } }.frame(maxWidth: .infinity).padding(.vertical, 38).padding(.horizontal, 20) }
}
struct IconTile: View {
    var symbol: String; var color = YubaiTheme.jade
    var body: some View { Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(color).frame(width: 42, height: 42).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13)) }
}
struct EntryRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    var entry: Entry
    var hideAmount = false
    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(spacing: 12) {
                IconTile(symbol: store.current.categories.first { $0.name == entry.category }?.symbol ?? entry.nature.symbol, color: entry.nature.uncertain ? YubaiTheme.amber : YubaiTheme.jade)
                VStack(alignment: .leading, spacing: 5) { Text(entry.title).font(.body.weight(.medium)).lineLimit(textSize.isAccessibilitySize ? 3 : 1); Text("\(entry.category) · \(store.current.accountName(entry.accountID))").font(.caption).foregroundStyle(.secondary).lineLimit(textSize.isAccessibilitySize ? 2 : 1) }
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: 6) }
            VStack(alignment: textSize.isAccessibilitySize ? .leading : .trailing, spacing: 5) { Text(hideAmount ? "••••••" : (entry.nature.inflow ? "+" : "−") + Money.text(entry.amount)).font(.system(.body, design: .rounded).weight(.medium)).foregroundStyle(entry.nature.inflow ? YubaiTheme.jade : .primary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6); Text(Dates.text(entry.date)).font(.caption2).foregroundStyle(.secondary) }
        }.padding(.vertical, 5).contentShape(Rectangle())
    }
}
struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("完成") { dismiss() }.accessibilityIdentifier("closeSheet") }
}
struct InlineNote: View {
    var text: String; var symbol = "info.circle"
    var body: some View { Label(text, systemImage: symbol).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
extension View {
    func appErrors() -> some View { modifier(AppErrorPresenter()) }
    func numericInput() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }
    func editorForm() -> some View { self.formStyle(.grouped).scrollDismissesKeyboard(.interactively) }
}

private struct AppErrorPresenter: ViewModifier {
    @Environment(AppStore.self) private var store
    @State private var identity = UUID()
    func body(content: Content) -> some View {
        content
            .onAppear { if !store.errorHosts.contains(identity) { store.errorHosts.append(identity) } }
            .onDisappear { store.errorHosts.removeAll { $0 == identity } }
            .alert("需要留意", isPresented: Binding(get: { store.error != nil && store.errorHosts.last == identity }, set: { value in if !value && store.errorHosts.last == identity { store.error = nil } })) {
                Button("知道了", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
}

struct WelcomeView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 30) {
                BrandMark().padding(.top, 32)
                Text("把钱理清，\n把生活留给自己。").font(.system(size: 38, weight: .medium, design: .serif)).lineSpacing(8).fixedSize(horizontal: false, vertical: true)
                Text("余额不等于可花的钱。余白把散落的账单、未来要付的钱和真正想做的事，放在同一处。") .font(.body).foregroundStyle(.secondary).lineSpacing(6)
                VStack(alignment: .leading, spacing: 24) {
                    feature("wallet.bifold", "一份可信的账本", "导入微信、支付宝与银行卡账单，自动整理，随时纠正。")
                    feature("calendar", "从今天安排未来", "先留出房租、还款和目标，再看此刻有多少余地。")
                    feature("lock.shield", "数据留在你手里", "无需注册，离线可用，可导出和加密备份。")
                }.padding(.vertical, 10)
                Button("开始我的账本") { store.update("建立账本") { $0.preferences.onboardingComplete = true }; store.sheet = .account(nil) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("startLedger")
                Button("先看看示例账本") { store.startDemo() }.font(.callout).accessibilityIdentifier("openDemo")
                Text("示例数据与你的账本完全分开。所有示例金额都是虚构的。") .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: 610, alignment: .leading).frame(maxWidth: .infinity).padding(.bottom, 40)
        }.toolbar { Button("恢复备份") { store.sheet = .backup } }
    }
    func feature(_ symbol: String, _ title: String, _ text: String) -> some View { HStack(alignment: .top, spacing: 15) { IconTile(symbol: symbol); VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } } }
}
