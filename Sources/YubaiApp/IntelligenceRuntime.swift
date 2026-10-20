import YubaiCore

/// Cloud assistance is optional; local calculations remain available without it.
@MainActor
enum IntelligenceRuntime {
    static func backend(for preferences: Preferences) -> CloudBackend? {
        CloudBackend.fromEnvironment(enabled: preferences.cloudAIEnabled)
    }

    static func availabilityText(for preferences: Preferences) -> String {
        guard preferences.cloudAIEnabled else {
            return "云端智能已关闭；使用本机计算结果。"
        }
        guard backend(for: preferences) != nil else {
            return "未配置 DeepSeek 密钥；使用本机计算结果。"
        }
        return "云端智能 · DeepSeek；请求失败时保留本机计算结果。"
    }
}
