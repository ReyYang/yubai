#!/usr/bin/env bash
# 过程债务检查：只报告，不删除。在仓库根目录运行（云端或 Mac 都行）。
#   scripts/debt-check.sh            报告
#   scripts/debt-check.sh --strict   有项时退出码 1
# 规则见 AGENTS.md「过程不欠债」。
set -u
cd "$(git rev-parse --show-toplevel)" || exit 2

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1
DAYS=7
NOW=$(date +%s)
LIMIT=$((DAYS * 86400))
FOUND=0

section() { printf '\n## %s\n' "$1"; }
item() { printf -- '- %s\n' "$1"; FOUND=$((FOUND + 1)); }

git fetch --quiet --prune origin 2>/dev/null || echo "（fetch 失败，按本地已知的远端状态检查）"
BASE=origin/main

section "已合并但没删的远端分支"
git branch -r --merged "$BASE" --format='%(refname:short)' \
  | grep -vE '^origin/(main|HEAD)$' | grep -v '^origin$' \
  | while read -r b; do echo "- $b"; done
n=$(git branch -r --merged "$BASE" --format='%(refname:short)' | grep -vE '^origin/(main|HEAD)$' | grep -vc '^origin$')
FOUND=$((FOUND + n))

section "超过 ${DAYS} 天没动的本地分支（未推送的提交会标出）"
current=$(git branch --show-current)
while read -r name ts track; do
  [ "$name" = "main" ] && continue
  [ "$name" = "$current" ] && continue
  if [ $((NOW - ts)) -gt $LIMIT ]; then
    item "$name ${track:-}"
  fi
done < <(git for-each-ref refs/heads --format='%(refname:short) %(committerdate:unix) %(upstream:track)')

section "超过 ${DAYS} 天的 stash"
while read -r ref ts msg; do
  [ -z "$ref" ] && continue
  [ $((NOW - ts)) -gt $LIMIT ] && item "$ref $msg"
done < <(git stash list --format='%gd %ct %gs')

section "失效的 worktree"
git worktree list --porcelain | awk '/^worktree /{w=$2} /^prunable/{print w}' \
  | while read -r w; do echo "- $w（git worktree prune）"; done
n=$(git worktree list --porcelain | grep -c '^prunable')
FOUND=$((FOUND + n))

section "build/ 里超过 ${DAYS} 天的文件夹"
if [ -d build ]; then
  while IFS= read -r d; do
    item "$d $(du -sh "$d" 2>/dev/null | cut -f1)"
  done < <(find build -mindepth 1 -maxdepth 1 -mtime +$DAYS)
fi

section "超过 1 GB 的本地目录"
for d in build .build .shots .verification .design-meta DerivedData; do
  [ -d "$d" ] || continue
  kb=$(du -sk "$d" 2>/dev/null | cut -f1)
  [ "${kb:-0}" -gt 1048576 ] && item "$d $(du -sh "$d" | cut -f1)"
done

section "按轮次命名的测试文件（应按功能命名）"
while IFS= read -r f; do item "$f"; done < <(git ls-files 'Tests/*' | grep -E '/Round[0-9]+[A-Za-z]*[^/]*\.swift$')

printf '\n共 %d 项。\n' "$FOUND"
[ $STRICT -eq 1 ] && [ $FOUND -gt 0 ] && exit 1
exit 0
