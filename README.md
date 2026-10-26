# SimLauncher

iPhone·iPad 가 없는 인원이 Mac 만으로 개발 중인 iOS 앱을 테스트할 수 있게 해 주는 Mac 앱이다. iOS 시뮬레이터를 직접 띄우고, 로컬 .app 파일이나 네트워크에 올려진 .app 을 시뮬레이터에 설치·실행한다.

**비개발자도 Xcode 설치·라이선스 동의·첫 실행 준비(앱이 단계별로 안내) 외에는 터미널·Xcode 조작 없이, 앱 화면에서 시뮬레이터 실행과 iOS 앱 설치·실행을 끝낼 수 있다.** 네트워크는 사용자가 등록한 빌드 카탈로그(`catalog.json`)와, 사용자가 고르거나 입력한 URL 에서 iOS 앱 빌드(.app 또는 .app 을 담은 zip)를 내려받을 때, 사용자가 설치를 고를 때 쓸 Xcode 의 기본 iOS 시뮬레이터 런타임을 Apple 서버에서 설치할 때만 쓴다. 공개 레포로, 어느 회사든 자기 빌드 저장소에 맞춰 쓸 수 있게 한다.

## 핵심 기능 (MVP)
- Xcode·iOS 시뮬레이터 런타임 확인과 설치 안내 (런타임은 앱에서 설치)
- 시뮬레이터 기기 목록, 부팅·종료, 생성·삭제·초기화, Simulator 앱 띄우기
- 로컬 .app(또는 zip) 을 골라 시뮬레이터에 설치·실행, 딥링크 열기
- URL 의 .app(zip) 을 내려받아 설치
- 켜진 기기 화면 스크린샷 (사진 폴더의 SimLauncher 폴더에 PNG 로 저장, Finder 에서 보이기)
- 빌드 카탈로그: 설정 창(⌘,)에 카탈로그 URL 을 등록하고, 기기 행 "앱 설치 > 카탈로그에서…" 의 앱·버전 목록에서 골라 설치. 카탈로그는 정적 `catalog.json` 하나라 GitHub Releases·S3·사내 웹 서버 어디에 둬도 된다 ([규격](docs/CATALOG.md))

## 샘플 카탈로그
레포의 GitHub Actions 예시 워크플로가 샘플 iOS 앱을 빌드해 Releases 에 올리고 카탈로그를 만든다. 앱 설정 창에 아래 주소를 등록하면 "카탈로그에서…" 로 샘플 앱을 설치해 볼 수 있다.

```
https://github.com/zopandagom/simlauncher-macos/releases/download/sample-catalog/catalog.json
```

- 새 빌드 올리기: Actions > Sample Catalog > Run workflow 를 **main 에서** 실행한다. 워크플로 파일이 main 과 다른 브랜치에서 실행하면 GitHub 이 릴리스 생성을 거절한다(draft 릴리스가 남을 수 있다. 카탈로그에는 영향이 없고 손으로 지운다).
- 동작, 자기 앱에 맞게 바꿀 곳, 재실행·정리 방법: [CATALOG.md 11절](docs/CATALOG.md#11-github-actions-예시)

## 기술 스택
- SwiftUI (규칙 기반 단방향 MV), Swift 6 strict concurrency, macOS 26.0+
- Tuist 모듈러 아키텍처 (Feature / Client Interface·Impl·Testing / Shared)
- Foundation `Process` 로 `xcrun simctl` 등 실행 (Command Client Impl)
- Foundation `URLSession` 으로 카탈로그·빌드 다운로드 (Download Client Impl)
- Foundation `UserDefaults` 로 사용자 설정(카탈로그 주소) 저장 (Preferences Client Impl)
- AppKit `NSWorkspace` 로 Finder 에서 보이기, Foundation `FileManager` 로 사진 폴더에 스크린샷 저장 폴더 준비·파일 이름 예약 (Workspace Client Impl)
- 필요 환경: Xcode 와 iOS 시뮬레이터 런타임 (이 앱을 쓰는 Mac 에도 필요. 런타임은 없으면 앱의 "개발 환경" 화면에서 Xcode 의 기본 iOS 버전을 설치할 수 있다)

## 시작하기
```bash
make bootstrap   # mise 로 tuist·swiftlint·swiftformat·xcbeautify 설치, git 훅(pre-commit: main 커밋 차단·String Catalog stale 표시 차단·lint, pre-merge-commit: main 머지 커밋 차단, pre-push: main push 차단) 연결
make generate    # SimLauncher.xcworkspace 생성 후 Xcode 로 열기
make test        # 전체 모듈 빌드 + 테스트 + git 훅 테스트
make test-hooks  # git 훅 동작 테스트만 (임시 레포에서 main 커밋·머지 커밋·push 차단, String Catalog stale 표시 커밋 차단과 기능 브랜치 통과 확인)
make lint        # 포맷·아키텍처 규칙 검사 (make format 으로 자동 수정)
make sample      # 샘플 iOS 앱을 시뮬레이터용으로 빌드해 build/SampleApp.zip 으로 묶기 (SAMPLE_BUILD_NUMBER=42 로 빌드 번호)
make catalog-check CATALOG=catalog.json   # catalog.json 하나를 앱과 같은 규칙으로 검사
make catalog-test  # 샘플 카탈로그 생성기·검증기 회귀 테스트
```

## 문서
- [아키텍처](docs/ARCHITECTURE.md)
- [개발 규칙: 해야 할 것 / 하지 말아야 할 것](docs/CONVENTIONS.md)
- [개발 계획과 로드맵](docs/DEVELOPMENT_PLAN.md)
- [빌드 카탈로그 규격](docs/CATALOG.md)
- [Claude Code 작업 안내](CLAUDE.md)

이 프로젝트는 [ios-harness](https://github.com/zopandagom/ios-harness) 템플릿으로 만들었다 (`.harness-version`).

## 라이선스
[MIT](LICENSE)
