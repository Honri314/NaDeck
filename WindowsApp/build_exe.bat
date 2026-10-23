@echo off
REM Windows에서만 실행 가능합니다. (macOS에서는 exe 크로스빌드 불가)
REM 만들기: NaDeck.exe (단일 파일, GUI)

cd /d %~dp0

if not exist .venv (
  python -m venv .venv
)

.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\pip install pyinstaller

.venv\Scripts\pyinstaller --onefile --windowed --name NaDeck ^
  --add-data "truenas_api.py;." ^
  main.py

echo.
echo 완료: dist\NaDeck.exe
pause
