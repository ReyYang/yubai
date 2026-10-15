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
                Text("权重按需下载到本机应用支持目录，不打进主包。删除后自动回到规则 / 模板路径。当前下载 URL 为占位配置，正式 CDN 就绪前不会发起真实网络请求。").font(.callout).foregroundStyle(.secondary)
            }
            Section("可选模型") {
                ForEach(ModelWeightCatalog.defaults) { spec in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(spec.displayName).font(.headline)
                        Text(sizeLabel(spec)).font(.caption).foregroundStyle(.secondary)
                        if let status = statuses[spec.id] {
                            Text(status.installed ? (status.verified ? "已安装 · 已校验" : "已安装 · 校验未通过") : "未下载")
                                .font(.caption)
                            if status.installed {
                                Text("占用 \(ByteCountFormatter.string(fromByteCount: status.bytesOnDisk, countStyle: .file))").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        HStack {
                            Button("下载") { download(spec) }
                                .disabled(busyID != nil || (statuses[spec.id]?.installed == true))
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
            Section("说明") {
                Text("推荐约 8 GB RAM 机型使用 1.5B；约 6 GB 可尝试 0.5B 或仅规则。真机 llama.cpp 推理尚未接入本版本。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .editorForm()
        .navigationTitle("本机模型权重")
        .onAppear { reload() }
    }

    func sizeLabel(_ spec: ModelWeightSpec) -> String {
        let size = ByteCountFormatter.string(fromByteCount: spec.approximateBytes, countStyle: .file)
        return "约 \(size) · 建议 ≥\(spec.recommendedMinRAMGB) GB RAM · \(spec.filename)"
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
                message = "下载完成。"
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
            try IntelligenceRuntime.weights.delete(spec: spec)
            message = "已删除本机权重。"
        } catch {
            message = error.localizedDescription
        }
        busyID = nil
        reload()
    }
}
