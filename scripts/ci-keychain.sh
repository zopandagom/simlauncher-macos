#!/bin/bash
# CI(release.yml build 잡)에서 Developer ID Application 인증서(.p12)를 담은 임시 키체인을 만들고 지운다.
# 대화상자 없이 codesign·xcodebuild export 가 쓰게 한다. 준비·절차: docs/RELEASING.md 4절
#
# 사용법: ci-keychain.sh setup <p12 경로> | ci-keychain.sh cleanup
# 입력 환경 변수(비밀 값은 인자로 받지 않는다):
#   RELEASE_KEYCHAIN  임시 키체인의 절대 경로, 끝이 .keychain-db (필수. scripts/release.sh CI 모드와 같은 변수)
#   P12_PASSWORD      p12 암호 (setup 만 필수). openssl 에는 -passin env: 로만 넘긴다
# set -x 를 쓰지 않는다. 암호·키 내용을 출력하지 않는다. stdout·stderr 는 사람이 읽는 로그일 뿐 출력 계약이 없다.
# 명령줄 예외: security 의 create-keychain·unlock-keychain·set-key-partition-list 는 키체인 암호를 인자로만 받는다.
#   이 암호는 setup 이 만드는 일회성 값이고(p12 암호가 아니다) 키체인과 함께 사라진다.
# 사용자 키체인 검색 목록: setup 은 키체인을 만들기 전에 원래 목록을 "$RELEASE_KEYCHAIN.search-list" 에 저장하고
#   맨 앞에 임시 키체인을 넣는다. cleanup 은 저장한 목록으로 되돌리고 키체인을 지운다(여러 번 불러도 된다).
#   기본 키체인·login 키체인은 건드리지 않는다.
# 종료 코드: 0 성공, 1 실패, 2 사용법 오류.
set -euo pipefail

die() {
  echo "ci-keychain: $*" >&2
  exit 1
}

usage() {
  echo "사용법: RELEASE_KEYCHAIN=<경로.keychain-db> [P12_PASSWORD=…] $0 setup <p12 경로> | cleanup" >&2
  exit 2
}

KEYCHAIN="${RELEASE_KEYCHAIN:-}"
[[ -n $KEYCHAIN ]] || die "RELEASE_KEYCHAIN 에 임시 키체인 경로를 주세요."
[[ $KEYCHAIN == /* && $KEYCHAIN == *.keychain-db ]] \
  || die "RELEASE_KEYCHAIN 은 .keychain-db 로 끝나는 절대 경로여야 합니다: $KEYCHAIN"
SEARCH_LIST_FILE="$KEYCHAIN.search-list"

# restore_search_list: 저장한 목록으로 사용자 검색 목록을 되돌리고 저장 파일을 지운다. 저장 파일이 없으면 할 일이 없다
restore_search_list() {
  [[ -f $SEARCH_LIST_FILE ]] || return 0
  local saved=() entry
  while IFS= read -r entry; do
    [[ -n $entry ]] && saved+=("$entry")
  done <"$SEARCH_LIST_FILE"
  security list-keychains -d user -s ${saved[@]+"${saved[@]}"} || return 1
  rm -f "$SEARCH_LIST_FILE" || return 1
  echo "키체인 검색 목록을 되돌렸습니다."
}

# delete_keychain: 임시 키체인을 지운다. 없으면 할 일이 없다
delete_keychain() {
  [[ -e $KEYCHAIN ]] || return 0
  security delete-keychain "$KEYCHAIN" || return 1
  echo "임시 키체인을 지웠습니다: $KEYCHAIN"
}

cleanup() {
  local status=0
  restore_search_list || {
    echo "ci-keychain: 키체인 검색 목록을 되돌리지 못했습니다 (저장해 둔 목록: $SEARCH_LIST_FILE)." >&2
    status=1
  }
  delete_keychain || {
    echo "ci-keychain: 임시 키체인을 지우지 못했습니다: $KEYCHAIN" >&2
    status=1
  }
  return "$status"
}

setup() {
  local p12=$1

  # 1. 입력 확인
  [[ -n ${P12_PASSWORD:-} ]] || die "P12_PASSWORD 에 p12 암호를 주세요."
  [[ -f $p12 && -r $p12 ]] || die "p12 파일을 읽을 수 없습니다: $p12"
  command -v openssl >/dev/null || die "openssl 이 없습니다."
  command -v security >/dev/null || die "security 가 없습니다 (macOS 에서만 됩니다)."
  [[ -d $(dirname "$KEYCHAIN") ]] || die "임시 키체인을 둘 폴더가 없습니다: $(dirname "$KEYCHAIN")"
  echo "openssl: $(openssl version)"

  # 2. p12 를 먼저 푼다: 여기까지 실패하면 키체인·검색 목록을 건드리지 않은 채 끝난다
  umask 077
  local work
  work=$(mktemp -d "$(dirname "$KEYCHAIN")/ci-keychain.XXXXXX") || die "임시 폴더를 만들지 못했습니다."
  # shellcheck disable=SC2064 # 경로는 지금 값으로 고정한다
  trap "rm -rf '$work'" EXIT
  local legacy=()
  if ! openssl pkcs12 -in "$p12" -passin env:P12_PASSWORD -nodes -out "$work/all.pem" 2>"$work/openssl.err"; then
    # OpenSSL 3 이상은 RC2 로 암호화한 예전 p12 를 -legacy 없이 못 읽는다
    legacy=(-legacy)
    openssl pkcs12 -legacy -in "$p12" -passin env:P12_PASSWORD -nodes -out "$work/all.pem" 2>>"$work/openssl.err" || {
      cat "$work/openssl.err" >&2
      die "p12 를 풀지 못했습니다 (암호·파일을 확인하세요). 키체인은 건드리지 않았습니다."
    }
  fi
  openssl pkey -in "$work/all.pem" -out "$work/key.pem" 2>"$work/openssl.err" || {
    cat "$work/openssl.err" >&2
    die "p12 에서 개인 키를 꺼내지 못했습니다. 키체인은 건드리지 않았습니다."
  }
  # 인증서는 개인 키와 짝인 것(-clcerts)만 꺼낸다. p12 에 중간 인증서가 같이 들어 있어도 순서에 기대지 않는다
  if ! openssl pkcs12 ${legacy[@]+"${legacy[@]}"} -in "$p12" -passin env:P12_PASSWORD -clcerts -nokeys \
    -out "$work/cert.pem" 2>"$work/openssl.err" || ! grep -q 'BEGIN CERTIFICATE' "$work/cert.pem"; then
    cat "$work/openssl.err" >&2
    die "p12 에서 인증서를 꺼내지 못했습니다. 키체인은 건드리지 않았습니다."
  fi

  # 3. 원래 사용자 검색 목록을 키체인을 만들기 전에 저장한다 (create-keychain 이 목록에 더하는지와 무관하게 복구 기준)
  [[ ! -e $SEARCH_LIST_FILE ]] || die "이전 setup 이 정리되지 않았습니다: $0 cleanup 을 먼저 실행하세요 ($SEARCH_LIST_FILE 이 있습니다)."
  [[ ! -e $KEYCHAIN ]] || die "임시 키체인이 이미 있습니다: $0 cleanup 을 먼저 실행하세요 ($KEYCHAIN)."
  local original=() line entry
  while IFS= read -r line; do
    entry=${line#"${line%%[![:space:]]*}"}
    entry=${entry#\"}
    entry=${entry%\"}
    [[ -n $entry ]] && original+=("$entry")
  done < <(security list-keychains -d user)
  : >"$SEARCH_LIST_FILE" || die "검색 목록을 저장하지 못했습니다: $SEARCH_LIST_FILE"
  for entry in ${original[@]+"${original[@]}"}; do
    printf '%s\n' "$entry" >>"$SEARCH_LIST_FILE"
  done
  # 여기부터 실패하면(종료 코드가 0 이 아니면) cleanup 으로 검색 목록·키체인을 되돌린다
  # shellcheck disable=SC2064 # 경로는 지금 값으로 고정한다
  trap "status=\$?; rm -rf '$work'; if [[ \$status != 0 ]]; then cleanup || true; fi; exit \$status" EXIT

  # 4. 키체인 만들기·가져오기. 암호는 셸 변수에만 둔다
  local password
  password=$(openssl rand -hex 32) || die "임시 키체인 암호를 만들지 못했습니다."
  if [[ ${GITHUB_ACTIONS:-} == true ]]; then
    echo "::add-mask::$password"
  fi
  security create-keychain -p "$password" "$KEYCHAIN" || die "임시 키체인을 만들지 못했습니다: $KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN" || die "임시 키체인 설정(6시간 뒤 잠금)을 하지 못했습니다."
  security unlock-keychain -p "$password" "$KEYCHAIN" || die "임시 키체인의 잠금을 풀지 못했습니다."
  security import "$work/key.pem" -k "$KEYCHAIN" -T /usr/bin/codesign >/dev/null \
    || die "개인 키를 임시 키체인에 넣지 못했습니다."
  security import "$work/cert.pem" -k "$KEYCHAIN" >/dev/null || die "인증서를 임시 키체인에 넣지 못했습니다."
  # 파티션 목록에 codesign 등을 넣어야 서명 때 키체인 접근 대화상자가 뜨지 않는다 (출력은 키 속성 덤프라 버린다)
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$KEYCHAIN" >/dev/null \
    || die "개인 키의 파티션 목록을 정하지 못했습니다."
  security list-keychains -d user -s "$KEYCHAIN" ${original[@]+"${original[@]}"} \
    || die "임시 키체인을 검색 목록에 넣지 못했습니다."

  # 5. 확인: 유효한 Developer ID Application 서명 인증서가 정확히 하나
  local valid count
  valid=$(security find-identity -v -p codesigning "$KEYCHAIN") || die "임시 키체인의 서명 인증서를 읽지 못했습니다."
  count=$(grep -c '"Developer ID Application: ' <<<"$valid" || true)
  if [[ $count == 0 ]]; then
    if security find-identity -p codesigning "$KEYCHAIN" | grep -q '"Developer ID Application: '; then
      die "인증서는 들어갔지만 신뢰 체인(G1 중간 인증서)을 확인하지 못했습니다. security find-identity -p codesigning 결과를 보세요."
    fi
    die "p12 에 Developer ID Application 인증서·키가 없습니다."
  elif [[ $count != 1 ]]; then
    die "임시 키체인에 Developer ID Application 인증서가 ${count}개 있습니다. p12 에는 하나만 넣으세요."
  fi
  echo "setup 완료: $KEYCHAIN"
}

case ${1:-} in
  setup)
    [[ $# == 2 ]] || usage
    setup "$2"
    ;;
  cleanup)
    [[ $# == 1 ]] || usage
    cleanup
    ;;
  *) usage ;;
esac
