#!/bin/bash
# 릴리스 워크플로(.github/workflows/release.yml)의 태그·버전·게시 판정 (docs/RELEASING.md 4절).
# 사용:
#   release-check.sh push <owner/repo> <태그>      태그 push 실행의 판정(check 잡). GH_TOKEN·로컬 태그·전체 이력이 필요하다
#   release-check.sh ref <owner/repo> <태그>       태그가 주석 태그이고 어느 커밋인지만 API 로 본다(publish 잡. 로컬 git 불필요)
#   release-check.sh trial <ref> <커밋 sha>        workflow_dispatch 시험 실행의 판정(main 에서만)
#   release-check.sh version <커밋>                그 커밋의 marketingVersion·buildNumber 를 읽는다
#   release-check.sh plan <태그>                   표준입력 = 릴리스 목록 JSON({tag_name, draft, prerelease} 들). stdout = --latest 값(true|false)
# push·ref·trial·version 은 결과를 $GITHUB_OUTPUT 파일에 key=value 로 쓴다(그 변수가 비어 있으면 종료 2).
#   push·trial: mode(publish|trial)·tag(trial 은 빈 값)·commit·version·build, ref: commit, version: version·build
# plan 은 $GITHUB_OUTPUT 을 쓰지 않는다. 진단은 stderr(::error::·::warning::), 실패는 종료 1, 사용법 오류는 종료 2.
# bash 3.2 호환(로컬 make test 가 /bin/bash 3.2 로 돌린다). 회귀 테스트: make release-scripts-test
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TAG_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
SHA_RE='^[0-9a-f]{40}$'
REPO_RE='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
VERSION_FILE=Tuist/ProjectDescriptionHelpers/Project+Templates.swift

die() {
  echo "::error::$*" >&2
  exit 1
}
usage() {
  echo "사용: release-check.sh push|ref <owner/repo> <태그> | trial <ref> <sha> | version <커밋> | plan <태그>" >&2
  exit 2
}
need_output() {
  [[ -n ${GITHUB_OUTPUT:-} ]] || {
    echo "::error::GITHUB_OUTPUT 이 비어 있습니다 (결과를 쓸 파일 경로)" >&2
    exit 2
  }
}
output() { printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"; }
check_tag() { [[ $1 =~ $TAG_RE ]] || die "버전 태그 이름이 아닙니다 (<major>.<minor>.<patch>): $1"; }
check_repo() { [[ $1 =~ $REPO_RE ]] || die "레포 이름이 owner/repo 가 아닙니다: $1"; }

# gh api 호출. 성공이면 stdout 을 그대로 내고 0, HTTP 404 면 44, 그 밖의 실패는 gh 의 오류를 stderr 로 내고 1.
# (gh 는 오류 때도 응답 본문을 stdout 에 내므로 실패 때 stdout 은 버린다)
gh_api() {
  local errfile result status
  errfile=$(mktemp)
  result=$(gh api "$@" 2>"$errfile") && status=0 || status=$?
  if ((status == 0)); then
    rm -f "$errfile"
    printf '%s\n' "$result"
    return 0
  fi
  if grep -q 'HTTP 404' "$errfile"; then
    rm -f "$errfile"
    return 44
  fi
  cat "$errfile" >&2
  rm -f "$errfile"
  return 1
}

# 태그 → (주석 태그 객체) → 커밋. API 만 쓴다. 결과는 전역 TAG_COMMIT.
resolve_tag() {
  local repo=$1 tag=$2 ref obj_type obj_sha status
  check_repo "$repo"
  check_tag "$tag"
  ref=$(gh_api "repos/$repo/git/ref/tags/$tag" --jq '.object.type + " " + .object.sha') && status=0 || status=$?
  ((status != 44)) || die "원격에 태그 $tag 가 없습니다"
  ((status == 0)) || die "태그 $tag 를 조회하지 못했습니다"
  obj_type=${ref%% *}
  obj_sha=${ref#* }
  [[ $obj_type == tag ]] || die "$tag 는 경량 태그입니다: git tag -a $tag -m \"SimLauncher $tag\" 로 지우고 다시 만드세요"
  [[ $obj_sha =~ $SHA_RE ]] || die "태그 객체 sha 가 올바르지 않습니다: $obj_sha"
  ref=$(gh_api "repos/$repo/git/tags/$obj_sha" --jq '.object.type + " " + .object.sha') \
    || die "태그 객체 $obj_sha 를 조회하지 못했습니다"
  obj_type=${ref%% *}
  TAG_COMMIT=${ref#* }
  [[ $obj_type == commit ]] || die "$tag 주석 태그가 커밋이 아닌 $obj_type 을 가리킵니다"
  [[ $TAG_COMMIT =~ $SHA_RE ]] || die "태그 커밋 sha 가 올바르지 않습니다: $TAG_COMMIT"
}

# 커밋의 버전 파일에서 marketingVersion·buildNumber 를 읽는다. 결과는 전역 VERSION·BUILD.
read_version() {
  local rev=$1 content lines count
  content=$(git show "$rev:$VERSION_FILE" 2>/dev/null) || die "$rev 의 $VERSION_FILE 를 읽지 못했습니다"
  lines=$(grep -E '^  static let marketingVersion = "[^"]+"$' <<<"$content" || true)
  count=$(grep -c . <<<"$lines" || true)
  ((count == 1)) || die "$rev 의 $VERSION_FILE 에서 marketingVersion 줄이 ${count}개입니다 (정확히 1개여야 합니다)"
  VERSION=$(sed -E 's/^  static let marketingVersion = "([^"]+)"$/\1/' <<<"$lines")
  lines=$(grep -E '^  static let buildNumber = "[^"]+"$' <<<"$content" || true)
  count=$(grep -c . <<<"$lines" || true)
  ((count == 1)) || die "$rev 의 $VERSION_FILE 에서 buildNumber 줄이 ${count}개입니다 (정확히 1개여야 합니다)"
  BUILD=$(sed -E 's/^  static let buildNumber = "([^"]+)"$/\1/' <<<"$lines")
  [[ $VERSION =~ $TAG_RE ]] || die "$rev 의 marketingVersion 이 <major>.<minor>.<patch> 가 아닙니다: $VERSION"
  [[ $BUILD =~ ^(0|[1-9][0-9]*)$ ]] || die "$rev 의 buildNumber 가 10진 정수가 아닙니다 (앞자리 0·숫자 아닌 글자 불가): $BUILD"
}

cmd_ref() {
  [[ $# == 2 ]] || usage
  need_output
  resolve_tag "$1" "$2"
  output commit "$TAG_COMMIT"
  echo "태그 $2: 주석 태그, 커밋 $TAG_COMMIT" >&2
}

cmd_push() {
  [[ $# == 2 ]] || usage
  need_output
  local repo=$1 tag=$2 status compare prev prev_commit build version
  resolve_tag "$repo" "$tag"
  local commit=$TAG_COMMIT

  compare=$(gh_api "repos/$repo/compare/$commit...main" --jq .status) || die "main 과 비교하지 못했습니다"
  [[ $compare == ahead || $compare == identical ]] \
    || die "$tag 의 커밋 $commit 은 main 에 머지된 커밋이 아닙니다 (main 기준 $compare)"

  read_version "$commit"
  version=$VERSION
  build=$BUILD
  [[ $version == "$tag" ]] || die "태그 $tag 와 커밋의 marketingVersion $version 이 다릅니다"

  gh_api "repos/$repo/releases/tags/$tag" --jq .id >/dev/null && status=0 || status=$?
  ((status != 0)) || die "$tag 의 Release 가 이미 게시되어 있습니다"
  ((status == 44)) || die "$tag 의 Release 를 조회하지 못했습니다"

  prev=$("$script_dir/release-notes.sh" previous-tag "$repo" "$commit" "$tag") || die "이전 릴리스 태그를 찾지 못했습니다"
  prev_commit=$(git rev-parse --verify --quiet "refs/tags/$prev^{commit}") || die "이전 태그 $prev 의 커밋을 찾지 못했습니다"
  read_version "$prev_commit"
  ((BUILD < build)) || die "빌드 번호가 늘지 않았습니다: 이전 $prev($BUILD) → 이번 $tag($build). buildNumber 를 올리세요"

  output mode publish
  output tag "$tag"
  output commit "$commit"
  output version "$version"
  output build "$build"
  echo "게시 판정 통과: $tag ($build), 커밋 $commit, 이전 릴리스 $prev ($BUILD)" >&2
}

cmd_trial() {
  [[ $# == 2 ]] || usage
  need_output
  local ref=$1 sha=$2
  [[ $ref == refs/heads/main ]] || die "시험 실행은 main 에서만 합니다: $ref"
  [[ $sha =~ $SHA_RE ]] || die "커밋 sha 가 올바르지 않습니다: $sha"
  read_version "$sha"
  output mode trial
  output tag ""
  output commit "$sha"
  output version "$VERSION"
  output build "$BUILD"
  echo "시험 실행: main $sha, $VERSION ($BUILD). 게시하지 않습니다" >&2
}

cmd_version() {
  [[ $# == 1 ]] || usage
  need_output
  read_version "$1"
  output version "$VERSION"
  output build "$BUILD"
}

cmd_plan() {
  [[ $# == 1 ]] || usage
  local tag=$1 releases same published highest
  check_tag "$tag"
  # 줄 형식(한 줄 JSON·여러 줄 JSON)에 기대지 않게 jq -s 로 모아 읽는다.
  releases=$(jq -cs '.') || die "릴리스 목록을 JSON 으로 읽지 못했습니다"
  same=$(jq -r --arg tag "$tag" '[.[] | select(.tag_name == $tag)] | if length == 0 then "" elif any(.[]; .draft) then "draft" else "release" end' <<<"$releases")
  if [[ $same == draft ]]; then
    die "$tag 의 초안 Release 가 남아 있습니다. 확인해 지운 뒤 Re-run failed jobs 로 다시 돌리세요"
  elif [[ -n $same ]]; then
    die "$tag 의 Release 가 이미 있습니다(반쯤 생긴 Release 일 수 있습니다). 확인해 지운 뒤 Re-run failed jobs 로 다시 돌리세요"
  fi
  published=$(jq -r '.[] | select((.draft | not) and (.prerelease | not)) | .tag_name' <<<"$releases" | grep -E "$TAG_RE" || true)
  highest=$(printf '%s\n%s\n' "$published" "$tag" | grep -E "$TAG_RE" | sort -V | tail -n 1)
  if [[ $highest == "$tag" ]]; then echo true; else echo false; fi
}

[[ $# -ge 1 ]] || usage
command=$1
shift
case $command in
  push) cmd_push "$@" ;;
  ref) cmd_ref "$@" ;;
  trial) cmd_trial "$@" ;;
  version) cmd_version "$@" ;;
  plan) cmd_plan "$@" ;;
  *) usage ;;
esac
