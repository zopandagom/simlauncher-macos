# 개발 계획

## 목표
- 누구에게: iPhone·iPad 가 없어 개발 중인 iOS 앱을 테스트하지 못하는 인원 (비개발자 포함). 공개 레포로 열어, 어느 회사든 자기 인프라(빌드 저장소)에 맞춰 쓸 수 있게 한다
- 무엇을: Mac 만 있으면 iOS 시뮬레이터를 띄우고 iOS 앱 빌드를 설치·실행해 테스트할 수 있게 한다
- 참고: 카카오페이 [멀티버스](https://tech.kakaopay.com/post/multiverse/) (가상 기기 + 앱 센터 + 테스트 편의 기능)
- 범위: iOS 시뮬레이터 먼저. Android 에뮬레이터는 후속
- 화면 언어: 한국어 먼저. 문자열은 처음부터 String Catalog(`Localizable.xcstrings`)에 둬서 영어를 나중에 추가한다
- 라이선스: MIT
- 출시 목표: 미정

## 핵심 기능 (MVP)
| 영역 | 기능 | 기술 메모 |
|---|---|---|
| 사용 환경 | Xcode·시뮬레이터 런타임 확인, 없으면 안내. iOS 런타임은 앱에서 설치 | `xcode-select -p`, `simctl runtime list`, `xcodebuild -downloadPlatform iOS`. 선택된 개발자 디렉터리가 Command Line Tools 이면 `/Applications` 의 Xcode 를 찾아 `DEVELOPER_DIR` 를 지정해 실행한다 (사용자에게 `xcode-select -s` 를 시키지 않는다). 이렇게 고른 Xcode 를 `simctl`·`xcodebuild` 가 함께 쓴다 (ARCHITECTURE §4). Xcode 는 App Store 페이지를 열고, 라이선스 동의·첫 실행 준비는 단계별 안내 |
| 시뮬레이터 | 기기 목록, 부팅·종료, 생성·삭제·초기화, Simulator 앱 띄우기 | `simctl list -j`, `boot`/`shutdown`, `create`/`delete`/`erase`, 개발자 디렉터리의 Simulator 앱(Xcode 27.1 은 DeviceHub)을 `open` |
| 앱 설치 | 로컬 .app(또는 .app 을 담은 zip)을 골라 설치. 드래그 앤 드롭 | `simctl install <기기> <.app>`. `AppBundle` Client 가 `Info.plist`(XML·바이너리)의 지원 플랫폼·`MinimumOSVersion` 과 실행 파일 Mach-O 헤더의 아키텍처를 읽고, Core 규칙이 대상 기기와 대조해 .ipa·Mac 앱·기기용·아키텍처·iOS 버전이 맞지 않는 빌드를 이유와 함께 거절. 꺼진 기기는 켜고, Simulator 앱을 열어(켜진 기기도) 설치하고 바로 실행 |
| 앱 설치 | URL 의 .app(zip) 을 내려받아 설치 ("직접 설치") | `URLSession` 다운로드(진행률·취소), `ditto -x -k` 로 압축 해제 |
| 빌드 카탈로그 | 설정에서 카탈로그 URL 을 등록하고, 앱·버전 목록에서 골라 설치 | 정적 `catalog.json` 하나 (규격은 아래). 서버 없이 GitHub Releases·S3·사내 웹 서버 어디든 둘 수 있다 |
| 앱 실행 | 설치한 앱 실행, 딥링크 열기 | `Info.plist` 의 번들 ID 로 `simctl launch`, `simctl openurl <기기> <url>` |

## 빌드 카탈로그
특정 회사 인프라에 묶이지 않도록, 앱이 읽는 카탈로그 형식을 이 프로젝트의 공개 규격으로 정한다.
- 사용자가 설정 화면에서 카탈로그 URL 을 하나 이상 등록한다. 회사 일괄 배포용으로 `defaults write` 나 MDM 으로 미리 넣을 수 있게 한다 (선택). 미리 넣은 값도 같은 사용자 설정 키라서 네트워크 규칙의 "사용자가 등록한 카탈로그"에 든다
- `catalog.json` 은 `schemaVersion` 과 앱 → 버전(이름·브랜치·태그·빌드 번호·생성 시각) → 빌드 zip URL 을 담는다. 규격 문서는 4단계에서 확정한다
- 레포에 예시 GitHub Actions 워크플로를 둔다: `xcodebuild -sdk iphonesimulator` → zip → Release 업로드 → `catalog.json` 갱신
- 첫 버전은 인증 없는 HTTPS URL 만 지원한다. 비공개 저장소(토큰 헤더 등) 인증은 후속
- 공개 레포의 GitHub Releases 는 누구나 받을 수 있다. 개발 중 확인은 샘플 앱 빌드로만 하고, 회사 앱 빌드는 각자 비공개 저장소에 둔다
- GitHub Releases 로 둘 때 고정 URL: `https://github.com/<owner>/<repo>/releases/latest/download/catalog.json` (파일당 2 GiB 미만, 릴리스당 파일 1000개, 전체 용량·트래픽 제한 없음)

## 로드맵
| 단계 | 목표 | 단계 목표 확인 |
|---|---|---|
| 0 | 하네스 확인과 첫 화면 (`Home` → `Launcher`) | `/verify` PASS, 앱이 실행되어 첫 화면이 보인다 |
| 1 | 기기 목록·부팅·종료·생성·삭제·초기화 (`Core` 값 타입, `Simulator` Client. Impl 은 Xcode 경로 provider 를 주입받고, 이 단계에서 App 은 `nil` 을 넘겨 `xcode-select` 기본값으로 실행) | 기기가 OS 별로 보이고, 부팅하면 Simulator 창이 뜬다. `simctl` JSON 해석 테스트 |
| 2 | 로컬 .app 설치·실행, 딥링크 (`AppBundle` Client 는 번들 검사·압축 해제만, 설치·실행·딥링크는 `Simulator` Client 에 추가) | 시뮬레이터용 .app 은 설치·실행되고, .ipa·기기용·아키텍처가 맞지 않는 빌드는 이유와 함께 거절된다 |
| 3 | 환경 확인과 런타임 설치 (`DevEnvironment` Client 는 Xcode 확인·선택·런타임 설치이고, `DevEnvironment` Client 가 고른 Xcode 경로를 App 이 `Simulator` Client 의 provider 로 연결한다. 런타임 목록은 `Simulator` Client 가 제공. `Setup` Feature) | Xcode·런타임이 없는 Mac 에서 할 일이 화면에 나오고, 런타임은 앱에서 설치된다 |
| 4 | 직접 URL 설치, 카탈로그 URL 설정·목록 (`Download` Client), 카탈로그 규격 문서와 예시 GitHub Actions | URL 이나 카탈로그 항목을 고르면 다운로드 → 압축 해제 → 설치 → 실행까지 이어진다. 네트워크 오류·잘못된 파일 처리 |
| 5 | 스크린샷·녹화, 여러 기기 동시 실행 | `simctl io screenshot`/`recordVideo` 결과가 저장되고 Finder 에서 열린다. 한 빌드를 여러 기기에 설치한다 |
| 6 | Developer ID 서명·공증 배포, 업데이트 알림 | 다른 Mac 에서 내려받아 Gatekeeper 경고 없이 실행된다. 새 버전이 있으면 알리고 다운로드 페이지를 연다 |
| 이후 | 비공개 저장소 인증, 업데이트 자동 교체(서명·팀 ID 검증 필수), 설치된 앱 관리(`listapps`·`uninstall`), 테스트 조건 바꾸기(외관·언어·위치·푸시·권한), 앱 로그 보기, 영어 지원, **Android 에뮬레이터** | — |

`simctl` 하위 명령은 모두 `Simulator` Client Impl 이 실행한다 (ARCHITECTURE §4). "단계 목표 확인" 열은 단계가 이룰 결과이고, 각 단계 작업을 시작할 때 명령으로 판정할 수용 확인(CONVENTIONS §6)과 사용자의 수동 확인(CONVENTIONS §5 "수동 확인" 행)으로 나눠 작업 범위에 적는다.

업데이트는 외부 의존성(Sparkle 등) 없이 구현한다 (ARCHITECTURE §4). 사용자는 Homebrew Cask 로도 업데이트할 수 있다.

## 작업 진행 방식
1. 로드맵의 단계 목표와 "단계 목표 확인" 열을 확인 → 작업 단위로 쪼갠다.
2. `feat|fix|chore/<요약>` 브랜치 생성 (일정 표시 없이, CONVENTIONS §5).
3. Client 가 필요하면 **Interface 먼저** 설계(프로토콜 + 값 타입) → Fake → Feature Model + 테스트 → Impl 순서. Impl 없이도 Example 앱으로 화면을 확인할 수 있다.
4. 역할 단위로 작업 범위·수용 확인을 정하고 구현 → `/verify` → `/arch-review`. 새 상태·실패 경로가 생기는 구현과 그 리뷰 지적 수정은 팀으로 한다 (CONVENTIONS §6 "팀 구현"). 커밋은 사용자 지시로 `/micro-commit` (CONVENTIONS §5).
5. 사용자 지시로 `/pr` (마지막 커밋 검사(빌드에 영향이 있으면 lint·빌드·테스트) + 전체 `/arch-review` → PR 생성, 유형 라벨) → CI + Claude 리뷰 → 리뷰 반영 커밋도 `/pr` 로 push (CI 지적에 답) → 머지 전 확인 뒤 Merge commit 으로 머지 (CONVENTIONS §5 "리뷰 지적 처리").
6. 결정이 바뀌었으면 문서 갱신을 같은 PR 에 포함한다 (별도 커밋, type 은 CONVENTIONS §5 마이크로 커밋 표).

## 완료 기준 (Definition of Done)
- [ ] `/pr` 의 마지막 커밋 검사 PASS·SKIP, 필수 체크 `ci-result` 통과, 머지 전 확인 충족 (CONVENTIONS §5 "리뷰 지적 처리")
- [ ] CONVENTIONS §3 이 요구하는 테스트 (미뤘으면 그 보류 기록, CONVENTIONS §5 "리뷰 지적 처리")
- [ ] 해당하는 수동 확인(Example 앱 주요 상태, 배포 서명 빌드) 완료 (CONVENTIONS §5 표 "수동 확인" 행)
- [ ] 제품 약속(CONVENTIONS §4) 위반 없음

## 출시 전 준비 체크리스트 (코드 외)
| 항목 | 필요 시점 | 상태 |
|---|---|---|
| Apple Developer Program 가입 | 배포 전 | ☑ |
| 팀 ID 를 `Env.developmentTeam` 에 입력 (팀 ID 는 공개 정보라 커밋해도 된다) | 배포 전 | ☐ |
| Developer ID Application 인증서 발급, `notarytool` 자격 증명 준비. 커밋하지 않고, CI 에서 쓰면 GitHub Secrets + 승인이 필요한 Environment 에 둔다 | 배포 전 | ☐ |
| `LICENSE`(MIT) | 공개 전 | ☑ |
| GitHub 설정: 공개 전환, 외부 기여자 워크플로 승인, Secret scanning·push protection, main 룰셋(필수 체크 `ci-result`) | 공개 시 | ☑ |
| 배포 경로: GitHub Releases 에 공증된 zip/dmg, Homebrew Cask (선택) | 6단계 | ☐ |

## 위험과 대응
| 위험 | 대응 |
|---|---|
| 사용하는 Mac 에 Xcode·iOS 시뮬레이터 런타임이 없으면 동작하지 않음 (비개발자는 설치가 낯설다) | 첫 실행에 환경을 확인한다. iOS 런타임은 앱에서 설치하고, Xcode 설치·라이선스 동의·첫 실행 준비는 화면에서 단계별로 안내 |
| 기기용 빌드(.ipa)는 시뮬레이터에 설치되지 않음 | 시뮬레이터용(`-sdk iphonesimulator`) .app 만 받는다고 화면에 알리고, 맞지 않는 파일은 이유와 함께 거절. 테스트할 iOS 앱 CI 에서 시뮬레이터 빌드를 올리는 작업이 따로 필요해, 예시 GitHub Actions 와 카탈로그 규격을 제공한다 |
| `xcrun simctl` 실행에는 App Sandbox 밖 동작이 필요해 Mac App Store 배포가 어려움 | Developer ID 서명·공증 배포 (ARCHITECTURE §4) |
| Apple 실리콘 Mac 에서는 arm64 slice 가 없는 시뮬레이터 빌드가 설치되지 않음 (`simctl install` 이 거절, Xcode 27.1·iOS 27.0 에서 확인) | 설치 전에 실행 파일 아키텍처를 검사해 이유를 보여 준다 (2단계) |
| 공개 레포라 외부 PR 이 워크플로를 돌리거나 Releases 의 빌드가 누구에게나 공개됨 | PR 트리거는 `pull_request` 만 쓰고 `pull_request_target` 은 쓰지 않는다(fork PR 은 시크릿 없음), 외부 기여자 워크플로는 승인 후 실행. Releases 에 올리는 iOS 앱 빌드는 샘플 앱만 (회사 앱 빌드는 각자 비공개 저장소에) |
| 입력받은 URL·zip 이 신뢰할 수 없는 내용일 수 있음 | HTTPS 만 허용, 압축 해제 경로가 대상 폴더를 벗어나지 않는지 검사 (CONVENTIONS §4) |
