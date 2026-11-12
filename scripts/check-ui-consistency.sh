#!/usr/bin/env bash
# Report only. No paid service, build, or Xcode required.
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
report 'Hand-made back buttons' '"chevron\.left"' 'DesignSystem.swift'
report 'Hidden navigation bars' '\.toolbar\(\.hidden,[[:space:]]*for:[[:space:]]*\.navigationBar\)' ''
report 'Chart annotations' '\.annotation[[:space:]]*\(' ''
report 'Direct Toast construction outside app root' '(^|[^[:alnum:]_])Toast[[:space:]]*\(' 'YubaiApp.swift'
exit 0
