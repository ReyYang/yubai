import SwiftUI
import YubaiCore

@MainActor extension AppStore {
    var cloudAIReady: Bool {
        preferences.isAIEnabled(for: .answers) && IntelligenceRuntime.isConfigured && IntelligenceRuntime.cloud.unavailableModel == nil
    }
    var organizationAIReady: Bool { preferences.isAIEnabled(for: .importClassification) && IntelligenceRuntime.isConfigured }
    func confirmSalary(_ candidate: SalaryCandidate) {
        guard SalaryDetection.candidate(in: current)?.key == candidate.key else { return }
        if update("工资", showToast: false, { ledger in
            SalaryDetection.confirm(candidate, in: &ledger)
        }) { toast = "工资已加到会回来的账单" }
    }
    func rejectSalary(_ candidate: SalaryCandidate) {
        if update("工资", showToast: false, { SalaryDetection.dismiss(candidate, in: &$0) }) { toast = nil }
    }

}

typealias LetterItem = HomeTask

@MainActor extension AppStore {
    var inboxItems: [HomeTask] {
        homeTasks.filter { item in
            if case .salary(let salary) = item { return !hiddenSalaryKeys.contains(salary.key) }
            return true
        }
    }
}

struct NowCardButtonStyle: ViewportButtonStyle {
    var primary = false
    var feedback: NowCardButtonFeedback { NowCardButtonFeedback(primary: primary) }
}
struct NowCardButtonFeedback: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.yubaiFont(YubaiFont.row, weight: primary ? .semibold : .regular).fixedSize(horizontal: false, vertical: true).padding(.horizontal, YubaiSpace.space16).frame(minHeight: YubaiSize.iconButton)
            .foregroundStyle(primary ? YubaiColor.onBrand : YubaiColor.label)
            .background(primary ? YubaiColor.brand : YubaiColor.card, in: Capsule())
            .yubaiHitTarget()
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(YubaiMotion.instant, value: configuration.isPressed)
    }
}
