#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

NAME="ScreenRec"
# 2026-07-31: 出力先をデスクトップから /Applications へ変更。
# デスクトップ版と /Applications 版の2つが並存して、どちらを見ているか分からなくなった。
DEST="/Applications/${NAME}.app"

DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build -c release --product ScreenRecorder

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
cp .build/release/ScreenRecorder "$DEST/Contents/MacOS/"
cp Info.plist "$DEST/Contents/Info.plist"
cp AppIcon.icns "$DEST/Contents/Resources/" 2>/dev/null || true

# ★踏んではいけない地雷 その1（2026-07-31）
# 以前は `codesign --force --deep --sign "$CERT"` だったが、出来上がった .app を
# `codesign -dv` で調べると adhoc,linker-signed / Info.plist=not bound /
# Sealed Resources=none になっていた（＝バンドルとして署名されていない）。
# その状態だと macOS は画面収録の許可をアプリに結びつけられず、許可を与えても
# 使う瞬間に無効化され、一覧から項目ごと消える。
# --deep を外し、--identifier を明示することで Info.plist が署名に結びつく。
#
# ★踏んではいけない地雷 その2（2026-07-31・実測で確認）
# ad-hoc署名（--sign -）だと、署名の指紋がアプリの「中身」から作られる。
# つまりソースを1文字でも変えてビルドし直すと指紋が変わり、macOS は別アプリと
# みなして画面収録の許可を無効化する。ビルドのたびに許可が外れる。
#   実測: ソース無変更の再ビルド → 許可は生きたまま録画できた
#         ソース変更ありの再ビルド → 許可が外れ「permission needed」に戻った
# 対策として、キーチェーンに作った自己署名のコード署名証明書で署名する。
# 証明書で署名すると macOS は「中身の指紋」ではなく「誰が署名したか」で判断する
# ので、ビルドし直しても許可が生き残る。
#
# 使う証明書（2026-07-31 時点で `security find-identity -v -p codesigning` にあるもの）
#   "Apple Development: darkstarman2019@gmail.com (K74T5Z7BG6)"
# 旧 build.sh には D60BB3F755BA4993EEDA2DCFF3905F3995CB212C というIDが書かれていたが、
# この一覧に存在しない（失効か削除）。存在しないIDを指定していたため署名が効かず、
# ad-hoc,linker-signed のまま出来上がっていた。**IDを直書きしない。名前で探す。**
#
# 証明書が失効したら `security find-identity -v -p codesigning` で現行のものを確認し、
# 下の SIGN_ID を書き換える。書き換えたら許可を一度入れ直す必要がある。
SIGN_ID="$(security find-identity -v -p codesigning \
  | grep -o '"[^"]*"' | tr -d '"' | head -1)"

if [ -z "$SIGN_ID" ]; then
  echo "❌ 使えるコード署名証明書がキーチェーンに1つもありません。"
  echo "   security find-identity -v -p codesigning で確認してください。"
  exit 1
fi
echo "署名に使う証明書: $SIGN_ID"

codesign --force --sign "$SIGN_ID" --identifier com.screenrecorder.app "$DEST"

# 署名が本当に有効かをここで確かめる。通らなければビルドを失敗させる。
codesign --verify --strict --verbose=2 "$DEST"
codesign -dv --verbose=2 "$DEST" 2>&1 | grep -E "Identifier=|Authority=|Info.plist|Sealed Resources"

echo "✅ $DEST"
