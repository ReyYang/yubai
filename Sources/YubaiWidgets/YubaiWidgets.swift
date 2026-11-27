#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit
import YubaiCore

@main struct YubaiWidgets: WidgetBundle {
    var body: some Widget {
        CaptureWidget()
        ScreenshotWidget()
        AddCaptureControl()
        ScreenshotCaptureControl()
    }
}
private struct CaptureTimelineEntry: TimelineEntry {
    let date: Date; let snapshot: QuickCaptureSnapshot?
}
private struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureTimelineEntry { CaptureTimelineEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (CaptureTimelineEntry) -> Void) {
        completion(CaptureTimelineEntry(date: Date(), snapshot: CaptureSnapshotBridge.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureTimelineEntry>) -> Void) {
        let now = Date(); let midnight = Dates.addDays(1, to: Dates.day(now))
        // 午夜直接移除过期数字，不把昨天笔数继续显示为今天。
        let current = CaptureTimelineEntry(date: now, snapshot: CaptureSnapshotBridge.read(now: now))
        completion(Timeline(entries: [current, CaptureTimelineEntry(date: midnight, snapshot: nil)], policy: .after(midnight)))
    }
}
private struct CaptureWidget: Widget {
    let kind = "app.yubai.quick-capture"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaptureProvider()) { entry in CaptureWidgetView(entry: entry) }
            .configurationDisplayName("记一笔与还能花").description("打开记一笔，查看今天记了几笔。")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium])
    }
}
private struct ScreenshotWidget: Widget {
    let kind = "app.yubai.screenshot-capture"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaptureProvider()) { _ in
            DSIconView(icon: .scanCapture, size: 22).accessibilityElement(children: .ignore).accessibilityLabel("截图记")
                .widgetURL(URL(string: "yubai://capture")!).containerBackground(.clear, for: .widget)
        }.configurationDisplayName("截图记").description("打开截图记。")
            .supportedFamilies([.accessoryCircular])
    }
}
private struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: CaptureTimelineEntry
    private var canvas: Color { scheme == .dark ? Color(red: 31 / 255, green: 27 / 255, blue: 20 / 255) : Color(red: 0.961, green: 0.945, blue: 0.898) }
    private var brand: Color { scheme == .dark ? Color(red: 134 / 255, green: 168 / 255, blue: 132 / 255) : Color(red: 0.333, green: 0.498, blue: 0.325) }
    private var raised: Color { scheme == .dark ? Color(red: 53 / 255, green: 48 / 255, blue: 38 / 255) : Color(red: 0.996, green: 0.984, blue: 0.918) }
    private var ink: Color { scheme == .dark ? Color(red: 230 / 255, green: 222 / 255, blue: 203 / 255) : Color(red: 56 / 255, green: 47 / 255, blue: 31 / 255) }
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: DSIconView(icon: .add, size: 22).accessibilityElement(children: .ignore).accessibilityLabel("记一笔")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    if let snapshot = entry.snapshot {
                        Text((snapshot.headlineTitle ?? "还能花") + " " + snapshot.money(snapshot.available)).font(.headline).monospacedDigit().privacySensitive()
                        Text("今天记了 \(snapshot.todayCount.formatted()) 笔").font(.caption).privacySensitive()
                    } else { Label("记一笔", icon: .add, size: 17) }
                }
            case .systemMedium: medium
            default: small
            }
        }.foregroundStyle(family == .systemSmall || family == .systemMedium ? ink : .primary)
            .widgetURL(CaptureSnapshotBridge.addURL())
            .containerBackground(for: .widget) { if family == .systemSmall || family == .systemMedium { canvas } else { Color.clear } }
    }
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let snapshot = entry.snapshot {
                Text(snapshot.headlineTitle ?? "还能花").font(.caption).foregroundStyle(.secondary)
                Text(snapshot.money(snapshot.available)).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1).privacySensitive()
                Text("今天记了 \(snapshot.todayCount.formatted()) 笔 · " + snapshot.money(snapshot.todayTotal)).font(.system(size: 11)).foregroundStyle(.secondary).privacySensitive()
            } else { Label("余白", systemImage: "square.righthalf.filled").font(.headline) }
            Spacer(minLength: 4)
            Link(destination: CaptureSnapshotBridge.addURL()) { Label("记一笔", icon: .add, size: 15).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 40).background(brand, in: Capsule()).foregroundStyle(scheme == .dark ? .black : .white) }
        }
    }
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.snapshot?.headlineTitle ?? "余白").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let snapshot = entry.snapshot { Text(snapshot.money(snapshot.available)).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().privacySensitive() }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let snapshot = entry.snapshot {
                    ForEach(snapshot.frequent.indices, id: \.self) { index in
                        let item = snapshot.frequent[index]
                        Link(destination: CaptureSnapshotBridge.addURL(category: item.category, amount: item.amount, purpose: item.purpose)) {
                            VStack(spacing: 2) { Text(item.purpose).fontWeight(.medium).lineLimit(1); Text(snapshot.money(item.amount)).monospacedDigit().foregroundStyle(.secondary) }
                                .font(.caption).frame(maxWidth: .infinity, minHeight: 44).background(raised, in: RoundedRectangle(cornerRadius: 14)).privacySensitive()
                        }
                    }
                } else {
                    Link(destination: URL(string: "yubai://capture")!) { Label("截图记", icon: .scanCapture, size: 17).frame(maxWidth: .infinity, minHeight: 44).background(raised, in: RoundedRectangle(cornerRadius: 14)) }
                }
                Link(destination: CaptureSnapshotBridge.addURL()) { DSIconView(icon: .add, size: 20).frame(width: 44, height: 44).background(brand, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(scheme == .dark ? .black : .white) }.accessibilityLabel("记一笔")
            }
        }
    }
}
private struct AddCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.yubai.control.add") {
            ControlWidgetButton(action: OpenCaptureControlIntent(.add)) { Label("记一笔", systemImage: "plus") }
        }.displayName("记一笔").description("打开余白记一笔。")
    }
}
private struct ScreenshotCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.yubai.control.screenshot") {
            ControlWidgetButton(action: OpenCaptureControlIntent(.screenshot)) { Label("截图记", systemImage: "text.viewfinder") }
        }.displayName("截图记").description("打开余白截图记。")
    }
}
#endif

extension QuickCaptureSnapshot {
    /// Amounts in the app's main currency, as the app published them; plain CNY from older snapshots.
    func money(_ cents: Int64) -> String { (display ?? .cny).text(cents, symbol: true) }
}
