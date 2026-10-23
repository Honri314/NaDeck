# 다운로드 사이트 (Website/)

TrueNAS에서 **pm2**로 돌아가는 기존 Node 서비스들과 같은 방식으로,
이 앱의 다운로드 페이지를 호스팅합니다 (표준 라이브러리만 쓰는 Python 서버).

## 구성

```
Website/
  index.html             다운로드 페이지 (한국어)
  server.py              표준 라이브러리 정적 서버 (기본 포트 8181)
  ecosystem.config.js    pm2 설정
  make_releases.py       다운로드 zip 생성 (macOS 앱 zip / Windows zip / 전체 소스 zip)
  releases/              생성된 다운로드 파일들
```

## TrueNAS에서 실행 (pm2)

TrueNAS SCALE에는 python3가 기본 포함되어 있습니다.

```bash
# 1) 사이트 폴더를 TrueNAS에 올립니다 (예: /mnt/tank/apps/truenas-manager/Website)

# 2) 다운로드 zip 생성 (macOS에서 먼저 만들어 올린 후 server.py만 서빙해도 됩니다)
python3 Website/make_releases.py

# 3) pm2로 실행
pm2 start Website/ecosystem.config.js
pm2 save

# 상태/로그
pm2 status
pm2 logs truenas-downloads
```

인터프리터 경로가 다르면 `ecosystem.config.js`의 `interpreter`를 조정하세요.

## 로컬(안) 확인

```bash
python3 Website/server.py 8181
# 브라우저: http://<NAS-IP>:8181
```

## 외부 접속 (TrueNAS 터널/프록시)

TrueNAS의 **앱 프록시/공유 터널 기능**(Share electrum Funnel 등)으로
pm2 서버 포트(예: 8181)를 외부에 노출할 수 있습니다.

요령:
1. TrueNAS 웹 UI에서 앱/서비스 프록시 설정으로 `127.0.0.1:8181` 또는 NAS IP:8181을 노출
2. 외부에서는 제공된 터널 주소로 접속

이 사이트는 systems/hivedesk/maccleaner처럼 **같은 터널 주소 뒤에 경로를 붙여** 접속할 수 있습니다:
- 터널에서 경로 `/nadeck`이 `127.0.0.1:8181`로 매핑되면
- 접속: `https://<터널주소>/nadeck/` (슬래시 없이 `/nadeck` 입력 시 자동 리다이렉트)
- 지원 접두사: `nadeck`, `downloads`, `deck` (`server.py`의 PATH_PREFIXES에서 수정 가능)
- 직접 접속(접두사 없이 `http://NAS-IP:8181`)도 그대로 동작

경로 추가 접속 검증 완료: /nadeck -> 301 리다이렉트, /nadeck/ -> 페이지 200, /nadeck/releases/NaDeck-Windows.zip -> 200

보안 주의: 다운로드 페이지는 공개되어도 되지만,
약한 파일 이름이라도 **인증된 사용자만** 접근하도록 터널 쪽에서 접근 제어를 넣는 것이 좋습니다.

## 새 버전 배포 절차

```bash
# (로컬 개발 맥에서)
./package.sh                            # dist/NaDeck.app 갱신
python3 Website/make_releases.py        # Website/releases/*.zip 갱신
# Website/ 폴더를 TrueNAS로 복사/동기화 (rsync 등)
```
