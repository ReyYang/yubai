# Screen gallery

Run `scripts/gallery.sh` from the repository root on the owner's Apple Silicon Mac. An optional first argument selects the simulator; otherwise the script uses `SIM`, then `37FDA39F-AF08-48EA-9E35-0AAB017AAFE0`. The project targets iOS 26, so the selected simulator needs a compatible runtime.

There are **286 planned states**: 242 in the full walk, 22 at accessibility Large, and 22 in dark appearance. These are planned screenshots, not screenshots verified on Linux. No app or UI test was compiled or run here. No commit or push was made.

The full walk uses light appearance for every fixture, including reused v45/receipt/welcome fixtures, without changing the simulator's global appearance. The reduced accessibility walk uses `UICTContentSizeCategoryAccessibilityL`; the other walks explicitly use the normal `UICTContentSizeCategoryL`. Dark is supported by `YubaiColor.adaptive`, `SettingsView`'s appearance picker, and `YubaiApp`'s `preferredColorScheme`.

**Output and failures**

- `.shots/` is cleared on each run and ignored by git. Each reached stop writes `<shot-name>.png` and a `.keepAlways` XCTAttachment with exactly the shot name.
- A missing stop records `<shot-name>-MISSING.png` and attaches its accessibility hierarchy. Each XCTest method continues through its remaining stops and emits an aggregate `XCTFail` at teardown, with `missing.txt` and a per-walk missing report attached.
- `missing.txt` and `index.txt` report missing stops, including stops never executed after an interruption. `expected.txt` is derived from the test source. The PNG count includes diagnostic `-MISSING` images; inspect the missing list before handing over.
- The script exits 0 whenever any PNG was produced, including when tests report missing stops. It exits nonzero when no PNG was produced. `index.txt` retains the xcodebuild exit status, git short SHA, sorted file list, count, and result-bundle path.
- Derived data, `.xcresult`, and the build/export logs stay under the printed `/tmp/yubai-gallery.*` directory.
- `TEST_RUNNER_YUBAI_GALLERY_DIR` is forwarded by xcodebuild as `YUBAI_GALLERY_DIR` to the XCTest runner. It is deliberately separate from `XCUIApplication.launchEnvironment`. This prefix is documented in [Apple's Xcode 13 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-13-release-notes).
- If direct PNG writes fail, attachments still survive. When no PNG is present, the script runs `xcresulttool export attachments` and uses `manifest.json`'s `exportedFileName` / `suggestedHumanReadableName` to restore the attachment names.
- The project has no test plan or existing per-class skip list. All three gallery methods use `XCTSkip` in setup unless a nonempty `YUBAI_GALLERY_DIR` is set. Ordinary UI runs do not launch the gallery.

**Fixtures and isolation**

`gallery`, `gallery-empty`, and `gallery-locked` are registered under the existing `DEBUG && targetEnvironment(simulator)` gate and still require a UUID-valued `--test-ledger`. Every area launches into a new cache directory; all fixture domain IDs are stable. New gallery ledgers clear only their own recent-question/snooze defaults so earlier gallery runs cannot change their pixels. No real ledger is edited; all assistant exchanges use offline transport and do not configure a key or contact iCloud. The only new app launch key is `YUBAI_GALLERY_APPEARANCE` (`light` / `dark`), consumed only while preparing registered simulator UI fixtures; ordinary tests without this key retain their prior behavior.

The rich ledger has 95 entries (94 active), 72 ordinary entries over three cycles, 14 monthly bills, nine accounts (credit debt and an archived account included), 40 categories (18 user categories, with long subcategories and a hidden category), an unitemized expense, a future entry, pinned/hidden repeats, reserves, one accepted payback and one pending offer, three goal progress states, eight wishes spanning all statuses and cooling/follow-up states, memories, values, a weekly letter, one eight-row import with two recognized plans and two unclassified rows, a pending plan proposal, and a recovery snapshot. Local cards are precomputed with stable IDs. Large recurring cash events occupy adjacent days; at the start of a month they share the first visible day and still produce at least three chart annotations.

`0.00` appears in real balances, budgets, and saved totals. `0.01`, `1,234,567.89`, credit debt `−1,234,567.89`, and overspent budgets are represented. Zero/negative transaction amounts are not injected: the domain rejects them. The CSV preview separately includes a zero-amount row to exercise import rejection. Dates follow the simulator's calendar day; existing v45 scripts retain their own clock-relative behavior.

The existing `v45-*`, `salary` / `by-party`, `v45-repeats`, `v45-receipt`, `profile-revisit`, `judge-ask`, `import`, `manual`, and `empty` fixtures supply their specific states. `gallery` also provides an offline `get_profile → propose_entry` exchange for the actual amount-confirmation/edit/save UI. The real Core tools validate both account IDs and locally parsed amounts. `YUBAI_UI_TEST_KEEP_UNDO=1` holds undo receipts.

**Source boundaries and states without an automated route**

- There are four tabs in this branch: 现在 / 存钱 / 账本 / 余白. The center ＋ is an action. Its tap and long-press states are included.
- `GoalEditor` has no call site in the active app, and goals have no list route or control. The fixture includes untouched, partial, and complete goals, and the formula renders their reservation. A goals screen cannot be reached without adding product navigation.
- Wish details render inline in `WishlistView`; there is no separate wish-detail page. Inline details, cooling, past wishes, purchase linking, follow-up data, and the focused wish sheet are included.
- Ordinary ledger rows open `EntryEditForm`, while unitemized rows push `EntryDetailView`. Normal entry detail is reached through the existing bought-wish purchase link. This distinction is intentional in the walk.
- `FlowRecordsView`, `SubcategoryInsightsView` / `SubcategoryRecordsView`, `UnsortedQuickSortView`, and the standalone `LettersView` survive as route/type definitions, but the active UI does not construct their routes. Category management and subcategory editors are covered; the current classification route is `LetterTriageView`.
- The old import-question sheet requires legacy `organization.questions`; current organizer fixtures explicitly discard those questions. No synthetic legacy question is introduced just to open an obsolete sheet. Actual fallback grouping, group details, triage, source expansion, and its separate undo bar are covered.
- `SyncVersionsView` needs a real iCloud conflict/choice. UUID test ledgers set `syncAllowed = false`, so that state is unavailable in this isolated walk.
- Backup and restore file pickers, the password export form, recovery versions, and the recovery confirmation dialog are included. The encrypted-restore password/validated-backup confirmation states are not automated: no existing fixture supplies a backup URL to the restore flow, and the walk does not select an arbitrary owner file in the system picker.
- Camera hardware, Photos authorization, device authentication prompts, notification authorization, Siri/Shortcuts, and widgets/control-center screens are external or hardware states. The existing receipt fixture covers recognition/selection/merge/category UI; the existing lock state is captured without authenticating.

These are source-audit boundaries, not observed simulator failures. Actual failures and screenshots only become available on the Mac in `.shots/missing.txt` and the xcresult.

**Mac checks most likely to need adjustment**

The first real Xcode build/type check is still required. Swift parser checks cannot validate SwiftUI or XCTest SDK types. The highest-risk runtime points are system document-picker localization/AX containment, nested category/calendar sheet transitions, long scrolling at accessibility sizes, and custom SwiftUI container frames. Each stop validates a destination marker before its screenshot; a changed tree should produce `-MISSING` with a hierarchy rather than silently count another page. The xcresult manifest export has been tested with representative grouped manifests, but the installed Xcode's exact export output still needs one real run.

**Validation on Linux**

- All 15 changed Swift sources are checked individually with `PATH=/opt/swift-rootfs/usr/bin:$PATH swiftc -frontend -parse -swift-version 5 <file>`.
- `YUBAI_LIVE_EVAL=0 swift test`: 1087 tests, 0 failures, 4 skipped. No Core source was changed.
- A temporary Foundation-only extraction of the fixture was linked against the real Core module. It validates deterministic ledger equality, row/plan/account/category minimums, positive available funds, at least three chart annotations, repeats, payback, empty ledger, and recognized import plans at 2026-11-01, 2026-11-12, 2026-02-28, 2028-02-29, and 2026-12-31. A real `LedgerRepository` save/load and recovery snapshot also validate. The CSV preview preserves its unknown long category and rejects the zero row. The real offline assistant exchange returns two validated entry drafts.
- `bash -n` checks both shell scripts. An isolated mock harness checks direct writes with test exit 65, manifest export/renaming, partial export with a malformed manifest, no-image failure, all planned images, SIM precedence, paths with spaces, and clearing stale output. These are shell tests, not simulator screenshots.
- The generator now discovers all `Tests/YubaiUITests/*.swift`, preserving the existing AppFlow object IDs. Generated source phases were checked: fixture → Yubai; gallery test → YubaiUITests. A second generation must be byte-identical.
- `scripts/check-ui-consistency.sh` reports only and exits 0. Its counts are matching source lines, with file:line listings, not a build gate. Current counts: raw text inputs 37, hand-made back buttons 1, hidden navigation bars 24, chart annotations 1, direct Toast construction outside the app root 0.

**Added accessibility identifiers**

All production view edits are additive identifiers; there are no layout, interaction, animation, or visible copy edits.

- `Sources/YubaiApp/ButlerViews.swift`: `butlerEvidence_{…}`, `butlerPrimary_{…}`, `butlerEvidencePage`, `butlerProposalPage`
- `Sources/YubaiApp/Editors.swift`: `editAccount`, `accountDetailPage`
- `Sources/YubaiApp/MemoryView.swift`: `memoriesPage`
- `Sources/YubaiApp/NowView.swift`: `nowScroll`
- `Sources/YubaiApp/OverviewView.swift`: `savingHistory`
- `Sources/YubaiApp/ProfileView.swift`: `profilePage`, `profileArea_{…}`, `profileAreaTitle`
- `Sources/YubaiApp/QuickCaptureSettingsView.swift`: `openCaptureCardRules`, `openCaptureMerchantRules`, `captureRulesPage`, `addCaptureRule`, `captureRuleName`
- `Sources/YubaiApp/SettingsView.swift`: `openRecoveryVersions`, `backupPage`, `backupPassword`, `importHistoryPage`, `recoveryVersion_{…}`
- `Sources/YubaiApp/SpendingPartsView.swift`: `budgetCategory_{…}`
- `Sources/YubaiApp/WishlistView.swift`: `wishlistPage`, `wishBoughtEntry_{…}`, `wish_{…}`, `wishPurchase_{…}`, `wishEntryPicker`
- `Sources/YubaiApp/YubaiApp.swift`: `lockedPage`

**Visible Chinese strings**

Production UI strings: none added or changed. New visible content is DEBUG simulator test data (titles/facts/status), plus the scripted status `两笔待确认` and synthetic error reasons `合成补记缺少账户或两笔本机金额。` / `合成补记缺少本机金额。`. No explanatory UI copy was added.

Fixture/test values are: `为了搬家以后和家人朋友一起长期使用而认真挑选并且反复比较尺寸颜色材质保修与运输安排的生活用品`; account names `合成工资卡` / `零钱` / `信用卡` / `投资账户` / `借出待收` / `已归档的旧银行卡` / `空账户`; `合成自建分类00…17`, `小项` and `小项` + long title; `合成日常0…71`, `没细记`, `合成未来账目` + long title, `合成已删账目`, `合成退款`, `合成超支分项` + long title; `合成判断：` + long title; `超过 2,000 等 48 小时`; `合成导入` + long title + `.csv`, `合成导入房租` + long title, `合成公司`, `合成未分类` + long title, `合成咖啡`; `合成待确认的固定账单` + long title, `每月` + amount; typed values `合成一分钱`, `合成绝对不存在的账目编号999`, `合成午饭 28 元`, `合成地铁 8 元`, `合成导入分类` + long title; synthetic source/recovery values `合成`, `合成补记`, `合成截图历史`, `合成截图夹具`; and existing confirmation text `抹掉`. Other Chinese category/status strings reuse existing domain values. Repository-save reasons and missing-stop errors are diagnostics, not new product labels.

The unbroken Latin value used for entry/bill/category/account/wish/memory stress is `SupercalifragilisticexpialidociousPneumonoultramicroscopicsilicovolcanoconiosis`.

**Changed files**

- `.gitignore`
- `Sources/YubaiApp/ButlerViews.swift`
- `Sources/YubaiApp/Editors.swift`
- `Sources/YubaiApp/MemoryView.swift`
- `Sources/YubaiApp/NowView.swift`
- `Sources/YubaiApp/OverviewView.swift`
- `Sources/YubaiApp/ProfileView.swift`
- `Sources/YubaiApp/QuickCaptureSettingsView.swift`
- `Sources/YubaiApp/Round45SecondBatchFixtures.swift`
- `Sources/YubaiApp/ScreenGalleryFixtures.swift`
- `Sources/YubaiApp/SettingsView.swift`
- `Sources/YubaiApp/SpendingPartsView.swift`
- `Sources/YubaiApp/UITestSupport.swift`
- `Sources/YubaiApp/WishlistView.swift`
- `Sources/YubaiApp/YubaiApp.swift`
- `Tests/YubaiUITests/ScreenGalleryTests.swift`
- `Yubai.xcodeproj/project.pbxproj`
- `docs/SCREEN_GALLERY.md`
- `scripts/check-ui-consistency.sh`
- `scripts/gallery.sh`
- `scripts/generate-project.py`

**Ordered shot checklist (286)**

Names below are in the same filename order used by `index.txt`. Each corresponds to a PNG on success; missing stops append `-MISSING`.

- [ ] `01-now-01-top`
- [ ] `01-now-02-middle`
- [ ] `01-now-03-bottom`
- [ ] `01-now-04-hidden-amounts`
- [ ] `01-now-05-todo`
- [ ] `01-now-06-weekly-review`
- [ ] `01-now-07-weekly-review-bottom`
- [ ] `01-now-08-hidden-ledger`
- [ ] `01-now-09-hidden-saving`
- [ ] `01-now-10-hidden-yubai`
- [ ] `01-now-11-butler-evidence-sheet`
- [ ] `01-now-12-proposal-sheet`
- [ ] `01-now-13-proposal-applied-toast`
- [ ] `02-saving-01-tab`
- [ ] `02-saving-02-reserve`
- [ ] `02-saving-03-payback-progress`
- [ ] `02-saving-04-payback-offer`
- [ ] `02-saving-05-payback-accepted`
- [ ] `02-saving-06-edit-total`
- [ ] `02-saving-07-reserve-adjustment-toast`
- [ ] `02-saving-08-monthly-fixed`
- [ ] `02-saving-09-monthly-share`
- [ ] `02-saving-10-monthly-amount`
- [ ] `02-saving-11-wishlist-top`
- [ ] `02-saving-12-wishlist-cooling`
- [ ] `02-saving-13-wish-detail-inline`
- [ ] `02-saving-14-wish-purchase-picker`
- [ ] `02-saving-15-wishlist-past`
- [ ] `02-saving-16-wishlist-past-bottom`
- [ ] `02-saving-17-wish-dropped-toast`
- [ ] `02-saving-18-monthly-history`
- [ ] `02-saving-19-payback-declined`
- [ ] `02-saving-20-focused-wish-sheet`
- [ ] `03-ledger-01-detail-top`
- [ ] `03-ledger-02-detail-middle`
- [ ] `03-ledger-03-detail-bottom`
- [ ] `03-ledger-04-search`
- [ ] `03-ledger-05-filter-unclassified`
- [ ] `03-ledger-06-filter-income`
- [ ] `03-ledger-07-future-entry`
- [ ] `03-ledger-08-entry-detail`
- [ ] `03-ledger-09-entry-edit`
- [ ] `03-ledger-10-entry-edit-keyboard`
- [ ] `03-ledger-11-split-unitemized`
- [ ] `03-ledger-12-split-filled`
- [ ] `03-ledger-13-split-toast`
- [ ] `03-ledger-14-split-undone`
- [ ] `03-ledger-15-where-top`
- [ ] `03-ledger-16-where-middle`
- [ ] `03-ledger-17-where-cash-chart`
- [ ] `03-ledger-18-where-chart-selected`
- [ ] `03-ledger-19-where-bottom`
- [ ] `03-ledger-20-where-category`
- [ ] `03-ledger-21-where-category-bottom`
- [ ] `03-ledger-22-category-records`
- [ ] `03-ledger-23-where-custom-range`
- [ ] `03-ledger-24-month-picker`
- [ ] `03-ledger-25-search-empty`
- [ ] `04-formula-01-current`
- [ ] `04-formula-02-bottom`
- [ ] `04-formula-03-cycle-menu`
- [ ] `04-formula-04-past-cycle`
- [ ] `04-formula-05-past-cycle-where`
- [ ] `04-formula-06-edit-reserve`
- [ ] `04-formula-07-edit-saving`
- [ ] `04-formula-08-budget`
- [ ] `04-formula-09-add-budget-alert`
- [ ] `04-formula-10-budget-alert-keyboard`
- [ ] `04-formula-11-budget-amount-sheet`
- [ ] `04-formula-12-budget-category-sheet`
- [ ] `05-accounts-01-list-top`
- [ ] `05-accounts-02-list-bottom`
- [ ] `05-accounts-03-credit`
- [ ] `05-accounts-04-credit-editor`
- [ ] `05-accounts-05-add-account`
- [ ] `05-accounts-06-editor-long-keyboard`
- [ ] `05-accounts-07-archived-account`
- [ ] `05-accounts-08-reconcile`
- [ ] `05-accounts-09-reconcile-one-account`
- [ ] `06-bills-01-list`
- [ ] `06-bills-02-list-bottom`
- [ ] `06-bills-03-editor`
- [ ] `06-bills-04-editor-schedule`
- [ ] `06-bills-05-detail`
- [ ] `06-bills-06-detail-history`
- [ ] `06-bills-07-long-press-menu`
- [ ] `06-bills-08-move-occurrence`
- [ ] `06-bills-09-move-future`
- [ ] `06-bills-10-move-toast`
- [ ] `06-bills-11-variable-pay`
- [ ] `06-bills-12-paid-toast`
- [ ] `06-bills-13-link-existing`
- [ ] `06-bills-14-match-existing`
- [ ] `06-bills-15-skip-toast`
- [ ] `06-bills-16-stop-confirmation`
- [ ] `06-bills-17-stop-toast`
- [ ] `06-bills-18-add-bill`
- [ ] `06-bills-19-add-bill-long-keyboard`
- [ ] `06-bills-20-add-bill-day`
- [ ] `06-bills-21-add-recurring-editor`
- [ ] `07-entry-01-expense-zero`
- [ ] `07-entry-02-category-grid`
- [ ] `07-entry-03-more-categories`
- [ ] `07-entry-04-more-categories-bottom`
- [ ] `07-entry-05-date-calendar`
- [ ] `07-entry-06-future-date`
- [ ] `07-entry-07-account-menu`
- [ ] `07-entry-08-purpose-keyboard`
- [ ] `07-entry-09-income`
- [ ] `07-entry-10-transfer`
- [ ] `07-entry-11-big-purchase-hint`
- [ ] `07-entry-12-big-from-reserve`
- [ ] `07-entry-13-discard-confirmation`
- [ ] `07-entry-14-saved-in-sheet`
- [ ] `07-entry-15-saved-toast`
- [ ] `07-entry-16-quick-repeat-menu`
- [ ] `07-entry-17-long-repeat-toast`
- [ ] `07-entry-18-undone-receipt`
- [ ] `07-entry-19-delete-toast`
- [ ] `07-entry-20-short-repeat-toast`
- [ ] `07-entry-21-long-saved-toast`
- [ ] `07-entry-22-income-toast`
- [ ] `07-entry-23-transfer-toast`
- [ ] `07-entry-24-calendar-future-selected`
- [ ] `08-categories-01-list`
- [ ] `08-categories-02-list-bottom`
- [ ] `08-categories-03-add-sheet`
- [ ] `08-categories-04-add-keyboard`
- [ ] `08-categories-05-add-long-name`
- [ ] `08-categories-06-new-category-toast`
- [ ] `08-categories-07-detail`
- [ ] `08-categories-08-subcategory`
- [ ] `08-categories-09-add-subcategory`
- [ ] `08-categories-10-merge-sheet`
- [ ] `08-categories-11-hidden`
- [ ] `08-categories-12-sort`
- [ ] `08-categories-13-income`
- [ ] `09-yubai-01-tab`
- [ ] `09-yubai-02-profile`
- [ ] `09-yubai-03-profile-bottom`
- [ ] `09-yubai-04-add-principle-keyboard`
- [ ] `09-yubai-05-add-principle-long`
- [ ] `09-yubai-06-principle-toast`
- [ ] `09-yubai-07-memories`
- [ ] `09-yubai-08-memory-editor`
- [ ] `09-yubai-09-memory-delete-toast`
- [ ] `09-yubai-10-ask-conversation`
- [ ] `09-yubai-11-ask-evidence`
- [ ] `09-yubai-12-ask-disabled`
- [ ] `09-yubai-13-recent-question`
- [ ] `09-yubai-14-profile-conversation`
- [ ] `09-yubai-15-purchase-questions`
- [ ] `09-yubai-16-purchase-verdict`
- [ ] `09-yubai-17-purchase-details`
- [ ] `09-yubai-18-ask-record-draft`
- [ ] `09-yubai-19-ask-record-edit`
- [ ] `09-yubai-20-ask-record-confirm`
- [ ] `09-yubai-21-ask-record-saved`
- [ ] `09-yubai-22-profile-area-editor`
- [ ] `10-settings-01-settings`
- [ ] `10-settings-02-frequent-entries`
- [ ] `10-settings-03-frequent-hidden`
- [ ] `10-settings-04-quick-capture`
- [ ] `10-settings-05-card-mappings`
- [ ] `10-settings-06-intelligence-privacy-top`
- [ ] `10-settings-07-intelligence-privacy-bottom`
- [ ] `10-settings-08-cloud-key`
- [ ] `10-settings-09-model-menu`
- [ ] `10-settings-10-custom-model`
- [ ] `10-settings-11-send-log`
- [ ] `10-settings-12-backup`
- [ ] `10-settings-13-recently-deleted`
- [ ] `10-settings-14-delete-permanently-dialog`
- [ ] `10-settings-15-recovery-versions`
- [ ] `10-settings-16-storage`
- [ ] `10-settings-17-delete-photos-sheet`
- [ ] `10-settings-18-erase-confirmation-sheet`
- [ ] `10-settings-19-erase-keyboard`
- [ ] `10-settings-20-card-mapping-editor`
- [ ] `10-settings-21-merchant-mappings`
- [ ] `10-settings-22-merchant-mapping-editor`
- [ ] `10-settings-23-backup-password-keyboard`
- [ ] `10-settings-24-backup-restore-picker`
- [ ] `10-settings-25-recovery-confirmation`
- [ ] `10-settings-26-clear-history-dialog`
- [ ] `11-import-01-picker`
- [ ] `11-import-02-system-file-picker`
- [ ] `11-import-03-history`
- [ ] `11-import-04-result-unclassified-and-plans`
- [ ] `11-import-05-recognized-plans-detail`
- [ ] `11-import-06-triage`
- [ ] `11-import-07-triage-source`
- [ ] `11-import-08-history-undo-dialog`
- [ ] `11-import-09-batch-undone-toast`
- [ ] `11-import-10-receipt-separate`
- [ ] `11-import-11-receipt-merged`
- [ ] `11-import-12-receipt-category`
- [ ] `11-import-13-fallback-groups`
- [ ] `11-import-14-fallback-group-detail`
- [ ] `11-import-15-unsorted-undo-bar`
- [ ] `11-import-16-preview`
- [ ] `11-import-17-preview-category-mapping`
- [ ] `12-states-01-payday-card`
- [ ] `12-states-02-payday-sheet`
- [ ] `12-states-03-payday-extra-to-savings`
- [ ] `12-states-04-payday-toast`
- [ ] `12-states-05-late-salary`
- [ ] `12-states-06-new-cycle-leftover`
- [ ] `12-states-07-leftover-saved`
- [ ] `12-states-08-overspend`
- [ ] `12-states-09-cover-save-less`
- [ ] `12-states-10-cover-level`
- [ ] `12-states-11-cover-toast`
- [ ] `12-states-12-cover-reserve-cushion`
- [ ] `12-states-13-cover-reserve-toast`
- [ ] `12-states-14-fast-spending`
- [ ] `12-states-15-reconcile-gap`
- [ ] `12-states-16-reconcile-keyboard`
- [ ] `12-states-17-payday-setup`
- [ ] `12-states-18-payday-setup-amount`
- [ ] `12-states-19-salary-candidate`
- [ ] `12-states-20-salary-confirmed-toast`
- [ ] `12-states-21-locked`
- [ ] `12-states-22-bill-due-card`
- [ ] `12-states-23-new-ledger-setup`
- [ ] `12-states-24-reconcile-difference`
- [ ] `12-states-25-reconcile-toast`
- [ ] `13-empty-01-now`
- [ ] `13-empty-02-saving`
- [ ] `13-empty-03-ledger`
- [ ] `13-empty-04-where`
- [ ] `13-empty-05-yubai`
- [ ] `13-empty-06-wishlist`
- [ ] `13-empty-07-memories`
- [ ] `13-empty-08-import-history`
- [ ] `13-empty-09-accounts`
- [ ] `13-empty-10-welcome`
- [ ] `13-empty-11-onboarding-account-keyboard`
- [ ] `13-empty-12-onboarding-privacy`
- [ ] `13-empty-13-fixed-bills`
- [ ] `13-empty-14-frequent-entries`
- [ ] `13-empty-15-budget`
- [ ] `80-a11y-01-now`
- [ ] `80-a11y-02-saving`
- [ ] `80-a11y-03-ledger`
- [ ] `80-a11y-04-where`
- [ ] `80-a11y-05-cash-chart`
- [ ] `80-a11y-06-yubai`
- [ ] `80-a11y-07-profile`
- [ ] `80-a11y-08-principle-keyboard`
- [ ] `80-a11y-09-principle-long`
- [ ] `80-a11y-10-toast`
- [ ] `80-a11y-11-formula`
- [ ] `80-a11y-12-accounts`
- [ ] `80-a11y-13-account-editor`
- [ ] `80-a11y-14-settings`
- [ ] `80-a11y-15-categories`
- [ ] `80-a11y-16-category-keyboard`
- [ ] `80-a11y-17-category-long`
- [ ] `80-a11y-18-entry-expense`
- [ ] `80-a11y-19-entry-keyboard`
- [ ] `80-a11y-20-entry-income`
- [ ] `80-a11y-21-entry-transfer`
- [ ] `80-a11y-22-long-repeat-toast`
- [ ] `90-dark-01-now`
- [ ] `90-dark-02-saving`
- [ ] `90-dark-03-ledger`
- [ ] `90-dark-04-where`
- [ ] `90-dark-05-cash-chart`
- [ ] `90-dark-06-yubai`
- [ ] `90-dark-07-profile`
- [ ] `90-dark-08-principle-keyboard`
- [ ] `90-dark-09-principle-long`
- [ ] `90-dark-10-toast`
- [ ] `90-dark-11-formula`
- [ ] `90-dark-12-accounts`
- [ ] `90-dark-13-account-editor`
- [ ] `90-dark-14-settings`
- [ ] `90-dark-15-categories`
- [ ] `90-dark-16-category-keyboard`
- [ ] `90-dark-17-category-long`
- [ ] `90-dark-18-entry-expense`
- [ ] `90-dark-19-entry-keyboard`
- [ ] `90-dark-20-entry-income`
- [ ] `90-dark-21-entry-transfer`
- [ ] `90-dark-22-long-repeat-toast`
