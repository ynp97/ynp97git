#!/bin/bash
#
# DiaryViewer.app を組み立てる。
#
#   ./build_app.sh              → dist/DiaryViewer.app を作る
#   ./build_app.sh --install    → さらに /Applications へコピーする
#
# 前提: macOS、Xcodeコマンドラインツール（swift と iconutil）。
#
# ★踏んではいけない地雷（2026-08-03）
#   Sources/DiaryViewer/Fixtures を同梱した SwiftPM のリソースバンドル
#   （DiaryViewer_DiaryViewer.bundle）を Contents/Resources へ入れ忘れると、
#   Bundle.module が実行時に fatalError で落ちる。JournalStore が
#   フォールバック読み込みで Bundle.module を触るため、フォルダ未選択の
#   初回起動が即クラッシュになる。コピー処理を消さないこと。

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DiaryViewer"
BUNDLE_ID="com.ynp97.diaryviewer"
VERSION="0.8.0"
BUILD_NUMBER="8"
MIN_MACOS="14.0"

DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
BUILD_PATH="${DIARY_BUILD_PATH:-.build}"
CONFIGURATION="${DIARY_CONFIGURATION:-release}"

echo "==> 1/5 ${CONFIGURATION} ビルド"
swift build -c "${CONFIGURATION}" --scratch-path "${BUILD_PATH}" --disable-sandbox

BIN_PATH="$(swift build -c "${CONFIGURATION}" --scratch-path "${BUILD_PATH}" --show-bin-path --disable-sandbox)"
if [ ! -x "${BIN_PATH}/${APP_NAME}" ]; then
    echo "エラー: 実行ファイルが見つかりません: ${BIN_PATH}/${APP_NAME}" >&2
    exit 1
fi

echo "==> 2/5 アイコンを変換"
if [ ! -d "AppIcon.iconset" ]; then
    echo "エラー: AppIcon.iconset がありません。先に python3 scripts/make_icon.py を実行してください。" >&2
    exit 1
fi
mkdir -p "${DIST_DIR}"
# 2026-09-08: 正常なPNGでもCodex制限内ではInvalid Iconsetとなった。
# 同じ入力が制限外で成功することを確認済み。画像を作り直す前に実行制限を確認。
iconutil -c icns AppIcon.iconset -o "${DIST_DIR}/AppIcon.icns"

echo "==> 3/5 .app を組み立て"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES}"

cp "${BIN_PATH}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
mv "${DIST_DIR}/AppIcon.icns" "${RESOURCES}/AppIcon.icns"

# SwiftPM のリソースバンドル（Fixtures入り）。地雷の項を参照。
RESOURCE_BUNDLE="${BIN_PATH}/DiaryViewer_DiaryViewer.bundle"
if [ ! -d "${RESOURCE_BUNDLE}" ]; then
    echo "エラー: リソースバンドルが見つかりません（Bundle.module が落ちます）" >&2
    exit 1
fi
# テスト実行後のビルド先でもテスト専用バンドルを配布物へ混ぜない。
cp -R "${RESOURCE_BUNDLE}" "${RESOURCES}/"
echo "    同梱: $(basename "${RESOURCE_BUNDLE}")"

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>日記</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "==> 4/5 署名（アドホック）"
# 署名しないと、macOSが「壊れている」と言って開かない場合がある。
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null \
    && echo "    アドホック署名しました" \
    || echo "    署名に失敗しましたが続行します（初回起動時に右クリック→開く で回避できます）"

echo "==> 5/5 完了"
echo "    ${PWD}/${APP_DIR}"

if [ "${1:-}" = "--install" ]; then
    echo "==> /Applications へインストール"
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "${APP_DIR}" "/Applications/${APP_NAME}.app"
    echo "    /Applications/${APP_NAME}.app"
fi

echo
echo "開くには:"
echo "    open \"${PWD}/${APP_DIR}\""
