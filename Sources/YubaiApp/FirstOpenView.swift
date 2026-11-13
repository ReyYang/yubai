import SwiftUI
import YubaiCore

struct FirstOpenView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height - YubaiSize.rootBottomPadding(for: .now)
            ScrollView {
                VStack(alignment: .leading, spacing: YubaiSpace.space8) {
                    HStack {
                        Spacer()
                        VStack(spacing: YubaiSpace.space20) {
                            VStack(spacing: YubaiSpace.space12) {
                                Text("余").frame(height: YubaiSize.firstOpenBrand)
                                Text("白").frame(height: YubaiSize.firstOpenBrand)
                            }.font(.system(size: YubaiSize.firstOpenBrand, weight: .semibold, design: .serif))
                                .accessibilityElement(children: .ignore).accessibilityLabel("余白")
                            AssistantMark(size: YubaiFont.callout.size, color: YubaiColor.onBrand)
                                .frame(width: YubaiSize.rowIcon - YubaiSpace.space6, height: YubaiSize.rowIcon - YubaiSpace.space6)
                                .background(YubaiColor.brand, in: RoundedRectangle(cornerRadius: YubaiSpace.space4)).accessibilityHidden(true)
                        }
                    }.padding(.trailing, YubaiSpace.space8)
                    Spacer(minLength: YubaiSpace.gapSection)
                    VStack(alignment: .leading, spacing: YubaiSpace.space4) {
                        Text("还能花").yubaiFont(YubaiFont.heroLabel)
                        HStack(alignment: .lastTextBaseline, spacing: YubaiSpace.space8) {
                            Text("¥").yubaiFont(YubaiFont.amountHero)
                            Rectangle().fill(YubaiColor.label.opacity(0.85)).frame(width: YubaiSize.firstOpenRule, height: YubaiSize.lineWidth)
                        }.accessibilityElement(children: .ignore).accessibilityLabel("还能花，尚未开始记账").accessibilityIdentifier("firstOpenEmptyAmount")
                    }
                    Button { store.beginFirstEntry(importing: true) } label: {
                        Text("已经有账单，导进来").yubaiFont(YubaiFont.callout).foregroundStyle(YubaiColor.brandInk)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: YubaiSize.tapMin).contentShape(Rectangle())
                    }.buttonStyle(PressButtonStyle()).accessibilityIdentifier("firstImport")
                }.padding(.horizontal, YubaiSpace.space28).padding(.top, YubaiSpace.space28)
                    .padding(.bottom, YubaiSpace.space12)
                    .frame(minHeight: max(YubaiSize.firstOpenMinimum, availableHeight), alignment: .topLeading)
            }.accessibilityIdentifier("firstOpenScroll").rootScrollContentMargins(for: .now).rootTabScroll(.now)
        }.background { FirstWindowWall() }.accessibilityElement(children: .contain).accessibilityIdentifier("firstOpenScene")
    }
}
