# 배포 (서명·공증 dmg)

SimLauncher 배포본을 만드는 방법이다. `make release` 가 [`scripts/release.sh`](../scripts/release.sh) 를 실행해 Developer ID 로 서명하고 Apple 공증을 받은 dmg 를 만든다. Mac App Store·Homebrew Cask·CI 서명은 하지 않는다 (ARCHITECTURE §4 배포 행).

## 1. 무엇을 만드나
`build/release/SimLauncher-<버전>.dmg` 하나:
- 안에 `SimLauncher.app`(Developer ID Application 서명·Hardened Runtime·공증·티켓 staple)과 `Applications` 바로가기(`/Applications` 를 가리키는 심볼릭 링크)가 있다. 배경·창 배치 같은 꾸밈은 없다.
- dmg 자체도 Developer ID 로 서명하고 공증·staple 한다.

`build/` 는 git 에 올리지 않는다. 같은 폴더의 `export/SimLauncher.app`(내보낸 앱)·`notary/`(공증 제출 결과 JSON·로그)·`archive.log`·`export.log` 는 원인 확인용으로 남는다. dmg 는 작업 이름 `unfinished-SimLauncher-<버전>.dmg` 로 만들어 서명·공증·staple·최종 검사를 하고, 모두 통과한 뒤에만 `SimLauncher-<버전>.dmg` 로 이름을 바꾼다. 실패하면 배포 이름 파일은 없고 작업 dmg 와 `notary/app-submit.zip`(앱 공증·staple 단계에서 실패했을 때)이 남을 수 있다 — 배포하지 않는다.

## 2. 한 번만 할 준비
이 Mac 에서 배포하는 사람이 한 번 한다. 비밀 값(앱 암호)은 키체인에만 두고 레포·명령줄·대화에 넣지 않는다.

1. **Xcode 계정**: Xcode → Settings → Accounts 에 팀(`XHV4ZL5K8T`) 의 Apple ID 로 로그인한다. 앱 서명은 내보내기(export) 때 Xcode 자동 서명이 클라우드 관리 Developer ID 인증서로 한다(이 Mac 키체인에 개인 키가 생기지 않는다).
2. **dmg 서명용 로컬 인증서**: Xcode → Settings → Accounts → 팀 선택 → Manage Certificates… → `+` → **Developer ID Application**. 개인 키가 로그인 키체인에 생기므로 백업해 둔다(키체인 접근에서 내보내기). 클라우드 관리 인증서로는 dmg 를 `codesign` 할 수 없어(`no identity found`, 실측) dmg 서명에만 이 인증서를 쓴다.
3. **공증 자격 증명**: [appleid.apple.com](https://appleid.apple.com) → 로그인 및 보안 → 앱 암호에서 암호를 만들고, Terminal 에서 아래를 실행해 암호는 프롬프트에 입력한다 (`--password` 를 명령줄에 쓰지 않는다).
   ```sh
   xcrun notarytool store-credentials simlauncher-notary --apple-id <Apple ID> --team-id XHV4ZL5K8T
   ```
   다른 프로필 이름을 썼다면 `NOTARY_PROFILE=<이름> make release` 로 넘긴다 (Makefile 기본값 `simlauncher-notary`).
4. **포크·다른 팀이 쓸 때 바꿀 값**: `Tuist/ProjectDescriptionHelpers/Project+Templates.swift` 의 `Env.developmentTeam`(자기 팀 ID), `Env.bundleIdPrefix`(`com.zopandagom.simlauncher` 는 이 팀의 번들 ID), 저작권 문구(`Env.appVersionInfoPlist` 의 `NSHumanReadableCopyright`), 공증 프로필 이름(`NOTARY_PROFILE`).

준비가 덜 되었으면 `make release` 가 빌드 전에 멈추고 빠진 항목을 모두 알린다 (4절 사전 확인).

## 3. 배포 순서
1. 버전을 올린다: `Env.marketingVersion`(dmg 이름에 쓰인다)과 `Env.buildNumber`(같은 버전을 다시 배포하면 올린다). 두 값은 앱 타깃의 `MARKETING_VERSION`·`CURRENT_PROJECT_VERSION` 을 거쳐 Info.plist 의 `CFBundleShortVersionString`·`CFBundleVersion` 이 된다.
2. 버전 변경을 PR 로 main 에 머지하고, main 최신을 받는다 (깨끗한 작업 트리에서 만드는 것을 권장).
3. **Terminal 에서** `make release` 를 실행한다. 확인 질문은 터미널(`/dev/tty`)에서만 답을 받는다.
4. 5단계 요약(앱·버전·서명·dmg 서명 인증서·커밋·공증 프로필·배포 dmg 경로·제출할 파일)을 확인하고 `y` 를 입력한다. 커밋되지 않은 변경이 있으면 그 목록이 다시 보이고 `dirty` 를 입력해야 계속한다.
5. 공증은 보통 몇 분 걸린다(최대 1시간 기다린다). 끝에 최종 검사가 모두 통과하고 `완료: build/release/SimLauncher-<버전>.dmg` 와 SHA-256 이 보이면 끝이다.
6. **태그**: dmg 를 만든 main 커밋에 주석 태그 `<버전>`(예 `1.0.0`, `v` 없음)을 붙여 push 한다. pre-push 훅과 GitHub 룰셋은 main 브랜치만 막으므로 태그 push 는 막히지 않고, 태그 push 로 도는 워크플로도 없다.
   ```sh
   git tag -a <버전> <커밋> -m "SimLauncher <버전>"
   git push origin refs/tags/<버전>
   ```
7. **GitHub Release**: 태그로 Release 를 게시하고 dmg 를 첨부한다. 노트는 한국어(README 와 같은 해요체)로 할 수 있는 것·준비물·설치하기(README `#설치하기` 링크)·파일 SHA-256 을 적는다.
   ```sh
   gh release create <버전> build/release/SimLauncher-<버전>.dmg --verify-tag --latest \
     --title "SimLauncher <버전>" --notes-file <노트 파일>
   ```
   README 설치 링크(`releases/latest`)는 Pre-release 가 아닌 가장 최근 Release 를 가리킨다. 샘플 카탈로그 워크플로의 Release(`sample-catalog`·`sample-build-…`)는 Pre-release 라 겹치지 않는다. `--latest` 로 이 Release 를 최신으로 지정한다.
8. **게시 확인**: `gh api repos/<소유자>/<레포>/releases/latest -q .tag_name` 이 `<버전>` 이고, 첨부 파일의 `digest` 에서 `sha256:` 접두어를 뺀 값(`… -q '.assets[].digest | ltrimstr("sha256:")'`)이 5번의 SHA-256 과 같은지 본다.
9. **내려받은 게시본 확인**: README 설치 링크에서 브라우저로 dmg 를 받는다(quarantine 이 붙는다). `xattr -p com.apple.quarantine`·`shasum -a 256`·5절의 dmg `spctl` 을 확인하고, 앱을 응용 프로그램 폴더로 옮겨(이미 있으면 대치) 실행해 Gatekeeper 차단 없이 열리고 "SimLauncher에 관하여" 버전이 맞는지 본다. 이 Mac 에서 만든 앱이 응용 프로그램 폴더에 이미 있으면 quarantine 이 없으므로 받은 앱으로 대치해야 확인이 된다. 이 확인은 받은 파일의 Gatekeeper 판정과 실행 허용을 본다. 로드맵 단계 목표의 "다른 Mac" 확인(이 Mac 의 인증서·이전 실행 허용이 없는 환경)은 6절대로 다른 Mac 이나 새 사용자 계정에서 같은 방법으로 한다.

## 4. 단계와 실패 시 할 일
진행 중에는 `==> [n/12] <단계>` 가, 실패하면 `실패 [n/12] <단계>: <이유>` 와 다음 할 일이 보인다. 실패해도 산출물·로그는 지우지 않는다(다음 실행이 처음에 `build/release` 를 지운다). 배포 이름 dmg 는 12단계를 통과해야만 생긴다.

| # | 단계 | 하는 일 | 실패하면 |
|---|---|---|---|
| 0 | 이전 산출물 정리 | 남은 마운트(`build/release/mnt`)를 분리 시도하고 `build/release` 를 지운다. `build/` 의 다른 내용은 건드리지 않는다 | 지우지 못하면 `hdiutil detach <레포>/build/release/mnt` 뒤 다시 실행 |
| 1 | 사전 확인 | P1 앱 타깃 빌드 설정(팀·버전·Hardened Runtime), P2 작업 트리(경고만), P3 dmg 서명 인증서, P4 공증 프로필(`notarytool history` 로 읽기만, 제출 아님)을 모두 검사하고 빠진 것을 한꺼번에 알린다 | 안내대로 2절 준비를 마친다. P1 은 `make project` 와 `Env` 값을 확인 |
| 2 | archive | Release 구성으로 archive (`build/release/DerivedData` 에서 매번 전체 빌드). 앱 타깃 서명 인증서가 `-` 라 여기서는 ad-hoc 이다 | `build/release/archive.log` 의 `error:` 줄 |
| 3 | Developer ID 내보내기 | `method developer-id`, `signingStyle automatic` 으로 export (`-allowProvisioningUpdates`). Xcode 가 Developer ID 로 다시 서명한다 | `build/release/export.log`. Xcode 계정 로그인 확인 |
| 4 | 앱 서명 검사 | `codesign --verify --strict --deep`, Authority 가 `Developer ID Application: … (<팀>)`, TeamIdentifier, Hardened Runtime(`flags` 에 `runtime`), 보안 타임스탬프, `get-task-allow` 없음, Info.plist 버전이 빌드 설정과 같음 | 어긋난 항목과 기대값·실제값이 보인다 |
| 5 | 확인 | 요약을 보이고 터미널에서 답을 받는다. 여기 전에는 공증 서비스로 파일을 보내지 않는다 (1단계 P4 의 자격 증명 확인과 3단계 내보내기 서명은 Apple 서버와 통신한다) | 거절(빈 답·터미널 없음 포함)이면 제출하지 않고 끝난다 |
| 6 | 앱 공증 | 앱을 zip 으로 묶어 `notarytool submit` → `wait` → `info` 의 `status` 가 `Accepted` 인지 본다 | 거절이면 `build/release/notary/app-log.json` 의 `issues`. 시간 초과면 안내된 `notarytool info` 로 확인 뒤 다시 실행 |
| 7 | 앱 staple | `stapler staple` → `stapler validate` | 공증 직후 티켓 배포가 늦을 수 있다. 잠시 뒤 다시 실행 |
| 8 | dmg 만들기 | 앱 + `Applications` 바로가기로 작업 이름 `unfinished-SimLauncher-<버전>.dmg` 로 `hdiutil create -format UDZO -fs APFS` | hdiutil 출력 |
| 9 | dmg 서명 | 로컬 Developer ID Application 인증서(SHA-1 로 지정)로 `codesign --timestamp`. 작업 이름이 서명에 남지 않게 식별자를 `-i SimLauncher-<버전>` 으로 준다 | 키체인 접근 대화상자에서 거절했으면 다시 실행해 "항상 허용" |
| 10 | dmg 공증 | 6단계와 같다 (`dmg-submit.json`·`dmg-info.json`·`dmg-log.json`) | 6단계와 같다 |
| 11 | dmg staple | 7단계와 같다 | 7단계와 같다 |
| 12 | 최종 검사 | 5절의 검사를 모두 돌리고 종료 코드로 판정. dmg 를 `build/release/mnt` 에 읽기 전용으로 마운트해 안의 앱과 `Applications` 바로가기도 본다. 모두 통과하면 `SimLauncher-<버전>.dmg` 로 이름을 바꾼다 | 실패한 검사 이름이 보인다. 작업 dmg 는 배포 이름으로 옮기지 않는다 |

스크립트 종료 코드: 0 성공, 1 단계 실패, 2 사전 확인 실패, 3 공증 제출을 거절함, 130 중단(Ctrl-C). `make release` 로 실행하면 make 자신은 실패를 모두 종료 2 로 돌려주고, 스크립트의 종료 코드는 마지막 줄 `make: *** [release] Error <코드>` 에 보인다.

- **재실행**: 언제나 0단계부터 처음부터 한다. 중간부터 이어 하지 않는다. 앞선 실행에서 앱 공증이 끝났어도 새 archive 로 다시 제출한다.
- **중단(Ctrl-C)**: 공증을 기다리던 중이면 제출 ID 와 확인 명령(`xcrun notarytool info <ID> --keychain-profile <프로필>`)을 알린다. 제출한 공증은 Apple 쪽에서 계속 처리된다(취소 명령이 없다). 검사용 마운트는 스크립트가 끝날 때 분리한다.
- **공증 거절 이유 보기**: `build/release/notary/<app|dmg>-log.json` 의 `issues` 에 파일 경로와 이유가 있다. 다시 받으려면 `xcrun notarytool log <제출 ID> --keychain-profile simlauncher-notary`.

## 5. 검사 명령 직접 돌리기
레포 루트에서:
```sh
codesign --verify --strict -v build/release/SimLauncher-<버전>.dmg
spctl -a -vv -t open --context context:primary-signature build/release/SimLauncher-<버전>.dmg
xcrun stapler validate build/release/SimLauncher-<버전>.dmg
spctl -a -vv -t exec build/release/export/SimLauncher.app   # staple 된 앱
```
모두 종료 0 이어야 한다. 공증 전 Developer ID 앱은 `spctl` 이 `source=Unnotarized Developer ID` 로 거절하고(종료 3), `stapler validate` 가 티켓 없음으로 실패한다(종료 65).

## 6. 배포 서명 빌드로 수동 확인하기
CONVENTIONS §5 "수동 확인" 행의 배포 서명 빌드는 `make release` 의 export 앱이다. 공증하지 않아도 사전 확인 P1~P4(로컬 Developer ID 인증서·공증 프로필 포함)는 모두 필요하다.
1. Terminal 에서 `make release` 를 실행하고 확인 질문에 `n` 을 입력한다 (종료 3, 제출 없음).
2. `build/release/export/SimLauncher.app` 이 남는다: Developer ID·Hardened Runtime 으로 서명했고 공증 전이다. 이 Mac 에서 만든 파일이라 quarantine 표시가 없어 그대로 실행된다.

Gatekeeper 동작(다운로드한 앱의 첫 실행)까지 보려면 공증된 dmg 를 브라우저로 내려받아(quarantine 이 붙도록) 연다. 이 Mac 에서는 받은 앱을 응용 프로그램 폴더에 대치해 받은 파일의 판정을 보고(3절 9번), 이 Mac 의 인증서·이전 실행 허용이 없는 환경(로드맵 단계 목표의 "다른 Mac")은 다른 Mac 이나 이 Mac 의 새 사용자 계정에서 본다. "확인되지 않은 개발자"·"손상되었습니다" 차단 없이 열려야 하고, 인터넷에서 받은 앱마다 뜨는 첫 실행 확인은 정상이다.

## 7. 서명 설정
설정은 모두 `Env`(`Tuist/ProjectDescriptionHelpers/Project+Templates.swift`)에 있다 (ARCHITECTURE §2 빌드 설정).
- **Hardened Runtime**: 앱 타깃(`SimLauncher`)만 `Env.appTargetSettings` 로 켠다. Example 앱·모듈·테스트에는 주지 않는다. Debug(ad-hoc) 빌드에서는 Xcode 가 Hardened Runtime 을 끄므로(`Disabling hardened runtime with ad-hoc codesigning`) 개발 실행은 지금과 같다.
- **entitlement·App Sandbox 없음**: Developer ID·Hardened Runtime 으로 서명하고 entitlement 없이 실행해, 앱이 쓰는 동작이 모두 돈다는 것을 확인했다 (2026-10-27, macOS 26.6·Xcode 27.1): `xcode-select`·`xcodebuild -checkFirstLaunchStatus`·`-license check`, `simctl` 목록·생성·켜기·설치·실행·`openurl`·스크린샷·녹화(`SIGINT` 로 멈춤)·끄기·삭제, `zipinfo`·`ditto`, URLSession 다운로드, `NSWorkspace` 로 Finder 에서 보이기. 자식 프로세스(`simctl` 등)는 자기 서명으로 돈다. App Sandbox 는 `simctl` 실행에 Sandbox 밖 동작이 필요해 쓰지 않는다 (ARCHITECTURE §4). 동영상 폴더(`~/Movies/SimLauncher`)에 녹화를 저장할 때 권한 팝업이 뜨지 않는 것은 배포 서명·공증 빌드(1.0.0)의 수동 확인으로 봤다 (2026-10-27).
- **서명 흐름**: 앱 타깃의 서명 인증서는 Tuist 기본 `-`(Sign to Run Locally)라 archive 는 ad-hoc 이고, developer-id export 가 클라우드 관리 Developer ID 인증서로 다시 서명한다. `make build`·`make test`·CI 는 `CODE_SIGNING_ALLOWED=NO` 로 서명하지 않는다.
- **버전·저작권**: `Env.appVersionInfoPlist` 가 앱 Info.plist 의 `CFBundleShortVersionString`·`CFBundleVersion` 을 빌드 설정으로, `NSHumanReadableCopyright`("SimLauncher에 관하여" 창)를 저작권 문구로 바꾼다.
