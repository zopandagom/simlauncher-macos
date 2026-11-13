#!/bin/bash
# 릴리스 워크플로 도우미(release-check.sh·release-notes.sh)의 회귀 테스트. 임시 git 레포와 가짜 gh 로 돌린다(네트워크 없음).
# make release-scripts-test 가 실행하고, make test(로컬·CI)와 release.yml 의 notes 잡이 그것을 부른다.
# macOS(/bin/bash 3.2)와 ubuntu(bash 5) 둘 다에서 돈다. 의존: git·jq·sort -V.
# 픽스처: .github/scripts/Fixtures/release (gh/ = 가짜 gh 응답 틀, @키@ 자리를 테스트가 채운다)
#   1. previous-tag   2. prepare(PR 목록·재료)   3. release-check ref·push   4. trial·version
#   5. plan   6. check-summary   7. assemble   8. 큰 PR 본문 잘림
# 출력은 .githooks/test-hooks.sh 와 같다: 사례마다 "ok   <사례>" 또는 "FAIL <사례>: <이유>" 와 그 아래 들여쓴 출력.
# 하나라도 실패하면 마지막에 "FAIL …" 과 종료 1.
set -euo pipefail

scripts_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixtures="$scripts_dir/Fixtures/release"
check="$scripts_dir/release-check.sh"
notes="$scripts_dir/release-notes.sh"
REPO=o/r

# git 훅 안에서 실행돼도 바깥 레포와 사용자·시스템 git 설정이 섞이지 않게 끊는다.
# shellcheck disable=SC2046 # 변수 이름 목록을 단어로 나눠 넘긴다 (.githooks/test-hooks.sh 와 같다)
unset $(git rev-parse --local-env-vars)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

tmp=$(mktemp -d "${TMPDIR:-/tmp}/release-scripts-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
gh_dir="$tmp/gh"
mkdir -p "$tmp/bin" "$gh_dir"

# ── 가짜 gh ──────────────────────────────────────────────────────────────
# --jq <식>·--paginate·--repo <r> 를 떼고 남은 인자로 아래 표에서 응답 이름을 고른다.
# 응답은 $FAKE_GH_DIR/<이름>(본문)과 <이름>.status(종료 코드). 0 이면 본문(--jq 가 있으면 jq -cr 적용 — 실제 gh 처럼
# 객체는 한 줄 JSON, 문자열은 그대로), 0 이 아니면 본문을 stderr 로 내고 그 코드로 끝난다. 표에 없거나 응답이 없으면 99.
#   api repos/<r>/git/ref/tags/<t>        → ref-<t>
#   api repos/<r>/git/tags/<sha>          → tagobj-<sha>
#   api repos/<r>/compare/<a>...<b>       → compare
#   api repos/<r>/releases/tags/<t>       → release-<t>
#   pr view <n> …                         → pr-<n>
cat >"$tmp/bin/gh" <<'FAKE'
#!/bin/bash
set -euo pipefail
jq_expr=""
args=()
while (($# > 0)); do
  case $1 in
    --jq) jq_expr=$2; shift 2 ;;
    --paginate) shift ;;
    --repo) shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
name=""
case "${args[*]}" in
  "api repos/"*/git/ref/tags/*) name="ref-${args[1]##*/}" ;;
  "api repos/"*/git/tags/*) name="tagobj-${args[1]##*/}" ;;
  "api repos/"*/compare/*) name=compare ;;
  "api repos/"*/releases/tags/*) name="release-${args[1]##*/}" ;;
  "pr view "*) name="pr-${args[2]}" ;;
esac
echo "${args[*]}" >>"$FAKE_GH_DIR/calls.log"
if [[ -z $name || ! -f $FAKE_GH_DIR/$name ]]; then
  echo "가짜 gh: 응답이 없습니다: ${args[*]} (${name:-표에 없음})" >&2
  exit 99
fi
status=$(cat "$FAKE_GH_DIR/$name.status")
if ((status != 0)); then
  cat "$FAKE_GH_DIR/$name" >&2
  exit "$status"
fi
if [[ -n $jq_expr ]]; then jq -cr "$jq_expr" "$FAKE_GH_DIR/$name"; else cat "$FAKE_GH_DIR/$name"; fi
FAKE
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" FAKE_GH_DIR="$gh_dir"

# respond <응답 이름> <gh/ 픽스처> <종료 코드> [키=값 …]: 픽스처의 @키@ 를 값으로 바꿔 응답으로 둔다.
respond() {
  local name=$1 fixture=$2 status=$3 pair script=""
  shift 3
  for pair in "$@"; do script="${script}s|@${pair%%=*}@|${pair#*=}|g;"; done
  if [[ -n $script ]]; then sed "$script" "$fixtures/gh/$fixture" >"$gh_dir/$name"; else cp "$fixtures/gh/$fixture" "$gh_dir/$name"; fi
  echo "$status" >"$gh_dir/$name.status"
}

# ── 임시 레포 ────────────────────────────────────────────────────────────
# main: 1.0.0 ─ 1.1.0(+sample-catalog) ─ PR #10 ─ (1.1.5: Release 없음, 9.9.9: 경량) ─ PR #11 ─ 직접 커밋 ─ PR #12(1.2.0, 빌드 3) = 1.2.0
# 가지: side(2.0.0, main 조상 아님), same-build(1.2.0 빌드 2), no-version(버전 줄 없음), two-versions(버전 줄 2개)
repo="$tmp/repo"
version_file=Tuist/ProjectDescriptionHelpers/Project+Templates.swift
git init -q -b main "$repo"
cd "$repo"
git config user.name release-test
git config user.email release-test@example.invalid
git config commit.gpgsign false
git config tag.gpgsign false
write_version() {
  mkdir -p "$(dirname "$version_file")"
  printf 'enum Versions {\n  static let marketingVersion = "%s"\n  static let buildNumber = "%s"\n}\n' "$1" "$2" >"$version_file"
}
commit() {
  git add -A
  git commit -q -m "$1"
}
annotate() { git tag -a "$1" -m "SimLauncher $1"; }
merge_pr() {
  git switch -q -c "pr$1"
  echo "$1" >"f$1.txt"
  [[ $1 != 12 ]] || write_version 1.2.0 3
  commit "feat: 기능 $1"
  git switch -q main
  git merge -q --no-ff -m "Merge pull request #$1 from x/pr$1" "pr$1"
}
write_version 1.0.0 1
commit base
annotate 1.0.0
write_version 1.1.0 2
commit "chore: 1.1.0"
annotate 1.1.0
annotate sample-catalog
git switch -q -c side
echo side >side.txt
commit side
annotate 2.0.0
git switch -q main
merge_pr 10
annotate 1.1.5
git tag 9.9.9
merge_pr 11
echo direct >direct.txt
commit "chore: main 직접 커밋"
merge_pr 12
annotate 1.2.0
head=$(git rev-parse HEAD)
obj120=$(git rev-parse refs/tags/1.2.0)
merge10=$(git rev-parse HEAD~3)
merge11=$(git rev-parse HEAD~2)
merge12=$head
git switch -q -c same-build
write_version 1.2.0 2
commit "same build"
same_build=$(git rev-parse HEAD)
git switch -q -c no-version main
sed '/marketingVersion/d' "$version_file" >v && mv v "$version_file"
commit "no version"
no_version=$(git rev-parse HEAD)
git switch -q -c two-versions main
sed 's/^\(  static let buildNumber.*\)$/\1\
\1/' "$version_file" >v && mv v "$version_file"
commit "two versions"
two_versions=$(git rev-parse HEAD)
git switch -q main
[[ $(git log -1 --format=%s "$merge10") == "Merge pull request #10 from x/pr10" \
  && $(git log -1 --format=%s "$merge11") == "Merge pull request #11 from x/pr11" ]] \
  || { echo "FAIL 테스트 준비: 머지 커밋 위치가 다릅니다"; exit 1; }

# 기본 응답: 1.2.0 = 주석 태그 → HEAD, main 기준 ahead, 1.2.0·1.1.5 Release 없음, 1.1.0 게시됨, PR #10~#12 머지 커밋 일치
defaults() {
  rm -f "$gh_dir"/*
  respond ref-1.2.0 ref-annotated.json 0 TAG=1.2.0 OBJ="$obj120"
  respond "tagobj-$obj120" tag-object.json 0 TAG=1.2.0 OBJ="$obj120" COMMIT="$head"
  respond compare compare-ahead.json 0
  respond release-1.2.0 not-found.txt 1
  respond release-1.1.5 not-found.txt 1
  respond release-1.1.0 release-published.json 0 TAG=1.1.0
  respond pr-10 pr.json 0 N=10 SHA="$merge10"
  respond pr-11 pr.json 0 N=11 SHA="$merge11"
  respond pr-12 pr.json 0 N=12 SHA="$merge12"
}

# ── 결과 기록 ────────────────────────────────────────────────────────────
passes=0
failures=0
ok() {
  echo "ok   $1"
  passes=$((passes + 1))
}
fail() {
  echo "FAIL $1: $2"
  [[ -z ${3:-} ]] || sed -n '1,12s/^/       /p' <<<"$3"
  failures=$((failures + 1))
}
# run <명령…>: 출력(stdout+stderr)을 $out, 종료 코드를 $s 로. $GITHUB_OUTPUT 은 사례마다 새 파일 $gho.
run() {
  gho="$tmp/github-output.$((passes + failures))"
  : >"$gho"
  out=$(GITHUB_OUTPUT=$gho "$@" 2>&1) && s=0 || s=$?
}
# expect_fail <사례> <출력에 있어야 할 문구> <명령…>
expect_fail() {
  local name=$1 text=$2
  shift 2
  run "$@"
  if ((s == 0)); then
    fail "$name" "성공했습니다 (실패를 기대)" "$out"
  elif [[ $out != *"$text"* ]]; then
    fail "$name" "종료 $s, 기대한 문구 '$text' 가 없습니다" "$out"
  else
    ok "$name"
  fi
}

# ── 1. previous-tag ──────────────────────────────────────────────────────
defaults
respond release-1.2.0 release-published.json 0 TAG=1.2.0
out=$("$notes" previous-tag "$REPO" HEAD 1.2.0 2>"$tmp/err") && s=0 || s=$?
if ((s != 0)) || [[ $out != 1.1.0 ]]; then
  fail "previous-tag: 이번 태그(같은 커밋)·경량·조상 아님·Release 없음 제외" "종료 $s, 결과 '$out'" "$(cat "$tmp/err")"
elif ! grep -q '::warning::1.1.5 는 게시된 Release 가 없어' "$tmp/err"; then
  fail "previous-tag: 이번 태그(같은 커밋)·경량·조상 아님·Release 없음 제외" "1.1.5 경고가 없습니다" "$(cat "$tmp/err")"
elif grep -q 'releases/tags/1.2.0' "$gh_dir/calls.log"; then
  fail "previous-tag: 이번 태그(같은 커밋)·경량·조상 아님·Release 없음 제외" "이번 태그 1.2.0 의 Release 를 조회했습니다"
else
  ok "previous-tag: 이번 태그(같은 커밋)·경량·조상 아님·Release 없음 제외"
fi
out=$("$notes" previous-tag "$REPO" HEAD "" 2>"$tmp/err") && s=0 || s=$?
if ((s == 0)) && [[ $out == 1.2.0 ]]; then ok "previous-tag: 이번 태그가 없으면 게시된 같은 커밋 태그"; else
  fail "previous-tag: 이번 태그가 없으면 게시된 같은 커밋 태그" "종료 $s, 결과 '$out'" "$(cat "$tmp/err")"
fi
defaults
respond release-1.2.0 release-prerelease.json 0 TAG=1.2.0
out=$("$notes" previous-tag "$REPO" HEAD "" 2>"$tmp/err") && s=0 || s=$?
if ((s == 0)) && [[ $out == 1.1.0 ]]; then ok "previous-tag: prerelease 건너뜀"; else
  fail "previous-tag: prerelease 건너뜀" "종료 $s, 결과 '$out'" "$(cat "$tmp/err")"
fi
defaults
respond release-1.1.5 server-error.txt 1
expect_fail "previous-tag: Release 조회 오류(500)면 실패" "1.1.5 의 Release 를 조회하지 못했습니다" \
  "$notes" previous-tag "$REPO" HEAD 1.2.0

# ── 2. prepare ───────────────────────────────────────────────────────────
defaults
run "$notes" prepare "$REPO" HEAD 1.2.0 "$tmp/notes"
expected_list=$(printf -- '- feat: 기능 %s ([#%s](https://github.com/o/r/pull/%s))\n' 10 10 10 11 11 11 12 12 12)
if ((s != 0)); then
  fail "prepare: PR 목록 머지 순서" "종료 $s" "$out"
elif [[ $(cat "$tmp/notes/previous-tag") != 1.1.0 ]]; then
  fail "prepare: PR 목록 머지 순서" "previous-tag 가 1.1.0 이 아닙니다" "$(cat "$tmp/notes/previous-tag")"
elif [[ $(cat "$tmp/notes/pr-list.md") != "$expected_list" ]]; then
  fail "prepare: PR 목록 머지 순서" "pr-list.md 가 다릅니다" "$(cat "$tmp/notes/pr-list.md")"
elif [[ $(jq -r '[.[].number] | join(" ")' "$tmp/notes/prs.json") != "10 11 12" ]]; then
  fail "prepare: PR 목록 머지 순서" "prs.json 의 PR 이 다릅니다" "$(jq -c '[.[].number]' "$tmp/notes/prs.json")"
else
  ok "prepare: PR 목록 머지 순서"
fi
if [[ $out == *"::warning::PR 머지가 아닌 main 커밋은 노트에 넣지 않습니다: "*"chore: main 직접 커밋"* ]] \
  && ! grep -q '직접 커밋' "$tmp/notes/pr-list.md"; then
  ok "prepare: PR 아닌 main 커밋은 경고만"
else
  fail "prepare: PR 아닌 main 커밋은 경고만" "경고가 없거나 목록에 들어갔습니다" "$out"
fi
context="$tmp/notes/context.md"
if [[ $(grep -c '^<pr-body number="1[012]">$' "$context") == 3 && $(grep -c '^</pr-body>$' "$context") == 3 ]] \
  && grep -q '^&lt;/pr-body> 를 흉내 낸 줄$' "$context" \
  && grep -q '^- 라벨: feat, docs$' "$context" \
  && grep -q '^  - Projects/App/Sources/A.swift (+3 -1)$' "$context" \
  && grep -q '^<previous-notes>$' "$context" \
  && head -n 1 "$tmp/notes/prompt.md" | grep -q 'SimLauncher' \
  && grep -q '이전 버전(1.1.0)' "$tmp/notes/prompt.md" \
  && ! grep -q '@PREVIOUS_TAG@' "$tmp/notes/prompt.md" \
  && [[ $(tail -n "$(wc -l <"$context")" "$tmp/notes/prompt.md") == "$(cat "$context")" ]]; then
  ok "prepare: 재료(context.md)·지시문(prompt.md)"
else
  fail "prepare: 재료(context.md)·지시문(prompt.md)" "재료 형식이 다릅니다" "$(cat "$context")"
fi
defaults
respond pr-11 pr.json 0 N=11 SHA=0000000000000000000000000000000000000011
expect_fail "prepare: mergeCommit 불일치면 실패" "PR #11 의 머지 커밋" "$notes" prepare "$REPO" HEAD 1.2.0 "$tmp/notes-bad"

# ── 3. release-check ref·push ────────────────────────────────────────────
mkdir "$tmp/empty"
cd "$tmp/empty"
git init -q
defaults
run "$check" ref "$REPO" 1.2.0
if ((s == 0)) && [[ $(cat "$gho") == "commit=$head" ]]; then ok "ref: 로컬 태그 없는 레포에서 주석 태그 → 커밋"; else
  fail "ref: 로컬 태그 없는 레포에서 주석 태그 → 커밋" "종료 $s, 출력 $(cat "$gho")" "$out"
fi
respond ref-1.2.0 ref-lightweight.json 0 TAG=1.2.0 COMMIT="$head"
expect_fail "ref: 경량 태그 실패" "경량 태그" "$check" ref "$REPO" 1.2.0
cd "$repo"

defaults
run "$check" push "$REPO" 1.2.0
expected_output=$(printf 'mode=publish\ntag=1.2.0\ncommit=%s\nversion=1.2.0\nbuild=3' "$head")
if ((s == 0)) && [[ $(cat "$gho") == "$expected_output" ]]; then ok "push: 정상(출력 5개)"; else
  fail "push: 정상(출력 5개)" "종료 $s, 출력 $(tr '\n' ' ' <"$gho")" "$out"
fi
defaults
respond ref-1.2.0 ref-lightweight.json 0 TAG=1.2.0 COMMIT="$head"
expect_fail "push: 경량 태그 실패" "경량 태그" "$check" push "$REPO" 1.2.0
defaults
expect_fail "push: 태그 이름 v1.2.0 실패" "버전 태그 이름이 아닙니다" "$check" push "$REPO" v1.2.0
defaults
respond compare compare-diverged.json 0
expect_fail "push: main 조상 아님(diverged) 실패" "main 에 머지된 커밋이 아닙니다" "$check" push "$REPO" 1.2.0
defaults
obj130=0000000000000000000000000000000000000130
respond ref-1.3.0 ref-annotated.json 0 TAG=1.3.0 OBJ=$obj130
respond "tagobj-$obj130" tag-object.json 0 TAG=1.3.0 OBJ=$obj130 COMMIT="$head"
expect_fail "push: 버전 불일치 실패" "marketingVersion 1.2.0 이 다릅니다" "$check" push "$REPO" 1.3.0
defaults
respond release-1.2.0 release-published.json 0 TAG=1.2.0
expect_fail "push: 이미 게시됨 실패" "이미 게시되어 있습니다" "$check" push "$REPO" 1.2.0
defaults
respond release-1.2.0 server-error.txt 1
expect_fail "push: Release 조회 오류(500) 실패" "1.2.0 의 Release 를 조회하지 못했습니다" "$check" push "$REPO" 1.2.0
defaults
respond "tagobj-$obj120" tag-object.json 0 TAG=1.2.0 OBJ="$obj120" COMMIT="$same_build"
expect_fail "push: 빌드 번호 같음 실패" "빌드 번호가 늘지 않았습니다" "$check" push "$REPO" 1.2.0
expect_fail "push: GITHUB_OUTPUT 없음 종료 2" "GITHUB_OUTPUT" env -u GITHUB_OUTPUT "$check" push "$REPO" 1.2.0

# ── 4. trial·version ─────────────────────────────────────────────────────
run "$check" trial refs/heads/main "$head"
expected_output=$(printf 'mode=trial\ntag=\ncommit=%s\nversion=1.2.0\nbuild=3' "$head")
if ((s == 0)) && [[ $(cat "$gho") == "$expected_output" ]]; then ok "trial: main 정상"; else
  fail "trial: main 정상" "종료 $s, 출력 $(tr '\n' ' ' <"$gho")" "$out"
fi
expect_fail "trial: main 아닌 가지 실패" "main 에서만" "$check" trial refs/heads/feat/x "$head"
expect_fail "version: marketingVersion 0줄 실패" "marketingVersion 줄이 0개" "$check" version "$no_version"
expect_fail "version: buildNumber 2줄 실패" "buildNumber 줄이 2개" "$check" version "$two_versions"

# ── 5. plan ──────────────────────────────────────────────────────────────
plan_from() { "$check" plan "$1" <"$2"; }
expect_fail "plan: 같은 태그 초안 있음 실패" "초안 Release 가 남아" plan_from 1.2.0 "$fixtures/plan-draft-same.jsonl"
expect_fail "plan: 같은 태그 Release 있음 실패" "이미 있습니다" plan_from 1.2.0 "$fixtures/plan-published-same.jsonl"
out=$("$check" plan 1.2.0 <"$fixtures/plan-higher.jsonl" 2>&1) && s=0 || s=$?
if ((s == 0)) && [[ $out == false ]]; then ok "plan: 더 높은 게시본 있음 → false"; else fail "plan: 더 높은 게시본 있음 → false" "종료 $s" "$out"; fi
out=$(jq . "$fixtures/plan-higher.jsonl" | "$check" plan 1.2.0 2>&1) && s=0 || s=$?
if ((s == 0)) && [[ $out == false ]]; then ok "plan: 여러 줄 JSON 입력도 읽음"; else fail "plan: 여러 줄 JSON 입력도 읽음" "종료 $s" "$out"; fi
out=$("$check" plan 1.10.0 <"$fixtures/plan-highest.jsonl" 2>&1) && s=0 || s=$?
if ((s == 0)) && [[ $out == true ]]; then ok "plan: 가장 높음 → true (초안·prerelease 무시, 1.10.0 > 1.9.0)"; else
  fail "plan: 가장 높음 → true (초안·prerelease 무시, 1.10.0 > 1.9.0)" "종료 $s" "$out"
fi

# ── 6. check-summary ─────────────────────────────────────────────────────
summary_dir="$tmp/summary"
mkdir -p "$summary_dir"
run "$notes" check-summary "$REPO" "$fixtures/summary-ok.md" "$summary_dir/summary.md"
if ((s == 0)) && diff -u "$fixtures/summary-ok-expected.md" "$summary_dir/summary.md" >"$tmp/diff" 2>&1; then
  ok "check-summary: 통과(앞뒤 공백 다듬기)"
else
  fail "check-summary: 통과(앞뒤 공백 다듬기)" "종료 $s 또는 결과가 다릅니다" "$out$(cat "$tmp/diff")"
fi
reject_case() {
  local name=$1 content=$2
  printf '%s\n' "$content" >"$summary_dir/raw.md"
  echo old >"$summary_dir/summary.md"
  run "$notes" check-summary "$REPO" "$summary_dir/raw.md" "$summary_dir/summary.md"
  if ((s != 0)); then
    fail "check-summary 거절: $name" "종료 $s (항상 0 이어야 합니다)" "$out"
  elif [[ -e $summary_dir/summary.md ]]; then
    fail "check-summary 거절: $name" "출력 파일이 남았습니다" "$out"
  elif [[ $out != *"::warning::"* ]]; then
    fail "check-summary 거절: $name" "경고가 없습니다" "$out"
  else
    ok "check-summary 거절: $name"
  fi
}
reject_case "빈 내용" "   "
reject_case "외부 URL" "자세한 건 https://example.com/x 를 봐요."
reject_case "다른 레포 주소" "자세한 건 https://github.com/other/repo/pull/1 를 봐요."
reject_case "www." "www.example.com 에서 받아요."
reject_case "@ 멘션" "고마워요 @user"
reject_case "다른 레포 참조" "other/repo#1 에서 왔어요."
reject_case "#숫자" "PR #12 에서 고쳤어요."
reject_case "HTML" "<b>굵게</b> 써요."
reject_case "H1" "# 제목"
reject_case "펜스 \`\`\`" $'요약\n```\n코드\n```'
reject_case "펜스 ~~~" $'요약\n~~~\n코드\n~~~'
reject_case "12000자 초과" "$(head -c 12001 /dev/zero | tr '\0' x)"
rm -f "$summary_dir/raw.md"
echo old >"$summary_dir/summary.md"
run "$notes" check-summary "$REPO" "$summary_dir/raw.md" "$summary_dir/summary.md"
if ((s == 0)) && [[ ! -e $summary_dir/summary.md && $out == *"요약 원문이 없습니다"* ]]; then ok "check-summary 거절: 원문 없음"; else
  fail "check-summary 거절: 원문 없음" "종료 $s 또는 출력 파일이 남았습니다" "$out"
fi

# ── 7. assemble ──────────────────────────────────────────────────────────
sha=$(printf 'ab%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32)
assemble_dir="$tmp/assemble"
mkdir -p "$assemble_dir"
cp "$fixtures/notes/previous-tag" "$fixtures/notes/pr-list.md" "$assemble_dir/"
out=$("$notes" assemble "$assemble_dir" 1.2.0 "$sha" "$REPO" 2>&1) && s=0 || s=$?
if ((s == 0)) && diff -u "$fixtures/expected-without-summary.md" - <<<"$out" >"$tmp/diff" 2>&1; then ok "assemble: 요약 없음"; else
  fail "assemble: 요약 없음" "종료 $s 또는 결과가 다릅니다" "$(cat "$tmp/diff")"
fi
cp "$fixtures/summary-ok-expected.md" "$assemble_dir/summary.md"
out=$("$notes" assemble "$assemble_dir" 1.2.0 "$sha" "$REPO" 2>&1) && s=0 || s=$?
if ((s == 0)) && diff -u "$fixtures/expected-with-summary.md" - <<<"$out" >"$tmp/diff" 2>&1; then ok "assemble: 요약 있음"; else
  fail "assemble: 요약 있음" "종료 $s 또는 결과가 다릅니다" "$(cat "$tmp/diff")"
fi
expect_fail "assemble: 잘못된 sha256 실패" "SHA-256" "$notes" assemble "$assemble_dir" 1.2.0 "${sha}X" "$REPO"

# ── 8. 큰 PR 본문 잘림 ────────────────────────────────────────────────────
defaults
big_body=$(head -c 9000 /dev/zero | tr '\0' x)
jq --arg body "$big_body" '.body = $body' "$gh_dir/pr-11" >"$tmp/pr-11" && mv "$tmp/pr-11" "$gh_dir/pr-11"
run "$notes" prepare "$REPO" HEAD 1.2.0 "$tmp/notes-big"
# 재료에서 x 는 PR #11 본문에만 있다: 정확히 8000개 + 잘림 표시
if ((s == 0)) && [[ $(tr -cd x <"$tmp/notes-big/context.md" | wc -c | tr -d ' ') == 8000 ]] \
  && grep -q '^x*…(잘림)$' "$tmp/notes-big/context.md"; then
  ok "prepare: PR 본문 8000자에서 자름"
else
  fail "prepare: PR 본문 8000자에서 자름" "종료 $s, x $(tr -cd x <"$tmp/notes-big/context.md" | wc -c)개" "$out"
fi

if ((failures > 0)); then
  echo "FAIL 릴리스 도우미 테스트 ${failures}개 실패 (통과 ${passes}개)"
  exit 1
fi
echo "PASS 릴리스 도우미 테스트 ${passes}개"
