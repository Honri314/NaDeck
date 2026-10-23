# 개발 규칙 (rule.md)

TrueNAS 관리 프로그램 개발 시 반드시 지키는 규칙. 코드/기능을 수정할 때마다 이 문서도 필요하면 갱신한다.

## 0. 문서 규칙

1. **이모지 사용 금지.** 모든 문서와 로그(buildlog.md 포함)에 이모지를 사용하지 않는다. 상태는 텍스트로 표기한다 (`OK` / `FAIL`).
2. 빌드·실행·테스트를 수행할 때마다 buildlog.md 최상단에 날짜와 함께 한 줄씩 기록한다.
3. README.md는 기능·사용법이 바뀌면 함께 갱신한다.
4. 새 규칙이나 예외가 생기면 이 rule.md에 추가한다.

## 1. 자동 빌드 (매번)

1. **코드를 수정할 때는 항상 그 직후 앱을 자동으로 빌드하고 검증한다.** 사용자가 요청하지 않아도 수행한다.
2. 검증은 프로젝트 루트의 `build.sh`로 통일한다:
   - `./build.sh` : Swift 빌드 + Python 컴파일 체크
   - `./build.sh --smoke` : 위 내용 + 두 앱 6초 실행 smoke test (주요 변경 시 이 옵션 사용)
3. 종료 코드(`SCRIPT_EXIT`)를 확인한다. 필터된 출력만 보고 성공이라고 판단하지 않는다.
4. 실패하면 원인을 고친다. 테스트를 건너뛰거나 오류를 무시해서 "성공"으로 만들지 않는다. 주석 처리·약한 검증으로 우회 금지.

## 2. 빌드 환경 (이 기기 기준)

1. Swift 빌드는 반드시 아래 DEVELOPER_DIR 사용 (CLT에는 SwiftUI 매크로 플러그인이 없다):
   과거에는 /Volumes/hub 볼륨의 Xcode를 사용했다가, 지금은 /Applications에 설치된 Xcode를 사용한다.
   ```bash
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   ```
2. Python 실행은 프로젝트 루트의 `.venv` 사용:
   ```bash
   .venv/bin/python WindowsApp/main.py
   ```
3. venv 의존성 설치(`pip install`) 후에는 smoke 테스트로 정상 로드까지 확인한다. 특히 PySide6는 설치가 불완전하면 Qt platform plugin 로드가 실패하므로, 실패 시 `pip install --force-reinstall PySide6`로 재설치한다.

## 3. 검증 규칙

1. 모든 코드 변경 후 실제로 돌려본다.
2. API는 실제 TrueNAS 장비에서 검증되지 않은 경우 그 한계를 코드·문서에 명시한다. (현재: 문서 기준 25.10 양식으로 작성, 실장비 응답 미검증)

## 4. 코드 컨벤션

1. UI 텍스트는 한국어로 통일한다.
2. TrueNAS 필드명(snake_case)은 API 원본 그대로 사용하고, Swift 모델의 불확실한 필드는 옵셔널 + 유연 디코딩으로 처리한다.
3. 파괴적 작업(삭제 계열)은 반드시 확인 대화상자를 통과시킨다.
4. API 키 등 민감정보는 소스에 넣지 않고, 앱의 저장소(UserDefaults/QSettings)에만 보관한다.
5. 공유 폴더 경로는 `/mnt/...` 형식만 허용한다.

## 5. 범위 제한

1. 사용자가 요청하지 않은 외부 시스템(트루나스 장비 데이터 삭제, 원격 배포 등)을 임의로 조작하지 않는다.
2. 자동 빌드는 로컬 빌드·검증에 한하며, 배포나 푸시는 사용자가 명시적으로 요청할 때만 한다.
