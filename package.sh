#!/usr/bin/env bash
# macOS .app 번들 패키징 스크립트
#   ./package.sh
# 결과: dist/NaDeck.app  (Finder에서 더블클릭으로 실행 가능)
# 사전 빌드가 없으면 먼저 ./build.sh 를 실행한다.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# 앱 버전: VERSION 파일 단일 소스 (UpdateChecker가 Info.plist의 CFBundleShortVersionString과 비교)
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 1.0.0)"
VERSION="$(echo "$VERSION" | tr -d '[:space:]')"

echo "[1/4] Swift 빌드 (MacApp)"
if ! (cd "$ROOT/MacApp" && swift build -c release); then
  echo "swift build 실패. 검증 후 다시 시도하세요."
  exit 1
fi

# [1.5/4] 기존 앱 버전 정리: dist에 남아 있는 기존 .app 전부를
# dist/과거버전/<버전>_<날짜>/ 로 옮겨 dist에는 신버전만 남는다.
PAST="$ROOT/dist/과거버전"
mkdir -p "$PAST"
DATESTAMP="$(date +%Y%m%d)"
for OLD in "$ROOT"/dist/*.app; do
  [ -d "$OLD" ] || continue
  OLDV="$(plutil -extract CFBundleShortVersionString raw -o - "$OLD/Contents/Info.plist" 2>/dev/null)"
  [ -n "$OLDV" ] || OLDV="알수없음"
  DEST="$PAST/${OLDV}_${DATESTAMP}_$(basename "$OLD" .app)"
  if [ -e "$DEST" ]; then DEST="${DEST}_$(date +%H%M%S)"; fi
  mv "$OLD" "$DEST"
  echo "  이동: $(basename "$OLD") -> dist/과거버전/$(basename "$DEST")"
done

BIN="$ROOT/MacApp/.build/release/TruNASApp"
[ -f "$BIN" ] || BIN="$ROOT/MacApp/.build/debug/TruNASApp"
if [ ! -f "$BIN" ]; then
  echo "빌드 산출물(TruNASApp)을 찾지 못했습니다."
  exit 1
fi

APP="$ROOT/dist/NaDeck.app"
echo "[2/4] .app 번들 구성 ($APP)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NaDeck"
chmod +x "$APP/Contents/MacOS/NaDeck"

# 앱 아이콘 (없으면 생성)
VENV="$HOME/.tnvenv"
if [ ! -f "$ROOT/Tools/AppIcon.icns" ]; then
  if [ -f "$VENV/bin/python" ]; then
    "$VENV/bin/python" "$ROOT/Tools/make_icon.py" >/dev/null || echo "아이콘 생성 실패 (계속 진행)"
  fi
fi
if [ -f "$ROOT/Tools/AppIcon.icns" ]; then
  [ -d "$ROOT/Tools/AppIcon.iconset" ] || echo "iconset 누락으로 icns 재생성 필요"
  cp "$ROOT/Tools/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>NaDeck</string>
    <key>CFBundleDisplayName</key>
    <string>NaDeck (TrueNAS 관리)</string>
    <key>CFBundleIdentifier</key>
    <string>kr.freebuff.nadeck</string>
    <key>CFBundleExecutable</key>
    <string>NaDeck</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
EOF

echo "[3/4] ad-hoc 서명"
codesign --force -s - "$APP" >/dev/null 2>&1 || echo "(서명 실패 - 로컬 실행에는 문제 없음)"

echo "[4/4] 실행 확인"
"$APP/Contents/MacOS/NaDeck" >/tmp/package_smoke.log 2>&1 &
PID=$!
sleep 5
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "OK"
else
  echo "FAIL - 실행 로그:"
  tail -3 /tmp/package_smoke.log
  exit 1
fi

echo ""
echo "완료: $APP"
echo "Finder에서 dist/NaDeck.app 을 더블클릭하거나: open dist/NaDeck.app"
