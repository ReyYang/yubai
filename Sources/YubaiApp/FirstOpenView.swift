import SwiftUI
import YubaiCore

struct FirstOpenView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.yubaiRootNavigationHeight) private var navigationHeight
    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height - navigationHeight
            ScrollView {
                VStack(alignment: .leading, spacing: YubaiSpace.gapSection) {
                    HStack {
                        Spacer()
                        VStack(spacing: YubaiSpace.space20) {
                            VStack(spacing: YubaiSpace.space12) {
                                Text("余").frame(height: YubaiSize.firstOpenBrand)
                                Text("白").frame(height: YubaiSize.firstOpenBrand)
                            }.font(.system(size: YubaiSize.firstOpenBrand, weight: .semibold, design: .default))
                                .accessibilityElement(children: .ignore).accessibilityLabel("余白")
                            AssistantMark(size: YubaiSize.firstOpenSealGlyph, color: YubaiColor.onBrand)
                                .frame(width: YubaiSize.firstOpenSeal, height: YubaiSize.firstOpenSeal)
                                .background(YubaiColor.brand, in: RoundedRectangle(cornerRadius: YubaiSpace.space8)).accessibilityHidden(true)
                        }
                    }.padding(.trailing, YubaiSpace.space8)
                    Spacer(minLength: YubaiSpace.gapSection)
                    Button {
                        if store.accounts.isEmpty || !store.preferences.onboardingComplete {
                            guard store.update("开始记账", recordUndo: false, entryMotion: false, showToast: false, {
                                FirstUse.prepareForEntry(&$0, now: Dates.now)
                            }) else { return }
                        }
                        store.sheetSource = nil
                        store.sheet = .paydaySetup
                    } label: {
                        VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                            HStack(spacing: YubaiSpace.space8) {
                                Text("还能花").yubaiFont(YubaiFont.heroLabel).foregroundStyle(YubaiColor.label)
                                Spacer(minLength: YubaiSpace.space8)
                                Image(systemName: "chevron.right").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.labelSecondary)
                            }
                            HStack(alignment: .lastTextBaseline, spacing: YubaiSpace.space8) {
                                Text("¥").yubaiFont(YubaiFont.amountHero).foregroundStyle(YubaiColor.label)
                                Rectangle().fill(YubaiColor.label.opacity(0.75)).frame(height: YubaiSize.lineWidth)
                                    .frame(maxWidth: .infinity)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(PressButtonStyle()).accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("还能花，尚未开始记账").accessibilityHint("设置发薪日和工资")
                        .accessibilityIdentifier("firstOpenEmptyAmount")
                    Spacer(minLength: YubaiSpace.space8)
                    Button { store.beginFirstEntry(importing: true) } label: {
                        Text("已经有账单，导进来").multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }.buttonStyle(SecondaryButtonStyle(compact: true)).accessibilityIdentifier("firstImport")
                }.padding(.horizontal, YubaiSpace.space28).padding(.top, YubaiSpace.space28)
                    .padding(.bottom, YubaiSpace.gapSection)
                    .frame(minHeight: max(YubaiSize.firstOpenMinimum, availableHeight), alignment: .topLeading)
            }.accessibilityIdentifier("firstOpenScroll").rootScrollContentMargins(for: .ledger).rootTabScroll(.ledger)
        }.background { FirstWindowWall() }.accessibilityElement(children: .contain).accessibilityIdentifier("firstOpenScene")
    }
}
