#!/usr/bin/env bash
# TrueNAS 관리 프로그램 빌드/검증 스크립트
#   ./build.sh          : Swift 빌드 + Python 모듈 컴파일 체크
#   ./build.sh --smoke  : 위 내용 + 두 앱 6초 실행 smoke test
# 결과는 buildlog.md에 기록한다.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# 파이썬 venv는 한글없는 안정 경로에서 쓴다 (경로에 한글/공백 있으면
# PySide6의 Qt platform plugin 스캔이 간혈적으로 실패함)
VENV="$HOME/.tnvenv"
if [ ! -f "$VENV/bin/python" ]; then
  echo "venv 없음 -> 새로 생성 후 의존성 설치 ($VENV)"
  python3 -m venv "$VENV" \
    && "$VENV/bin/pip" install --quiet --upgrade pip \
    && "$VENV/bin/pip" install --quiet -r "$ROOT/WindowsApp/requirements.txt" pillow \
    || { echo "venv 생성 실패"; exit 1; }
fi
SWIFT_OK=0
PY_OK=0
SMOKE_OK=0
MODE="${1:-}"
# Xcode 위치: 기존 /Volumes/hub 볼륨 구성에서 /Applications로 옮겨졌다.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "=================================================="
echo " Developer 단위: $(xcodebuild -version 2>/dev/null | head -1)"
echo "=================================================="

# -------- 1. Swift macOS 앱 빌드
echo "[1/2] Swift 빌드 (MacApp)"
if (cd "$ROOT/MacApp" && swift build); then
  SWIFT_OK=1
else
  SWIFT_OK=0
fi

# -------- 2. Python 앱 컴파일 체크
echo "[2/2] Python 컴파일 체크 (WindowsApp)"
if "$VENV/bin/python" -m py_compile "$ROOT/WindowsApp/main.py" "$ROOT/WindowsApp/truenas_api.py"; then
  PY_OK=1
else
  PY_OK=0
fi

# -------- 옵션: smoke test
if [ "$MODE" = "--smoke" ]; then
  echo "[smoke/1] Swift 앱 6초 실행 테스트"
  "$ROOT/MacApp/.build/debug/TruNASApp" >/tmp/tn_smoke_swift.log 2>&1 &
  P1=$!
  sleep 6
  if kill -0 "$P1" 2>/dev/null; then
    kill "$P1"
    SMOKE_SWIFT=ok
  else
    SMOKE_SWIFT=fail
  fi

  echo "[smoke/2] Python 앱 6초 실행 테스트"
  "$VENV/bin/python" "$ROOT/WindowsApp/main.py" >/tmp/tn_smoke_py.log 2>&1 &
  P2=$!
  sleep 6
  if kill -0 "$P2" 2>/dev/null; then
    kill "$P2"
    SMOKE_PY=ok
  else
    SMOKE_PY=fail
  fi

  if [ "$SMOKE_SWIFT" = ok ] && [ "$SMOKE_PY" = ok ]; then
    SMOKE_OK=1
  else
    echo "-- smoke 실패 상세:"
    echo "-- swift log:"; tail -5 /tmp/tn_smoke_swift.log 2>/dev/null
    echo "-- python log:"; tail -5 /tmp/tn_smoke_py.log 2>/dev/null
  fi
fi

echo "=================================================="
echo " 결과: swift_build=$SWIFT_OK py_compile=$PY_OK smoke=$SMOKE_OK"
echo "=================================================="

# 종료 코드: 비트 플래그 (swift=1, py=2, smoke=4)
EXITCODE=$(( SWIFT_OK | (PY_OK << 1) | (SMOKE_OK << 2) ))
[ "$MODE" != "--smoke" ] && EXITCODE=$(( EXITCODE | 4 ))
exit $(( 7 - EXITCODE ))
