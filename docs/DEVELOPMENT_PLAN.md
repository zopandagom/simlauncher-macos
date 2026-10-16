# 개발 계획

## 목표
- 누구에게: 회사에서 iPhone·iPad 가 없어 개발 중인 iOS 앱을 테스트하지 못하는 인원 (비개발자 포함)
- 무엇을: Mac 만 있으면 iOS 시뮬레이터를 띄우고 iOS 앱 빌드를 설치·실행해 테스트할 수 있게 한다
- 출시 목표: 미정

## 핵심 기능 (MVP)
| 영역 | 기능 | 기술 메모 |
|---|---|---|
| 시뮬레이터 | 기기 목록 보기, 고른 기기 부팅, Simulator 앱 띄우기 | `xcrun simctl list -j`, `simctl boot`, `open -a Simulator` |
| 앱 설치 | 로컬 .app 파일을 골라 설치 | 파일 선택, `simctl install <기기> <.app>` |
| 앱 설치 | URL 의 .app(zip) 을 내려받아 설치 | `URLSession` 다운로드, zip 압축 해제 후 `simctl install` |
| 앱 실행 | 설치한 앱 실행 | .app 의 `Info.plist` 에서 번들 ID 를 읽어 `simctl launch` |
| 사용 환경 | Xcode·시뮬레이터 런타임이 없으면 설치 안내 | `xcode-select -p`, `simctl runtime list` |

## 로드맵
첫 단계: 하네스 확인과 첫 화면

## 작업 진행 방식
1. 로드맵의 단계 목표와 완료 기준을 확인 → 작업 단위로 쪼갠다.
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
| Apple Developer Program 가입, 팀 ID 를 `Env.developmentTeam` 에 입력 | 배포 전 | ☐ |
| App ID `com.zopandagom.simlauncher` 등록 | 배포 전 | ☐ |
| App Store Connect 앱 생성, 앱 이름 선점 ("SimLauncher") | 가능한 빨리 | ☐ |
| `PrivacyInfo.xcprivacy`, 개인정보 처리방침 페이지 | 출시 전 | ☐ |
| 스토어 스크린샷·설명·키워드 (ASO) | 출시 전 | ☐ |

## 위험과 대응
| 위험 | 대응 |
|---|---|
| CI macOS 분 소진 (비공개 무료 플랜 2,000분, macOS 10배) | 문서만 바뀐 PR 은 CI 생략, lint 는 Ubuntu. 부족하면 셀프 호스트 러너나 레포 공개 검토 |
| 사용하는 Mac 에 Xcode·iOS 시뮬레이터 런타임이 없으면 동작하지 않음 (비개발자는 설치가 낯설다) | 첫 실행에 환경을 확인하고 설치 방법을 화면에서 안내 |
| 기기용 빌드(.ipa)는 시뮬레이터에 설치되지 않음 | 시뮬레이터용(`-sdk iphonesimulator`) .app 만 받는다고 화면에 알리고, 맞지 않는 파일은 이유와 함께 거절. 테스트할 iOS 앱 CI 에서 시뮬레이터 빌드를 올리는 작업이 따로 필요 |
| `xcrun simctl` 실행에는 App Sandbox 밖 동작이 필요해 Mac App Store 배포가 어려움 | Developer ID 서명·공증 배포 (ARCHITECTURE §4) |
