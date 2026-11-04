# 第二十八轮 · 现金怎么走

owner 于 2026-11-04 明确确认并授权实现四张 390pt HTML。以下原稿逐字节归档；未改写原稿，也未写入外部设计稿或 artifact 链接。

| 文件 | 状态 | SHA-256 |
|---|---|---|
| `V28-Home-Cashflow.dc.html` | 首页默认窗口 | `46e9fc366176f9bb45ac7931afbf5d9a322ebb1221256fff2ad72e224d67126b` |
| `V28-Home-Cashflow-Scrub.dc.html` | 按住查看一天 | `201308442b89d3b999eab9906bb34252eedee496906e2e2a049bd5a3e1a3893c` |
| `V28-Home-Cashflow-Low.dc.html` | 低于始终留着 | `1bfaf6e0b264006c416e910ecb246bb335bb12deb9345c2446880cc89187e2c7` |
| `V28-Home-Cashflow-Earlier.dc.html` | 更早的窗口 | `581540ae1119069341e20f793b25e9326a8bd2c92b2f012c6e8aa9bd27f3da85` |

HTML 保留原有 `support.js`、`ds/yubai/tokens.css`、字体和其他页面的相对引用；本轮未提供这些依赖，归档不能独立预览。实际 App 使用系统 Swift Charts 和现有 SwiftUI tokens，不加载网页资源。原稿 Earlier 的网页标题仍含“拖滑动条”，按 owner 本轮明确要求，实际操作是横拖图表，底部细条仅指示位置。

源码映射、算法选择、可见文案、差异及验证边界见 [设计登记](../../DESIGN.md#2026-11-04--第二十八轮现金怎么走owner-确认)。原稿数字为合成样例；实际数据来自用户账本，未读取真实财务文件。Apple SDK 编译、视觉／大字号／读屏和真机交互仍待验证，外部画布与分发资源未同步。
