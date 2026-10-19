#!/usr/bin/env bash
# 项目文档体检 —— 只读：不改、不删、不建任何文件
# 用法: bash 体检.sh [项目路径]
# 依赖: bash + GNU find / xargs（Windows 上 git-bash 自带）
#
# 大项目上的注意事项：
#   - 不用 du 扫全树（会很慢）。仓库体积靠 git count-objects 算。
#   - 常用巨型目录用 -prune 直接不进去，不是“列出来再排除”。
#   - 所有 find 都限了深度；md 文件最多统计 400 个。
#   - 还是慢的话：调小 DEPTH。

DEPTH="${DEPTH:-4}"          # 找文件的最大深度
MD_LIMIT="${MD_LIMIT:-400}"  # 最多统计多少个 md 的行数

PROJ="${1:-.}"
cd "$PROJ" 2>/dev/null || { echo "进不去目录: $PROJ"; exit 1; }

# 一律不进这些目录（给 find 用的 prune 片段）
PRUNE=(
  -name .git -o -name node_modules -o -name __pycache__ -o -name .venv -o -name venv
  -o -name vendor -o -name target -o -name dist -o -name build -o -name .next
  -o -name .cache -o -name .idea -o -name .gradle
)

echo "======================================"
echo " 项目体检（只读）"
echo " 路径: $(pwd)"
echo " 时间: $(date '+%Y-%m-%d %H:%M')  深度上限 $DEPTH"
echo " 扫描中…（大项目可能要几十秒，可以 Ctrl-C 中途停）"
echo "======================================"

say() { printf '\n== %s ==\n' "$1"; }

say "版本控制"
if [ -d .git ]; then
  echo "有 git"
  echo "提交数: $(git rev-list --count HEAD 2>/dev/null || echo 0)"
  echo "最后一次: $(git log -1 --format='%h  %ad  %s' --date=short 2>/dev/null || echo '（还没有提交）')"
  echo "未提交改动: $(git status --porcelain 2>/dev/null | wc -l | tr -d ' ') 个文件"
  # 不用 du 扫 .git：大仓库上会卡住。改用 git 自己数对象
  loose=$(git count-objects -vH 2>/dev/null | sed -n 's/^size: //p')
  pack=$(git count-objects -vH 2>/dev/null | sed -n 's/^size-pack: //p')
  [ -n "$loose$pack" ] && echo "对象体积: 松散 ${loose:-?} / 打包 ${pack:-?}（git count-objects）"
else
  echo "!! 没有 git —— 先建立、存一份基线，再谈整理"
fi

say "主要文档行数（上限：AGENTS.md 60，TODO.md 120）"
found=0
for f in AGENTS.md TODO.md README.md CLAUDE.md; do
  if [ -f "$f" ]; then
    n=$(wc -l < "$f" | tr -d ' ')
    mark=""
    case "$f" in
      AGENTS.md) [ "$n" -gt 60 ]  && mark="   !! 超过 60 行上限" ;;
      TODO.md)   [ "$n" -gt 120 ] && mark="   !! 超过 120 行上限" ;;
    esac
    printf '  %-14s %6s 行%s\n' "$f" "$n" "$mark"
    found=1
  fi
done
[ "$found" = "1" ] || echo "  （没找到 AGENTS.md / TODO.md）"

say "md 文件按行数排（前 15，最多统计 $MD_LIMIT 个）"
find . -maxdepth "$DEPTH" \( "${PRUNE[@]}" \) -prune -o -type f -name '*.md' -print 2>/dev/null \
  | head -n "$MD_LIMIT" \
  | while IFS= read -r p; do printf '%s\t%s\n' "$(wc -l < "$p" 2>/dev/null | tr -d ' ')" "$p"; done \
  | sort -rn | head -15 \
  | awk -F'\t' '{printf "  %6s 行  %s\n", $1, $2}'
echo "  （看不到东西就是没有 md 文件）"

say "疑似手写备份（这类内容应该交给版本控制）"
find . -maxdepth "$DEPTH" \( "${PRUNE[@]}" \) -prune -o -type f \
  \( -iname '*backup*' -o -iname '*.bak' -o -iname '*.orig' -o -iname '*_旧*' \
     -o -iname '*备份*' -o -iname '*before*' -o -iname '*副本*' -o -iname '*-copy*' \) \
  -print 2>/dev/null | head -20
echo "  （上面为空 = 干净）"

say "大文件（大于 5 MB，前 10；大小直接取自文件元数据，不扫内容）"
find . -maxdepth "$DEPTH" \( "${PRUNE[@]}" \) -prune -o -type f -size +5M -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn | head -10 | while IFS=$'\t' read -r s p; do
      mb=$(awk -v b="$s" 'BEGIN{printf "%.0fM", b/1048576}')
      ign=""
      if [ -d .git ] && git check-ignore -q "$p" 2>/dev/null; then ign="   （已忽略）"; fi
      printf '  %6s  %s%s\n' "$mb" "$p" "$ign"
    done
echo "  （没标「已忽略」的大文件会进版本控制，想想该不该进）"

say "忽略清单"
if [ -f .gitignore ]; then
  echo ".gitignore 有 $(wc -l < .gitignore | tr -d ' ') 行，内容："
  sed 's/^/    /' .gitignore | head -25
else
  echo "!! 没有 .gitignore"
fi

say "文件最多的目录（前 10，深度 $DEPTH 内）"
find . -maxdepth "$DEPTH" \( "${PRUNE[@]}" \) -prune -o -type f -printf '%h\n' 2>/dev/null \
  | sort | uniq -c | sort -rn | head -10 \
  | awk '{printf "  %6s 个文件  %s\n", $1, $2}'

say "脚本堆积情况（深度 $DEPTH 内）"
js=$(find . -maxdepth "$DEPTH" \( "${PRUNE[@]}" \) -prune -o -type f -name '*.js' -print 2>/dev/null | wc -l | tr -d ' ')
py=$(find . -maxdepth "$DEPTH" \( "${PRUNE[@]}" \) -prune -o -type f -name '*.py' -print 2>/dev/null | wc -l | tr -d ' ')
sh=$(find . -maxdepth "$DEPTH" \( "${PRUNE[@]}" \) -prune -o -type f -name '*.sh' -print 2>/dev/null | wc -l | tr -d ' ')
echo "  js $js 个 / py $py 个 / sh $sh 个"
echo "  （说不清用途的那些，就是该删或该归到「工具」目录的那些）"

say "脚本给的建议"
tips=0
if [ ! -d .git ]; then echo "  - 没有版本控制：先建立仓库 + 写忽略清单 + 提交一次基线"; tips=1; fi
if [ -f TODO.md ]; then
  n=$(wc -l < TODO.md | tr -d ' ')
  [ "$n" -gt 120 ] && { echo "  - TODO.md $n 行：先把历史冻结归档，再写一份只讲「现在」的"; tips=1; }
fi
if [ -f AGENTS.md ]; then
  n=$(wc -l < AGENTS.md | tr -d ' ')
  [ "$n" -gt 60 ] && { echo "  - AGENTS.md $n 行：只留每次都要看的，解释性内容挪到单独文件"; tips=1; }
fi
[ -f .gitignore ] || { echo "  - 没有 .gitignore"; tips=1; }
bk=$(find . -maxdepth "$DEPTH" \( "${PRUNE[@]}" \) -prune -o -type f \
  \( -iname '*backup*' -o -iname '*.bak' -o -iname '*.orig' -o -iname '*_旧*' \
     -o -iname '*备份*' -o -iname '*before*' -o -iname '*副本*' -o -iname '*-copy*' \) \
  -print 2>/dev/null | wc -l | tr -d ' ')
[ "$bk" -gt 0 ] && { echo "  - 找到 $bk 个疑似手写备份：确认已进版本控制后删掉"; tips=1; }
[ "$tips" = "0" ] && echo "  （没发现明显问题）"

cat <<'EOF'

======================================
 体检结束。接下来：把这份结果给用户看，
 列一张「哪个文件、现在多少行、改成多少行、原来的内容去哪」的表，
 等用户确认再动手。
======================================
EOF
