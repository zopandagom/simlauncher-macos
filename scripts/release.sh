#!/bin/bash
# 배포 dmg 를 만든다: 사전 확인 → archive → Developer ID 내보내기 → 앱 서명 검사 → (사용자 확인) →
# 앱 공증·staple → dmg 만들기·서명 → dmg 공증·staple → 최종 검사 → 배포 이름으로 옮기기. 준비·절차·실패별 할 일: docs/RELEASING.md
#
# 입력 환경 변수 (docs/RELEASING.md 4절):
#   로컬(기본): NOTARY_PROFILE(공증 키체인 프로필 이름, 필수), WORKSPACE(기본 SimLauncher.xcworkspace).
#   CI 모드(RELEASE_CI=1, 그 밖의 값은 오류): RELEASE_KEYCHAIN(scripts/ci-keychain.sh 가 만든 임시 키체인 경로),
#     NOTARY_KEY_PATH(App Store Connect API 키 .p8 파일 경로)·NOTARY_KEY_ID·NOTARY_ISSUER_ID 가 필수이고 NOTARY_PROFILE 은 쓰지 않는다.
#     RELEASE_NO_SUBMIT=1 이면 5단계에서 제출하지 않고 종료 3 (로컬 Mac 시험용. GITHUB_ACTIONS=true 와 함께면 사전 확인 오류).
#     CI 모드는 묻지 않고 제출하고, 내보내기는 임시 키체인의 인증서로 manual 서명한다.
# 비밀 값(앱 암호·API 키 내용·p12)은 다루지 않는다: 프로필 이름이나 키 파일 경로·키 ID·발급자 ID 만 notarytool 에 넘기고
# 환경 변수를 출력하지 않는다. set -x 를 쓰지 않는다.
# 종료 코드: 0 성공, 1 단계 실패, 2 사전 확인 실패(준비 안 됨), 3 공증 제출을 거절함, 130 중단.
# 산출물에 영향이 없는 정리(rm)·검사용 마운트 분리·SHA-256 계산이 실패하면 "경고:" 만 보이고 계속한다.
# 외부 출력은 codesign -dvv 의 영어 줄·security find-identity 줄·-showBuildSettings JSON·notarytool JSON 만 해석한다
# (CI 모드는 security list-keychains 줄과 사전 확인 P5 의 spctl --status 문구도 본다. CI 러너 로케일은 영어).
# hdiutil(출력이 현지화됨)·spctl·stapler 는 종료 코드로만 판정하고 출력은 그대로 보여 준다.
# shellcheck disable=SC2015 # "A && B || fail …" 은 A·B 중 하나라도 실패하면 fail 하라는 뜻으로 쓴다
set -euo pipefail

cd "$(dirname "$0")/.."

# 모드: RELEASE_CI 가 비어 있으면 로컬, 1 이면 CI. 그 밖의 값은 오타로 보고 아무것도 하지 않고 멈춘다
case ${RELEASE_CI:-} in
  "") CI_MODE=0 ;;
  1) CI_MODE=1 ;;
  *)
    echo "RELEASE_CI 는 비우거나 1 이어야 합니다 (실제: '$RELEASE_CI'). docs/RELEASING.md 4절" >&2
    exit 2
    ;;
esac
NO_SUBMIT=0
if [[ $CI_MODE == 0 ]]; then
  : "${NOTARY_PROFILE:?NOTARY_PROFILE 에 공증 키체인 프로필 이름을 주세요 (docs/RELEASING.md)}"
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
  # 안내 문구에 넣는 공증 인증 인자 (실제 값. 비밀이 아닌 프로필 이름)
  NOTARY_AUTH_HINT="--keychain-profile $NOTARY_PROFILE"
else
  RELEASE_KEYCHAIN="${RELEASE_KEYCHAIN:-}"
  NOTARY_KEY_PATH="${NOTARY_KEY_PATH:-}"
  NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
  NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:-}"
  [[ ${RELEASE_NO_SUBMIT:-} == 1 ]] && NO_SUBMIT=1
  NOTARY_AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
  # CI 안내 문구는 값 대신 자리표시자를 쓴다 (로그에 키 ID·발급자 ID 를 다시 찍지 않는다)
  NOTARY_AUTH_HINT="--key <API 키 파일> --key-id <키 ID> --issuer <발급자 ID>"
fi
WORKSPACE="${WORKSPACE:-SimLauncher.xcworkspace}"
SCHEME=SimLauncher
CONFIGURATION=Release
APP_NAME=SimLauncher

OUT=build/release
ARCHIVE="$OUT/$APP_NAME.xcarchive"
EXPORT_OPTIONS="$OUT/ExportOptions.plist"
APP="$OUT/export/$APP_NAME.app"
NOTARY_DIR="$OUT/notary"
DMG_ROOT="$OUT/dmg-root"
MOUNT_POINT="$PWD/$OUT/mnt"
TOTAL_STEPS=12

STEP=""
MOUNTED=0
NOTARY_ID=""

step() {
  STEP="[$1/$TOTAL_STEPS] $2"
  echo
  echo "==> $STEP"
}

# fail <종료 코드> <메시지…>: 산출물은 지우지 않는다(원인 확인용, 다음 실행이 처음에 지운다)
fail() {
  local code=$1
  shift
  {
    echo
    echo "실패 $STEP: $1"
    shift
    local line
    for line in "$@"; do echo "  $line"; done
  } >&2
  exit "$code"
}

on_exit() {
  if [[ $MOUNTED == 1 ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}

on_interrupt() {
  echo >&2
  echo "중단됨 $STEP" >&2
  if [[ -n $NOTARY_ID ]]; then
    echo "제출 ID $NOTARY_ID 는 Apple 쪽에서 계속 처리됩니다. 확인: xcrun notarytool info $NOTARY_ID $NOTARY_AUTH_HINT" >&2
  fi
  exit 130
}

trap on_exit EXIT
trap on_interrupt INT TERM

# --- 0. 이전 산출물 정리 -------------------------------------------------------
step 0 "이전 산출물 정리"
# 이전 실행이 SIGKILL·크래시로 마운트를 남겼을 수 있다. 스크립트가 쓰는 경로만 분리를 시도한다.
if [[ -d $MOUNT_POINT ]]; then
  hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
fi
rm -rf "$OUT" 2>/dev/null || fail 1 "build/release 를 지우지 못했습니다." \
  "마운트된 디스크 이미지를 분리(hdiutil detach $MOUNT_POINT)한 뒤 다시 실행하세요."
mkdir -p "$OUT" "$NOTARY_DIR" || fail 1 "build/release 를 만들지 못했습니다 (위 mkdir 출력)." \
  "디스크 공간과 레포 폴더의 쓰기 권한을 확인한 뒤 다시 실행하세요."

# canonical_path <경로>: 폴더의 심볼릭 링크를 푼 절대 경로 (키체인 검색 목록과 비교용). 폴더가 없으면 실패
canonical_path() {
  local dir
  dir=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$dir" "$(basename "$1")"
}

# keychain_in_search_list <경로>: 사용자 키체인 검색 목록(security list-keychains -d user 의 따옴표 줄)에 있는가
keychain_in_search_list() {
  local want line entry
  want=$(canonical_path "$1") || return 1
  while IFS= read -r line; do
    entry=${line#"${line%%[![:space:]]*}"}
    entry=${entry#\"}
    entry=${entry%\"}
    [[ -n $entry ]] || continue
    if [[ $entry == "$want" || $(canonical_path "$entry" 2>/dev/null || true) == "$want" ]]; then
      return 0
    fi
  done < <(security list-keychains -d user)
  return 1
}

# --- 1. 사전 확인: P1~P4 (CI 모드는 P5 까지) 를 모두 검사하고 실패를 한꺼번에 보인다 ------------
step 1 "사전 확인"
PREFLIGHT_ERRORS=()
if [[ $CI_MODE == 1 ]]; then
  case ${RELEASE_NO_SUBMIT:-} in
    "" | 1) ;;
    *) PREFLIGHT_ERRORS+=("RELEASE_NO_SUBMIT 는 비우거나 1 이어야 합니다 (실제: '$RELEASE_NO_SUBMIT').") ;;
  esac
  if [[ $NO_SUBMIT == 1 && ${GITHUB_ACTIONS:-} == true ]]; then
    PREFLIGHT_ERRORS+=("CI 러너(GITHUB_ACTIONS=true)에서는 RELEASE_NO_SUBMIT 를 쓰지 않습니다. 로컬 Mac 에서 CI 모드를 시험할 때만 씁니다 (docs/RELEASING.md 4절).")
  fi
fi
TEAM=""
MARKETING_VERSION=""
BUILD_NUMBER=""
DMG_IDENTITY=""
DMG_IDENTITY_NAME=""

# P1 빌드 설정
if settings_json=$(xcodebuild -showBuildSettings -workspace "$WORKSPACE" -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" -json 2>/dev/null) \
  && settings=$(jq -er --arg target "$APP_NAME" '.[] | select(.target == $target) | .buildSettings
    | [.DEVELOPMENT_TEAM // "", .MARKETING_VERSION // "", .CURRENT_PROJECT_VERSION // "",
       .ENABLE_HARDENED_RUNTIME // ""] | map(tostring) | join("\u001f")' <<<"$settings_json"); then
  # 구분자는 공백이 아닌 문자여야 빈 값이 사라지지 않는다 (탭은 IFS 공백이라 빈 칸이 당겨진다)
  IFS=$'\x1f' read -r TEAM MARKETING_VERSION BUILD_NUMBER hardened_runtime <<<"$settings"
  [[ -n $TEAM ]] || PREFLIGHT_ERRORS+=("P1 Env.developmentTeam 이 비어 있습니다 (Tuist/ProjectDescriptionHelpers/Project+Templates.swift).")
  [[ $hardened_runtime == YES ]] || PREFLIGHT_ERRORS+=("P1 앱 타깃의 ENABLE_HARDENED_RUNTIME 이 YES 가 아닙니다(실제: '$hardened_runtime'). 공증에 필요합니다 (Env.appTargetSettings).")
  [[ -n $MARKETING_VERSION && -n $BUILD_NUMBER ]] || PREFLIGHT_ERRORS+=("P1 버전(MARKETING_VERSION)이나 빌드 번호(CURRENT_PROJECT_VERSION)가 비어 있습니다 (Env.marketingVersion·Env.buildNumber).")
else
  PREFLIGHT_ERRORS+=("P1 $SCHEME 타깃의 빌드 설정을 읽지 못했습니다. make project 가 성공하는지 확인하세요.")
fi

# P2 작업 트리: 로컬은 변경을 경고만 한다. CI 모드는 깨끗한 체크아웃만 배포하므로 변경이 오류다
# (RELEASE_NO_SUBMIT=1 이면 제출하지 않아 배포물이 생기지 않으므로 경고). git 을 읽지 못하면 오류다
COMMIT=""
DIRTY=""
if COMMIT=$(git rev-parse --short HEAD) && DIRTY=$(git status --porcelain); then
  if [[ -n $DIRTY ]]; then
    if [[ $CI_MODE == 0 ]]; then
      echo "경고: 커밋되지 않은 변경이 있습니다. 확인 질문에서 다시 묻습니다."
    elif [[ $NO_SUBMIT == 1 ]]; then
      echo "경고: 커밋되지 않은 변경이 있습니다. RELEASE_NO_SUBMIT=1 이라 공증에 제출하지 않으므로 계속합니다."
    else
      git status --short || true
      PREFLIGHT_ERRORS+=("P2 커밋되지 않은 변경이 있습니다(위 목록). CI 모드는 깨끗한 체크아웃만 배포합니다.")
    fi
  fi
else
  PREFLIGHT_ERRORS+=("P2 git 으로 커밋·작업 트리를 읽지 못했습니다(위 git 출력). 레포 폴더에서 git status 가 되는지 확인하세요.")
fi

# P3 dmg 서명용 로컬 Developer ID Application 인증서. CI 모드는 임시 키체인(RELEASE_KEYCHAIN)에서만 찾고
# 내보내기(3단계)도 이 인증서로 서명한다
FIND_IDENTITY_KEYCHAIN=()
keychain_ready=1
if [[ $CI_MODE == 1 ]]; then
  if [[ -z $RELEASE_KEYCHAIN ]]; then
    PREFLIGHT_ERRORS+=("P3 RELEASE_KEYCHAIN 에 임시 키체인 경로를 주세요 (scripts/ci-keychain.sh setup 이 만든 키체인, docs/RELEASING.md 4절).")
    keychain_ready=0
  elif [[ ! -f $RELEASE_KEYCHAIN ]]; then
    PREFLIGHT_ERRORS+=("P3 임시 키체인이 없습니다: $RELEASE_KEYCHAIN (scripts/ci-keychain.sh setup 을 먼저 실행하세요).")
    keychain_ready=0
  elif ! keychain_in_search_list "$RELEASE_KEYCHAIN"; then
    PREFLIGHT_ERRORS+=("P3 임시 키체인이 사용자 키체인 검색 목록(security list-keychains -d user)에 없습니다: $RELEASE_KEYCHAIN (scripts/ci-keychain.sh setup 이 넣습니다).")
    keychain_ready=0
  else
    FIND_IDENTITY_KEYCHAIN=("$RELEASE_KEYCHAIN")
  fi
fi
if [[ -z $TEAM ]]; then
  PREFLIGHT_ERRORS+=("P3 팀을 몰라 dmg 서명 인증서를 검사하지 못했습니다 (P1 을 먼저 고치세요).")
elif [[ $keychain_ready == 1 ]]; then
  identity_pattern='^ *[0-9]+\) ([0-9A-F]{40}) "(Developer ID Application: .* \('"$TEAM"'\))"$'
  while IFS= read -r line; do
    if [[ $line =~ $identity_pattern ]]; then
      DMG_IDENTITY=${BASH_REMATCH[1]}
      DMG_IDENTITY_NAME=${BASH_REMATCH[2]}
      break
    fi
  done < <(security find-identity -v -p codesigning ${FIND_IDENTITY_KEYCHAIN[@]+"${FIND_IDENTITY_KEYCHAIN[@]}"})
  if [[ -z $DMG_IDENTITY && $CI_MODE == 0 ]]; then
    PREFLIGHT_ERRORS+=("P3 dmg 서명용 Developer ID Application 인증서($TEAM)가 이 Mac 에 없습니다. Xcode → Settings → Accounts → 팀 → Manage Certificates… → + → Developer ID Application 으로 한 번 만드세요 (docs/RELEASING.md).")
  elif [[ -z $DMG_IDENTITY ]]; then
    # -v 없이는 보이면 인증서·키는 들어갔지만 유효하다고 판정되지 않은 것(대개 중간 인증서 신뢰 체인)
    if security find-identity -p codesigning "$RELEASE_KEYCHAIN" | grep -Fq "\"Developer ID Application: "; then
      PREFLIGHT_ERRORS+=("P3 임시 키체인에 Developer ID Application 인증서는 있지만 유효한 서명 인증서로 보이지 않습니다. 신뢰 체인(G1 중간 인증서) 문제일 수 있습니다: security find-identity -p codesigning $RELEASE_KEYCHAIN")
    else
      PREFLIGHT_ERRORS+=("P3 임시 키체인에 팀($TEAM)의 Developer ID Application 인증서·개인 키가 없습니다: $RELEASE_KEYCHAIN (p12 내용을 확인하세요, docs/RELEASING.md 4절).")
    fi
  fi
fi

# P4 공증 자격 증명: 읽기 전용 조회(제출 아님). 빌드 몇 분 뒤에야 자격 증명 문제를 알게 되지 않게 먼저 본다.
# CI 모드는 API 키 값이 비었거나 키 파일을 읽을 수 없으면 notarytool 을 부르지 않고 오류다
notary_missing=()
if [[ $CI_MODE == 1 ]]; then
  [[ -n $NOTARY_KEY_PATH ]] || notary_missing+=(NOTARY_KEY_PATH)
  [[ -n $NOTARY_KEY_ID ]] || notary_missing+=(NOTARY_KEY_ID)
  [[ -n $NOTARY_ISSUER_ID ]] || notary_missing+=(NOTARY_ISSUER_ID)
fi
if ((${#notary_missing[@]} > 0)); then
  PREFLIGHT_ERRORS+=("P4 App Store Connect API 키 값이 비어 있습니다: ${notary_missing[*]} (docs/RELEASING.md 4절).")
elif [[ $CI_MODE == 1 && ! -r $NOTARY_KEY_PATH ]]; then
  PREFLIGHT_ERRORS+=("P4 API 키 파일을 읽을 수 없습니다: NOTARY_KEY_PATH=$NOTARY_KEY_PATH")
else
  notary_error=$(xcrun notarytool history "${NOTARY_AUTH[@]}" --output-format json 2>&1 >/dev/null) \
    && notary_status=0 || notary_status=$?
  if [[ $CI_MODE == 1 ]]; then
    if [[ $notary_status != 0 ]]; then
      PREFLIGHT_ERRORS+=("P4 App Store Connect API 키로 공증 서비스에 로그인하지 못했습니다(종료 $notary_status). 키 ID·발급자 ID·키 파일·키 권한과 네트워크를 확인하세요. notarytool: $notary_error")
    fi
  elif [[ $notary_status == 69 ]]; then
    PREFLIGHT_ERRORS+=("P4 키체인에 공증 프로필 $NOTARY_PROFILE 이 없습니다. 터미널에서 xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID> --team-id ${TEAM:-<팀 ID>} 를 실행하고 앱 암호는 프롬프트에 입력하세요 (docs/RELEASING.md).")
  elif [[ $notary_status != 0 ]]; then
    PREFLIGHT_ERRORS+=("P4 공증 서비스에 로그인하지 못했습니다(종료 $notary_status). 앱 암호·네트워크를 확인하세요. notarytool: $notary_error")
  fi
fi

# P5 (CI 모드만) Gatekeeper 평가: 꺼져 있으면 12단계의 spctl 검사가 판정하지 못하므로 archive·공증 전에 멈춘다
if [[ $CI_MODE == 1 ]]; then
  gatekeeper_status=$(spctl --status 2>&1) || true
  if [[ $gatekeeper_status != "assessments enabled" ]]; then
    PREFLIGHT_ERRORS+=("P5 이 Mac 의 Gatekeeper 평가가 꺼져 있어 12단계 검사가 판정하지 못합니다 (spctl --status: '$gatekeeper_status').")
  fi
fi

if ((${#PREFLIGHT_ERRORS[@]} > 0)); then
  fail 2 "준비되지 않은 항목이 ${#PREFLIGHT_ERRORS[@]}개 있습니다." "${PREFLIGHT_ERRORS[@]}"
fi
if [[ $CI_MODE == 0 ]]; then
  echo "팀 $TEAM, 버전 $MARKETING_VERSION ($BUILD_NUMBER), dmg 서명 인증서 $DMG_IDENTITY_NAME, 공증 프로필 $NOTARY_PROFILE"
else
  echo "팀 $TEAM, 버전 $MARKETING_VERSION ($BUILD_NUMBER), 서명 인증서 $DMG_IDENTITY_NAME (임시 키체인), 공증: App Store Connect API 키"
fi

# --- 2. archive: 앱 타깃은 Sign to Run Locally(ad-hoc)라 여기서는 ad-hoc, export 가 다시 서명한다 ----
step 2 "archive"
xcodebuild archive -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -derivedDataPath "$OUT/DerivedData" \
  >"$OUT/archive.log" 2>&1 \
  || fail 1 "xcodebuild archive 가 실패했습니다. 로그: $OUT/archive.log" \
    "$(grep -m 20 'error:' "$OUT/archive.log" || true)"

# --- 3. Developer ID 내보내기: 로컬은 Xcode 자동 서명(클라우드 관리 인증서), ---------------
# CI 모드는 임시 키체인의 Developer ID Application 인증서(P3 의 SHA-1)로 manual 서명 (프로필·Xcode 계정 없음)
step 3 "Developer ID 내보내기"
if [[ $CI_MODE == 0 ]]; then
cat >"$EXPORT_OPTIONS" <<PLIST || fail 1 "내보내기 설정 파일을 쓰지 못했습니다: $EXPORT_OPTIONS" \
  "디스크 공간과 build/release 의 쓰기 권한을 확인한 뒤 다시 실행하세요."
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$TEAM</string>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$EXPORT_OPTIONS" -allowProvisioningUpdates >"$OUT/export.log" 2>&1 \
  || fail 1 "Developer ID 내보내기가 실패했습니다. 로그: $OUT/export.log" \
    "$(grep -m 20 'error:' "$OUT/export.log" || true)" \
    "Xcode → Settings → Accounts 에 팀($TEAM) 계정으로 로그인했는지 확인하세요."
else
cat >"$EXPORT_OPTIONS" <<PLIST || fail 1 "내보내기 설정 파일을 쓰지 못했습니다: $EXPORT_OPTIONS" \
  "디스크 공간과 build/release 의 쓰기 권한을 확인한 뒤 다시 실행하세요."
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>$DMG_IDENTITY</string>
  <key>teamID</key>
  <string>$TEAM</string>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$EXPORT_OPTIONS" >"$OUT/export.log" 2>&1 \
  || fail 1 "Developer ID 내보내기(manual)가 실패했습니다. 로그: $OUT/export.log" \
    "$(grep -m 20 'error:' "$OUT/export.log" || true)" \
    "임시 키체인($RELEASE_KEYCHAIN)의 잠금이 풀려 있고 Developer ID Application 인증서·개인 키($DMG_IDENTITY_NAME)가 있는지 확인하세요 (scripts/ci-keychain.sh)."
fi

# --- 4. 앱 서명 검사 ---------------------------------------------------------------
step 4 "앱 서명 검사"
[[ -d $APP ]] || fail 1 "내보낸 앱이 없습니다: $APP"
APP_PROBLEMS=()
codesign --verify --strict --deep "$APP" 2>&1 || APP_PROBLEMS+=("codesign --verify --strict --deep 실패")
signature=$(codesign -dvv "$APP" 2>&1) || APP_PROBLEMS+=("codesign -dvv 실패: $signature")
grep -Eq "^Authority=Developer ID Application: .* \\($TEAM\\)$" <<<"$signature" \
  || APP_PROBLEMS+=("Authority: 기대 'Developer ID Application: … ($TEAM)', 실제 '$(grep -m 1 '^Authority=' <<<"$signature" || true)'")
grep -Fxq "TeamIdentifier=$TEAM" <<<"$signature" \
  || APP_PROBLEMS+=("TeamIdentifier: 기대 '$TEAM', 실제 '$(grep -m 1 '^TeamIdentifier=' <<<"$signature" || true)'")
grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime[^)]*\)' <<<"$signature" \
  || APP_PROBLEMS+=("Hardened Runtime: flags 에 runtime 이 없습니다 ('$(grep -m 1 '^CodeDirectory ' <<<"$signature" || true)')")
grep -q '^Timestamp=' <<<"$signature" || APP_PROBLEMS+=("보안 타임스탬프(Timestamp=)가 없습니다")
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q 'get-task-allow'; then
  APP_PROBLEMS+=("entitlement 에 get-task-allow 가 있습니다 (디버그 서명)")
fi
app_version=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null || true)
app_build=$(plutil -extract CFBundleVersion raw "$APP/Contents/Info.plist" 2>/dev/null || true)
[[ $app_version == "$MARKETING_VERSION" ]] \
  || APP_PROBLEMS+=("CFBundleShortVersionString: 기대 '$MARKETING_VERSION', 실제 '$app_version'")
[[ $app_build == "$BUILD_NUMBER" ]] || APP_PROBLEMS+=("CFBundleVersion: 기대 '$BUILD_NUMBER', 실제 '$app_build'")
if ((${#APP_PROBLEMS[@]} > 0)); then
  fail 1 "내보낸 앱의 서명이 배포 조건과 다릅니다." "${APP_PROBLEMS[@]}"
fi
VERSION=$MARKETING_VERSION
DMG="$OUT/$APP_NAME-$VERSION.dmg"
# 서명·공증·staple·최종 검사는 작업 이름으로 하고, 모두 통과한 뒤에만 배포 이름으로 옮긴다
WORK_DMG="$OUT/unfinished-$APP_NAME-$VERSION.dmg"
APP_AUTHORITY=$(grep -m 1 '^Authority=' <<<"$signature")
echo "통과: ${APP_AUTHORITY#Authority=}, Hardened Runtime, 타임스탬프, 버전 $VERSION ($BUILD_NUMBER)"

# --- 5. 확인 요약·사용자 확인: 여기부터 Apple 공증 서비스로 파일이 나간다 --------------------
step 5 "확인"
echo "앱:            $APP"
echo "버전:          $VERSION ($BUILD_NUMBER)"
echo "앱 서명:       ${APP_AUTHORITY#Authority=} (팀 $TEAM)"
echo "dmg 서명:      $DMG_IDENTITY_NAME"
echo "커밋:          $COMMIT"
if [[ $CI_MODE == 0 ]]; then
  echo "공증 프로필:   $NOTARY_PROFILE"
else
  echo "공증:          App Store Connect API 키"
  echo "키체인:        $RELEASE_KEYCHAIN"
  echo "모드:          CI (API 키 공증, 확인 없이 제출)"
fi
echo "배포 dmg:      $DMG (모든 검사를 통과한 뒤에만 이 이름으로 생깁니다)"
echo "제출할 것:     ① 앱 zip ② 앱을 담은 dmg — 두 파일이 Apple 공증 서비스로 올라갑니다."
if [[ $CI_MODE == 1 ]]; then
  # CI 모드는 묻지 않는다. RELEASE_NO_SUBMIT=1(러너 밖 시험)만 여기서 멈춘다
  if [[ $NO_SUBMIT == 1 ]]; then
    if [[ -n $DIRTY ]]; then
      echo
      echo "경고: 커밋되지 않은 변경이 있습니다"
      git status --short || echo "(변경 목록을 보이지 못했습니다. 터미널에서 git status 로 확인하세요)"
    fi
    fail 3 "제출하지 않고 멈췄습니다 (RELEASE_NO_SUBMIT=1)." \
      "Developer ID 로 서명한 앱(공증 전)은 $APP 에 있습니다."
  fi
else
  expected_answer="y"
  if [[ -n $DIRTY ]]; then
    echo
    echo "경고: 커밋되지 않은 변경이 있습니다"
    git status --short || echo "(변경 목록을 보이지 못했습니다. 터미널에서 git status 로 확인하세요)"
    expected_answer="dirty"
    prompt="그래도 공증에 제출하려면 dirty 를 입력하세요: "
  else
    prompt="공증에 제출할까요? [y/N] "
  fi
  # 답은 /dev/tty 에서만 읽는다: 파이프(echo y | make release)로는 통과하지 않고, 터미널이 없으면 빈 답 = 거절
  answer=""
  if { exec 3</dev/tty; } 2>/dev/null; then
    printf '%s' "$prompt" >/dev/tty
    read -r -u 3 answer || answer=""
    exec 3<&-
  fi
  if [[ $expected_answer == dirty ]]; then
    [[ $answer == dirty ]] && accepted=1 || accepted=0
  else
    [[ $answer == y || $answer == Y || $answer == yes ]] && accepted=1 || accepted=0
  fi
  if [[ $accepted != 1 ]]; then
    fail 3 "공증에 제출하지 않고 멈췄습니다." \
      "Developer ID 로 서명한 앱(공증 전)은 $APP 에 있습니다."
  fi
fi

# notarize <이름> <파일>: 제출 → 대기 → info JSON 의 status == Accepted 만 성공으로 본다
notarize() {
  local name=$1 file=$2
  local submit_json="$NOTARY_DIR/$name-submit.json"
  local info_json="$NOTARY_DIR/$name-info.json"
  local log_json="$NOTARY_DIR/$name-log.json"
  # --wait 없이 제출해 제출 ID 를 먼저 얻는다 (중단·시간 초과 안내에 쓴다)
  xcrun notarytool submit "$file" "${NOTARY_AUTH[@]}" --output-format json >"$submit_json" \
    || fail 1 "공증 제출이 실패했습니다. 네트워크·자격 증명을 확인한 뒤 다시 실행하세요." "$(cat "$submit_json")"
  NOTARY_ID=$(jq -r '.id // empty' "$submit_json" 2>/dev/null || true)
  [[ -n $NOTARY_ID ]] || fail 1 "공증 제출 결과에서 제출 ID 를 찾지 못했습니다: $submit_json" "$(cat "$submit_json")"
  echo "제출 ID: $NOTARY_ID (Apple 처리를 기다립니다. 보통 몇 분 걸립니다)"
  # wait 의 종료 코드는 판정에 쓰지 않는다. 판정은 아래 info 의 status 로만 한다
  xcrun notarytool wait "$NOTARY_ID" "${NOTARY_AUTH[@]}" --timeout 1h || true
  local status="" info_read=0
  if xcrun notarytool info "$NOTARY_ID" "${NOTARY_AUTH[@]}" --output-format json \
    >"$info_json"; then
    info_read=1
    status=$(jq -r '.status // empty' "$info_json" 2>/dev/null || true)
  fi
  # 상태를 모를 때(조회 실패·status 없음·모르는 값)는 거절로 보지 않고 직접 확인할 명령을 알린다
  local check_lines=(
    "제출 ID: $NOTARY_ID"
    "확인: xcrun notarytool info $NOTARY_ID $NOTARY_AUTH_HINT"
    "결과가 Accepted 면 다시 실행하세요(처음부터 새로 제출합니다). Invalid·Rejected 면 xcrun notarytool log $NOTARY_ID $NOTARY_AUTH_HINT 로 이유를 보세요."
  )
  case $status in
    Accepted)
      echo "공증 통과: $NOTARY_ID"
      NOTARY_ID=""
      return
      ;;
    "In Progress")
      fail 1 "Apple 이 아직 처리 중입니다(제출 ID $NOTARY_ID)." \
        "xcrun notarytool info $NOTARY_ID $NOTARY_AUTH_HINT 로 확인한 뒤 다시 실행하세요."
      ;;
    Invalid | Rejected)
      xcrun notarytool log "$NOTARY_ID" "${NOTARY_AUTH[@]}" "$log_json" || true
      fail 1 "공증 거절: $status (제출 ID $NOTARY_ID)" \
        "이유는 $log_json 의 issues 를 보세요. info: $info_json"
      ;;
    "")
      if [[ $info_read == 0 ]]; then
        fail 1 "공증 상태를 조회하지 못했습니다(notarytool info 실패, 위 출력). 거절인지 아직 모릅니다. 네트워크나 위 오류를 확인하세요." \
          "${check_lines[@]}"
      fi
      fail 1 "공증 상태를 읽지 못했습니다: $info_json 에 status 가 없습니다. 거절인지 아직 모릅니다." "${check_lines[@]}"
      ;;
    *)
      fail 1 "공증 상태를 알 수 없습니다: '$status'. Accepted 가 아니라 멈췄습니다. info: $info_json" "${check_lines[@]}"
      ;;
  esac
}

# --- 6. 앱 공증 ---------------------------------------------------------------------
step 6 "앱 공증"
APP_ZIP="$NOTARY_DIR/app-submit.zip"
ditto -c -k --keepParent "$APP" "$APP_ZIP" \
  || fail 1 "공증에 올릴 앱 zip 을 만들지 못했습니다 (위 ditto 출력). 공증에는 아무것도 제출하지 않았습니다." \
    "디스크 공간을 확인한 뒤 다시 실행하세요."
notarize app "$APP_ZIP"

# --- 7. 앱 staple -------------------------------------------------------------------
step 7 "앱 staple"
xcrun stapler staple "$APP" && xcrun stapler validate "$APP" \
  || fail 1 "앱에 공증 티켓을 붙이지 못했습니다." "공증 직후에는 티켓 배포가 늦을 수 있습니다. 잠시 뒤 다시 실행하세요."
rm -f "$APP_ZIP" \
  || echo "경고: 공증에 올린 앱 zip 을 지우지 못했습니다: $APP_ZIP (배포에는 영향이 없고, 다음 실행이 0단계에서 지웁니다)." >&2

# --- 8. dmg 만들기: 앱 + Applications 바로가기 ------------------------------------------
step 8 "dmg 만들기"
{ mkdir -p "$DMG_ROOT" && ditto "$APP" "$DMG_ROOT/$APP_NAME.app" && ln -s /Applications "$DMG_ROOT/Applications"; } \
  || fail 1 "dmg 에 담을 폴더를 준비하지 못했습니다: $DMG_ROOT (위 출력)." "디스크 공간을 확인한 뒤 다시 실행하세요."
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -format UDZO -fs APFS "$WORK_DMG" \
  || fail 1 "디스크 이미지를 만들지 못했습니다 (위 hdiutil 출력)."
rm -rf "$DMG_ROOT" \
  || echo "경고: dmg 를 만든 임시 폴더를 지우지 못했습니다: $DMG_ROOT (배포에는 영향이 없고, 다음 실행이 0단계에서 지웁니다)." >&2

# --- 9. dmg 서명: 클라우드 관리 인증서로는 dmg 를 서명할 수 없어 로컬 인증서를 SHA-1 로 지정한다 ----
# 작업 이름이 서명에 남지 않게 식별자를 배포 이름으로 준다. CI 모드는 임시 키체인에서만 찾는다
step 9 "dmg 서명"
if [[ $CI_MODE == 0 ]]; then
  codesign -s "$DMG_IDENTITY" -i "$APP_NAME-$VERSION" --timestamp "$WORK_DMG" \
    && codesign --verify --strict "$WORK_DMG" \
    || fail 1 "dmg 를 서명하지 못했습니다 ($DMG_IDENTITY_NAME)." \
      "키체인 접근 대화상자에서 거절했다면 다시 실행해 '항상 허용'을 고르세요 (docs/RELEASING.md)."
else
  codesign -s "$DMG_IDENTITY" --keychain "$RELEASE_KEYCHAIN" -i "$APP_NAME-$VERSION" --timestamp "$WORK_DMG" \
    && codesign --verify --strict "$WORK_DMG" \
    || fail 1 "dmg 를 서명하지 못했습니다 ($DMG_IDENTITY_NAME, 키체인 $RELEASE_KEYCHAIN)." \
      "임시 키체인의 잠금이 풀려 있고 개인 키의 파티션 목록에 codesign 이 있는지 확인하세요 (scripts/ci-keychain.sh)."
fi

# --- 10. dmg 공증 -------------------------------------------------------------------
step 10 "dmg 공증"
notarize dmg "$WORK_DMG"

# --- 11. dmg staple -----------------------------------------------------------------
step 11 "dmg staple"
xcrun stapler staple "$WORK_DMG" && xcrun stapler validate "$WORK_DMG" \
  || fail 1 "dmg 에 공증 티켓을 붙이지 못했습니다." "공증 직후에는 티켓 배포가 늦을 수 있습니다. 잠시 뒤 다시 실행하세요."

# --- 12. 최종 검사: 명령과 출력을 보이고 종료 코드로 판정한다 -------------------------------
step 12 "최종 검사"
FAILED_CHECKS=()
check() {
  local name=$1
  shift
  echo "--- $name: $*"
  "$@" 2>&1 || FAILED_CHECKS+=("$name")
}
check "dmg 서명" codesign --verify --strict -v "$WORK_DMG"
check "dmg Gatekeeper" spctl -a -vv -t open --context context:primary-signature "$WORK_DMG"
check "dmg 공증 티켓" xcrun stapler validate "$WORK_DMG"
mkdir -p "$MOUNT_POINT" \
  || fail 1 "검사용 마운트 폴더를 만들지 못했습니다: $MOUNT_POINT" \
    "배포 이름($DMG)으로 옮기지 않았습니다. 검사하지 못한 dmg 는 $WORK_DMG 에 남습니다(배포하지 마세요)."
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MOUNT_POINT" "$WORK_DMG" \
  || fail 1 "검사하려고 dmg 를 마운트하지 못했습니다 (위 hdiutil 출력)." \
    "배포 이름($DMG)으로 옮기지 않았습니다. 검사하지 못한 dmg 는 $WORK_DMG 에 남습니다(배포하지 마세요)."
MOUNTED=1
check "앱 서명" codesign --verify --strict --deep "$MOUNT_POINT/$APP_NAME.app"
check "앱 Gatekeeper" spctl -a -vv -t exec "$MOUNT_POINT/$APP_NAME.app"
check "앱 공증 티켓" xcrun stapler validate "$MOUNT_POINT/$APP_NAME.app"
applications_link=$(readlink "$MOUNT_POINT/Applications" || true)
echo "--- Applications 바로가기: $applications_link"
[[ $applications_link == /Applications ]] || FAILED_CHECKS+=("Applications 바로가기")
# 분리 실패는 검사 결과·dmg 에 영향이 없어 경고만 한다 (MOUNTED=1 로 두어 끝날 때 on_exit 이 한 번 더 시도한다)
if hdiutil detach "$MOUNT_POINT"; then
  MOUNTED=0
else
  echo "경고: 검사용 마운트를 분리하지 못했습니다: $MOUNT_POINT (위 hdiutil 출력). 스크립트가 끝날 때 한 번 더 시도합니다. 끝난 뒤에도 남아 있으면 hdiutil detach $MOUNT_POINT 로 분리하세요." >&2
fi
if ((${#FAILED_CHECKS[@]} > 0)); then
  fail 1 "최종 검사가 실패했습니다: ${FAILED_CHECKS[*]}" \
    "배포 이름($DMG)으로 옮기지 않았습니다. 검사한 dmg 는 $WORK_DMG 에 남습니다(배포하지 마세요)."
fi
# 최종 검사를 통과한 파일만 배포 이름으로 옮긴다 (같은 폴더 안 이름 바꾸기라 서명·티켓이 그대로다).
# mv 에 -n 을 주지 않는다: macOS 에서 대상이 있으면 옮기지 않고 0 으로 끝난다. 대상은 0단계가 지워 없다
mv "$WORK_DMG" "$DMG" \
  || fail 1 "검사를 통과한 dmg 를 배포 이름으로 옮기지 못했습니다." \
    "검사를 통과한 dmg 는 $WORK_DMG 에 있습니다. 이름을 $DMG 로 바꾸면 됩니다."

STEP=""
echo
shasum -a 256 "$DMG" \
  || echo "경고: SHA-256 을 구하지 못했습니다. shasum -a 256 $DMG 로 직접 구하세요 (Release 노트·게시 확인에 씁니다)." >&2
echo "완료: $DMG"
