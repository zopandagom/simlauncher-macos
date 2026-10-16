# SimLauncher

iPhone·iPad 가 없는 사내 인원이 Mac 만으로 개발 중인 iOS 앱을 테스트할 수 있게 해 주는 Mac 앱이다. iOS 시뮬레이터를 직접 띄우고, 로컬 .app 파일이나 네트워크에 올려진 .app 을 시뮬레이터에 설치·실행한다.

**비개발자도 Xcode 설치 외에는 터미널·Xcode 조작 없이, 앱 화면에서 시뮬레이터 실행과 iOS 앱 설치·실행을 끝낼 수 있다.** 네트워크는 사용자가 입력한 URL 에서 iOS 앱 빌드(.app 또는 .app 을 담은 zip)를 내려받을 때만 쓴다.

## 핵심 기능 (MVP)
- 시뮬레이터 기기 목록 보기, 고른 기기 부팅과 Simulator 앱 띄우기
- 로컬 .app 파일을 골라 시뮬레이터에 설치
- URL 의 .app(zip) 을 내려받아 시뮬레이터에 설치
- 설치한 앱 실행
- Xcode·iOS 시뮬레이터 런타임이 없으면 설치 안내

## 기술 스택
- SwiftUI (규칙 기반 단방향 MV), Swift 6 strict concurrency, macOS 26.0+
- Tuist 모듈러 아키텍처 (Feature / Client Interface·Impl·Testing / Shared)
- Foundation `Process` 로 `xcrun simctl` 실행 (Simulator Client Impl)
- Foundation `URLSession` 으로 빌드 다운로드 (Download Client Impl)
- 필요 환경: Xcode 와 iOS 시뮬레이터 런타임 (이 앱을 쓰는 Mac 에도 필요)

## 시작하기
```bash
make bootstrap   # mise 로 tuist·swiftlint·swiftformat·xcbeautify 설치, git 훅(pre-commit: main 커밋 차단·lint, pre-merge-commit: main 머지 커밋 차단, pre-push: main push 차단) 연결
make generate    # SimLauncher.xcworkspace 생성 후 Xcode 로 열기
make test        # 전체 모듈 빌드 + 테스트 + git 훅 테스트
make test-hooks  # git 훅 동작 테스트만 (임시 레포에서 main 커밋·머지 커밋·push 차단과 기능 브랜치 통과 확인)
make lint        # 포맷·아키텍처 규칙 검사 (make format 으로 자동 수정)
```

## 문서
- [아키텍처](docs/ARCHITECTURE.md)
- [개발 규칙: 해야 할 것 / 하지 말아야 할 것](docs/CONVENTIONS.md)
- [개발 계획과 로드맵](docs/DEVELOPMENT_PLAN.md)
- [Claude Code 작업 안내](CLAUDE.md)

이 프로젝트는 [ios-harness](https://github.com/zopandagom/ios-harness) 템플릿으로 만들었다 (`.harness-version`).
