#!/bin/bash
# String Catalog(Localizable.xcstrings)의 영어(en) 값 검사. 판정은 check-xcstrings.jq 가 하고(규칙 목록은 그 파일 머리),
# 이 스크립트는 파일 열거·복수형 목록 읽기·jq 호출·종료 코드만 맡는다. 빌드 없이 카탈로그 파일만 본다.
# 사용: check-xcstrings.sh [--github] [--plural-keys <목록>] [<카탈로그>...]
#   카탈로그를 주지 않으면 레포 루트에서 git ls-files 로 Projects/ 아래 Localizable.xcstrings 를 모두 검사하고(무시된 build 폴더를
#   줍지 않는다), 복수형 목록의 모듈 가운데 카탈로그가 없는 것도 위반으로 본다.
#   모듈 이름은 Projects/<층>/<모듈>/… 의 <모듈>, 그 밖의 경로(픽스처)는 파일 이름에서 확장자를 뺀 것이다.
#   --plural-keys: 복수형이 필요한 키 목록(한 줄에 "모듈<TAB>키", # 줄·빈 줄 건너뜀). 기본 .github/scripts/xcstrings-plural-keys.txt
#   --github: 위반을 GitHub 워크플로 명령 "::error file=<파일>::<키>: <이유>" 로 쓴다(CI lint 잡)
# 출력: 위반마다 한 줄 "파일<TAB>키(JSON 문자열)<TAB>이유". 키를 JSON 문자열로 써서 줄바꿈·따옴표가 든 키도 한 줄이다.
# 종료: 위반 없음 0, 위반 1, 사용법·도구 오류(카탈로그·목록을 읽지 못함) 2.
# bash 3.2 호환(로컬 make 가 /bin/bash 3.2 로 돌린다: declare -A·mapfile·${x,,} 를 쓰지 않고, set -u 에서 빈 배열을 펼치지 않는다).
# 실제 카탈로그 검사: make strings-check, 회귀 테스트: make strings-check-test (.github/scripts/StringsFixtures)
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
program="$script_dir/check-xcstrings.jq"
plural_list="$script_dir/xcstrings-plural-keys.txt"
github=false
files=()

usage() {
  echo "사용: check-xcstrings.sh [--github] [--plural-keys <목록>] [<카탈로그>...]" >&2
  exit 2
}

while (($# > 0)); do
  case "$1" in
    --github) github=true ;;
    --plural-keys)
      (($# >= 2)) || usage
      plural_list=$2
      shift
      ;;
    -*) usage ;;
    *) files+=("$1") ;;
  esac
  shift
done

all=false
if ((${#files[@]} == 0)); then
  all=true
  cd "$(git -C "$script_dir" rev-parse --show-toplevel)"
  while IFS= read -r file; do
    files+=("$file")
  done < <(git ls-files -- 'Projects/*/Localizable.xcstrings')
  ((${#files[@]} > 0)) || { echo "검사할 Localizable.xcstrings 가 없습니다" >&2; exit 2; }
fi

# 복수형 목록 → [{module, key, line}]. 탭이 없는 줄은 형식 오류다.
[[ -r $plural_list ]] || { echo "복수형 목록을 읽을 수 없습니다: $plural_list" >&2; exit 2; }
if ! list=$(jq -Rnc '[inputs | select(test("^\\s*(#|$)") | not) | split("\t")
    | if length == 2 and (.[0] | length) > 0 and (.[1] | length) > 0 then {module: .[0], key: .[1]}
      else error("형식 오류(모듈<TAB>키): \(join("\t"))") end]' "$plural_list"); then
  echo "복수형 목록을 읽지 못했습니다: $plural_list" >&2
  exit 2
fi

module_of() {
  case "$1" in
    Projects/*/*/*) echo "$1" | cut -d/ -f3 ;;
    *)
      local name
      name=$(basename "$1")
      echo "${name%.*}"
      ;;
  esac
}

violations=""
modules=""
for file in "${files[@]}"; do
  module=$(module_of "$file")
  modules+="$module"$'\n'
  if ! out=$(jq -r --arg file "$file" --argjson plural "$(jq -c --arg m "$module" 'map(select(.module == $m) | .key)' <<<"$list")" \
    -f "$program" "$file"); then
    echo "카탈로그를 읽지 못했습니다: $file" >&2
    exit 2
  fi
  [[ -z $out ]] || violations+="$out"$'\n'
done

# 전체 검사에서는 목록의 모듈이 실제 카탈로그 모듈이어야 한다 (모듈 이름이 틀리면 그 줄을 아무도 보지 않는다).
if $all; then
  out=$(jq -r --arg file "$plural_list" --arg modules "$modules" \
    '($modules | split("\n")) as $known | .[] | select(.module as $m | $known | index($m) | not)
      | "\($file)\t\(.key | @json)\t복수형 목록의 모듈 \(.module) 에 해당하는 카탈로그가 없습니다"' <<<"$list")
  [[ -z $out ]] || violations+="$out"$'\n'
fi

[[ -n $violations ]] || exit 0
while IFS=$'\t' read -r file key reason; do
  if $github; then
    message="$key: $reason"
    message=${message//\%/%25}
    message=${message//$'\r'/%0D}
    message=${message//$'\n'/%0A}
    echo "::error file=$file::$message"
  else
    printf '%s\t%s\t%s\n' "$file" "$key" "$reason"
  fi
done <<<"${violations%$'\n'}"
exit 1
