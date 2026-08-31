#!/bin/zsh
set -u
cd "$(dirname "$0")"

LOG_DIR="$HOME/Library/Application Support/PokecaRecordsSwiftUI"
mkdir -p "$LOG_DIR"
BUILD_LOG="$LOG_DIR/build.log"
APP_LOG="$LOG_DIR/app.log"
ERR_LOG="$LOG_DIR/app_error.log"

exec > >(tee "$BUILD_LOG") 2>&1

echo "ポケカ戦績 SwiftUI版 v1.18 をビルドします..."
echo "場所: $(pwd)"
echo "ビルドログ: $BUILD_LOG"
echo ""

if ! command -v swift >/dev/null 2>&1; then
  echo "ERROR: swift コマンドが見つかりません。"
  echo "xcode-select --install を実行してください。"
  read -n 1 -s -r "?何かキーを押すと閉じます..."
  exit 1
fi

swift --version

echo ""
echo "ビルド中..."
if ! swift build -c release; then
  echo ""
  echo "ERROR: ビルドに失敗しました。上のエラーを送ってください。"
  read -n 1 -s -r "?何かキーを押すと閉じます..."
  exit 1
fi

BIN=".build/release/PokecaRecords"
APP="PokecaRecords_v1.18.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
EXEC_NAME="PokecaRecords_v1.18"

if [ ! -f "$BIN" ]; then
  echo "ERROR: ビルド後の実行ファイルが見つかりません: $BIN"
  read -n 1 -s -r "?何かキーを押すと閉じます..."
  exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$BIN" "$MACOS/$EXEC_NAME"
chmod +x "$MACOS/$EXEC_NAME"
cp "PokecaRecords.icns" "$RES/PokecaRecords.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ja</string>
    <key>CFBundleExecutable</key>
    <string>PokecaRecords_v1.18</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.pokecarecords.v118</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PokecaRecords_v1.18</string>
    <key>CFBundleDisplayName</key>
    <string>ポケカ戦績</string>
    <key>CFBundleIconFile</key>
    <string>PokecaRecords.icns</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.18</string>
    <key>CFBundleVersion</key>
    <string>118</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSBackgroundOnly</key>
    <false/>
</dict>
</plist>
PLIST

echo "APPL????" > "$CONTENTS/PkgInfo"
xattr -cr "$APP" 2>/dev/null || true

if command -v codesign >/dev/null 2>&1; then
  echo "署名中..."
  codesign --force --sign - "$APP" || true
  codesign --verify --strict "$APP" || true
fi

echo ""
echo "完了しました。"
echo "生成されたアプリ: $(pwd)/$APP"
echo ""
echo "Finderで PokecaRecords_v1.18.app を右クリック → 開く で起動してください。"
echo "起動が遅くなるランチャー方式はやめて、アプリ本体を直接起動する形式に変更しました。"
echo ""
echo "ログ:"
echo "$BUILD_LOG"
echo ""
read -n 1 -s -r "?何かキーを押すと閉じます..."
