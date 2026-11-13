#!/bin/bash
# 릴리스 노트 도우미 (.github/workflows/release.yml 의 notes·publish 잡, docs/RELEASING.md 4절).
# 사용:
#   release-notes.sh previous-tag <owner/repo> <대상 커밋> <이번 태그|"">
#       이전 릴리스 태그 한 줄을 stdout 으로. 버전 이름이고, 주석 태그이고, 이번 태그가 아니고(있으면 그보다 낮고),
#       대상 커밋의 조상(같은 커밋 포함)이고, GitHub Release 가 게시된(초안·prerelease 아님) 태그 중 가장 높은 것.
#   release-notes.sh prepare <owner/repo> <대상 커밋> <이번 태그|""> <출력 폴더>
#       이전 태그 이후 main 의 first-parent 머지 커밋에서 PR 목록을 만들고 Claude 재료를 쓴다.
#       출력: previous-tag, prs.json, pr-list.md(제목·번호 링크, 머지 순서), context.md(Claude 재료), prompt.md(지시문 + 재료)
#   release-notes.sh check-summary <owner/repo> <요약 원문> <출력 파일>
#       Claude 요약을 검사해 통과하면 앞뒤 공백을 다듬어 출력 파일로, 거절이면 출력 파일을 지운다. 항상 종료 0.
#   release-notes.sh assemble <폴더> <버전> <sha256> <owner/repo>
#       prepare 의 출력 폴더(+ summary.md)로 게시할 노트 전체를 stdout 으로.
# $GITHUB_OUTPUT 은 읽지 않는다. 진단은 stderr(::error::·::warning::). gh·git·jq·sort -V 를 쓴다.
# bash 3.2 호환(로컬 make test 가 /bin/bash 3.2 로 돌린다). 회귀 테스트: make release-scripts-test
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TAG_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
REPO_RE='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
PROMPT_FILE="$script_dir/release-notes-prompt.md"
# Claude 재료 크기 상한과 줄이는 순서: 넘으면 바뀐 파일 목록을 빼고, 그래도 넘으면 PR 본문을 짧게 자른다.
CONTEXT_MAX_BYTES=300000
BODY_MAX_CHARS=8000
BODY_SHORT_CHARS=2000
FILES_MAX=150
SUMMARY_MAX_CHARS=12000
# GitHub 의 Merge commit 머지 제목. 이것만 PR 로 본다
MERGE_RE='^Merge pull request #([0-9]+) from '

die() {
  echo "::error::$*" >&2
  exit 1
}
warn() { echo "::warning::$*" >&2; }
usage() {
  echo "사용: release-notes.sh previous-tag <repo> <커밋> <태그|\"\"> | prepare <repo> <커밋> <태그|\"\"> <폴더>" \
    "| check-summary <repo> <원문> <출력> | assemble <폴더> <버전> <sha256> <repo>" >&2
  exit 2
}
check_repo() { [[ $1 =~ $REPO_RE ]] || die "레포 이름이 owner/repo 가 아닙니다: $1"; }

# gh api 호출: 성공 0(stdout 그대로), HTTP 404 는 44, 그 밖의 실패는 1 (release-check.sh 와 같은 규칙)
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

resolve_commit() {
  git rev-parse --verify --quiet "$1^{commit}" || die "커밋을 찾지 못했습니다: $1"
}

# a 가 b 보다 sort -V 로 낮은가
version_lower() { [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1) == "$1" ]]; }

previous_tag() {
  local repo=$1 target=$2 current=$3 tag tag_commit state status
  check_repo "$repo"
  [[ -z $current || $current =~ $TAG_RE ]] || die "이번 태그가 버전 이름이 아닙니다: $current"
  target=$(resolve_commit "$target")
  for tag in $(git tag -l | grep -E "$TAG_RE" | sort -rV); do
    [[ $(git cat-file -t "refs/tags/$tag") == tag ]] || continue
    [[ $tag != "$current" ]] || continue
    tag_commit=$(git rev-parse "refs/tags/$tag^{commit}")
    git merge-base --is-ancestor "$tag_commit" "$target" || continue
    [[ -z $current ]] || version_lower "$tag" "$current" || continue
    state=$(gh_api "repos/$repo/releases/tags/$tag" --jq '[.draft, .prerelease] | map(tostring) | join(" ")') \
      && status=0 || status=$?
    if ((status == 44)); then
      warn "$tag 는 게시된 Release 가 없어 건너뜁니다"
      continue
    fi
    ((status == 0)) || die "$tag 의 Release 를 조회하지 못했습니다"
    if [[ $state != "false false" ]]; then
      warn "$tag 의 Release 가 초안이거나 prerelease 라 건너뜁니다 (draft prerelease = $state)"
      continue
    fi
    echo "$tag"
    return 0
  done
  die "이전 릴리스 태그가 없습니다 (게시된 Release 가 있는 주석 버전 태그 중 대상 커밋의 조상인 것)"
}

# PR 재료(prs.json)로 context.md 를 만든다. $1 = 파일 목록 포함(true|false), $2 = 본문 최대 글자 수
render_context() {
  local out=$1 include_files=$2 body_max=$3 prev=$4 prev_body=$5
  {
    echo "# 재료"
    echo
    echo "이전 버전: $prev"
    echo
    if [[ -n $prev_body ]]; then
      echo "## 이전 버전($prev) 릴리스 노트 — 말투 예시"
      echo
      echo "<previous-notes>"
      printf '%s\n' "$prev_body"
      echo "</previous-notes>"
      echo
    fi
    echo "## 이번 버전에 머지된 PR (머지 순서)"
    echo
    jq -r --argjson files "$include_files" --argjson bodymax "$body_max" --argjson filesmax "$FILES_MAX" '
      def clip($n): if length > $n then .[0:$n] + "…(잘림)" else . end;
      if length == 0 then "- 없음" else
      .[] | (
        "### PR \(.number): \(.title)",
        "- 라벨: \(if (.labels | length) == 0 then "없음" else [.labels[].name] | join(", ") end)",
        "- 바뀐 파일: \(.files | length)개",
        (if $files then
          (.files[0:$filesmax][] | "  - \(.path) (+\(.additions) -\(.deletions))"),
          (if (.files | length) > $filesmax then "  - …외 \((.files | length) - $filesmax)개" else empty end)
        else empty end),
        "",
        "<pr-body number=\"\(.number)\">",
        ((.body // "") | gsub("</pr-body"; "&lt;/pr-body") | clip($bodymax)),
        "</pr-body>",
        ""
      ) end
    ' "$out/prs.json"
  } >"$out/context.md"
}

cmd_previous_tag() {
  [[ $# == 3 ]] || usage
  previous_tag "$1" "$2" "$3"
}

cmd_prepare() {
  [[ $# == 4 ]] || usage
  local repo=$1 target=$2 current=$3 out=$4 prev line sha subject number pr oid prev_body size
  check_repo "$repo"
  target=$(resolve_commit "$target")
  [[ -f $PROMPT_FILE ]] || die "지시문 파일이 없습니다: $PROMPT_FILE"
  mkdir -p "$out"
  prev=$(previous_tag "$repo" "$target" "$current")
  echo "$prev" >"$out/previous-tag"
  echo "이전 릴리스: $prev, 대상 커밋: $target" >&2

  local tmp
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064 # 지금 값으로 지운다
  trap "rm -rf '$tmp'" EXIT
  : >"$tmp/prs.jsonl"
  : >"$out/pr-list.md"
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    sha=${line%%$'\x1f'*}
    subject=${line#*$'\x1f'}
    if [[ $subject =~ $MERGE_RE ]]; then
      number=${BASH_REMATCH[1]}
    else
      warn "PR 머지가 아닌 main 커밋은 노트에 넣지 않습니다: $sha $subject"
      continue
    fi
    pr=$(gh pr view "$number" --repo "$repo" --json number,title,url,labels,mergeCommit,body,files) \
      || die "PR #$number 를 조회하지 못했습니다"
    oid=$(jq -r '.mergeCommit.oid // ""' <<<"$pr")
    [[ $oid == "$sha" ]] || die "PR #$number 의 머지 커밋($oid)이 main 의 머지 커밋($sha)과 다릅니다"
    [[ $(jq -r '.number' <<<"$pr") == "$number" ]] || die "PR #$number 조회 결과의 번호가 다릅니다"
    jq -c . <<<"$pr" >>"$tmp/prs.jsonl"
    # 링크는 조회 결과의 url 대신 레포·번호로 만든다(노트에 이 레포 밖 주소가 들어가지 않게).
    jq -r --arg url "https://github.com/$repo/pull/$number" '"- \(.title) ([#\(.number)](\($url)))"' <<<"$pr" \
      >>"$out/pr-list.md"
  done < <(git log --first-parent --reverse --format='%H%x1f%s' "$prev..$target")
  jq -s . "$tmp/prs.jsonl" >"$out/prs.json"
  [[ -s $out/pr-list.md ]] || echo "- 없음" >"$out/pr-list.md"
  echo "PR $(jq length "$out/prs.json")개" >&2

  prev_body=$(gh_api "repos/$repo/releases/tags/$prev" --jq '.body // ""') || {
    warn "$prev 의 릴리스 노트를 읽지 못해 말투 예시 없이 만듭니다"
    prev_body=""
  }
  render_context "$out" true "$BODY_MAX_CHARS" "$prev" "$prev_body"
  size=$(wc -c <"$out/context.md" | tr -d ' ')
  if ((size > CONTEXT_MAX_BYTES)); then
    warn "재료가 ${size} 바이트라 바뀐 파일 목록을 뺍니다"
    render_context "$out" false "$BODY_MAX_CHARS" "$prev" "$prev_body"
    size=$(wc -c <"$out/context.md" | tr -d ' ')
  fi
  if ((size > CONTEXT_MAX_BYTES)); then
    warn "재료가 ${size} 바이트라 PR 본문을 ${BODY_SHORT_CHARS}자로 줄입니다"
    render_context "$out" false "$BODY_SHORT_CHARS" "$prev" "$prev_body"
  fi
  {
    sed "s/@PREVIOUS_TAG@/$prev/g" "$PROMPT_FILE"
    echo
    cat "$out/context.md"
  } >"$out/prompt.md"
  echo "재료 $(wc -c <"$out/context.md" | tr -d ' ') 바이트: $out" >&2
}

# 요약 원문을 검사한다. 거절 이유는 ::warning:: 한 줄, 통과면 다듬어 출력 파일로. 항상 종료 0.
cmd_check_summary() {
  [[ $# == 3 ]] || usage
  local repo=$1 raw=$2 out=$3 reason="" chars url tmp
  check_repo "$repo"
  if [[ ! -f $raw ]]; then
    reason="요약 원문이 없습니다 ($raw)"
  elif ! grep -q '[^[:space:]]' "$raw"; then
    reason="요약이 비어 있습니다"
  else
    chars=$(jq -Rs 'length' "$raw" 2>/dev/null || echo $((SUMMARY_MAX_CHARS + 1)))
    if ((chars > SUMMARY_MAX_CHARS)); then
      reason="요약이 ${chars}자로 ${SUMMARY_MAX_CHARS}자를 넘습니다"
    elif grep -Eq '^[[:space:]]*(```|~~~)' "$raw"; then
      reason="코드 펜스가 있습니다"
    elif grep -Eq '<[A-Za-z/!]' "$raw"; then
      reason="HTML 태그가 있습니다"
    elif grep -Eq '^# ' "$raw"; then
      reason="H1 제목이 있습니다"
    elif grep -Eiq 'www\.' "$raw"; then
      reason="www. 주소가 있습니다"
    elif grep -Eq '@[A-Za-z0-9]' "$raw"; then
      reason="@ 멘션이 있습니다"
    elif grep -Eq '[A-Za-z0-9-]+/[A-Za-z0-9._-]+#[0-9]' "$raw"; then
      reason="다른 레포 참조(owner/repo#N)가 있습니다"
    elif grep -Eq '#[0-9]' "$raw"; then
      reason="#숫자(이슈·PR 자동 링크)가 있습니다"
    else
      while IFS= read -r url; do
        if [[ $url != "https://github.com/$repo/"* ]]; then
          reason="이 레포 밖 주소가 있습니다: $url"
          break
        fi
      done < <(grep -Eio 'https?://[^[:space:])>]*' "$raw" || true)
    fi
  fi
  if [[ -n $reason ]]; then
    warn "Claude 요약을 쓰지 않고 PR 목록만으로 노트를 만듭니다: $reason"
    rm -f "$out"
    return 0
  fi
  if tmp=$(mktemp "$(dirname "$out")/.summary.XXXXXX") \
    && jq -Rrs 'sub("\\A\\s+"; "") | sub("\\s+\\z"; "")' "$raw" >"$tmp" && mv -f "$tmp" "$out"; then
    echo "Claude 요약 통과: $out" >&2
  else
    rm -f "$tmp" "$out"
    warn "Claude 요약을 쓰지 못해 PR 목록만으로 노트를 만듭니다"
  fi
  return 0
}

cmd_assemble() {
  [[ $# == 4 ]] || usage
  local dir=$1 version=$2 sha=$3 repo=$4 prev
  [[ $version =~ $TAG_RE ]] || die "버전이 <major>.<minor>.<patch> 가 아닙니다: $version"
  [[ $sha =~ ^[0-9a-f]{64}$ ]] || die "SHA-256 이 64자리 소문자 16진수가 아닙니다: $sha"
  check_repo "$repo"
  [[ -f $dir/previous-tag && -f $dir/pr-list.md ]] || die "$dir 에 previous-tag·pr-list.md 가 없습니다"
  prev=$(cat "$dir/previous-tag")
  [[ $prev =~ $TAG_RE ]] || die "previous-tag 가 버전 이름이 아닙니다: $prev"
  if [[ -s $dir/summary.md ]]; then
    cat "$dir/summary.md"
  else
    echo "SimLauncher $version 이에요. 이번 버전에 들어간 변경은 아래 PR 목록을 봐 주세요."
  fi
  cat <<EOF

## 설치·업데이트하기
아래 **Assets** 에서 \`SimLauncher-$version.dmg\` 를 내려받아 열고, **SimLauncher** 를 **Applications**(응용 프로그램) 폴더로 끌어다 놓으세요. 이전 버전을 쓰고 있다면 SimLauncher 를 종료한 뒤 대치하면 되고, 설정과 등록한 카탈로그는 그대로 남아요. Apple 의 Developer ID 로 서명하고 공증을 받은 앱이라 바로 열 수 있어요.

처음 실행하는 방법과 기능별 사용법, 문제 해결은 [README](https://github.com/$repo#설치하기) 를 봐 주세요.

## 이번 버전에 들어간 PR ($prev 이후)
EOF
  if grep -q '[^[:space:]]' "$dir/pr-list.md"; then cat "$dir/pr-list.md"; else echo "- 없음"; fi
  cat <<EOF

## 파일
| 파일 | SHA-256 |
|---|---|
| \`SimLauncher-$version.dmg\` | \`$sha\` |
EOF
}

[[ $# -ge 1 ]] || usage
command=$1
shift
case $command in
  previous-tag) cmd_previous_tag "$@" ;;
  prepare) cmd_prepare "$@" ;;
  check-summary) cmd_check_summary "$@" ;;
  assemble) cmd_assemble "$@" ;;
  *) usage ;;
esac
