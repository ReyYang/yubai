import SwiftUI
import YubaiCore

struct ModelWeightsSettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var statuses: [String: ModelWeightStatus] = [:]
    @State private var message: String?
    @State private var busyID: String?

    var body: some View {
        Form {
            Section {
                Text("开发者选项。日常使用请在设置中开启「增强智能（云端）」。本机模型默认关闭，以避免真机加载导致卡顿或退出。").font(.callout).foregroundStyle(.secondary)
            }
            Section("可选模型") {
                ForEach(ModelWeightCatalog.defaults) { spec in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(simpleName(spec)).font(.headline)
                            if spec.id == ModelWeightCatalog.recommendedSpecID {
                                Text("推荐").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Text(sizeLabel(spec)).font(.caption).foregroundStyle(.secondary)
                        if let status = statuses[spec.id] {
                            Text(status.installed ? (status.verified ? "已就绪" : "文件异常，建议删除后重下") : "未下载")
                                .font(.caption)
                            if status.installed {
                                Text("占用 \(ByteCountFormatter.string(fromByteCount: status.bytesOnDisk, countStyle: .file))").font(.caption2).foregroundStyle(.secondary)
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
                    .padding(.vertical, 4)
                }
            }
            if let message {
                Section { Text(message).font(.callout).foregroundStyle(YubaiTheme.amber) }
            }
            Section {
                Button("重置本机模型保护开关") {
                    IntelligenceRuntime.resetLocalInferenceGate()
                    message = "已重置；仍需在「高级选项」中启用本机模型才会尝试加载。"
                }
            }
            Section("说明") {
                Text("权重保存在本机应用目录，不打进安装包。金额计算永不交模型修改。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .editorForm()
        .navigationTitle("本机模型（开发者）")
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
}
