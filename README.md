# SimLauncher

iPhone·iPad 가 없어도 Mac 만으로 개발 중인 iOS 앱을 테스트할 수 있게 해 주는 Mac 앱이다. iOS 시뮬레이터 기기를 켜고, 개발자가 준 iOS 앱 빌드(.app 또는 .app 을 담은 zip)를 시뮬레이터에 설치·실행한다.

**비개발자도 Xcode 설치·라이선스 동의·첫 실행 준비(앱이 단계별로 안내) 외에는 터미널·Xcode 조작 없이, 앱 화면에서 시뮬레이터 실행과 iOS 앱 설치·실행을 끝낼 수 있다.**

![기기 목록](docs/media/device-list.png)

- [설치](#설치) · [첫 실행 준비](#첫-실행-준비) · [사용법](#사용법) · [회사 빌드 카탈로그 등록](#회사-빌드-카탈로그-등록) · [문제 해결](#문제-해결)
- 개발자용: [개발](#개발)

## 요구 사항
- macOS 26 이상
- Xcode (App Store 에서 무료로 설치). 설치하지 않았다면 앱이 첫 실행 때 안내한다.
- iOS 시뮬레이터. Xcode 에 들어 있지 않다면 앱의 "개발 환경" 화면에서 설치할 수 있다.

## 설치
1. [GitHub Releases 최신 페이지](https://github.com/zopandagom/simlauncher-macos/releases/latest)에서 `SimLauncher-<버전>.dmg`(예: `SimLauncher-1.0.0.dmg`)를 내려받는다.
2. dmg 를 열고 **SimLauncher** 를 **Applications**(응용 프로그램) 폴더로 끌어다 놓는다.

   ![dmg 창](docs/media/install-dmg.png)

3. 응용 프로그램 폴더에서 SimLauncher 를 연다. 인터넷에서 받은 앱이라 처음 한 번 "열겠습니까?" 확인이 뜨면 **열기** 를 누른다. 앱은 Apple 의 공증을 받아 다른 경고 없이 열린다.

## 첫 실행 준비
앱을 열면 Xcode 가 준비되었는지 확인한다. 준비되어 있으면 바로 기기 목록이 열린다. 준비되지 않은 단계가 있으면 그 단계만 안내하고, 각 단계를 마치고 이 앱으로 돌아오면 자동으로 다시 확인한다.

| 단계 | 화면 제목 | 할 일 |
|---|---|---|
| Xcode 설치 | Xcode 를 설치하세요 | **App Store 열기** 를 눌러 Xcode 를 설치한다. 내려받는 데 시간이 걸릴 수 있다. |
| 라이선스 동의 | Xcode 라이선스에 동의하세요 | **Xcode 열기** 를 누르면 Xcode 가 라이선스 동의 창을 띄운다. 관리자 암호가 필요하다. |
| 첫 실행 준비 | Xcode 첫 실행 준비를 마치세요 | **Xcode 열기** 를 누르면 Xcode 가 추가 구성요소를 설치하는 창을 띄운다. 끝날 때까지 기다린다. 관리자 암호가 필요하다. |
| iOS 시뮬레이터 설치 | iOS 시뮬레이터를 설치하세요 | 위 단계를 이 화면에서 마쳤는데 iOS 시뮬레이터가 없으면 보인다. **iOS 시뮬레이터 설치** 를 누르면 이 Xcode 에 맞는 iOS 버전을 Apple 서버에서 받아 설치한다. 창을 닫아도 설치는 계속된다. 이미 다른 iOS 버전의 기기가 있으면 설치하지 않고 넘어가도 된다. |

단계를 마치면 "준비가 끝났습니다" 가 보인다. **기기 목록 열기** 를 누른다.

Xcode 는 준비되었지만 iOS 시뮬레이터가 없는 채로 기기 목록이 열리면, 목록에 "iOS 시뮬레이터가 설치되어 있지 않습니다" 가 보인다. 그 아래 **iOS 설치** 를 눌러 설치한다. 언제든 기기 목록 오른쪽 위의 **개발 환경** 을 누르면 이 화면을 다시 열어 상태를 확인하고 iOS 시뮬레이터를 설치할 수 있다.

![준비가 끝난 화면](docs/media/setup-ready.png)

## 사용법
기기 목록은 iOS 버전별로 iPhone·iPad 시뮬레이터 기기를 보인다. 행마다 오른쪽에 그 기기의 버튼이 있다.

### 기기 켜기·끄기
행의 **켜기** 를 누르면 기기를 켜고 Simulator 앱 창에 기기 화면을 띄운다. 켜진 기기는 **끄기** 로 끈다.

![기기 켜기](docs/media/boot-device.gif)

### 기기 만들기
오른쪽 위 **+**(기기 만들기)를 누르고 이름·iOS 버전·기기 종류를 고른 뒤 **만들기** 를 누른다.

![새 기기 만들기](docs/media/create-device.png)

### 기기 초기화·삭제
행 끝의 **…**(기기 작업) 메뉴에서 **초기화…** 또는 **삭제…** 를 고른다. 초기화는 설치한 앱·데이터·설정을 모두 지워 처음 상태로 돌리고, 삭제는 기기를 없앤다. 둘 다 되돌릴 수 없어 한 번 더 확인하며, 기기를 끈 뒤에만 할 수 있다.

![기기 작업 메뉴](docs/media/device-actions.png)

### 앱 설치·실행
행의 **앱 설치** 메뉴에서 빌드를 가져올 곳을 고른다. 기기가 꺼져 있으면 켜고, 설치가 끝나면 앱을 바로 실행한다.

![앱 설치 메뉴](docs/media/install-menu.png)

- **파일에서 고르기…**: Mac 에 있는 시뮬레이터용 .app 이나 그 .app 을 압축한 zip 을 고른다. 파일을 기기 행에 끌어다 놓아도 된다.
- **URL 에서…**: zip 파일의 `https://` 주소를 입력하고 **받아서 설치** 를 누른다. 받는 동안 행에 진행률이 보이고 취소할 수 있다. 로그인이 필요한 주소에서는 받을 수 없다.

  ![URL 에서 앱 설치](docs/media/install-url.png)

- **카탈로그에서…**: 설정에 등록한 [빌드 카탈로그](#회사-빌드-카탈로그-등록)의 앱과 버전 목록에서 골라 **받아서 설치** 를 누른다.

  ![카탈로그에서 앱 설치](docs/media/catalog-install.png)

  ![카탈로그에서 설치하는 모습](docs/media/install-catalog.gif)

> iOS 기기용 `.ipa` 나 Mac 용 앱은 시뮬레이터에 설치할 수 없다. 개발자에게 **시뮬레이터용으로 빌드한 .app**(또는 그 zip)을 달라고 한다.

### 링크 열기
행의 **링크 열기…** 를 누르고 앱 스킴 링크(딥링크, 예: `myapp://item/1`)나 웹 주소를 입력한 뒤 **열기** 를 누르면 그 기기에서 연다. 기기가 꺼져 있으면 켠다.

![링크 열기](docs/media/open-url.png)

### 여러 기기에 한 번에
목록에서 ⌘ 키를 누른 채 클릭하면 여러 대를, ⇧ 키를 누른 채 클릭하면 사이의 기기를 함께 고른다. 그다음 툴바에서 고른다.
- **선택한 기기에 앱 설치**: 파일·URL·카탈로그 중 하나로 같은 빌드를 고른 기기 모두에 설치하고 실행한다. 빌드는 한 번만 받는다. 설치할 수 없는 기기는 건너뛰고, 실패한 기기는 알림 하나에 이유와 함께 모아 보인다.
- **선택한 기기 켜기**: 고른 기기 중 꺼진 기기를 함께 켠다.

![선택한 기기에 앱 설치 메뉴](docs/media/multi-select.png)

![여러 기기에 설치하는 모습](docs/media/multi-install.gif)

### 스크린샷
켜진 기기 행의 **스크린샷** 을 누르면 기기 화면을 **사진** 폴더의 `SimLauncher` 폴더에 PNG 로 저장하고 Finder 에서 보여 준다.

![스크린샷](docs/media/screenshot.gif)

### 화면 녹화
켜진 기기 행의 **녹화** 를 누르면 녹화를 시작하고, 행에 녹화 시간과 **중지** 가 보인다. **중지** 를 누르면 **동영상** 폴더의 `SimLauncher` 폴더에 저장하고 Finder 에서 보여 준다. 녹화 중에는 그 기기를 끄거나 초기화·삭제할 수 없다. 녹화 중에 앱을 종료하면 녹화를 저장하고 종료할지 묻는다.

![녹화 중인 기기](docs/media/recording.png)

## 회사 빌드 카탈로그 등록
빌드 카탈로그는 회사가 올려 둔 앱 빌드 목록(`catalog.json` 파일 하나)이다. 등록해 두면 빌드 주소를 매번 입력하지 않고 "카탈로그에서…" 목록에서 골라 설치한다.

1. 메뉴 막대의 **SimLauncher > 설정…**(⌘,)을 연다.
2. **빌드 카탈로그** 의 "카탈로그 주소" 칸에 담당자에게 받은 `https://` 주소를 입력하고 **등록** 을 누른다.
3. 앱이 주소를 한 번 받아 형식을 확인한다. "등록했습니다. 앱 N개가 있습니다." 가 보이면 끝이다. 카탈로그는 여러 개 등록할 수 있고, 휴지통 버튼으로 지운다.

![설정 창의 빌드 카탈로그](docs/media/settings-catalog.png)

먼저 써 보려면 이 레포의 샘플 카탈로그를 등록한다.

```
https://github.com/zopandagom/simlauncher-macos/releases/download/sample-catalog/catalog.json
```

- 회사 관리자가 카탈로그 목록을 미리 정해 두었다면, 설정 창에 "관리자가 정한 목록이라 이 Mac 에서 바꿀 수 없습니다." 가 보이고 등록·삭제를 할 수 없다.
- 카탈로그를 만드는 쪽(개발자·관리자)은 [빌드 카탈로그 규격](docs/CATALOG.md)을 본다. GitHub Releases·S3·사내 웹 서버 어디에 두어도 되고, 로그인 없이 받을 수 있는 `https://` 주소면 된다.

## 문제 해결
앱의 알림과 안내 문구에 이유와 할 일이 함께 나온다. 자주 만나는 경우는 다음과 같다.

| 증상 | 할 일 |
|---|---|
| 기기가 켜지지 않거나 목록이 비어 있음 | 오른쪽 위 **개발 환경** 을 눌러 Xcode 준비 상태를 확인한다. 계속 실패하면 Mac 을 재시동한다. |
| 기기 행이 "사용할 수 없음" | 그 기기의 iOS 버전이 이 Mac 에 없거나 지금 Xcode 가 그 기기를 지원하지 않는다. **개발 환경** 에서 iOS 시뮬레이터를 설치하거나, 다른 기기를 쓴다. 쓸 일이 없으면 기기 작업 메뉴에서 삭제한다. |
| "iOS 시뮬레이터용 빌드가 아닙니다", ".ipa 파일은 설치할 수 없습니다" | 개발자에게 시뮬레이터용으로 빌드한 .app(또는 그 zip)을 요청한다. |
| "이 앱은 iOS … 이상에서 실행됩니다" | 더 높은 iOS 버전의 기기에 설치한다. 없으면 기기 만들기로 만든다. |
| "zip 맨 위에 .app 이 없습니다" / "여러 개 있습니다" | .app 하나를 바로 압축한 zip 이어야 한다. 빌드를 준 사람에게 알린다. |
| URL·카탈로그에서 받지 못함 ("서버 주소를 찾지 못했습니다", "서버에 연결하지 못했습니다") | 주소 철자를 확인한다. 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인한다. |
| "서버가 로그인이나 접근 권한을 요구해 받지 못했습니다" | 로그인이 필요한 주소는 쓸 수 없다. 로그인 없이 받을 수 있는 주소를 담당자에게 받는다. |
| "https:// 로 시작하는 주소만 …" | `http://` 주소는 쓸 수 없다. `https://` 주소를 쓴다. |
| 카탈로그 "형식이 맞지 않아 읽지 않았습니다" / "JSON 객체로 읽지 못했습니다" | 주소가 로그인 페이지 같은 웹 페이지가 아니라 `catalog.json` 파일을 바로 가리키는지 확인하고, 맞다면 카탈로그를 만든 사람에게 알린다. |
| "이 카탈로그는 이 앱보다 새 규격 …" | SimLauncher 를 [최신 버전](https://github.com/zopandagom/simlauncher-macos/releases/latest)으로 업데이트한다. |
| 설치 뒤 "앱이 시작되지 않았거나 시작하자마자 종료되었습니다" | 시뮬레이터에서 앱 아이콘을 눌러 다시 실행해 보고, 계속되면 앱 개발자에게 알린다. |
| 기기를 끄거나 초기화·삭제할 수 없음 | 녹화 중이면 녹화를 먼저 멈춘다. 초기화·삭제는 기기를 끈 뒤에 할 수 있다. |

## 네트워크 사용
앱은 다음 세 경우에만 네트워크를 쓴다.
- 등록한 빌드 카탈로그(`catalog.json`)를 받을 때
- 고르거나 입력한 URL 에서 iOS 앱 빌드(.app 또는 .app 을 담은 zip)를 받을 때
- 설치를 고른 iOS 시뮬레이터를 Apple 서버에서 받을 때

---

## 개발
공개 레포로, 어느 회사든 자기 빌드 저장소에 맞춰 쓸 수 있게 한다.

### 기술 스택
- SwiftUI (규칙 기반 단방향 MV), Swift 6 strict concurrency, macOS 26.0+
- Tuist 모듈러 아키텍처 (Feature / Client Interface·Impl·Testing / Shared)
- Foundation `Process` 로 `xcrun simctl` 등 실행 (Command Client Impl)
- Foundation `URLSession` 으로 카탈로그·빌드 다운로드 (Download Client Impl)
- Foundation `UserDefaults` 로 사용자 설정(카탈로그 주소) 저장 (Preferences Client Impl)
- AppKit `NSWorkspace` 로 Finder 에서 보이기, Foundation `FileManager` 로 사진·동영상 폴더에 스크린샷·녹화 저장 폴더 준비·파일 이름 예약 (Workspace Client Impl)

### 시작하기
```bash
make bootstrap   # mise 로 tuist·swiftlint·swiftformat·xcbeautify 설치, git 훅(pre-commit: main 커밋 차단·String Catalog stale 표시 차단·lint, pre-merge-commit: main 머지 커밋 차단, pre-push: main push 차단) 연결
make generate    # SimLauncher.xcworkspace 생성 후 Xcode 로 열기
make test        # 전체 모듈 빌드 + 테스트 + git 훅 테스트
make test-hooks  # git 훅 동작 테스트만 (임시 레포에서 main 커밋·머지 커밋·push 차단, String Catalog stale 표시 커밋 차단과 기능 브랜치 통과 확인)
make lint        # 포맷·아키텍처 규칙 검사 (make format 으로 자동 수정)
make sample      # 샘플 iOS 앱을 시뮬레이터용으로 빌드해 build/SampleApp.zip 으로 묶기 (SAMPLE_BUILD_NUMBER=42 로 빌드 번호)
make catalog-check CATALOG=catalog.json   # catalog.json 하나를 앱과 같은 규칙으로 검사
make catalog-test  # 샘플 카탈로그 생성기·검증기 회귀 테스트
make release     # 서명·공증 dmg 만들기 (준비: docs/RELEASING.md)
```

### 샘플 카탈로그 운영
레포의 GitHub Actions 예시 워크플로가 샘플 iOS 앱을 빌드해 Releases 에 올리고 카탈로그를 만든다 ([위 주소](#회사-빌드-카탈로그-등록)).

- 새 빌드 올리기: Actions > Sample Catalog > Run workflow 를 **main 에서** 실행한다. 워크플로 파일이 main 과 다른 브랜치에서 실행하면 GitHub 이 릴리스 생성을 거절한다(draft 릴리스가 남을 수 있다. 카탈로그에는 영향이 없고 손으로 지운다).
- 동작, 자기 앱에 맞게 바꿀 곳, 재실행·정리 방법: [CATALOG.md 11절](docs/CATALOG.md#11-github-actions-예시)

### 문서
- [아키텍처](docs/ARCHITECTURE.md)
- [개발 규칙: 해야 할 것 / 하지 말아야 할 것](docs/CONVENTIONS.md)
- [개발 계획과 로드맵](docs/DEVELOPMENT_PLAN.md)
- [빌드 카탈로그 규격](docs/CATALOG.md)
- [배포(서명·공증)](docs/RELEASING.md)
- [Claude Code 작업 안내](CLAUDE.md)

이 프로젝트는 [ios-harness](https://github.com/zopandagom/ios-harness) 템플릿으로 만들었다 (`.harness-version`).

## 라이선스
[MIT](LICENSE)
