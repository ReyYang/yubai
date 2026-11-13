#!/usr/bin/env bash
# Legacy-control inventory plus enforced round-46 shell contracts. No Xcode required.
set -u
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." || exit 0
report() {
    local title="$1" pattern="$2" exclude="$3" hits file
    hits="$(for file in Sources/YubaiApp/*.swift; do
        case "/$exclude/" in *"/$(basename "$file")/"*) continue ;; esac
        grep -nHE "$pattern" "$file" || true
    done)"
    printf '\n%s: %s sites\n' "$title" "$(printf '%s\n' "$hits" | grep -c . || true)"
    [[ -z "$hits" ]] || printf '%s\n' "$hits"
}
report 'Raw text inputs' '(TextField|SecureField|TextEditor)[[:space:]]*\(' 'DesignSystem.swift/EntryFormComponents.swift'
report 'Hand-made back buttons (calendar paging excluded)' '"chevron\.left"' 'DesignSystem.swift/EntryCalendarView.swift'
report 'Hidden navigation bars' '\.toolbar\(\.hidden,[[:space:]]*for:[[:space:]]*\.navigationBar\)' ''
report 'Direct Toast construction outside app root' '(^|[^[:alnum:]_])Toast[[:space:]]*\(' 'YubaiApp.swift'
failed=0
enforce_absent() {
    local title="$1" pattern="$2" directory="$3"
    if rg -n --glob '*.swift' "$pattern" "$directory"; then
        printf '\nFAIL: %s\n' "$title"
        failed=1
    else
        printf '\nPASS: %s\n' "$title"
    fi
}
enforce_absent 'No deleted line-chart code or types' 'CashTimeline|PaceChart|LineMark|AreaMark|AnswerChart|ShowChartTool|show_chart|import Charts' Sources
enforce_absent 'Current visible vocabulary' '我的消费观|常记的几笔|进出记录|藏起来的|分一分|一个个分|按对方分|余白想这样改|整理好了|待处理' Sources/YubaiApp
enforce_absent 'One native pushed-page back implementation' 'LedgerPageHeader|navigationBarBackButtonHidden|"arrow.left"' Sources/YubaiApp
exit "$failed"
