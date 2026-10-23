# 빌드 로그 (buildlog.md)

빌드·실행·테스트를 수행할 때마다 최상단에 날짜와 함께 한 줄씩 추가한다. 상태 표기: OK / FAIL. 이모지 사용 금지.

---

## 2026-10-20 (40차)

- **[문서/홈페이지]** 버전 업데이트 로그 항목을 신규(new)/개선(improve)/수정(bugfix) 유형으로 분류·재작성, 서술 정리 + 오탈자/중복 문구 제거(“밲업” → 원인 파악, 1.2.0 중복 라인 병합 등).
- **[검증]** HTML 태그 짝 파싱 HTML_OK, 유형 라벨 24건(신규7/개선7/수정10).
- **[배포/검증]** 서버 업로드 + pm2 재시작 DEPLOY_EXIT=0, 공개 URL 실측: /nadeck/ 200, 페이지 응답에 유형 라벨(신규 7/개선 7/수정 10)과 “버전 업데이트 로그” 확인. releases/VERSION=1.4.3 유지. OK

---

## 2026-10-20 (39차)

- **[기능/홈페이지]** 다운로드 사이트(Website/index.html)에 "버전 업데이트 로그" 섹션 추가: 1.0.0~1.4.3 버전별 주요 변화를 최신순으로 표기(최신 버전 강조 카드).
- **[기능/홈페이지]** 디스코드 참여 링크(https://discord.com/invite/FGqZ7jJpFD) 추가: 상단 내비게이션 + 히어로 버튼(디스코드 로고 SVG) + 푸터 링크. 새 창으로 열림(target=_blank, rel=noopener).
- **[검증]** HTML 구조 파싱(태그 짝) 무결성 OK, 디스코드 링크 3곳/버전 로그 10건 실측.
- **[배포/검증]** 서버 업로드 + pm2 재시작 DEPLOY_EXIT=0, 공개 URL 실측: /nadeck/ 200, 페이지 응답에 디스코드 링크 3건·id="changelog"·"버전 업데이트 로그" 텍스트 확인, releases/VERSION=1.4.3 유지. OK

---

## 2026-10-20 (38차)

- **[기능/NAS 현황]** 사이드바 맨 상단에 "NAS 현황" 화면 추가(요청: "설정에서 골라야 하는 불편"). macOS — NavItem 최선단 nasOverview + NasOverviewView: 저장된 모든 프로파일을 임시 클라이언트로 병렬 조회(AppModel.loadNasOverview, /system/info + /pool + /alert/list), NAS별 카드(풀 사용률 RingGauge, 버전, 활성 알림, 연결 실패 표시). 카드의 "이 NAS로 전환" → selectProfile + 대시보드 새로고침. "연결 설정 열기" 버튼.
- **[기능/NAS 현황/Windows]** 사이드바 목룍 첫 카테고리로 "NAS 현황 - 전체 보기"(NasOverviewPage): 프로파일별 카드(QScrollArea, 풀 사용률 원형 게이지 + 대표 풀 사용률 + 상태/알림/버전). 카드 또는 "전환" 버튼 클릭 → switch_profile로 전체 화면 재구성. "연결 설정 열기" 버튼(show_connection_page). 연결 실패 NAS는 카드에 오류 표시.
- **[검증/빌드]** py_compile PY_OK, ./build.sh --smoke SCRIPT_EXIT=0(swift=1 py=1 smoke=1).
- **[버전/배포]** VERSION 1.4.3. package.sh PKG_EXIT=0(기존 dist 앱 1.4.2는 과거버전으로 이동, Info.plist 1.4.3 확인), make_releases REL_EXIT=0(dmg 1322KiB/exe 51610KiB).
- **[배포/검증]** 서버 업로드(131MB)+pm2 재시작, 공개 URL: releases/VERSION=1.4.3, DMG md5 일치(1dc453e3), EXE Content-Length 일치(52848813), build-info.json built_at 2026-10-20 17:41. OK

---

## 2026-10-20 (37차)

- **[기능/완성]** macOS에 웹 대시보드 기반의 남은 화면 일괄 추가(Windows에는 이미 전부 존재): 부팅 환경(활성화/유지·삭제, 확인 대화상자), 시스템 업데이트(상태 확인 + 설치·재부팅 이중 확인), 감사 로그(MIDDLEWARE 최근 100건), 앱 카탈로그(검색·버전 확인), API 키(생성·폐기, 발급 키 1회 표시), 네트워크 요약(IP/게이트웨이/DNS), 정적 라우트(EntitySpec /staticroute 생성·삭제). ExtraViews.swift 신규 + RootView NavItem/sections/전환 추가 + Fmt.epochString 유틸.
- **[검증/빌드]** swift 전체 빌드 오류 0 + ./build.sh --smoke SCRIPT_EXIT=0(swift=1 py=1 smoke=1).
- **[버전/배포]** VERSION 1.4.2. package.sh PKG_EXIT=0(기존 dist 앱은 과거버전/1.4.0_20261020_NaDeck_172023로 이동, Info.plist 1.4.2 확인), make_releases REL_EXIT=0(dmg 1297KiB/exe 51611KiB).
- **[배포/검증]** 서버 tar 업로드(131MB) + pm2 재시작, 공개 URL 실측: releases/VERSION=1.4.2, DMG md5 일치(7474f077), EXE Content-Length 일치(52850490), build-info.json built_at 2026-10-20 17:21. OK
- **[문서]** README: 부팅 환경/시스템 업데이트/감사 로그/앱 카탈로그/API 키/네트워크 요약/정적 라우트 반영.

---

## 2026-10-20 (36차)

- **[기능/대시보드]** 램 표시 높이를 CPU 칸과 동일 크기로: macOS — CPU·메모리 GroupBox를 maxHeight infinity로 같은 행 높이에 맞추고 RingGauge 72→104pt(선 굵기/글자 크기도 지름 비례), Windows — RingGauge 96→150px. 요청: "cpu는 엄청 큰데 램이 엄청 작게 표시됨".
- **[검증/빌드]** ./build.sh --smoke SCRIPT_EXIT=0(swift=1 py=1 smoke=1), package.sh PKG_EXIT=0(기존 1.4.0 dist 앱은 과거버전/1.4.0_20261020_NaDeck_170926으로 자동 이동됨 확인).
- **[버전/배포]** VERSION 1.4.1. make_releases REL_EXIT=0(dmg 1168KiB/exe 51619KiB). scp 업로드 시 이전 명령의 tar 잘못(exclude 옵션 처리)로 29바이트 파일이 갔던 것을 발견 → tar 재생성(131MB) 후 재업로드.
- **[배포/검증]** 서버 ~/nadeck-website/Website/releases/VERSION=1.4.1 실측, 공개 URL /nadeck/ 200, DMG 로컬·원격 md5 일치(7c594db1), EXE Content-Length 일치(52858186), build-info.json built_at 2026-10-20 17:10.

---

- **[기능/패키징]** package.sh에 과거버전 정리 추가: dist에 남아 있는 기존 .app 전부를 dist/과거버전/<앱버전>_<날짜>_<이름>/ 로 이동하고 dist에는 신버전 NaDeck.app만 남긴다. 이동 시 Info.plist에서 이전 앱의 버전을 읽어 폴더명에 기록(없으면 알수없음), 같은 이름 중복 충돌 시 시각 접미로 회피. (요청: 사용자 — 기존 버전은 과거버전 폴더로, 신버전만 dist에 유지)
- **[정리/실측]** 기존 dist의 NaDeck 2.app(1.2.0)/NaDeck 3.app(1.3.0)/NaDeck.app(1.4.0) → dist/과거버전/로 이동됨 확인. dist에는 NaDeck.app(1.4.0)만 남음. package.sh PKG_EXIT=0(실행 확인 OK).
- **[재생/재검증]** 신버전 NaDeck.app로 make_releases.py REL_EXIT=0(dmg 1166KiB/exe 51621KiB/VERSION 1.4.0), ./build.sh SCRIPT_EXIT=0(swift=1 py=1).

---

## 2026-10-19 (34차)

- **[버전/배포]** VERSION 1.4.0. ./build.sh --smoke SCRIPT_EXIT=0(swift=1 py=1 smoke=1), package.sh PKG_EXIT=0(dist/NaDeck.app), make_releases REL_EXIT=0(dmg 1166KiB / exe 51610KiB).
- **[환경/수정]** package.sh의 DEVELOPER_DIR도 /Applications/Xcode.app 경로로 갱신(build.sh와 동일).
- **[배포/서버]** 대상 디렉터리 확정: pm2 스크립트 경로가 /home/honri/nadeck-website/Website/server.py라 실제 서빙 루트는 ~/nadeck-website/Website(pm2 재시작 online 확인).
- **[배포/검증]** 공개 URL 실측: releases/VERSION=1.4.0, /nadeck/ 200, NaDeck-macOS.dmg 바이트 일치(cmp OK), NaDeck.exe Content-Length 일치(52849423바이트), build-info.json built_at 2026-10-19 13:38. OK
- **[문서]** README: 램 원형 게이지, SMB/NFS·사용자 편집 기능 반영.

---

## 2026-10-19 (33차)

- **[기능/편집]** macOS 범용 엔티티 화면에 편집 기능: EntitySpec.editFields(SMB/NFS 공유, 사용자) 추가, GenericEntityView 툴바에 편집 버튼 + EntityEditSheet 시트(기존 값 사전채우기, PUT /endpoint/id/{id}, 빈 텍스트는 전송 생략). AppModel.updateEntity + TruenasClient.putAny 추가.
- **[기능/램]** 대시보드 메모리 표시를 막대에서 원형(도넛) 게이지로 교체: macOS RingGauge(SwiftUI trim/stroke, 74pt, 항목별 % 표시), Windows RingGauge(PySide6 QPainter drawArc, 전체 사용률). 요청: 램 사용량 부분이 CPU에 비해 너무 작아서 원형으로 강조. 양쪽.
- **[검증/py]** main.py + truenas_api.py py_compile PY_OK, Windows 앱 6초 실행 smoke SMOKE_PY_OK.
- **[환경/수정]** Xcode가 /Applications/Xcode.app(27.1)으로 이동 설치됨 확인. build.sh 기본 DEVELOPER_DIR과 rule.md 2.1을 새 경로로 갱신(기존 /Volumes/hub 경로는 볼륨 미마운트로 부재).
- **[버그/수정]** AppModel의 client.get(path) as [String: Any] 3곳 컴파일 오류(Any는 Decodable 부합 불가) — client.getAny(path) as? [String: Any] 로 수정(/update/status, /network/general/summary, /network/configuration).
- **[버그/수정]** Windows 정적 라우트 페이지 로딩 TypeError: action_button.disconnect() 인자 부족 — try/except로 clicked 신호 해제 처리.
- **[전체검증]** ./build.sh --smoke SCRIPT_EXIT=0(swift=1 py=1 smoke=1). OK

---

## 2026-10-19 (32차)

- **[버그/수정]** 알림 무시(dismiss) 시 500 Internal Server Error: Swift postAny가 베어 문자열 본문을 따옴표 없이 전송해 서버 JSON 파싱 실패. JSONEncoder 인코딩으로 수정(알림 무시/복원, 서비스 시작/중지, 앱 시작/정지/재배포 전부 영향).
- **[기능/CPU]** 대시보드 CPU 정보 상세화: CPU 모델명 + 코어(스레드) 수 + 코어별 사용률 막대(25.10 reporting cpu 그래프 cpu0..N 시리즈, 실측 확인: AMD Ryzen 5 5600X, 12스레드). Windows/ macOS 양쪽.
- **[기능/디스크]** 디스크 페이지에 온도 열 추가(POST /disk/temperatures 결과를 장치명으로 병합; 실측 sda 32 / sdb 33 / nvme0n1 44.85 섭씨). 양쪽.
- **[기능/추가1]** 스냅샷 롤백/클론(POST /pool/snapshot/rollback {id}, /pool/snapshot/clone {snapshot, dataset_dst}) + 확인 대화상자. 양쪽.
- **[기능/추가2]** 서비스 재시작(POST /service/restart {service: 이름}) + 시스템 재부팅/종료(POST /system/reboot, /system/shutdown {reason}). Windows는 서비스 화면 버튼, macOS는 대시보드 시스템 작업 + 서비스 화면 재시작 버튼. 파괴적 작업에는 확인 대화상자 통과(rule.md 4.3).
- **[기능/추가3]** Windows 알림 화면에 무시된 알림 표시(무시됨 열) + 무시 알림 복원(POST /alert/restore).
- **[검증/실기기]** Windows 클라이언트: cpu_core_usages(12코어 실측), disk_temperatures(3디스크), all_alerts OK.
- **[버전/배포]** VERSION 1.3.0. build.sh --smoke SCRIPT_EXIT=0(swift=1 py=1 smoke=1), package.sh PKG_EXIT=0, make_releases REL_EXIT=0, 서버 배포 DEPLOY_EXIT=0 + 공개 URL 실측(dmg/exe 바이트 일치, VERSION 1.3.0, /nadeck/ 200).
- **[한계]** S.M.A.R.T. 검사는 25.10 REST에 라우트가 존재하지 않음(웹 UI의 데이터 보호 화면은 웹소켓 전용 모듈) — 앱에서 제공 불가. 대신 스크럽(풀 단위 검사) 제공됨. 웹 대시보드 기타 기능은 1차 요청 분 이해서 단계 확장 예정.

## 2026-10-19 (31차)

- **[원인/확인]** 사용자가 25.10.7에서 "여전히 엔드포인트 오류 + 앱 업그레이드 불가" 재보고. 원인: 실행 중이던 앱이 배포판 1.1.0(서버 releases VERSION=1.1.0) 이었고 30차 수정은 아직 배포판에 반영되지 않았음.
- **[macOS 보완]** Windows는 앞서 제거했지만 macOS 앱에 WebDAV 화면이 남아 /sharing/webdav 404 가능 — RootView와 EntitySpec에서 .sharesWebDAV 제거.
- **[버전/빌드]** VERSION 1.1.0 -> 1.2.0. ./build.sh --smoke SCRIPT_EXIT=0(swift=1 py=1 smoke=1), ./package.sh PKG_EXIT=0(Info.plist 1.2.0), make_releases REL_EXIT=0.
- **[배포/서버]** 배포 대상 확정(honri@100.113.209.56 터널 운영 노드; ssh config의 ubuntu-ai=100.98.120.115는 오프라인) — Website/ 갱신 후 pm2 restart truenas-downloads. DEPLOY_EXIT=0.
- **[배포/검증]** 공개 URL 실측: releases/VERSION=1.2.0, NaDeck-macOS.dmg 바이트 일치(cmp OK), NaDeck.exe 바이트 일치(cmp OK), /nadeck/ 200, build-info.json built_at 2026-10-19. OK
- **[참고]** strings 기반 라우트 검증은 릴리스 빌드 문자 최적화(작은 문자열 인라인)로 무의미 — 클린 릴리스 재빌드 성공과 smoke로만 판정.

- **[원인/실측]** 사용자 보고 "25.10.7로 업그레이드 후에도 엔드포인트 오류 + 앱 업데이트 불가". 저장된 프로파일(포트 50001)로 실 NAS(TrueNAS-25.10.7)에 전 엔드포인트 실측 + /api/v2.0/openapi.json 공식 스펙 610경로 대조.
- **[진단 결과]** 25.10.7에서 없어졌거나 다른 형태의 라우트: /alert(->/alert/list), /alert/dismiss/{id}(-> POST /alert/dismiss 본문=uuid), /app/{action}/{name}(-> POST /app/{action} 본문=이름), /app/delete/{name}(-> DELETE /app/id/{name}), /app/upgrade(POST 본문={app_name}), /vm/{action}/{id}(-> POST /vm/id/{id}/{action}), /vm/delete/{id}(-> DELETE /vm/id/{id}), /system/cpu,/system/memory(REST 제거 -> /reporting/get_data), /service/start|stop/{id}(-> POST /service/start|stop 본문=서비스명), /pool/scrub/run/{id}(-> POST 본문={name:풀명}), /rsync-task(-> /rsynctask), /sharing/webdav(없음 - 기능 자체 제거). 대시보드 알림 표시 필드도 severity/alert -> level/formatted 로 변경 필요.
- **[Windows 수정]** truenas_api.py: 위 라우트 전부 반영. create_vm은 POST /vm(장치 없음) 후 POST /vm/device(vm, attributes, order) 부착. reporting 폴백 하이픈 경로 제거, get_data만 사용. 서비스 시작/중지는 서비스 이름 본문. scrub_run은 풀 이름 조회 후 본문 전송. main.py: WebDAV 카테고리 제거, Rsync 경로 rsynctask, 서비스 토글 id->이름, 알림 표시 level/formatted. (import re 누락 보완.)
- **[macOS 수정]** AppModel: /alert/list 대시보드, dismissAlert(uuid 본문), appAction(start/stop/redeploy=이름 본문, delete=/app/id/, upgrade={app_name}), vmAction(POST /vm/id/{id}/{action}, DELETE /vm/id/{id}), createVM = POST /vm 후 /vm/device 부착, runScrub=풀 이름 본문, toggleService(이름 본문). TruenasClient.postAny 문자열 본문 지원 + clientMessage 케이스. Models: Alert(id=uuid문자열, formatted/alert, level/severity), SystemInfo.physmem. SystemViews: 서비스 토글 이름 사용. EntitySpec: rsynctask.
- **[CPU/메모리 폴백 실측 반영]** 25.10 get_data: cpu 시리즈=[time,cpu,cpu0..N](%), memory 시리즈=[time, available(바이트)] -> 전체 유지: available/physmem 계산, cpu는 'cpu' 시리즈 사용. 실측 데이터로 정상값 확인(Windows 클라이언트: cpu 0.0%, mem used 40.5%).
- **[실기기 검증]** 25.10.7 저장 프로파일로 Windows 클라이언트 고수준 조회 전수 OK: system_info/cpu(mem)/alerts/apps/vms/services/rsynctask/cloudsync/scrub_tasks.
- **[기록/확인]** TrueNAS 앱 업그레이드 행위 프로브 1건 실제 승격(nginx-proxy-manager, job 237 SUCCESS) 발생 - 사용자 보고에 명시.
- **[전체/검증]** `./build.sh --smoke` PIPESTATUS 캡처 SCRIPT_EXIT=0(swift_build=1 py_compile=1 smoke=1). OK

## 2026-10-18 (29차)

- **[macOS/레이아웃]** "전체화면에서 윗부분이 두꺼워져서 가려진다" 수정: 화면 제목이 툴바 제목과 콘텐츠 안 큰 제목으로 2중 표시되던 것 정리 — 대시보드의 콘텐츠 내 "대시보드" 큰 제목 제거(툴바만 사용), 범용 엔티티 화면 헤더바의 큰 제목 제거(항목 수만 표시), WindowGroup에 .windowToolbarStyle(.unified) 고정.
- **[기능/다중NAS]** "여러 트루나스를 다중 관리" 구현(양 앱):
  - macOS: NasProfile + ProfileStore(truenas.profiles.v1 JSON) 도입, 기존 단일 설정/옛 bundle id 설정 1회 이식(마이그레이션 유지). Settings 상단에 "NAS 선택(다중 관리)" 섹션: 프로파일 피커로 전환(화면 데이터 전량 리셋+재로딩 안내), "지금 설정으로 새 NAS 저장", 2개 이상일 때 프로파일 삭제(확인 대화상자). 편집 중 설정은 활성 프로파일에 즉시 자동 저장(AppModel.persistProfiles).
  - Windows: Config에 profiles(JSON: active+list).
  - 좌측 상단 NAS 선택 콤보 추가, 전환 시 트리/페이지 전체 재구성(_build_pages), ConnectionPage 저장이 표시 이름=프로파일 이름으로 저장, 새 NAS 저장/삭제 지원, 구 단일 연결 자동 이식.
- **[기능/업데이트]** "앱 업데이트 미지원 -> 앱 내에서 해결" 구현(양 앱) + 버전 단일 소스:
  - VERSION 파일(Repo root, 1.1.0) 신설; package.sh가 Info.plist CFBundleShortVersionString에 반영(번들=1.1.0 확인), make_releases가 releases/VERSION 배포 + Windows pyc에 nadeck_version.py 임베딩.
  - macOS: UpdateChecker.swift 신설(서버 releases/VERSION 비교, 시작 시 자동 확인 -> 상단 안내, 설정 "앱 업데이트" 섹션: 현재/최신 버전 표시, 업데이트 확인, 새 버전 안내, 다운로드 페이지 열기).
  - Windows: UpdatesPage 추가( 설정 카테고리), APP_VERSION(nadeck_version) /서버 VERSION 비교, 새 버전이면 "다운로드 페이지 열기" 활성; _is_newer 세부 비교.
- **[사이트/정리]** 설치 카드 문구 정정: mac 카드의 남은 "zip 다운로드/해제" 구절과 탈락한 build_exe.bat 안내를 제거하고 DMG/EXE 중심으로 통일, "실행 중 자동 업데이트 확인" 문구 추가.
- **[배포/검증]** 서버 재배포 후 공개 URL 실측: releases/VERSION=200(원문 1.1.0), NaDeck-macOS.dmg=200(다운로드 1,119,503바이트 = 로컬 완전 일치), NaDeck.exe=200(52,825,551바이트 = 로컬 일치, application/x-msdos-program). OK
- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0(swift_build=1 py_compile=1 smoke=1) — 첫 실행에서 persistProfiles 정의 누락 오류, 추가 후 재실행 통과. `./package.sh` PKG_EXIT=0(dist/NaDeck.app 재생성, plist 1.1.0), `python3 Website/make_releases.py` REL_EXIT=0(dmg/exe/VERSION/build-info). OK
  - 한계: 프로파일 전환/업데이트 UI는 실연동(TrueNAS 다중 장비 사용 경험)에서 최종 확인 필요; Windows 이번 분울 변경(pythonw에서 프로파일 콤보)은 Windows에서만 실기동 검증 가능.

- **[macOS/배포]** 맥 다운로드를 zip -> **DMG**로 교체: make_releases에서 hdiutil(UDZO)로 NaDeck.app + Applications 심볼릭 링크 스테이징 → NaDeck-macOS.dmg(1,043KiB) 생성, 구 mac zip 삭제.
- **[windows/배포]** 윈도 다운로드를 zip -> **단일 exe(SFX)**로 교체: 7zSD.sfx(Windows PE, github ghfw-build-extra에서 확보, Tools/sfx/) + SFX config(hidcon:NaDeck.bat) + 7zz -t7z -mx=7 런타임 아카이브(50MB) 결합 -> NaDeck.exe 생성. NaDeck.bat(pythonw NaDeck.pyc)의 %~dp0 기반이므로 임시 폴더 추출 후 그대로 동작.
  - 디버깅 기록: 7-zip 공식 사이트 7zsd.sfx 404 -> extra 패키지(7z2501, SFX 모듈 부재) 확인 -> ghfw 미러 사용; os.system 수정 중 인서트된 자잘한 사 오타(%s, archive7z_src) 정정; --mx=7 -> -mx=7 정정 후 생성 성공.
- **[사이트/문구]** "홈페이지 설명이 이상하다" 지적 반영: 히어로/설치 카드를 DMG+EXE 중심으로 정리(macOS DMG 다운로드 / Windows EXE 다운로드), zip은 대체용 안내로만 남김, exe/dmg 참조 문구 통일.
- **[배포/검증]** 서버 재배포 후 공개 URL 실측: NaDeck-macOS.dmg=200, NaDeck.exe=200(52,821,732바이트, application/x-msdos-program), 페이지 참조 확인(mac zip 삭제). OK
  - 한계: exe(SFX) 실제 실행은 Windows에서만 검증 가능(이 맥은 macOS) — 사용자 테스트 필요. exe는 미서명이라 SmartScreen 경고가 처음 뜰 수 있음.
- **[전체/검증]** `python3 Website/make_releases.py` REL_EXIT=0 (dmg/exe/build-info), build.sh 재실행 대상 코드는 없으나 추가 확인 생략(변경사항: 문서/릴리스 스크립트만). OK

## 2026-10-18 (27차)

- **[사이트/이미지]** 이미지 안 깨지게 수정: 아이콘 PNG를 인라인 base64 데이터 URI로 심음(퍼널/캐시/경로 문제와 무관하게 랜더링) — 검증: 공개 페이지 내 data:image/png 5곳, icon MD5 원격=로컬 일치(이미 검증됨). 기능 아이콘은 이모지 -> 인라인 SVG로 교체(폰트 의존 제거). OK
- **[사이트/정책]** 소스 공유 방침(사용자 확정) 반영: 다운로드 페이지에서 전체 소스 카드 제거, make_releases에서 NaDeck-Manager-source.zip 생성 완전 제거, 서버의 구 소스 zip 삭제(공개 404 확인). OK
- **[windows/패키징]** 받아서 바로 실행되는 Windows 포터블 패키지 구축:
  - 구성: Python 3.9.13 embeddable amd64 + PySide6-Essentials 6.10.3 cp39-abi3 win 휠 + requests의존성 휠 -> runtime/Lib/site-packages 전개, python39._pth(import site + site-packages) 작성, .pyi 스텁 제거(216M).
  - 앱 코드는 소스 미포함: python3.9로 main.py/truenas_api.py를 pyc 컴파일(NaDeck.pyc/truenas_api.pyc) + NaDeck.bat 더블클릭 런처(pythonw) + README.txt.
  - make_releases는 캐시(WindowsApp/portable_win/NaDeckWin)를 재사용하고 빌드 때마다 pyc를 최신화 후 NaDeck-Windows.zip(84,715,642 바이트) 생성.
  - 배포/검증: 서버 재배포(공개 zip 200, size=84715642 완전 일치, 소스 zip 404), pythonw.exe/qwindows.dll 등 런타임 정합성 확인. OK
  - 한계: Windows 실기동 검증 불가(이 맥은 macOS) — 사용자가 zip 받아 NaDeck.bat 실행 결과 확인 필요.
  - 문서: Website/README 개선 필요하면 다음 라운드에 반영.
- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0 (swift_build=1 py_compile=1 smoke=1), `./package.sh` PKG_EXIT=0, `python3 Website/make_releases.py` REL_EXIT=0. OK

## 2026-10-18 (26차)

- **[사이트/제작]** 다운로드 페이지 전면 리디자인(사용자 피드백: "다른 사이트는 잘 만들었는데 홈페이지가 왜 이래"). 기존 사이트(systems/hivedesk) 스타일과 동일한 톤으로: Pretendard 폰트, 스티키 네이브, 그라디언트 히어로 + 앱 아이콘, 기능 그리드(앱/VM 신규 배지), 설치 패널(mac/윈도우/소스), 연결 방법 섹션. 앱 아이콘 icns -> PNG(32/64/128, sips) 생성 후 assets/ 사용.
  - 배포/검증: tar+scp로 홈서버 ~/nadeck-website/ 갱신, 공개 URL 실측 — /nadeck/ 200 + Pretendard 적용 확인 + icon_64.png 200 + zip 200. OK
- **[기능/앱버그]** "API 연동했는데 앱 목록이 안 불러와지는" 문제 진단·수정:
  - 실측: 저장된 키로 실 NAS API GET /app 직접 호출 -> 200, 앱 3개(nginx-proxy-manager 등) 존재, 필드 구조(name/state/version/upgrade_available/latest_version) 파싱과 일치. 즉 서버측 문제 아님.
  - 원인 1(Windows): 페이지들이 쓰는 MainWindow.client()가 저장된 port/auth_mode/basic_user를 반영하지 않아 인증 폴백이 저장돼도 X-API-Key로만 요청되는 문제 — Config.load에 항목 추가 + client()에 전달로 수정.
  - 원인 2(macOS): 리네임으로 bundle id 도메인(kr.freebuff.nadeck)이 바뀌며 기존 연결 설정이 미보이는 상황 — ConfigStore.load에서 이전 도메인(kr.freebuff.truenas-manager)의 설정 1회 마이그레이션 추가.
  - 개선: 앱 목록에 업그레이드 가능 표시(버전 -> latest_version, 주황색) 양 앱 모두 적용.
  - 검증: `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0, `python3 Website/make_releases.py` REL_EXIT=0, 서버 전개 후 공개 zip 실측 200(SIZE=675641바이트 증가 확인). OK
  - 남음: 사용자 앱 재다운로드/재실행 확인 필요. 증상 지속 시 앱의 오류 문구(2초 자동 소멸 전) 전달 요청.

## 2026-10-18 (25차)

- **[배포/완료]** 사용자 지시에 따라 홈서버(honri@100.113.209.56, tailscale funnel 운영 중)에 NaDeck 다운로드 사이트 실제 배포 완료.
  - SSH 접속 발견: "honri"는 SSH 사용자명(이 맥 ~/.ssh/config의 ubuntu-ai 호스트에 User honri + id_ed25519). BatchMode 접속 성공.
  - 배포: Website/ 폴 tar.gz(1.2MB)로 전송 -> ~/nadeck-website/ 에 전개. 기존 pm2 서비스(systems/hivedesk/notchfriend/volumemixer/maccleaner) 미건드림.
  - pm2: name truenas-downloads(id 9, 8181, python3 /usr/bin) 기동 + pm2 save. 서버 내부 curl 8181=200.
  - 퍼널: tailscale 1.102.2 구문에 맞춰 `tailscale funnel --bg --yes --set-path /nadeck 8181`로 마운트 등록, serve status에 /nadeck 인입 확인(기존 /Systems,/hivedesk,/MacCleaner 유지).
  - 공개 URL 실측(이 맥에서 curl): https://ubuntu.tail543772.ts.net/nadeck/ = 200, .../releases/NaDeck-Windows.zip = 200, build-info.json = {"built_at":"2026-10-18 15:37"}, index.html 한국어 응답 확인. OK
  - 교훈: 사이트 접속(honri)이 SSH 사용자명이므로, 어이성 이름>을 사용자 식별자로 오해한 재작성 필요 없음.

## 2026-10-18 (24차)

- **[사이트/경로]** 기존 pm2 사이트들(systems/hivedesk/maccleaner)과 같은 터널에서 **경로 추가**로 접속하도록 지원 (사용자 지적 반영).
  - server.py: PATH_PREFIXES(nadeck/downloads/deck) 접두사 제거 후 파일 매핑, /nadeck(슬래시 없음) -> 301 리다이렉트, 직접 접속(root)도 유지.
  - 실기동 검증: ROOT=200, /nadeck=301, /nadeck/=200, /nadeck/releases/NaDeck-Windows.zip=200(-L 포함), /nadeck/releases/build-info.json=200, 미등록 접두사=404.
  - Website/README.md에 터널 경로 매핑 방법(/nadeck -> 127.0.0.1:8181)과 검증 결과 명시.
  - `./build.sh --smoke` SCRIPT_EXIT=0 (py_compile 등 재검증). OK

---

## 2026-10-18 (23차)

- **[리네임]** 프로그램 이름 NaDeck(나덱)으로 확정(사용자 선택) 후 전체 적용:
  - macOS 번들: package.sh -> dist/NaDeck.app, 실행 파일 NaDeck, CFBundleName/DisplayName "NaDeck (TrueNAS 관리)", bundle id kr.freebuff.nadeck.
  - Windows: 창 제목 "NaDeck — TrueNAS 관리", build_exe.bat의 exe명 NaDeck.exe.
  - 릴리스/사이트: make_releases.py가 NaDeck-macOS.zip / NaDeck-Windows.zip / NaDeck-Manager-source.zip 생성, index.html 제목/링크/기능소개 갱신(앱·VM기능 포함), Website/README 배포 절차 문구 갱신.
  - 오래된 아티팩트(dist/TruNAS.app, releases/TruNAS-macOS.zip, TrueNAS-Windows.zip, TrueNAS-Manager-source.zip) 삭제 후 재생성.
  - 기술 식별자(SPM product TruNASApp, truenas_api 모듈, API 경로)는 변경하지 않음(빌드 구조 영향 방지).
  - 검증: `./build.sh --smoke` SCRIPT_EXIT=0 (swift_build=1 py_compile=1 smoke=1), `./package.sh` PKG_EXIT=0 (dist/NaDeck.app 재생성), `python3 Website/make_releases.py` REL_EXIT=0 (658KiB/59KiB/484KiB). OK



## 2026-10-18 (22차)

- **[python/기능]** 앱(Applications) + 가상머신(VM) 관리 추가 (v25.10 API 문서 기준).
  - truenas_api.py: apps(), app_action(start/stop/redeploy/upgrade), app_delete, vms(), vm_action(start/stop/restart/poweroff), vm_delete, create_vm.
  - main.py: AppsPage(목록/상태/컨테이너/동작 버튼 + 삭제 확인창), VMPage(목록/동작 버튼 + VM 생성 대화상자: 이름/vCPU/메모리/디스크 ZVOL/ISO/NIC/자동시작). 카탈로그에 '앱/가상머신' 카테고리 등록.
  - 앱 새 설치는 스키마 설정 때문에 웹 UI 권장 안내 문구 포함. VM 생성 바디는 vm.create 스펙(name/vcpus/cores/threads/memory MiB/devices: DISK create_zvol+zvol_name/zvol_volsize, CDROM path, NIC VIRTIO+nic_attach).
- **[swift/기능]** macOS 동일 구현: NavItem에 .apps/.vms 추가(섹션 앱/가상머신), AppModel에 apps/vms published + loadApps/appAction/loadVMs/vmAction/createVM, 새 파일 AppVMViews.swift(AppsView/VMsView/CreateVMSheet: 업그레이드 취향의 Menu 동작 + 삭제 확인 + VM 생성 시트). RootView 라우팅 연결.
  - 작성 도중 잘못된 더미 코드(pools 배열 캐스징/오타)를 만들었으나 파일 전체 재작성으로 정정 후 빌드 확인.
- **[문서/갱신]** README 기능표에 앱/가상머신 행 추가. OK
- **[전체/검증]** `./build.sh` SCRIPT_EXIT=0, `./build.sh --smoke` SCRIPT_EXIT=0 (swift_build=1 py_compile=1 smoke=1), `./package.sh` PKG_EXIT=0, `python3 Website/make_releases.py` REL_EXIT=0 (macOS zip 658KiB 재생성). OK
  - 한계: vm.create/app 동작은 실장비에서 미검증(여기서 접속 불가). Docker 풀 미설정 시 앱 목록은 빈 결과 + 안내 문구.

## 2026-10-18 (21차)

- **[macOS/레이아웃]** 범용 엔티티 화면에서 인터페이스 등 열이 많은 항목을 볼 때 사이드바가 밀리는 문제 수정.
  - 원인: GenericEntityView가 열 폭을 고정 픽셀(190/110)로 잡아 행 총폭이 보이는 영역보다 넓어지면 상세 화면 최소폭이 커져 NavigationSplitView의 사이드바를 밀었음.
  - 수정: 열/헤더를 유연 폭(minWidth 0, maxWidth .infinity) + lineLimit(1) 잘림으로 변경, 내부 VStack에 maxWidth .infinity / minWidth 0 부여. 사이드바는 navigationSplitViewColumnWidth(min 190/ideal 220/max 300)로 폭 고정 범위 부여.
- **[python/레이아웃]** Windows 동일 문제 방지: 사이드바 QTreeWidget setMinimumWidth(220) -> setFixedWidth(230)로 고정, 콘텐츠가 사이드바 폭을 좌우하지 못하게 함.
  - 검증: `./build.sh --smoke` SCRIPT_EXIT=0 (swift_build=1 py_compile=1 smoke=1), `./package.sh` PKG_EXIT=0, `python3 Website/make_releases.py` REL_EXIT=0 (macOS zip 595KiB 재생성). OK

## 2026-10-18 (20차)

- **[진단/고도화]** 404 오류 메시지에 실패 경로를 직접 표시하도록 개선: "엔드포인트를 찾을 수 없습니다\n(경로: /xxx, 서버 원문: ...)" (Swift TruenasClient.perform / python _request 양쪽). 어떤 엔드포인트가 없는지 사용자가 즉시 공유 가능.
- **[robust/스냅샷]** 스냅샷 화면 로딩을 부분 실패에도 견디게 수정: 스냅샷 목록은 필수, 복제(/replication)·데이터셋(/pool/dataset)은 선택 데이터로 분리해 개별 실패 시에도 스냅샷 목록은 표시되고 실패 사유를 화면에 안내 (AppModel.loadSnapshots / WindowsApp SnapshotsPage.load).
  - 참고: 25.10 API 문서상 /pool/snapshot, /replication, /pool/dataset 쿼리는 존재하므로, 실제 404가 재발하면 이제 경로가 오류에 표시됨 — 다음 공유로 원인 확정.
  - 검증: `./build.sh --smoke` SCRIPT_EXIT=0 (swift_build=1 py_compile=1 smoke=1), `./package.sh` PKG_EXIT=0, `python3 Website/make_releases.py` REL_EXIT=0 (macOS zip 592KiB 재생성). OK

## 2026-10-18 (19차)

- **[버그/폴백]** 대시보드 CPU/RAM이 여전히 비어 있는 문제 정밀 수정. 원인 2가지:
  1. v25.10 공식 API 문서 조회 결과: reporting.get_data의 data는 {시리즈명: 값} 딕션너리 배열 + aggregations.mean 제공. 기존 파서는 리스트 행만 읽어 실패.
  2. REST 경로 표기: get_data(언더스코어)와 get-data(하이픈) 양쪽이 존재 가능해 양쪽 순차 시도가 필요.
  - 수정: 양앱 모두 dict 샘플 파싱(_reporting_sample/pickSeries) + 경로 폴백 + 분율(0~1) 정규화 + idle 기반 역산 지원; macOS는 한국어 라벨(사용/남음), Windows는 mem['free'] 표시 양식 유지.
  - 단위 검증: 스텁 payload로 cpu=20.00, mem={free:40.0, used:60.0}, 구형 legend-리스트형도 cpu=20.00 확인 (TEST_EXIT=0).
  - 실장비 검증은 여전히 불가(여기서 접속 불가) — 폴백 실패 시 CPU/RAM만 '-'로 표시됨.
  - 검증: `./build.sh --smoke` SCRIPT_EXIT=0 (swift_build=1 py_compile=1 smoke=1), `./package.sh` PKG_EXIT=0, `python3 Website/make_releases.py` REL_EXIT=0 (macOS zip 592KiB 재생성). OK

## 2026-10-18 (18차)

- **[macOS/기능]** 상태/오류 메시지가 상시로 남아 있던 문제 수정: 오버레이가 2초 후 자동으로 사라지게 함(AppModel에 statusSeq 추가, RootView StatusOverlay에 task(id:) 타이머). 새 메시지가 오면 타이머가 다시 시작됨. OK
- **[python/기능]** Windows 앱 동일 적용: MainWindow에 show_message/sticky 도입(QTimer 2000ms 단발). 정보/오류/작업 결과는 2초 후 자동 삭제, '테스트 중'/'진단 중' 진행 표시는 sticky로 유지. 일괄 치환 도중 show_message 내부가 재귀로 바뀌는 문제 발견 즉시 복구(info_label.setText로 되돌림) 후 재검증. OK
  - 연결 결과(result_list)는 원래 영구 목록이라 그대로 유지.
  - 검증: `./build.sh --smoke` SCRIPT_EXIT=0 (swift_build=1 py_compile=1 smoke=1), `./package.sh` PKG_EXIT=0, `python3 Website/make_releases.py` REL_EXIT=0 (zip 591KiB/55KiB/476KiB 재생성). OK

## 2026-10-18 (17차)

- **[macOS/버그]** 대시보드 새로고침 시 "엔드포인트를 찾을 수 없습니다"가 뜨고 CPU/메모리가 안 뜨는 문제 수정.
  - 원인: 최신 TrueNAS에서 /system/cpu, /system/memory 가 웹소켓 전용이라 REST GET 시 404발생. 기존 코드는 CPU/메모리/알림을 대시보드 요청에 묶어서 하나 실패하면 새로고침 전체가 실패함.
  - 수정: CPU/메모리/알림을 필수가 아닌 선택 데이터로 분리해 개별 실패가 새로고침 전체를 죽이지 않게 하고, 실패 시 POST /reporting/get-data(graphs: cpu/memory)로 폴백 계산(AppModel.swift). CPU는 legend의 user+system 합(없으면 값 평균, 코어별 식별자는 코어 평균), 메모리는 used/(used+free) 백분율.
  - 결과: CPU/메모리 엔드포인트가 404여도 호스트/풀/알림은 정상 표시되고 CPU/메모리는 reporting 폴백으로 채워짐.
  - 한계: /reporting/get-data 응답 형식(legend/식별자별 값 배치)은 실장비에서 미검증. 폴백 파싱 실패 시 CPU/메모리만 "-"로 표시됨(buildlog 문서 한계 명시).
- **[python/기능]** Windows 앱 동일 폴백: truenas_api.py에 _reporting_components/_reporting_rows/_num 헬퍼 추가, cpu_usage/memory_usage 실패 시 reporting 폴백(on_loaded의 mem['free'] 퍼센트 양식 유지). OK
- **[문서/갱신]** README.md "사용된 TrueNAS 엔드포인트"에 reporting/get-data 폴백 동작 명시. OK
- **[전체/검증]** `./build.sh` SCRIPT_EXIT=0 (swift_build=1 py_compile=1), `./build.sh --smoke` SCRIPT_EXIT=0 (smoke=1), `./package.sh` PKG_EXIT=0, `python3 Website/make_releases.py` REL_EXIT=0 → zip 3종/빌드인포 재생성(586KiB/55KiB/475KiB). OK---

## 2026-10-18 (23차)

- **[리네임]** 프로그램 이름 NaDeck(나덱)으로 확정(사용자 선택) 후 전체 적용:
  - macOS 번들: package.sh -> dist/NaDeck.app, 실행 파일 NaDeck, CFBundleName/DisplayName "NaDeck (TrueNAS 관리)", bundle id kr.freebuff.nadeck.
  - Windows: 창 제목 "NaDeck — TrueNAS 관리", build_exe.bat의 exe명 NaDeck.exe.
  - 릴리스/사이트: make_releases.py가 NaDeck-macOS.zip / NaDeck-Windows.zip / NaDeck-Manager-source.zip 생성, index.html 제목/링크/기능소개 갱신(앱·VM기능 포함), Website/README 배포 절차 문구 갱신.
  - 오래된 아티팩트(dist/TruNAS.app, releases/TruNAS-macOS.zip, TrueNAS-Windows.zip, TrueNAS-Manager-source.zip) 삭제 후 재생성.
  - 기술 식별자(SPM product TruNASApp, truenas_api 모듈, API 경로)는 변경하지 않음(빌드 구조 영향 방지).
  - 검증: `./build.sh --smoke` SCRIPT_EXIT=0 (swift_build=1 py_compile=1 smoke=1), `./package.sh` PKG_EXIT=0 (dist/NaDeck.app 재생성), `python3 Website/make_releases.py` REL_EXIT=0 (658KiB/59KiB/484KiB). OK



## 2026-10-18 (16차)

- **[사이트]** 다운로드 웹사이트 추가 (Website/): 한국어 index.html, 표준라이브러리 서버(server.py, 기본 8181), pm2 ecosystem.config.js, 릴리스 zip 생성기(make_releases.py), TrueNAS 터널/프록시 외부 노출 안내 README. OK
  - 검증: 서버 로컬 기동 후 통신까지 지정해 재검증 -> 페이지 200(4264B), TruNAS-macOS.zip 200(595KB), build-info.json 200. OK
  - 활용: pm2 start Website/ecosystem.config.js 로 기존 pm2 서비스들과 같은 방식으로 운영.
- **[python/기능]** Windows 앱 인증 방식 폴백 구현: auth_mode/basic_user 설정 반영, 401/403 시 X-API-Key→Bearer→Basic 자동 실험(Basic은 사용자 이름 필요), 성공 방식 자동 저장. OK
  - py_compile OK + smoke OK. OK
- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0, make_releases.py 실행 -> Website/releases/에 macOS zip/Windows zip/전체 소스 zip/build-info.json 생성 확인. OK

## 2026-10-18 (15차)

- **[python/버그]** Windows 진단 결과 복사 버튼이 진단 실행마다 레이아웃에 중복 추가되던 문제 수정 - 버튼을 ConnectionPage 초기화에서 한 번만 생성, 진단 후에만 활성화. 재검증: py_compile OK + 6초 smoke OK.
- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0. OK
- **[진단/고도화]** API 키 붙여넣었는데도 "API 키를 확인하라" 오류 지속 대응: 진단 결과에 서버 HTTP 응답 코드와 원문(json error 내용 그대로) 표시 - 서버가 실제로 무엇이라고 했는지 확인 가능.
- **[진단/공유]** 양쪽 앱에 '진단 결과 복사' 버튼 추가 (macOS NSPasteboard / Windows QApplication.clipboard).

## 2026-10-18 (14차)

- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0. OK
- **[진단/고도화]** API 키 붙여넣었는데도 "API 키를 확인하라" 오류 지속 대응: 진단 결과에 서버 HTTP 응답 코드와 원문(json error 내용 그대로) 표시하도록 강화 - 마스킹 추정 말고 서버가 실제로 무엇이라고 했는지 확인 가능.
- **[진단/공유]** 양쪽 앱에 '진단 결과 복사' 버튼 추가 (macOS NSPasteboard / Windows QApplication.clipboard) - 사용자가 원인 공유를 쉽게.

## 2026-10-18 (13차)

- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0. OK
- **[안내/한글화]** API 키 발급 안내를 단계별 한국어로 강화 (macOS SettingsView + Windows ConnectionPage): 6단계 안내, Copy 버튼/공백 주의 사항, 재발급 안내 포함. OK

## 2026-10-18 (12차)

- **[python/수정]** Windows 연결 진단에서 언어 적용이 백그라운드 시작 이후에 이루어지는 순서 문제 정리(메시지 언어 일관성). 재검증: py_compile OK + 6초 smoke OK.
- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0. OK
- **[mac/버그]** API 키 삭제 시 사이드바가 통째로 사라지는 버그 수정: 루트에서 isConfigured에 따라 뷰 트리를 교체하지 않고 항상 NavigationSplitView를 유지, 연결이 깨지면 nav를 자동으로 연결 설정 화면으로 이동. OK
- **[진단]** 연결 진단 기능 추가(양쪽 앱): 단계1 해석된 주소, 단계2 API 키 요약(마스킹/길이), 단계3 실제 서버 응답 - 401/403 원문 포함. 성공시 hostname/버전 표시. macOS는 연결 설정 화면의 '진단 실행' 버튼 + 결과 블록, Windows는 '진단 실행' 버튼 + 결과 리스트. OK

## 2026-10-18 (11차)

- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0. OK
- **[mac/버그]** API 키 삭제 시 사이드바가 통째로 사라지는 버그 수정: 루트에서 isConfigured에 따라 뷰 트리(json 코드 Intro's)를 교체하지 않고 항상 NavigationSplitView를 유지, 연결이 깨지면 nav를 진보적으로 연결 설정 화면으로 자동 이동. OK
- **[진단]** 연결 진단 기능 추가(양쪽 앱): 단계1 해석된 주소, 단계2 API 키 요약(마스킹/길이), 단계3 실제 서버 응답 - 401/403 원문 포함. 성공시 hostname/버전 표시. macOS는 연결 설정 화면의 '진단 실행' 버튼 + 결과 블록, Windows는 '진단 실행' 버튼 + 결과 리스트. OK

## 2026-10-18 (10차)

- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0. OK
- **[인증/개선]** "api가 안맞다"(API key invalid) 원인 후보 정리 및 완화: 클라이언트가 X-API-Key를 붙여넝온 원본 그대로 전송해 공백/줄바꿊/따옴표가 섞이면 서버가 무효 키로 처리 - 양쪽 앱에서 키 자동 정리(strip + 따옴표 제거) 후 전송. 401/403 + 'invalid key' 상세 시 한국어 재발급/복사 안내 추가.
- **[장비진단]** 사용자 장비에서 발생한 'Failed to sync TRUENAS catalog ... Failed to clone https://github.com/truenas/apps' 오류는 NAS가 인터넷(GitHub)에 접속하지 못해 앱 카탈로그(앱스) 동기화가 실패한 NAS 측 문제. 본 프로그램의 API 연동과는 별개. 원인·해결은 답변에 정리(사내 프로그램 코드 변경 없음).

## 2026-10-18 (9차)

- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0. OK
- **[mac/버그]** iSCSI 아이콘 2차 수정: "harddrive"도 이 시스템(macOS 27.2 SDK)에 존재하지 않아 NSImage(systemSymbolName:) 직접 렌더 테스트로 후보 검증 -> 존재하는 "cylinder.split.1x2"로 교체. 나머지 전체 사이드바 심볼 20개 동일 테스트에서 전부 OK 확인(ALL 이외 harddrive 만 문제). OK

## 2026-10-18 (8차)

- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0 (복구된 연결 설정 포함 dist/TruNAS.app 재생성). OK
- **[mac/버그/복구]** 연결 설정 화면에서 API 키 입력칸이 이전 편집 중 누락되어 화면에 없었음 -> SecureField 복원(포트 필드와 자가서명 토글 사이). Windows 앱은 정상이었음(API 키 행 존재 확인). OK
- **[mac/버그]** 사이드바 iSCSI 항목 아이콘 미표시 원인: SF Symbol "burst.badge.clock"은 실제 존재하지 않음 -> 존재하는 "harddrive"로 교체. OK

## 2026-10-18 (7차 - 문서만, 빌드 불필요)

- **[문서]** README에 포트 안내(https 443 / http 80, 생략 가능)와 연결 실패 한국어 안내 동작을 추가. 코드 변경 없음.
- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0 (NAS형 아이콘 v3 포함 dist/TruNAS.app 재생성). OK
- **[아이콘 v3]** NAS 장비형 재디자인: 랙마운트 스토리지 박스 + 드라이브 베이 4개(트레이·환기구·LED - 3번 베이 주홏, 나머지 초록) + 코너 리벳 + 하단 LAN 포트 2개 + 전원 LED. icns/ico 재생성. OK
  - 수정 과정: URLError 서버 인증서 코드 중 존재하지 않는 serverCertificateExpired 제거 후 빌드 성공.
- **[연결오류/한국어]** Swift 앱의 영어 원문 오류("Could not connect to the server." 등) 한국어 매핑: URLError 코드별 안내(호스트 없음/연결 거부/네트워크 없음/초과/TLS 인증서). Python도 requests 원문 오류를 키워드별 한국어로 변환(_friendly_connection_error).
- **[포트/연결]** 연결 설정 화면에 관리 API 기본 포트 안내 추가(https 443 / http 80, 보통 공란) + 포트 선택 필드 추가(비워두면 기본, 입력 시 호스트 뒤에 자동 부착). 주소에 직접 'host:8443' 형식으로 쓰는 것도 지원.

## 2026-10-18 (6차)

- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0 (NAS형 아이콘 v3 포함 dist/TruNAS.app 재생성). OK
- **[아이콘 v3]** NAS 장비형 재디자인: 랙마운트 스토리지 박스 + 드라이브 베이 4개(트레이·환기구·LED - 3번 베이 주홏, 나머지 초록) + 코너 리벳 + 하단 LAN 포트 2개 + 전원 LED. icns/ico 재생성. OK
  - 수정 과정: URLError 서버 인증서 코드 중 존재하지 않는 serverCertificateExpired 제거 후 빌드 성공.
- **[연결오류/한국어]** Swift 앱의 영어 원문 오류("Could not connect to the server." 등) 한국어 매핑: URLError 코드별 안내(호스트 없음/연결 거부/네트워크 없음/초과/TLS 인증서). Python도 requests 원문 오류를 키워드별 한국어로 변환(_friendly_connection_error).
- **[포트/연결]** 연결 설정 화면에 관리 API 기본 포트 안내 추가(https 443 / http 80, 보통 공란) + 포트 선택 필드 추가(비워두면 기본, 입력 시 호스트 뒤에 자동 부착). 주소에 직접 'host:8443' 형식으로 쓰는 것도 지원.

## 2026-10-18 (5차)

- **[python/수정]** 시작 시 저장된 언어 설정이 API 오류 메시지에 바로 적용되도록 main()에서 set_language 호출 추가(정의 순서 NameError 수정 포함). 재검증: py_compile OK + 6초 smoke OK.
- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0 (아이콘 v2 포함 dist/TruNAS.app 재생성). OK
- **[아이콘 v2]** 재디자인: 남색 드라이브 -> 트루나스 블루 그라데이션 + 흰색 데이터 레이어 스택(3장) + LED 도트. icns/ico 재생성 완료. OK
  - 수정 과정: SettingsView에 다중행 T() 문자열 이어쓰기 문법 오류(쉼표 누락) 위치 수정 후 빌드 성공.
- **[테일스케일]** Tailscale 매직DNS(*.ts.net) 또는 100.x.x.x IP로 API 연결 지원: 주소 정규화 문서화, 연결 설정 화면에 안내 문구 추가(두 앱 모두). 기존 normalize 동작으로 이미 호환됨 - 실장비 검증은 미수행.
- **[언어설정]** 한국어/English 표시 언어 설정 추가 (macOS UserDefaults, Windows QSettings).
  - 연결 테스트/오류 안내 문구 현지화: HTTP 코드별 한국어 안내(401/403 인증 실패, 404 엔드포인트 없음, 5xx 서버 오류 등) + 원본 API 오류 상세를 괄호로 함께 표시.
  - 적용 범위: 연결 설정 화면 전체 + 상태 메시지 + API 오류. 목록/폼 등 일반 화면 문구는 한국어 고정(차후 확장 가능).

## 2026-10-18 (4차)

- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0, `./package.sh` PKG_EXIT=0 (아이콘 v2 포함 dist/TruNAS.app 재생성). OK
- **[아이콘 v2]** 재디자인: 남색 드라이브 -> 트루나스 블루 그라데이션 + 흰색 데이터 레이어 스택(3장) + LED 도트. icns/ico 재생성 완료. OK
  - 수정 과정: SettingsView에 다중행 T() 문자열 이어쓰기 문법 오류(쉼표 누락) 위치 수정 후 빌드 성공.
- **[테일스케일]** Tailscale 매직DNS(*.ts.net) 또는 100.x.x.x IP로 API 연결 지원: 주소 정규화 문서화, 연결 설정 화면에 안내 문구 추가(두 앱 모두). 기존 normalize 동작으로 이미 호환됨 - 실장비 검증은 미수행.
- **[언어설정]** 한국어/English 표시 언어 설정 추가 (macOS UserDefaults, Windows QSettings).
  - 연결 테스트/오류 안내 문구 현지화: HTTP 코드별 한국어 안내(401/403 인증 실패, 404 엔드포인트 없음, 5xx 서버 오류 등) + 원본 API 오류 상세를 괄호로 함께 표시.
  - 적용 범위: 연결 설정 화면 전체 + 상태 메시지 + API 오류. 목록/폼 등 일반 화면 문구는 한국어 고정(차후 확장 가능).

## 2026-10-18 (3차)

- **[전체/검증]** `./build.sh --smoke` -> swift_build=1 py_compile=1 smoke=1, SCRIPT_EXIT=0. OK
- **[mac/패키징]** `./package.sh` -> release 재빌드 + `dist/TruNAS.app` 재생성, `Contents/Resources/AppIcon.icns` 포함, 5초 smoke 통과, PKG_EXIT=0. OK
- **[아이콘]** `Tools/make_icon.py` 실행 -> AppIcon.iconset PNG 10종 + `Tools/AppIcon.icns`(iconutil 변환) + `WindowsApp/TrueNAS.ico`(Pillow) 생성 완료. OK
  - 디자인: 남색 그라데이션 라운드 스퀘어 + 드라이브 몸체/슬랫/스핀들 + LED 3개.
  - 수정 과정: QPixmap은 QGuiApplication 생성 이후에만 사용 가능 -> 스크립트 상단에 앱 인스턴스 생성 추가.
- **[mac/빌드]** Swift 카테고리 확장 전체 빌드 -> `Build complete! (3.14초)`. OK
  - 수정 과정: NavItem 중복 선언(AppModel/RootView) 제거, severityIcon 공용화, GenericEntityView 형식 추론 과부하 및 macOS 13 호환(foregroundColor 사용) 정리.
- **[python/검증]** 카테고리 사이드바 구조로 main.py 대규모 확장 후 smoke -> 7초 정상 기동. OK
  - 수정 과정: EntitySpec에 read_only 누락 속성 추가, 사용자 생성 필드 복원, 종속성 중복 정리.

## 2026-10-18 (2차)

- **[python/근본원인]** Qt platform plugin 반복 크래시의 원인 확정: **프로젝트 경로의 한글·공백**이 원인. 근거 - 동일 PySide6를 `/tmp` (ASCII 경로)에 복사해 로드하면 `QAPP_OK`. OK
  - 해결 1: main.py에서 플러그인 경로를 import 전에 명시적으로 설정.
  - 해결 2: venv를 한글/공백 없는 안정 경로 `$HOME/.tnvenv`로 재생성 (PySide6/requests/pillow). 기존 `.venv` 제거.
  - build.sh: venv를 자동 생성·사용하도록 갱신.
- **[python/기능]** TrueNAS 웹 UI 기능 대폭 확장 - 카테고리별 사이드바(QTreeWidget/QStackedWidget) + 사양 기반 범용 목록/생성/삭제 엔진. 기능 카탈로그: 시스템(대시보드/알림/서비스 토글), 스토리지(풀/데이터셋/디스크/스냅샷/복제/스크럽), 공유(SMB/NFS/WebDAV/iSCSI), 네트워크(인터페이스), 계정(사용자/그룹), 작업(Cron/Rsync/CloudSync), 보안(인증서).
- **[python/API]** truenas_api.py에 서비스 시작/중지, 스크럽 작업/실행, 알림 무시(dismiss) 엔드포인트 추가.
- **[mac/기능]** 동일 카테고리 구성으로 SwiftUI 확장: 사양 기반 GenericEntityView(목록/생성/삭제), 알림 무시, 서비스 시작/중지 토글, 스크럽 수동 실행.
- **[mac/버그]** 아이피만 입력 시 연결 테스트 실패 원인: TruenasClient가 원본 문자열을 그대로 URL로 사용 -> normalizeBaseURL 적용으로 수정.

## 2026-10-18 (1차)

- **[도구]** `package.sh` 추가: release 빌드 -> dist/TruNAS.app 번들 생성, ad-hoc 서명, smoke 후 연결 테스트. `WindowsApp/build_exe.bat` 추가 (exe는 Windows에서만 빌드 가능).
- **[mac/패키징]** `dist/TruNAS.app` 생성 및 `open` 실행 확인. OK
- **[전체/검증]** `./build.sh --smoke` SCRIPT_EXIT=0. OK
- **[python/검증]** PySide6 force-reinstall 후 QApplication 생성 확인. OK (부분 증상이었다가 2차에서 근본 원인 확정)
- **[문서]** rule.md 규칙 추가: 이모지 금지, 코드 수정 시 자동 빌드(build.sh).

## 2026-10-17

- **[python/실행]** `.venv/bin/python WindowsApp/main.py` 기동 확인(recurring issue는 위 2차 항목 참고). OK
- **[python/의존성]** venv 생성 및 pip 설치. OK
- **[mac/실행]** `MacApp/.build/debug/TruNASApp` 기동 확인. OK
- **[mac/빌드]** `DEVELOPER_DIR=/Volumes/hub/Applications/Xcode.app/Contents/Developer swift build` 최초 성공. OK (CLT 단독은 SwiftUI 매크로 플러그인 없어서 FAIL - rule.md 2.1)
- **[API/검증]** https://api.truenas.com/v25.10.0/ 메서드 확인. 실장비 응답 형식은 미검증.
