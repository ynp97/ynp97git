#!/bin/bash
# ============================================================
# 移行スクリプト（2026-08-15 作成）
#   M5 → BENJAMIN → 15インチAir へ、Vaultの外にある実体をまとめて運ぶ
#
#   使い方:
#     M5側   : bash migrate_app_data.sh collect
#     Air側  : bash migrate_app_data.sh restore-apps
#
#   collect      … 下のリストをすべて BENJAMIN の受け渡しフォルダへ集める
#   restore      … 受け渡しフォルダから、元と同じ場所へ全部戻す
#   restore-apps … 同上だが ~/Desktop（189GB）を除く。15インチAir向け（2026-08-16 追加）
#
#   Vault本体（3.7GB）も一緒に運ぶ。Obsidianは閉じてから実行すること。
# ============================================================

set -u

SSD="/Volumes/BENJAMIN"
STAGE="$SSD/_移行データ"
MODE="${1:-collect}"

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; OFF=$'\033[0m'
ok=0; ng=0; skip=0

say()  { printf '%s\n' "$*"; }
good() { printf '%s\n' "${GRN}  OK${OFF}   $*"; ok=$((ok+1)); }
warn() { printf '%s\n' "${YEL}  なし${OFF} $*"; skip=$((skip+1)); }
bad()  { printf '%s\n' "${RED}  失敗${OFF} $*"; ng=$((ng+1)); }

# --- 運ぶものの一覧 -----------------------------------------
# 「元の絶対パス」を並べる。restore は同じ場所へ戻す。
ITEMS=(
  "$HOME/Library/Application Support/ZatsuTodo"
  "$HOME/Library/Preferences/com.ynp97.zatsutodo.plist"
  "/Applications/ZatsuTodo.app"
  "$HOME/Library/Application Support/出席簿"
  "/Applications/出席簿.app"
  "$HOME/Desktop"
  "/Applications/ラベル管理.app"
  "$HOME/Library/Application Support/ynp97 TODOインボックス"
  "/Applications/TODOインボックス.app"
)
# ※ デスクトップは丸ごと運ぶ。2026-06-27に「今後のアプリ関係の実体は原則
#    ~/Desktop/AI関係/ の中に展開する」と決めてあり、ラベル管理のsqlite、
#    e-bay・ヤフオク、GAMES、説教関係、学校関係なども全部ここにあるため。
#    個別に拾うと必ず漏れる。
# ※ ~/Library/Application Support/ラベル管理_使わない退避_20260627 は
#    2026-06-27に「使わない」と決めて退避したもの。意図的に含めない。
#
# ★★ このリストで運べないもの（2026-08-16 追記・実際に穴が開いた）
#    ブラウザの localStorage に保存するアプリのデータは、ここに一切入らない。
#    Chrome のプロファイルが対象外なので、ファイルコピーでは運べない。
#    該当＝ラベル管理（送付済み台帳＝二重発送防止）、三本立てTODO 等の単体HTMLアプリ。
#    → アプリ内の「全データをJSON書き出し」→ 新機で「JSONから復元」で運ぶ。
#      手順の正本は アプリ引き継ぎ/J 資料請求ラベル管理システム.md の J-3。

# --- 事前チェック -------------------------------------------
if [ ! -d "$SSD" ]; then
  say "${RED}BENJAMIN が見つかりません。${OFF} SSDを挿してから実行してください。"
  exit 1
fi

if pgrep -x "Obsidian" >/dev/null 2>&1; then
  say "${RED}Obsidianが起動しています。${OFF} 終了してから実行してください（書きかけが混ざります）。"
  exit 1
fi

# パスを受け渡しフォルダ内の名前へ変換（/ を ∕ に置き換えて平らに持つ）
stage_name() { printf '%s' "${1//\//∕}"; }

# ============================================================
case "$MODE" in

size)
  say "== 大きさを測るだけ（コピーはしません）"
  total=0
  for src in "${ITEMS[@]}"; do
    if [ ! -e "$src" ]; then warn "$src"; continue; fi
    kb=$(du -sk "$src" 2>/dev/null | cut -f1)
    total=$((total + kb))
    printf '  %8s  %s\n' "$(du -sh "$src" 2>/dev/null | cut -f1)" "$src"
  done
  gb=$((total / 1024 / 1024))
  say ""
  say "合計 約 ${gb} GB"
  say "  BENJAMIN の空き: $(df -h "$SSD" | awk 'NR==2{print $4}')"
  say "  ※ 15インチAirは SSD 256GB。macOSを引くと実質200GB程度が上限。"
  if [ "$gb" -gt 150 ]; then
    say "${YEL}  150GBを超えています。デスクトップの中で重いフォルダ（写真・音源・録画）を${OFF}"
    say "${YEL}  M5に残すか、BENJAMINへ置きっぱなしにするか決めたほうがよいです。${OFF}"
  fi
  exit 0
  ;;

collect)
  say "== 集める → $STAGE"
  mkdir -p "$STAGE" || { say "${RED}受け渡しフォルダを作れません${OFF}"; exit 1; }

  : > "$STAGE/_manifest.txt"
  for src in "${ITEMS[@]}"; do
    if [ ! -e "$src" ]; then warn "$src"; continue; fi
    dst="$STAGE/$(stage_name "$src")"
    rm -rf "$dst"
    if ditto "$src" "$dst" 2>/dev/null; then
      printf '%s\n' "$src" >> "$STAGE/_manifest.txt"
      good "$(du -sh "$dst" 2>/dev/null | cut -f1)  $src"
    else
      bad "$src"
    fi
  done
  # Air側で使えるよう、このスクリプト自身も受け渡しフォルダの直下へ置く
  cp "$0" "$STAGE/migrate_app_data.sh" 2>/dev/null

  say ""
  say "受け渡しフォルダの合計: $(du -sh "$STAGE" 2>/dev/null | cut -f1)"
  ;;

restore|restore-apps)
  if [ "$MODE" = "restore-apps" ]; then
    say "== 戻す（アプリと設定だけ・デスクトップは除く） ← $STAGE"
    say "${YEL}  ※ ~/Desktop（189GB）は入れません。256GBのAirに載らないため。${OFF}"
    say "${YEL}  ※ ラベル管理のsqlite等、実データがデスクトップ側にあるものは${OFF}"
    say "${YEL}    アプリだけ入って中身が空に見えます。必要ならBENJAMINから個別に拾う。${OFF}"
    say ""
  else
    say "== 戻す ← $STAGE"
  fi
  if [ ! -f "$STAGE/_manifest.txt" ]; then
    say "${RED}$STAGE/_manifest.txt がありません。${OFF} 先にM5側で collect を実行してください。"
    exit 1
  fi

  while IFS= read -r dest; do
    [ -z "$dest" ] && continue
    if [ "$MODE" = "restore-apps" ] && [ "$dest" = "$HOME/Desktop" ]; then
      warn "${dest}（restore-apps では意図的に除外）"; continue
    fi
    src="$STAGE/$(stage_name "$dest")"
    if [ ! -e "$src" ]; then warn "${dest}（受け渡しフォルダ内に無い）"; continue; fi

    mkdir -p "$(dirname "$dest")"
    # 既にあるものは消さずに退避する
    if [ -e "$dest" ]; then
      mv "$dest" "$dest.bak-$(date +%Y%m%d%H%M%S)" 2>/dev/null
    fi
    if ditto "$src" "$dest" 2>/dev/null; then
      # 自作アプリは署名が弱いので、隔離属性を外しておく
      case "$dest" in *.app) xattr -dr com.apple.quarantine "$dest" 2>/dev/null ;; esac
      good "$dest"
    else
      bad "$dest"
    fi
  done < "$STAGE/_manifest.txt"
  ;;

*)
  say "使い方: bash migrate_app_data.sh [size|collect|restore|restore-apps]"
  say "  restore      … デスクトップ189GBも含めて全部戻す（M5級の容量が要る）"
  say "  restore-apps … アプリ・アプリのデータ・設定だけ戻す（15インチAir向け）"
  exit 1
  ;;
esac

# ============================================================
say ""
say "成功 $ok / なし $skip / 失敗 $ng"
if [ "$ng" -gt 0 ]; then
  say "${RED}失敗が出ています。上の行を見てください。${OFF}"
  exit 1
fi
if [ "$MODE" = "collect" ]; then
  say "次: BENJAMIN を取り出して Air に挿し、Air 側で restore を実行する。"
else
  say "次: 各アプリを開いて中身が入っているか見る。"
  say "    確かめ方 = 雑TODOに80件・出席簿に生徒・ラベル管理に送付履歴が出ていれば入っています。"
  say "    ★BENJAMIN の _移行データ は消さない（2026-08-15 決定＝Desktop等189GBの恒久置き場）。"
fi
