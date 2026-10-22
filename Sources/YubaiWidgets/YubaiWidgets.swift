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
            Image(systemName: "text.viewfinder").font(.title2).accessibilityLabel("截图记")
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
            case .accessoryCircular: Image(systemName: "plus").font(.title2).accessibilityLabel("记一笔")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    if let snapshot = entry.snapshot {
                        Text("还能花 " + Money.text(snapshot.available)).font(.headline).monospacedDigit().privacySensitive()
                        Text("今天记了 \(snapshot.todayCount) 笔").font(.caption).privacySensitive()
                    } else { Label("记一笔", systemImage: "plus") }
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
                Text("还能花").font(.caption).foregroundStyle(.secondary)
                Text(Money.text(snapshot.available)).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1).privacySensitive()
                Text("今天记了 \(snapshot.todayCount) 笔 · " + Money.text(snapshot.todayTotal)).font(.system(size: 11)).foregroundStyle(.secondary).privacySensitive()
            } else { Label("余白", systemImage: "water.waves").font(.headline) }
            Spacer(minLength: 4)
            Link(destination: CaptureSnapshotBridge.addURL()) { Label("记一笔", systemImage: "plus").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 40).background(brand, in: Capsule()).foregroundStyle(scheme == .dark ? .black : .white) }
        }
    }
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.snapshot == nil ? "余白" : "还能花").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let snapshot = entry.snapshot { Text(Money.text(snapshot.available)).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().privacySensitive() }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if let snapshot = entry.snapshot {
                    ForEach(snapshot.frequent.indices, id: \.self) { index in
                        let item = snapshot.frequent[index]
                        Link(destination: CaptureSnapshotBridge.addURL(category: item.category, amount: item.amount, purpose: item.purpose)) {
                            VStack(spacing: 2) { Text(item.purpose).fontWeight(.medium).lineLimit(1); Text(Money.text(item.amount)).monospacedDigit().foregroundStyle(.secondary) }
                                .font(.caption).frame(maxWidth: .infinity, minHeight: 44).background(raised, in: RoundedRectangle(cornerRadius: 14)).privacySensitive()
                        }
                    }
                } else {
                    Link(destination: URL(string: "yubai://capture")!) { Label("截图记", systemImage: "text.viewfinder").frame(maxWidth: .infinity, minHeight: 44).background(raised, in: RoundedRectangle(cornerRadius: 14)) }
                }
                Link(destination: CaptureSnapshotBridge.addURL()) { Image(systemName: "plus").frame(width: 44, height: 44).background(brand, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(scheme == .dark ? .black : .white) }.accessibilityLabel("记一笔")
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
