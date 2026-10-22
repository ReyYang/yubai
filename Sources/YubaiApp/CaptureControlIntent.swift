#if os(iOS) && canImport(AppIntents)
import AppIntents

enum CaptureDestination: String, AppEnum {
    case add, screenshot
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "快速记账入口"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.add: "记一笔", .screenshot: "截图记"]
}
struct OpenCaptureControlIntent: OpenIntent {
    static let title: LocalizedStringResource = "打开快速记账"
    static var openAppWhenRun: Bool = true
    @Parameter(title: "入口") var target: CaptureDestination
    init() { target = .add }
    init(_ destination: CaptureDestination) { target = destination }
    @MainActor func perform() async throws -> some IntentResult {
        #if !YUBAI_WIDGET_EXTENSION
        AppStore.shared.requestCaptureSheet(target == .add ? .addEntry : .screenshotCapture(nil))
        #endif
        return .result()
    }
}
#endif
