import SwiftUI
import YubaiCore

struct ModelWeightsSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var statuses: [String: ModelWeightStatus] = [:]
    @State private var message: String?
    @State private var busyID: String?

    var body: some View {
        Form {
            introductionSection
            modelsSection
            if let message {
                Section { InlineNote(text: message, style: .explanation) }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
            }
            resetSection
            explanationSection
        }
        .editorForm()
        .navigationTitle("本机模型（开发者）").yubaiNavigation()
        .onAppear { reload() }
    }

    func simpleName(_ spec: ModelWeightSpec) -> String {
        if spec.id.contains("05b") { return "小模型（省内存）" }
        if spec.id.contains("15b") { return "标准模型" }
        return spec.displayName
    }

    func sizeLabel(_ spec: ModelWeightSpec) -> String {
        let size = ByteCountFormatter.string(fromByteCount: spec.approximateBytes, countStyle: .file)
        return "约 \(size) · 建议内存 ≥\(spec.recommendedMinRAMGB) GB"
    }

    func reload() {
        var next: [String: ModelWeightStatus] = [:]
        for spec in ModelWeightCatalog.defaults {
            next[spec.id] = IntelligenceRuntime.weights.status(for: spec)
        }
        statuses = next
    }

    func download(_ spec: ModelWeightSpec) {
        busyID = spec.id
        message = nil
        Task {
            do {
                try await IntelligenceRuntime.weights.download(spec: spec)
                message = "下载完成并已校验。"
            } catch {
                message = error.localizedDescription
            }
            busyID = nil
            reload()
        }
    }

    func delete(_ spec: ModelWeightSpec) {
        busyID = spec.id
        message = nil
        do {
            IntelligenceRuntime.unloadLocalModel()
            try IntelligenceRuntime.weights.delete(spec: spec)
            message = "已删除本机权重；已回到规则 / 模板路径。"
        } catch {
            message = error.localizedDescription
        }
        busyID = nil
        reload()
    }

    private var introductionSection: some View {
        Section {
            Text("开发者选项。日常使用请在设置中开启「增强智能（云端）」。本机模型默认关闭，以避免真机加载导致卡顿或退出。").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var modelsSection: some View {
        Section("可选模型") {
            ForEach(ModelWeightCatalog.defaults) { spec in
                VStack(alignment: .leading, spacing: YubaiSpace.space10) {
                    HStack {
                        Text(simpleName(spec)).yubaiFont(YubaiFont.rowTitle)
                        if spec.id == ModelWeightCatalog.recommendedSpecID {
                            Text("推荐").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                        }
                    }
                    Text(sizeLabel(spec)).yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
                    if let status = statuses[spec.id] {
                        Text(status.installed ? (status.verified ? "已就绪" : "文件异常，建议删除后重下") : "未下载")
                            .yubaiFont(YubaiFont.caption)
                        if status.installed {
                            Text("占用 \(ByteCountFormatter.string(fromByteCount: status.bytesOnDisk, countStyle: .file))").yubaiFont(YubaiFont.meta).foregroundStyle(YubaiColor.labelSecondary)
                        }
                    }
                    HStack {
                        Button("下载") { download(spec) }
                            .disabled(busyID != nil || (statuses[spec.id]?.installed == true && statuses[spec.id]?.verified == true))
                        Button("删除", role: .destructive) { delete(spec) }
                            .disabled(busyID != nil || statuses[spec.id]?.installed != true)
                    }
                    if busyID == spec.id { ProgressView("处理中…") }
                }
                .padding(.vertical, YubaiSpace.space4)
            }
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var resetSection: some View {
        Section {
            Button("重置本机模型保护开关") {
                IntelligenceRuntime.resetLocalInferenceGate()
                message = "已重置；仍需在「高级选项」中启用本机模型才会尝试加载。"
            }
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
    private var explanationSection: some View {
        Section("说明") {
            Text("权重保存在本机应用目录，不打进安装包。金额计算永不交模型修改。").yubaiFont(YubaiFont.caption).foregroundStyle(YubaiColor.labelSecondary)
        }.listRowBackground(YubaiColor.card).listRowSeparatorTint(YubaiColor.separator)
    }
}
