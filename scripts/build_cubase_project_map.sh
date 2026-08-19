#!/bin/zsh

set -u

vault="/Users/yoshiakinagumo/Documents/Obsidian Vault"
output="$vault/🎛 Cubaseプロジェクト地図.md"
index="$vault/scripts/cubase_cpr_index.txt"
group_index="$vault/scripts/cubase_cpr_group_index.txt"
paths="$(mktemp)"
rows="$(mktemp)"
trap 'rm -f "$paths" "$rows"' EXIT

find /Users/yoshiakinagumo -type f -iname '*.cpr' \
  -not -path '*/Library/Caches/*' \
  -not -path '*/.Trash/*' \
  -not -path '*/.git/*' \
  -not -path '*/Library/Group Containers/UBF8T346G9.OneDriveStandaloneSuite/OneDrive.noindex/*' \
  2>/dev/null | sort -u > "$paths"

cp "$paths" "$index"
: > "$group_index"
while IFS= read -r project_path; do
  file_name="${project_path:t}"
  stem="${file_name:r}"
  group_name=$(print -r -- "$stem" | perl -CSDA -Mutf8 -pe 's/(?:[-_ ]?[0-9０-９]+)+$//; s/[-_ ]+$//')
  [[ -n "$group_name" ]] || group_name="$stem"
  printf '%s|||%s|||%s\n' "$group_name" "$file_name" "$project_path" >> "$group_index"
done < "$paths"

while IFS= read -r file; do
  [[ -f "$file" ]] || continue
  folder="${file:h}"
  name="${file:t}"
  epoch=$(stat -f '%m' "$file" 2>/dev/null || print 0)
  date=$(date -r "$epoch" '+%Y-%m-%d' 2>/dev/null || print '不明')
  bytes=$(stat -f '%z' "$file" 2>/dev/null || print 0)
  size=$(awk -v b="$bytes" 'BEGIN { if (b >= 1048576) printf "%.1f MB", b/1048576; else printf "%.0f KB", b/1024 }')

  if [[ "$file" == *'/Library/CloudStorage/OneDrive-'* ]]; then
    place='OneDrive'
  elif [[ "$file" == *'/Desktop/'* ]]; then
    place='デスクトップ'
  elif [[ "$file" == *'/Documents/'* ]]; then
    place='書類'
  elif [[ "$file" == *'/Music/'* ]]; then
    place='ミュージック'
  elif [[ "$file" == *'/Library/Preferences/Cubase '* ]]; then
    place='Cubaseテンプレート'
  else
    place='その他'
  fi

  audio='なし'
  for candidate in "$folder/Audio" "$folder/audio" "$folder/AUDIO"; do
    if [[ -d "$candidate" ]]; then
      audio='あり'
      break
    fi
  done

  bak_count=$(find "$folder" -maxdepth 1 -type f \( -iname '*.bak' -o -iname '*.cpr.bak' \) 2>/dev/null | wc -l | tr -d ' ')
  safe_name=${name//|/｜}
  safe_folder=${folder//|/｜}
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$epoch" "$place" "$date" "$size" "$audio" "$bak_count" "$safe_name" "$safe_folder" >> "$rows"
done < "$paths"

total=$(wc -l < "$rows" | tr -d ' ')
onedrive=$(awk -F '\t' '$2=="OneDrive"{n++} END{print n+0}' "$rows")
desktop=$(awk -F '\t' '$2=="デスクトップ"{n++} END{print n+0}' "$rows")
documents=$(awk -F '\t' '$2=="書類"{n++} END{print n+0}' "$rows")
music=$(awk -F '\t' '$2=="ミュージック"{n++} END{print n+0}' "$rows")
templates=$(awk -F '\t' '$2=="Cubaseテンプレート"{n++} END{print n+0}' "$rows")
generated=$(date '+%Y-%m-%d %H:%M')

{
  print '# Cubaseプロジェクト地図'
  print
  print "> 更新: $generated / 診断対象: 内蔵ストレージ / 移動・削除なし"
  print
  print '## 概要'
  print
  print -r -- "- 利用者向けのCPR: **${total}件**"
  print -r -- "- OneDrive: ${onedrive}件"
  print -r -- "- デスクトップ: ${desktop}件"
  print -r -- "- 書類: ${documents}件"
  print -r -- "- ミュージック: ${music}件"
  print -r -- "- Cubaseテンプレート: ${templates}件"
  print -r -- '- OneDrive内部管理用の鏡（OneDrive.noindex）は重複計上していません。'
  print -r -- '- `Audioあり`は、CPRと同じフォルダにAudioフォルダがあるという意味です。実際の紐づきはCubaseのプールで確認します。'
  print
  print '## 全プロジェクト（更新日の新しい順）'
  print
  print '|更新日|場所|プロジェクト|容量|Audio|BAK|保存フォルダ|'
  print '|---|---|---|---:|:---:|---:|---|'
  sort -t $'\t' -k1,1nr "$rows" | awk -F '\t' '{printf "|%s|%s|%s|%s|%s|%s|`%s`|\n", $3,$2,$7,$4,$5,$6,$8}'
} > "$output"

print "作成: $output"
print "件数: $total"
