#!/bin/bash
# 배포 dmg 를 만든다: 사전 확인 → archive → Developer ID 내보내기 → 앱 서명 검사 → (사용자 확인) →
# 앱 공증·staple → dmg 만들기·서명 → dmg 공증·staple → 최종 검사 → 배포 이름으로 옮기기. 준비·절차·실패별 할 일: docs/RELEASING.md
#
# 입력 환경 변수: NOTARY_PROFILE(공증 키체인 프로필 이름, 필수), WORKSPACE(기본 SimLauncher.xcworkspace).
# 비밀 값(앱 암호)은 다루지 않는다: 프로필 이름만 notarytool 에 넘기고 환경 변수를 출력하지 않는다.
# 종료 코드: 0 성공, 1 단계 실패, 2 사전 확인 실패(준비 안 됨), 3 공증 제출을 거절함, 130 중단.
# 외부 출력은 codesign -dvv 의 영어 줄·security find-identity 줄·-showBuildSettings JSON·notarytool JSON 만 해석한다.
# hdiutil(출력이 현지화됨)·spctl·stapler 는 종료 코드로만 판정하고 출력은 그대로 보여 준다.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${NOTARY_PROFILE:?NOTARY_PROFILE 에 공증 키체인 프로필 이름을 주세요 (docs/RELEASING.md)}"
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
    echo "제출 ID $NOTARY_ID 는 Apple 쪽에서 계속 처리됩니다. 확인: xcrun notarytool info $NOTARY_ID --keychain-profile $NOTARY_PROFILE" >&2
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
mkdir -p "$OUT" "$NOTARY_DIR"

# --- 1. 사전 확인: P1~P4 를 모두 검사하고 실패를 한꺼번에 보인다 ---------------------
step 1 "사전 확인"
PREFLIGHT_ERRORS=()
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

# P2 작업 트리 (경고만)
COMMIT=$(git rev-parse --short HEAD)
DIRTY=$(git status --porcelain)
if [[ -n $DIRTY ]]; then
  echo "경고: 커밋되지 않은 변경이 있습니다. 확인 질문에서 다시 묻습니다."
fi

# P3 dmg 서명용 로컬 Developer ID Application 인증서
if [[ -z $TEAM ]]; then
  PREFLIGHT_ERRORS+=("P3 팀을 몰라 dmg 서명 인증서를 검사하지 못했습니다 (P1 을 먼저 고치세요).")
else
  identity_pattern='^ *[0-9]+\) ([0-9A-F]{40}) "(Developer ID Application: .* \('"$TEAM"'\))"$'
  while IFS= read -r line; do
    if [[ $line =~ $identity_pattern ]]; then
      DMG_IDENTITY=${BASH_REMATCH[1]}
      DMG_IDENTITY_NAME=${BASH_REMATCH[2]}
      break
    fi
  done < <(security find-identity -v -p codesigning)
  if [[ -z $DMG_IDENTITY ]]; then
    PREFLIGHT_ERRORS+=("P3 dmg 서명용 Developer ID Application 인증서($TEAM)가 이 Mac 에 없습니다. Xcode → Settings → Accounts → 팀 → Manage Certificates… → + → Developer ID Application 으로 한 번 만드세요 (docs/RELEASING.md).")
  fi
fi

# P4 공증 자격 증명: 읽기 전용 조회(제출 아님). 빌드 몇 분 뒤에야 자격 증명 문제를 알게 되지 않게 먼저 본다
notary_error=$(xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json 2>&1 >/dev/null) \
  && notary_status=0 || notary_status=$?
if [[ $notary_status == 69 ]]; then
  PREFLIGHT_ERRORS+=("P4 키체인에 공증 프로필 $NOTARY_PROFILE 이 없습니다. 터미널에서 xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID> --team-id ${TEAM:-<팀 ID>} 를 실행하고 앱 암호는 프롬프트에 입력하세요 (docs/RELEASING.md).")
elif [[ $notary_status != 0 ]]; then
  PREFLIGHT_ERRORS+=("P4 공증 서비스에 로그인하지 못했습니다(종료 $notary_status). 앱 암호·네트워크를 확인하세요. notarytool: $notary_error")
fi

if ((${#PREFLIGHT_ERRORS[@]} > 0)); then
  fail 2 "준비되지 않은 항목이 ${#PREFLIGHT_ERRORS[@]}개 있습니다." "${PREFLIGHT_ERRORS[@]}"
fi
echo "팀 $TEAM, 버전 $MARKETING_VERSION ($BUILD_NUMBER), dmg 서명 인증서 $DMG_IDENTITY_NAME, 공증 프로필 $NOTARY_PROFILE"

# --- 2. archive: 앱 타깃은 Sign to Run Locally(ad-hoc)라 여기서는 ad-hoc, export 가 다시 서명한다 ----
step 2 "archive"
xcodebuild archive -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -derivedDataPath "$OUT/DerivedData" \
  >"$OUT/archive.log" 2>&1 \
  || fail 1 "xcodebuild archive 가 실패했습니다. 로그: $OUT/archive.log" \
    "$(grep -m 20 'error:' "$OUT/archive.log" || true)"

# --- 3. Developer ID 내보내기: Xcode 자동 서명(클라우드 관리 인증서) ----------------------
step 3 "Developer ID 내보내기"
cat >"$EXPORT_OPTIONS" <<PLIST
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
echo "공증 프로필:   $NOTARY_PROFILE"
echo "배포 dmg:      $DMG (모든 검사를 통과한 뒤에만 이 이름으로 생깁니다)"
echo "제출할 것:     ① 앱 zip ② 앱을 담은 dmg — 두 파일이 Apple 공증 서비스로 올라갑니다."
expected_answer="y"
if [[ -n $DIRTY ]]; then
  echo
  echo "경고: 커밋되지 않은 변경이 있습니다"
  git status --short
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

# notarize <이름> <파일>: 제출 → 대기 → info JSON 의 status == Accepted 만 성공으로 본다
notarize() {
  local name=$1 file=$2
  local submit_json="$NOTARY_DIR/$name-submit.json"
  local info_json="$NOTARY_DIR/$name-info.json"
  local log_json="$NOTARY_DIR/$name-log.json"
  # --wait 없이 제출해 제출 ID 를 먼저 얻는다 (중단·시간 초과 안내에 쓴다)
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --output-format json >"$submit_json" \
    || fail 1 "공증 제출이 실패했습니다. 네트워크·자격 증명을 확인한 뒤 다시 실행하세요." "$(cat "$submit_json")"
  NOTARY_ID=$(jq -r '.id // empty' "$submit_json" 2>/dev/null || true)
  [[ -n $NOTARY_ID ]] || fail 1 "공증 제출 결과에서 제출 ID 를 찾지 못했습니다: $submit_json" "$(cat "$submit_json")"
  echo "제출 ID: $NOTARY_ID (Apple 처리를 기다립니다. 보통 몇 분 걸립니다)"
  # wait 의 종료 코드는 판정에 쓰지 않는다. 판정은 아래 info 의 status 로만 한다
  xcrun notarytool wait "$NOTARY_ID" --keychain-profile "$NOTARY_PROFILE" --timeout 1h || true
  local status="" message=""
  if xcrun notarytool info "$NOTARY_ID" --keychain-profile "$NOTARY_PROFILE" --output-format json \
    >"$info_json"; then
    status=$(jq -r '.status // empty' "$info_json" 2>/dev/null || true)
    message=$(jq -r '.message // empty' "$info_json" 2>/dev/null || true)
  fi
  if [[ $status == Accepted ]]; then
    echo "공증 통과: $NOTARY_ID"
    NOTARY_ID=""
    return
  fi
  if [[ $status == "In Progress" ]]; then
    fail 1 "Apple 이 아직 처리 중입니다(제출 ID $NOTARY_ID)." \
      "xcrun notarytool info $NOTARY_ID --keychain-profile $NOTARY_PROFILE 로 확인한 뒤 다시 실행하세요."
  fi
  xcrun notarytool log "$NOTARY_ID" --keychain-profile "$NOTARY_PROFILE" "$log_json" || true
  fail 1 "공증 거절: ${status:-상태 없음} ${message}" \
    "이유는 $log_json 의 issues 를 보세요. info: $info_json"
}

# --- 6. 앱 공증 ---------------------------------------------------------------------
step 6 "앱 공증"
APP_ZIP="$NOTARY_DIR/app-submit.zip"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
notarize app "$APP_ZIP"

# --- 7. 앱 staple -------------------------------------------------------------------
step 7 "앱 staple"
xcrun stapler staple "$APP" && xcrun stapler validate "$APP" \
  || fail 1 "앱에 공증 티켓을 붙이지 못했습니다." "공증 직후에는 티켓 배포가 늦을 수 있습니다. 잠시 뒤 다시 실행하세요."
rm -f "$APP_ZIP"

# --- 8. dmg 만들기: 앱 + Applications 바로가기 ------------------------------------------
step 8 "dmg 만들기"
mkdir -p "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -format UDZO -fs APFS "$WORK_DMG" \
  || fail 1 "디스크 이미지를 만들지 못했습니다 (위 hdiutil 출력)."
rm -rf "$DMG_ROOT"

# --- 9. dmg 서명: 클라우드 관리 인증서로는 dmg 를 서명할 수 없어 로컬 인증서를 SHA-1 로 지정한다 ----
# 작업 이름이 서명에 남지 않게 식별자를 배포 이름으로 준다
step 9 "dmg 서명"
codesign -s "$DMG_IDENTITY" -i "$APP_NAME-$VERSION" --timestamp "$WORK_DMG" \
  && codesign --verify --strict "$WORK_DMG" \
  || fail 1 "dmg 를 서명하지 못했습니다 ($DMG_IDENTITY_NAME)." \
    "키체인 접근 대화상자에서 거절했다면 다시 실행해 '항상 허용'을 고르세요 (docs/RELEASING.md)."

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
mkdir -p "$MOUNT_POINT"
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
hdiutil detach "$MOUNT_POINT" && MOUNTED=0
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
shasum -a 256 "$DMG"
echo "완료: $DMG"
