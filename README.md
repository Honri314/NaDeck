# NaDeck — TrueNAS 관리 프로그램

TrueNAS(SCALE/Core)를 Windows 및 macOS에서 관리하는 크로스 플랫폼 앱입니다. TrueNAS 공식 WebSocket/REST API(위임 브라우저 방식 화면 재사용)를 기반으로 구성됩니다.

## 다운로드 / 웹
- 웹: https://ubuntu.tail543772.ts.net/nadeck
- 릴리스: https://github.com/Honri314/NaDeck/releases (Windows 설치 EXE, 포터블 ZIP, macOS DMG)
- 현재 버전: `VERSION` 파일 기준 (릴리스 첨부 파일의 build-info.json 참고)

## 앱 구성

### macOS 앱 (`MacApp/` — SwiftPM, 외부 의존성 0개)
모듈명은 `TruNASApp`이고 총 4,500여 줄입니다.

| 파일 | 역할 |
|---|---|
| `TruenasClient.swift` | TrueNAS API 클라이언트. 로그인 토큰(auth/mech), WebSocket 연동, 요청 재시도. 결과는 디코딩 모델로 수신 |
| `AppModel.swift` | 연결 상태/데이터 새로고침 액션(models/disks/pools/datasets/plugins/shares/jobs 재생), 에러 처리, 연결 유지 관리 |
| `RootView.swift` | 메인 분할 레이아웃: 사이드바(Dashboard/Storage/Pools/Datasets/Apps/Shares/System/Jobs/Snapshots/Settings) + 콘텐츠 |
| `EntitySpec.swift` / `GenericEntityView.swift` | 풀-데이터셋/공유/플러그인 같은 TrueNAS 엔트리를 한 뷰로 표시하는 "엔트리 스펙" 추상화(속성, 아이콘, 편집 양식, 검증) |
| `AppVMViews.swift` | Apps/Virtual Machines 직접 관리 (설치, 시작/중지/재시작, 리소스 관련 표) |
| `SnapshotsView.swift` | 스냅샷 목록/생성/롤백/삭제 |
| `SystemViews.swift` | 시스템 상태(CPU/RAM/네트워크/전체 디스크) 정보 카드 |
| `SettingsView.swift` | 호스트·API 키 저장(Keychain), 한/영 UI 언어 전환 |
| `UpdateChecker.swift` | 앱 개정 확인 (릴리스 태그 기준) |
| `L10n.swift` | 한국어/영어 라벨 리소스 |
| `Models.swift` | API 응답 디코드 모델 |

### Windows 앱 (`WindowsApp/` — Python, PySide6)
- `main.py`: Qt(QRunnable + WorkerSignals) 스레드를 사용해 UI 블로킹 없이 API 요청 — 연결 페이지(호스트/API 키), 대시보드(전체 상태 카드/게이지), TrueNAS 사양 페이지, 앱/VM 관리 페이지, 스냅샷 페이지 등 탭 구성.
- `truenas_api.py`: HTTP 클라이언트 (토큰 방식), 스레드 안전 요청 래퍼.
- `t(korean, english)` 대응: 언어 설정을 config로 관리해서 앱 전체 한/영 전환.
- `build_exe.bat` + `portable_win/`: PyInstaller 실행(설치 EXE와 포터블 ZIP 두 가지 배포).
- `TrueNAS.ico` 포함, `requirements.txt`는 PySide6만 사용.

## 웹사이트 (Website/)
- `server.py`: Python 표준 라이브러리만 사용한 Threading 다운로드 사이트 서버(포트 8181, 퍼널 `/nadeck` 경로 분기 지원).
- `index.html`: 최신 버전 확인·다운로드 페이지.
- `make_releases.py`: 로컬 빌드 산출물을 `releases/`로 모으고 `build-info.json`(빌드 시각)을 생성.
- `releases/`: NaDeck-macOS.dmg / NaDeck.exe(설치형) / NaDeck-Windows.zip(포터블) — 큰 파일은 리포가 아니라 GitHub 릴리스로 배포.

## 개발 구조 메모
- `Tools/`: 스크립트/보조 도구.
- `build.sh` / `package.sh`: macOS 빌드/패키지 스크립트(SwiftPM release 빌드 후 .app 번들 제작).
- `dist/`, `WindowsApp/portable_win/`, `MacApp/.build/`: 빌드 산출물. 리포에는 커밋되지 않습니다(.gitignore).
- 이력 백업 폴더 등 개인 사본은 `hub/` 대신 로컬 참고용이므로 리포에서 제외했습니다.

## 빌드
```
# macOS
cd MacApp && swift build -c release && swift run
# Windows (Python + PySide6)
pip install -r WindowsApp/requirements.txt
python WindowsApp/main.py
# 다운로드 사이트
python Website/server.py 8181
```

## 보안 노트
- TrueNAS API 키는 OS 보안 저장소(macOS Keychain / Windows 설정에서의 별도 구拠점)에 보관하도록 동작하며, 코드나 리포에 평문 저장되지 않습니다.
- 커밋 서명은 GitHub noreply 이메일(개인정보 노출 아님)을 씁니다.
