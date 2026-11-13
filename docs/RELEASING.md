# 배포 (서명·공증 dmg)

SimLauncher 배포본을 만드는 방법이다. 기본 경로는 **버전 태그 push** 다: 태그를 push 하면 릴리스 워크플로(`.github/workflows/release.yml`)가 [`scripts/release.sh`](../scripts/release.sh) 를 CI 모드로 돌려 Developer ID 로 서명하고 Apple 공증을 받은 dmg 를 만들고, 릴리스 노트를 써서 GitHub Release 를 게시한다. 로컬 `make release` 는 같은 스크립트를 이 Mac 에서 돌리는 예비 경로로 남긴다(러너를 쓸 수 없을 때, 배포 서명 빌드로 수동 확인할 때). Mac App Store·Homebrew Cask 는 하지 않는다 (ARCHITECTURE §4 배포 행).

## 1. 무엇을 만드나
`build/release/SimLauncher-<버전>.dmg` 하나:
- 안에 `SimLauncher.app`(Developer ID Application 서명·Hardened Runtime·공증·티켓 staple)과 `Applications` 바로가기(`/Applications` 를 가리키는 심볼릭 링크)가 있다. 배경·창 배치 같은 꾸밈은 없다.
- dmg 자체도 Developer ID 로 서명하고 공증·staple 한다.

`build/` 는 git 에 올리지 않는다. 같은 폴더의 `export/SimLauncher.app`(내보낸 앱)·`notary/`(공증 제출 결과 JSON·로그)·`archive.log`·`export.log` 는 원인 확인용으로 남는다. dmg 는 작업 이름 `unfinished-SimLauncher-<버전>.dmg` 로 만들어 서명·공증·staple·최종 검사를 하고, 모두 통과한 뒤에만 `SimLauncher-<버전>.dmg` 로 이름을 바꾼다. 실패하면 배포 이름 파일은 없고 작업 dmg 와 `notary/app-submit.zip`(앱 공증·staple 단계에서 실패했을 때)이 남을 수 있다 — 배포하지 않는다. 성공한 실행에도 지우지 못했다는 `경고:` 가 보였으면 `notary/app-submit.zip`·`dmg-root/` 가, 분리하지 못했다는 `경고:` 가 보였으면 `mnt/` 에 마운트된 dmg 가 남을 수 있다(스크립트가 끝날 때 한 번 더 분리를 시도한다. 배포 dmg 를 읽기 전용으로 마운트한 것이라 배포 dmg 에는 영향이 없고, 다음 실행이 0단계에서 정리한다).

릴리스 워크플로는 이 산출물을 run 의 아티팩트로도 남긴다(3일 보존, `release-logs` 만 7일): `SimLauncher-dmg`(배포 dmg), `release-logs`(archive·export 로그와 공증 결과 JSON, 실패한 run 의 원인 확인용), `release-notes-parts`(노트 재료: PR 목록·요약·이전 태그), 시험 실행이면 `release-notes`(조립한 노트). 공개 레포라 로그인한 GitHub 사용자 누구나 받을 수 있다. 시크릿 값은 들어 있지 않다(시크릿 가림은 로그에만 적용되므로 아티팩트에 비밀을 넣지 않는다).

## 2. 한 번만 할 준비
비밀 값(인증서 개인 키·암호·API 키)은 키체인이나 GitHub `release` 환경 시크릿에만 두고 레포·명령줄·대화에 넣지 않는다.

### 2.1 태그 배포(CI) 준비
레포 관리자가 한 번 한다. 아래 `<소유자>/<레포>` 는 이 레포(`zopandagom/simlauncher-macos`)나 포크다.

1. **Developer ID Application 인증서 내보내기(.p12)**: 2.2 의 2번에서 만든 dmg 서명용 로컬 인증서를 키체인 접근에서 개인 키와 함께 골라 `.p12` 로 내보낸다(내보낼 때 암호를 정한다). 파일은 레포 밖에 두고, 시크릿 등록 뒤에는 지우거나 안전한 곳에 백업한다. CI 는 이 인증서 하나로 앱(manual export, 프로비저닝 프로필 없음)과 dmg 를 모두 서명한다. 지금 인증서는 **2027-02-01** 에 만료되므로 그 전에 새 인증서를 만들어 로컬 키체인과 시크릿을 함께 바꾼다.
2. **App Store Connect API 키(공증용)**: App Store Connect → 사용자 및 액세스 → 통합 → App Store Connect API → 팀 키에서 키를 만든다(역할은 Developer 로 시작하고, 공증이 권한 문제로 거절되면 높인다. 최소 역할은 아직 확인하지 않았다). `.p8` 파일은 한 번만 받을 수 있다. 같은 화면의 **키 ID** 와 **발급자 ID** 를 적어 둔다.
3. **`release` 환경**: 시크릿을 쓸 수 있는 ref 를 main 브랜치와 버전 태그로 제한한다. 승인자는 두지 않는다(태그 push 로 끝까지 게시).
   ```sh
   gh api -X PUT repos/<소유자>/<레포>/environments/release --input - <<'JSON'
   { "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true } }
   JSON
   gh api -X POST repos/<소유자>/<레포>/environments/release/deployment-branch-policies -f name=main -f type=branch
   gh api -X POST repos/<소유자>/<레포>/environments/release/deployment-branch-policies -f name='*.*.*' -f type=tag
   ```
4. **환경 시크릿 5개**: 값은 파일·표준 입력·프롬프트로만 넣는다(명령줄에 값을 쓰지 않는다).
   ```sh
   base64 -i <Developer ID .p12> | gh secret set DEVELOPER_ID_P12_BASE64 --env release
   gh secret set DEVELOPER_ID_P12_PASSWORD --env release          # 프롬프트에 .p12 암호
   gh secret set NOTARY_API_KEY_P8 --env release < <AuthKey_XXXX.p8>
   gh secret set NOTARY_API_KEY_ID --env release                  # 프롬프트에 키 ID
   gh secret set NOTARY_API_ISSUER_ID --env release               # 프롬프트에 발급자 ID
   ```
   노트 요약에 쓰는 `CLAUDE_CODE_OAUTH_TOKEN` 은 CI 리뷰가 이미 쓰는 레포 시크릿을 그대로 쓴다.
5. **버전 태그 룰셋**: 버전 태그(`*.*.*`)를 만들고 옮기고 지우는 것은 관리자만 하게 한다(샘플 카탈로그 태그 `sample-*` 는 점이 없어 걸리지 않는다).
   ```sh
   gh api -X POST repos/<소유자>/<레포>/rulesets --input - <<'JSON'
   {
     "name": "버전 태그 보호",
     "target": "tag",
     "enforcement": "active",
     "conditions": { "ref_name": { "include": ["refs/tags/*.*.*"], "exclude": [] } },
     "rules": [ { "type": "creation" }, { "type": "update" }, { "type": "deletion" } ],
     "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" } ]
   }
   JSON
   ```
   (`actor_id 5` 는 Repository admin 역할이다.)
6. **확인**: `gh api repos/<소유자>/<레포>/environments/release/deployment-branch-policies --jq '[.branch_policies[]|{name,type}]'` 에 main(branch)·`*.*.*`(tag), `gh secret list --env release` 에 이름 5개, `gh api repos/<소유자>/<레포>/rulesets --jq '.[]|{name,target,enforcement}'` 에 `버전 태그 보호`(tag, active)가 보인다.

러너는 잡마다 임시 키체인을 만들어 .p12 를 넣고(`scripts/ci-keychain.sh`), 끝나면 성공·실패와 관계없이 원래 키체인 검색 목록으로 되돌리고 지운다. 비밀이 명령줄에 들어가는 유일한 예외는 이 임시 키체인의 암호다(`security create-keychain`·`unlock-keychain`·`set-key-partition-list` 가 인자로만 받는다). 스크립트가 잡 안에서 새로 만든 일회성 값이라 로그에서 가리고, 잡이 끝나면 키체인과 함께 사라진다. .p12 암호·.p8·API 키는 명령줄에 들어가지 않는다.

### 2.2 로컬(예비 경로 `make release`) 준비
이 Mac 에서 배포하는 사람이 한 번 한다. 공증 자격 증명은 키체인에만 둔다.

1. **Xcode 계정**: Xcode → Settings → Accounts 에 팀(`XHV4ZL5K8T`) 의 Apple ID 로 로그인한다. 로컬 `make release` 의 앱 서명은 내보내기(export) 때 Xcode 자동 서명이 클라우드 관리 Developer ID 인증서로 한다(이 Mac 키체인에 개인 키가 생기지 않는다).
2. **dmg 서명용 로컬 인증서**: Xcode → Settings → Accounts → 팀 선택 → Manage Certificates… → `+` → **Developer ID Application**. 개인 키가 로그인 키체인에 생기므로 백업해 둔다(키체인 접근에서 내보내기, 2.1 의 1번 .p12 가 이것이다). 클라우드 관리 인증서로는 dmg 를 `codesign` 할 수 없어(`no identity found`, 실측) dmg 서명에만 이 인증서를 쓴다.
3. **공증 자격 증명**: [appleid.apple.com](https://appleid.apple.com) → 로그인 및 보안 → 앱 암호에서 암호를 만들고, Terminal 에서 아래를 실행해 암호는 프롬프트에 입력한다 (`--password` 를 명령줄에 쓰지 않는다).
   ```sh
   xcrun notarytool store-credentials simlauncher-notary --apple-id <Apple ID> --team-id XHV4ZL5K8T
   ```
   다른 프로필 이름을 썼다면 `NOTARY_PROFILE=<이름> make release` 로 넘긴다 (Makefile 기본값 `simlauncher-notary`).
4. **포크·다른 팀이 쓸 때 바꿀 값**: `Tuist/ProjectDescriptionHelpers/Project+Templates.swift` 의 `Env.developmentTeam`(자기 팀 ID), `Env.bundleIdPrefix`(`com.zopandagom.simlauncher` 는 이 팀의 번들 ID), 저작권 문구(`Env.appVersionInfoPlist` 의 `NSHumanReadableCopyright`), 공증 프로필 이름(`NOTARY_PROFILE`). 태그 배포를 쓰려면 2.1 을 자기 레포에 한다.

준비가 덜 되었으면 `make release` 가 빌드 전에 멈추고 빠진 항목을 모두 알린다 (4절 사전 확인).

## 3. 배포 순서
### 3.1 태그로 배포 (기본)
1. 버전을 올린다: `Env.marketingVersion`(태그·dmg 이름에 쓰인다)과 `Env.buildNumber`(배포할 때마다 1씩 올린다. 버전이 바뀌어도 되돌리지 않는다. 워크플로가 이전 릴리스보다 큰지 검사한다). 두 값은 앱 타깃의 `MARKETING_VERSION`·`CURRENT_PROJECT_VERSION` 을 거쳐 Info.plist 의 `CFBundleShortVersionString`·`CFBundleVersion` 이 된다.
2. 버전 변경을 PR 로 main 에 머지한다.
3. **시험 실행**(첫 배포, 러너·Xcode·워크플로·서명 설정을 바꾼 뒤): main 에서 `gh workflow run release.yml --ref main` 을 실행하고 `gh run watch <run ID> --exit-status` 로 끝까지 본다. 검사·서명·공증·노트까지 돌고 게시(publish)는 하지 않는다(Release·태그가 생기지 않는다). 공증은 실제로 제출된다. `gh run download <run ID> -n SimLauncher-dmg -n release-notes` 로 받은 dmg 와 노트를 확인한다. 러너·Xcode 를 바꾼 첫 회는 로컬 `make release` 결과와 비교한다(앱 Info.plist 버전, `codesign -dvv` 의 Authority·TeamIdentifier, entitlement 없음, 5절 검사). 러너 레이블(`runs-on: xcode-27`)을 바꾸면 미리보기 레이블을 actionlint 에 알려 둔 `.github/actionlint.yaml` 도 같이 고친다.
4. **태그**: main 에 머지된 버전 커밋에 주석 태그 `<버전>`(예 `1.2.0`, `v` 없음)을 붙여 push 한다. 버전 태그는 태그 룰셋으로 관리자만 만들 수 있다(2.1 의 5번). 경량 태그·main 에 없는 커밋·`Env.marketingVersion` 과 다른 태그는 워크플로가 거절한다.
   ```sh
   git tag -a <버전> <커밋> -m "SimLauncher <버전>"
   git push origin refs/tags/<버전>
   ```
5. **워크플로**: check(태그 검사) → build(서명·공증·staple·최종 검사, 보통 수십 분) ∥ notes(노트 재료·요약) → publish(게시) 순서로 돈다. Actions 탭에서 진행을 보고, 실패하면 4절 "릴리스 워크플로가 실패하면" 대로 한다.
6. **노트**: 워크플로가 아래 순서로 쓴다. README 와 같은 해요체다.
   - 바뀐 점: Claude 가 이번 PR 들의 본문·바뀐 파일 목록을 읽고 이전 버전 대비 바뀐 점을 요약한다(Claude Code CLI, 도구 없이). 요약이 실패하거나 거절되면 기본 문장 하나로 대신하고 게시는 막지 않는다.
   - 설치·업데이트하기: dmg 설치·대치 방법과 README `#설치하기` 링크.
   - 이번 버전에 들어간 PR: 이전 릴리스 태그(게시된 Release 가 있고 이번 버전보다 낮은 버전 태그 중 가장 높은 것) 이후 main 에 머지된 PR 의 제목·번호.
   - 파일: dmg 의 SHA-256.

   README 설치 링크(`releases/latest`)는 Pre-release 가 아닌 latest Release 를 가리킨다. 워크플로는 이 버전이 게시된 버전 중 가장 높을 때만 latest 로 지정한다(예전 버전 줄의 수정 릴리스가 새 버전을 밀어내지 않게). 샘플 카탈로그 워크플로의 Release(`sample-catalog`·`sample-catalog-v2`·`sample-build-…`)는 Pre-release 라 겹치지 않는다. 게시 뒤 노트를 손보려면 `gh release edit <버전> --notes-file <파일>`.
7. **예비 경로**: 러너를 쓸 수 없으면 3.2 대로 로컬에서 만들어 게시한다.
8. **게시 확인**: `gh api repos/<소유자>/<레포>/releases/latest -q .tag_name` 이 `<버전>` 이고, 첨부 파일의 `digest` 에서 `sha256:` 접두어를 뺀 값(`… -q '.assets[].digest | ltrimstr("sha256:")'`)이 노트 "파일" 표의 SHA-256(로컬이면 3.2 의 3번 값)과 같은지 본다.
9. **내려받은 게시본 확인**: README 설치 링크에서 브라우저로 dmg 를 받는다(quarantine 이 붙는다). `xattr -p com.apple.quarantine`·`shasum -a 256`·5절의 dmg `spctl` 을 확인하고, 앱을 응용 프로그램 폴더로 옮겨(이미 있으면 대치) 실행해 Gatekeeper 차단 없이 열리고 "SimLauncher에 관하여" 버전이 맞는지 본다. 이 Mac 에서 만든 앱이 응용 프로그램 폴더에 이미 있으면 quarantine 이 없으므로 받은 앱으로 대치해야 확인이 된다. 이 확인은 받은 파일의 Gatekeeper 판정과 실행 허용을 본다. 로드맵 단계 목표의 "다른 Mac" 확인(이 Mac 의 인증서·이전 실행 허용이 없는 환경)은 6절대로 다른 Mac 이나 새 사용자 계정에서 같은 방법으로 한다.

### 3.2 로컬 `make release` 로 배포 (예비 경로)
3.1 의 1·2번 뒤 main 최신을 받고(깨끗한 작업 트리에서 만드는 것을 권장):
1. **Terminal 에서** `make release` 를 실행한다. 확인 질문은 터미널(`/dev/tty`)에서만 답을 받는다.
2. 5단계 요약(앱·버전·서명·dmg 서명 인증서·커밋·공증 프로필·배포 dmg 경로·제출할 파일)을 확인하고 `y` 를 입력한다. 커밋되지 않은 변경이 있으면 그 목록이 다시 보이고 `dirty` 를 입력해야 계속한다.
3. 공증은 보통 몇 분 걸린다(최대 1시간 기다린다). 끝에 최종 검사가 모두 통과하고 `완료: build/release/SimLauncher-<버전>.dmg` 와 SHA-256 이 보이면 끝이다. SHA-256 을 구하지 못했다는 `경고:` 가 보이면 `shasum -a 256 build/release/SimLauncher-<버전>.dmg` 로 직접 구한다.
4. **태그**: 3.1 의 4번처럼 dmg 를 만든 main 커밋에 주석 태그를 push 한다. 태그 push 는 릴리스 워크플로를 시작하므로, 로컬 dmg 로 게시할 때는 시작된 run 을 바로 취소한다(Actions 탭 또는 `gh run list --workflow release.yml` 로 찾아 `gh run cancel <run ID>`). 워크플로가 먼저 게시하면 같은 버전을 두 번 올리게 된다.
5. **GitHub Release**: 태그로 Release 를 게시하고 dmg 를 첨부한다. 노트는 3.1 의 6번과 같은 구성으로 직접 쓴다. latest 는 이 버전이 게시된 버전 중 가장 높을 때만 준다(아니면 `--latest=false`).
   ```sh
   gh release create <버전> build/release/SimLauncher-<버전>.dmg --verify-tag --latest \
     --title "SimLauncher <버전>" --notes-file <노트 파일>
   ```
6. 3.1 의 8·9번으로 게시본을 확인한다.

## 4. 단계와 실패 시 할 일
진행 중에는 `==> [n/12] <단계>` 가, 실패하면 `실패 [n/12] <단계>: <이유>` 와 다음 할 일이 보인다. 실패해도 산출물·로그는 지우지 않는다(다음 실행이 처음에 `build/release` 를 지운다). 배포 이름 dmg 는 12단계를 통과해야만 생긴다. 산출물에 영향이 없는 정리(임시 파일 지우기)·검사용 마운트 분리·SHA-256 계산이 실패하면 `경고:` 줄과 할 일만 보이고 계속한다.

**CI 모드**: 릴리스 워크플로(`.github/workflows/release.yml` 의 build 잡)는 같은 `make release` 를 환경 변수로 CI 모드로 돌린다. 단계 번호·종료 코드는 같고, 다른 점은 아래 표의 "CI 모드:" 부분이다. 로컬 `make release` 는 이 변수들을 주지 않으므로 지금처럼 동작한다.

| 변수 | 로컬(기본) | CI 모드 |
|---|---|---|
| `RELEASE_CI` | 비워 둔다 | `1` 일 때만 CI 모드. 그 밖의 값은 아무것도 하지 않고 종료 2 |
| `NOTARY_PROFILE` | 공증 키체인 프로필 이름(필수, Makefile 기본 `simlauncher-notary`) | 쓰지 않는다 |
| `RELEASE_KEYCHAIN` | 쓰지 않는다 | 임시 키체인 경로(필수). [`scripts/ci-keychain.sh`](../scripts/ci-keychain.sh) `setup` 이 이 경로에 .p12 를 넣은 키체인을 만들어 사용자 검색 목록 맨 앞에 넣고, `cleanup` 이 저장해 둔 원래 목록으로 되돌리고 지운다(기본·login 키체인은 건드리지 않는다. p12 암호는 env `P12_PASSWORD` 로만 받는다) |
| `NOTARY_KEY_PATH`·`NOTARY_KEY_ID`·`NOTARY_ISSUER_ID` | 쓰지 않는다 | App Store Connect 팀 API 키(.p8 파일 경로·키 ID·발급자 ID, 필수). notarytool 에 `--key`·`--key-id`·`--issuer` 로 넘긴다 |
| `RELEASE_NO_SUBMIT` | 쓰지 않는다 | `1` 이면 5단계에서 제출하지 않고 종료 3(로컬 Mac 에서 CI 모드를 시험할 때만). 워크플로는 주지 않고, `GITHUB_ACTIONS=true` 와 함께 오면 사전 확인 오류 |

| # | 단계 | 하는 일 | 실패하면 |
|---|---|---|---|
| 0 | 이전 산출물 정리 | 남은 마운트(`build/release/mnt`)를 분리 시도하고 `build/release` 를 지운다. `build/` 의 다른 내용은 건드리지 않는다 | 지우지 못하면 `hdiutil detach <레포>/build/release/mnt` 뒤 다시 실행. `build/release` 를 만들지 못하면 디스크 공간·쓰기 권한 확인 뒤 다시 실행 |
| 1 | 사전 확인 | P1 앱 타깃 빌드 설정(팀·버전·Hardened Runtime), P2 작업 트리(변경은 경고만, git 으로 읽지 못하면 오류), P3 dmg 서명 인증서, P4 공증 프로필(`notarytool history` 로 읽기만, 제출 아님)을 모두 검사하고 빠진 것을 한꺼번에 알린다. **CI 모드:** P2 는 변경이 있으면 오류(깨끗한 체크아웃만 배포. `RELEASE_NO_SUBMIT=1` 일 때만 경고). P3 은 `RELEASE_KEYCHAIN` 에서만 찾고, 키체인 파일이 없거나 사용자 검색 목록에 없으면 오류. P4 는 API 키로 `notarytool history`(세 값 중 빈 것이 있거나 키 파일을 읽을 수 없으면 notarytool 전에 오류). P5 `spctl --status` 가 `assessments enabled` 가 아니면 오류(Gatekeeper 가 꺼져 있으면 12단계 검사가 판정하지 못하므로 archive·공증 전에 멈춘다) | 안내대로 2절 준비를 마친다. P1 은 `make project` 와 `Env` 값을 확인. **CI 모드:** P3 에서 "인증서는 있지만 유효한 서명 인증서로 보이지 않습니다" 면 신뢰 체인(G1 중간 인증서) 문제, "인증서·개인 키가 없습니다" 면 .p12 내용(Developer ID Application 인증서와 개인 키)을 확인한다. P4 는 키 ID·발급자 ID·키 파일·키 역할을 확인 |
| 2 | archive | Release 구성으로 archive (`build/release/DerivedData` 에서 매번 전체 빌드). 앱 타깃 서명 인증서가 `-` 라 여기서는 ad-hoc 이다 | `build/release/archive.log` 의 `error:` 줄 |
| 3 | Developer ID 내보내기 | `method developer-id`, `signingStyle automatic` 으로 export (`-allowProvisioningUpdates`). Xcode 가 Developer ID 로 다시 서명한다. **CI 모드:** `signingStyle manual`, `signingCertificate` = P3 에서 찾은 인증서의 SHA-1 로 export(`-allowProvisioningUpdates`·Xcode 계정·프로필 없음) | `build/release/export.log`. Xcode 계정 로그인 확인. 설정 파일(`ExportOptions.plist`)을 쓰지 못하면 디스크 공간·쓰기 권한. **CI 모드:** 임시 키체인의 잠금·인증서와 개인 키 확인 |
| 4 | 앱 서명 검사 | `codesign --verify --strict --deep`, Authority 가 `Developer ID Application: … (<팀>)`, TeamIdentifier, Hardened Runtime(`flags` 에 `runtime`), 보안 타임스탬프, `get-task-allow` 없음, Info.plist 버전이 빌드 설정과 같음 | 어긋난 항목과 기대값·실제값이 보인다 |
| 5 | 확인 | 요약을 보이고 터미널에서 답을 받는다. 여기 전에는 공증 서비스로 파일을 보내지 않는다 (1단계 P4 의 자격 증명 확인과 3단계 내보내기 서명은 Apple 서버와 통신한다). **CI 모드:** 요약에 `공증: App Store Connect API 키`·`키체인:`·`모드: CI (API 키 공증, 확인 없이 제출)` 를 보이고 묻지 않고 진행한다 | 거절(빈 답·터미널 없음 포함)이면 제출하지 않고 끝난다. **CI 모드:** `RELEASE_NO_SUBMIT=1` 이면 `제출하지 않고 멈췄습니다 (RELEASE_NO_SUBMIT=1).` 로 끝난다(종료 3) |
| 6 | 앱 공증 | 앱을 zip 으로 묶어 `notarytool submit` → `wait` → `info` 의 `status` 가 `Accepted` 인지 본다. **CI 모드:** 같은 흐름을 API 키 인자(`--key`·`--key-id`·`--issuer`)로 한다 | 거절(`Invalid`·`Rejected`)이면 `build/release/notary/app-log.json` 의 `issues`. 시간 초과(`In Progress`)면 안내된 `notarytool info` 로 확인 뒤 다시 실행. 상태를 조회하지 못했거나(`notarytool info` 실패, `status` 없음) 모르는 상태면 거절로 보지 않고 제출 ID 와 확인 명령을 알린다: `Accepted` 면 다시 실행, `Invalid`·`Rejected` 면 `notarytool log` 로 이유를 본다. 앱 zip 을 만들지 못하면(제출 전) 디스크 공간 확인 뒤 다시 실행. **CI 모드:** 안내 명령의 인증 인자는 자리표시자(`--key <API 키 파일> --key-id <키 ID> --issuer <발급자 ID>`)로 보인다 |
| 7 | 앱 staple | `stapler staple` → `stapler validate` | 공증 직후 티켓 배포가 늦을 수 있다. 잠시 뒤 다시 실행 |
| 8 | dmg 만들기 | 앱 + `Applications` 바로가기로 작업 이름 `unfinished-SimLauncher-<버전>.dmg` 로 `hdiutil create -format UDZO -fs APFS` | 앱·바로가기를 담을 폴더를 준비하지 못하면 디스크 공간 확인 뒤 다시 실행. 이미지를 만들지 못하면 hdiutil 출력 |
| 9 | dmg 서명 | 로컬 Developer ID Application 인증서(SHA-1 로 지정)로 `codesign --timestamp`. 작업 이름이 서명에 남지 않게 식별자를 `-i SimLauncher-<버전>` 으로 준다. **CI 모드:** 같은 인증서를 `--keychain <임시 키체인>` 에서만 찾는다 | 키체인 접근 대화상자에서 거절했으면 다시 실행해 "항상 허용". **CI 모드:** 임시 키체인의 잠금과 개인 키 파티션 목록(`ci-keychain.sh setup` 이 codesign 을 넣는다) 확인 |
| 10 | dmg 공증 | 6단계와 같다 (`dmg-submit.json`·`dmg-info.json`·`dmg-log.json`) | 6단계와 같다 |
| 11 | dmg staple | 7단계와 같다 | 7단계와 같다 |
| 12 | 최종 검사 | 5절의 검사를 모두 돌리고 종료 코드로 판정. dmg 를 `build/release/mnt` 에 읽기 전용으로 마운트해 안의 앱과 `Applications` 바로가기도 본다. 모두 통과하면 `SimLauncher-<버전>.dmg` 로 이름을 바꾼다. **CI 모드:** 같다(Gatekeeper 가 켜져 있는지는 1단계 P5 가 이미 봤다) | 실패한 검사 이름이 보인다. 작업 dmg 는 배포 이름으로 옮기지 않는다. 마운트 폴더를 만들지 못하거나 마운트하지 못하면 검사하지 못한 것으로 멈춘다. 검사 뒤 분리하지 못하거나 SHA-256 을 구하지 못하면 경고만 하고 끝까지 간다(배포 dmg 는 그대로 유효). `spctl` 검사만 실패하고 `spctl --status` 가 `assessments disabled` 면 이 Mac 의 Gatekeeper 평가가 꺼져 있어 판정하지 못한 것이다: 켠 Mac 에서 다시 한다 |

스크립트 종료 코드: 0 성공, 1 단계 실패, 2 사전 확인 실패, 3 공증 제출을 거절함(CI 모드에서는 `RELEASE_NO_SUBMIT=1` 로 멈춤), 130 중단(Ctrl-C). `RELEASE_CI` 값이 틀리면(비어 있지도 `1` 도 아니면) 0단계 전에 종료 2. `경고:` 만 나온 실행은 종료 0 이다. `make release` 로 실행하면 make 자신은 실패를 모두 종료 2 로 돌려주고, 스크립트의 종료 코드는 마지막 줄 `make: *** [release] Error <코드>` 에 보인다.

- **재실행**: 언제나 0단계부터 처음부터 한다. 중간부터 이어 하지 않는다. 앞선 실행에서 앱 공증이 끝났어도 새 archive 로 다시 제출한다.
- **중단(Ctrl-C)**: 공증을 기다리던 중이면 제출 ID 와 확인 명령(`xcrun notarytool info <ID> --keychain-profile <프로필>`, CI 모드는 `--key <API 키 파일> --key-id <키 ID> --issuer <발급자 ID>`)을 알린다. 제출한 공증은 Apple 쪽에서 계속 처리된다(취소 명령이 없다). 검사용 마운트는 스크립트가 끝날 때 분리한다.
- **공증 거절 이유 보기**: `build/release/notary/<app|dmg>-log.json` 의 `issues` 에 파일 경로와 이유가 있다(CI 는 build 잡이 실패하면 `release-logs` 아티팩트에 `notary/*.json` 이 올라간다). 다시 받으려면 `xcrun notarytool log <제출 ID> --keychain-profile simlauncher-notary`, CI 에서 제출한 것은 같은 팀 API 키로 `xcrun notarytool log <제출 ID> --key <AuthKey_….p8> --key-id <키 ID> --issuer <발급자 ID>`(로컬 Mac 에서, 키 파일은 레포 밖에 둔다). 상태를 조회하지 못했거나 status 가 없거나 모르는 상태로 멈춘 경우에는 `log.json` 을 받지 않는다. 안내된 `xcrun notarytool info`·`log` 를 직접 실행한다.

### 릴리스 워크플로가 실패하면
워크플로(`.github/workflows/release.yml`)는 check → build ∥ notes → publish 순서로 돈다. 실패한 잡과 로그는 Actions 탭의 run 에서 본다.

| 증상 | 원인 | 할 일 |
|---|---|---|
| check 실패: 경량 태그·버전 불일치·빌드 번호가 이전 릴리스보다 크지 않음·main 에 머지되지 않은 커밋·이미 게시된 Release | 태그를 잘못 붙였거나 버전 PR 이 빠졌다 | 태그를 지우고(`git push origin :refs/tags/<버전>`, `git tag -d <버전>`) 원인을 고친 뒤 3.1 순서대로 주석 태그를 다시 push 한다. 이미 게시된 버전이면 새 버전으로 올린다 |
| build·publish 실패로 게시하지 못한 태그 | archive·서명·공증·게시 중 실패 | 일시적 실패(네트워크·Apple 지연)면 run 의 **Re-run failed jobs**. 고칠 것이 있으면 태그를 지우고 고친 뒤 다시 push 한다. 게시되지 않은 태그를 그대로 두면 다음 릴리스 노트는 그 태그를 "이전 릴리스" 로 보지 않고 건너뛴다(게시된 Release 가 있는 태그만 이전 태그로 쓴다) |
| build 가 Queued 로 오래 머문다(최대 24시간) | `xcode-27` 러너 레이블(미리보기)의 대기열이 막혔거나 레이블이 바뀌었다 | actions/runner-images 의 공지와 레이블을 확인한다. 급하면 run 을 취소하고 3.2 의 로컬 `make release` 로 게시한다(예비 경로) |
| run 이 취소됨 | 같은 동시 실행 그룹(`release`)에서 대기 중인 run 은 하나만 남아, 태그를 연달아 push 하면 가운데 run 이 취소될 수 있다 | 앞 run 이 끝난 뒤 취소된 run 을 **Re-run all jobs** |
| notes 잡 실패(도우미 테스트 `make release-scripts-test`·노트 재료 `release-notes.sh prepare`: 이전 릴리스 태그 없음·PR 조회 실패·머지 커밋 불일치, 요약 검사 단계 자체의 오류) | gh API 일시 오류, 머지 방식이 바뀌어 머지 커밋에서 PR 을 찾지 못함 | publish 가 돌지 않아 게시되지 않는다. 로그로 원인을 확인하고 일시적이면 **Re-run failed jobs**, 고칠 것이 있으면 고친 뒤 태그를 지우고 다시 push 한다 |
| notes 잡의 Claude 설치·요약(Claude) 단계 실패(잡은 계속 진행)·요약 검사의 거절 경고 | CLI 설치·실행 실패, 또는 요약에 링크·멘션 등 허용하지 않는 내용이 있어 거절했다 | 할 일 없음. 경고만 남고 노트는 기본 문장 + PR 목록으로 게시된다. 게시 뒤 노트를 손보려면 `gh release edit <버전> --notes-file <파일>` |
| publish 실패: 같은 태그의 Release(초안 포함)가 이미 있다 | 앞선 실행이 반쯤 만든 Release 나 손으로 만든 초안이 남았다 | `gh release view <버전>` 으로 확인해 지운 뒤(`gh release delete <버전>`, 태그는 지우지 않는다) **Re-run failed jobs** |
| publish 실패: 게시 확인 불일치(초안·Pre-release·첨부 파일 SHA-256·latest) | 게시는 되었지만 상태가 기대와 다르다 | 3.1 의 8·9번대로 게시본을 직접 확인하고, 틀린 것은 `gh release edit`·첨부 파일 교체로 고친다 |
| build 의 1단계 사전 확인 P5 실패(Gatekeeper 꺼짐) | 러너 이미지의 Gatekeeper 평가가 꺼져 있다 | 공증 전에 멈췄으므로 게시물은 없다. 러너에서 켜는 단계를 둘지, CI 는 stapler·codesign 만 보고 Gatekeeper 는 3.1 의 9번(사람)으로 확인할지 다시 정한다 |

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

릴리스 워크플로의 시험 실행(3.1 의 3번)이 남긴 `SimLauncher-dmg` 아티팩트(공증된 dmg)의 앱으로 확인해도 된다. 같은 Developer ID 인증서로 서명했고 entitlement 도 같다.

Gatekeeper 동작(다운로드한 앱의 첫 실행)까지 보려면 공증된 dmg 를 브라우저로 내려받아(quarantine 이 붙도록) 연다. 이 Mac 에서는 받은 앱을 응용 프로그램 폴더에 대치해 받은 파일의 판정을 보고(3.1 의 9번), 이 Mac 의 인증서·이전 실행 허용이 없는 환경(로드맵 단계 목표의 "다른 Mac")은 다른 Mac 이나 이 Mac 의 새 사용자 계정에서 본다. "확인되지 않은 개발자"·"손상되었습니다" 차단 없이 열려야 하고, 인터넷에서 받은 앱마다 뜨는 첫 실행 확인은 정상이다.

## 7. 서명 설정
설정은 모두 `Env`(`Tuist/ProjectDescriptionHelpers/Project+Templates.swift`)에 있다 (ARCHITECTURE §2 빌드 설정).
- **Hardened Runtime**: 앱 타깃(`SimLauncher`)만 `Env.appTargetSettings` 로 켠다. Example 앱·모듈·테스트에는 주지 않는다. Debug(ad-hoc) 빌드에서는 Xcode 가 Hardened Runtime 을 끄므로(`Disabling hardened runtime with ad-hoc codesigning`) 개발 실행은 지금과 같다.
- **entitlement·App Sandbox 없음**: Developer ID·Hardened Runtime 으로 서명하고 entitlement 없이 실행해, 앱이 쓰는 동작이 모두 돈다는 것을 확인했다 (2026-10-27, macOS 26.6·Xcode 27.1): `xcode-select`·`xcodebuild -checkFirstLaunchStatus`·`-license check`, `simctl` 목록·생성·켜기·설치·실행·`openurl`·스크린샷·녹화(`SIGINT` 로 멈춤)·끄기·삭제, `zipinfo`·`ditto`, URLSession 다운로드, `NSWorkspace` 로 Finder 에서 보이기. 자식 프로세스(`simctl` 등)는 자기 서명으로 돈다. App Sandbox 는 `simctl` 실행에 Sandbox 밖 동작이 필요해 쓰지 않는다 (ARCHITECTURE §4). 동영상 폴더(`~/Movies/SimLauncher`)에 녹화를 저장할 때 권한 팝업이 뜨지 않는 것은 배포 서명·공증 빌드(1.0.0)의 수동 확인으로 봤다 (2026-10-27). 1.1.0 배포 빌드의 수동 확인(2026-11-02, export 앱과 게시본): Android 기기를 켤 때 마이크(`kTCCServiceMicrophone`)와 AppleEvents 는 entitlement(`com.apple.security.device.audio-input`·`automation.apple-events`)가 없어 tccd 가 팝업 없이 거부하지만, 에뮬레이터는 계속 켜져 동작하고 사용자 기능에는 영향이 없다. 사진·동영상 폴더에 Android 스크린샷·녹화를 저장할 때도 권한 팝업 없이 저장되고, 빈 폴더에 앱이 설치한 Android SDK 로 켠 에뮬레이터는 Gatekeeper 에 막히지 않았다.
- **서명 흐름**: 앱 타깃의 서명 인증서는 Tuist 기본 `-`(Sign to Run Locally)라 archive 는 ad-hoc 이다. 로컬 `make release` 는 developer-id export(`signingStyle automatic`)가 클라우드 관리 Developer ID 인증서로 다시 서명하고, 릴리스 워크플로(CI 모드)는 임시 키체인의 Developer ID Application 인증서(.p12, dmg 서명과 같은 인증서)로 manual export(`signingStyle manual`, 프로비저닝 프로필 없음) 한다. `make build`·`make test`·PR CI 는 `CODE_SIGNING_ALLOWED=NO` 로 서명하지 않는다.
- **버전·저작권**: `Env.appVersionInfoPlist` 가 앱 Info.plist 의 `CFBundleShortVersionString`·`CFBundleVersion` 을 빌드 설정으로, `NSHumanReadableCopyright`("SimLauncher에 관하여" 창)를 저작권 문구로 바꾼다.
