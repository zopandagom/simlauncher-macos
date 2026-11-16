# String Catalog(Localizable.xcstrings) 하나의 영어(en) 값 검사. check-xcstrings.sh 가 파일마다 부른다.
# 입력: 카탈로그 JSON. 인자: $file(출력에 쓰는 경로), $plural(이 카탈로그에서 복수형이 필요한 키 배열, xcstrings-plural-keys.txt).
# 출력(jq -r): 위반마다 한 줄 "파일<TAB>키(JSON 문자열)<TAB>이유". 위반이 없으면 아무것도 쓰지 않는다.
# 원문(ko 값, 없으면 키)과 en 의 모든 문구(단순 값, variations.plural, substitutions 의 plural)를 본다:
#   1. en 이 있다 (shouldTranslate: false 항목은 건너뛴다)
#   2. en 의 stringUnit 마다 state 가 translated 이고 값이 공백만이 아니다
#   3. en 값에 한글이 없다
#   4. 포맷 지정자: en 이 쓰는 인자마다 원문의 같은 번호 인자와 종류가 같고, 원문의 인자를 en 전체에서 한 번 이상 쓴다
#      (복수형 one 이 숫자를 빼는 것은 허용). 짝 없는 % 는 오류
#   5. 원문의 인자가 하나가 아닌 키에 최상위 variations.plural 을 쓰지 않는다 (어느 인자로 고르는지 모호하다. substitutions 를 쓴다)
#   6. $plural 의 키는 en 에 variations.plural 이나 substitutions 가 있다. 목록의 키가 카탈로그에 없어도 위반이다

# 포맷 지정자 하나: %[n$](#@이름@ | % | arg | [플래그][폭][.정밀도][길이]변환). 뒤가 맞지 않는 % 는 모든 캡처가 null 이다.
def spec_re:
  "%(?<pos>[0-9]+\\$)?(?:#@(?<sub>[A-Za-z0-9_]+)@|(?<pct>%)|(?<arg>arg)|[-+ #0']*[0-9]*(?:\\.[0-9]+)?(?<len>hh|h|ll|l|q|L|z|t|j)?(?<conv>[@dDuUxXoOfeEgGcCsSpaFA]))?";

# 문구 하나의 지정자를 인자 번호·종류로 푼다. 위치를 주지 않은 지정자는 앞 지정자 번호 + 1 이다.
# $subs: en 의 substitutions(없으면 {}), $own: 이 문구가 substitution 안의 변형이면 그 substitution(%arg 의 인자), 아니면 null.
# 결과: [{n, type}] 또는 [{bad: 이유}].
def tokens($s; $subs; $own):
  reduce ($s | [capture(spec_re; "g")])[] as $c ({i: 0, out: []};
    ($c.pos | if . == null then null else rtrimstr("$") | tonumber end) as $pos
    | if $c.pct != null then .
      elif $c.sub != null then
        ($subs[$c.sub]) as $d
        | if $d == null then .out += [{bad: "없는 substitution %#@\($c.sub)@ 를 씁니다"}]
          else ($pos // $d.argNum) as $n | .i = $n | .out += [{n: $n, type: $d.formatSpecifier}]
          end
      elif $c.arg != null then
        if $own == null then .out += [{bad: "%arg 는 substitution 의 변형 안에서만 씁니다"}]
        else .out += [{n: $own.argNum, type: $own.formatSpecifier}]
        end
      elif $c.conv != null then
        ($pos // (.i + 1)) as $n | .i = $n | .out += [{n: $n, type: (($c.len // "") + $c.conv)}]
      else .out += [{bad: "짝 없는 % 가 있습니다 (글자 % 는 %% 로 씁니다)"}]
      end)
  | .out;

def has_hangul: test("\\p{Hangul}");

# en 의 stringUnit 들: [{where, unit, own}]. where 는 이유에 쓰는 위치 이름.
def units($en):
  [ ($en.stringUnit | select(. != null) | {where: "en", unit: ., own: null}),
    ($en.variations.plural // {} | to_entries[]
      | {where: "en plural.\(.key)", unit: .value.stringUnit, own: null}),
    ($en.substitutions // {} | to_entries[] | .key as $name | .value as $d
      | ($d.variations.plural // {} | to_entries[]
        | {where: "en substitutions.\($name).\(.key)", unit: .value.stringUnit, own: $d})) ];

# 한 항목의 위반 이유 목록.
def entry_problems($key; $entry; $needs_plural):
  ($entry.localizations.en) as $en
  | ($entry.localizations.ko.stringUnit.value // $key) as $source
  | (tokens($source; {}; null)) as $source_tokens
  | ($source_tokens | map(select(.n != null)) | group_by(.n) | map({key: (.[0].n | tostring), value: .[0].type})
    | from_entries) as $args
  | if $en == null then ["en 값이 없습니다"]
    else
      ($en.substitutions // {}) as $subs
      | units($en) as $units
      | [ ($source_tokens[] | select(.bad != null) | "원문: \(.bad)"),
          ($source_tokens | map(select(.n != null)) | group_by(.n)[] | select((map(.type) | unique | length) > 1)
            | "원문의 인자 \(.[0].n) 의 종류가 여러 가지입니다"),
          (($en.variations // {}) | keys[] | select(. != "plural") | "지원하지 않는 변형 variations.\(.) 를 씁니다"),
          (if $en.stringUnit != null and $en.variations != null then "en 에 stringUnit 과 variations 를 함께 씁니다" else empty end),
          (if $en.stringUnit == null and $en.variations == null then "en 에 stringUnit 도 variations 도 없습니다" else empty end),
          (if $en.substitutions != null and $en.stringUnit == null
           then "substitutions 를 쓰는 en 에 그것을 부르는 stringUnit 이 없습니다" else empty end),
          # 복수형 범주: 영어는 one·other
          (((if $en.variations.plural != null then [{where: "en plural", plural: $en.variations.plural}] else [] end)
            + ($subs | to_entries | map({where: "en substitutions.\(.key)", plural: .value.variations.plural})))[]
            | .where as $w
            | if .plural == null then "\($w) 에 variations.plural 이 없습니다"
              else (["one", "other"] - (.plural | keys))[] | "\($w) 에 \(.) 변형이 없습니다"
              end),
          ($subs | to_entries[]
            | select((.value.argNum | type) != "number" or (.value.formatSpecifier | type) != "string")
            | "en substitutions.\(.key) 에 argNum(숫자)·formatSpecifier(문자열)가 없습니다"),
          # 상태·빈 값·한글
          ($units[] | .where as $w
            | if .unit == null then "\($w) 에 stringUnit 이 없습니다"
              else (if .unit.state != "translated" then "\($w) 의 state 가 translated 가 아닙니다 (\(.unit.state))" else empty end),
                   (if ((.unit.value // "") | test("^\\s*$")) then "\($w) 값이 비었습니다" else empty end),
                   (if ((.unit.value // "") | has_hangul) then "\($w) 값에 한글이 있습니다" else empty end)
              end),
          # 지정자
          ($units[] | select(.unit.value != null) | .where as $w
            | tokens(.unit.value; $subs; .own)[]
            | if .bad != null then "\($w): \(.bad)"
              elif .n == null or $args[.n | tostring] == null then "\($w) 이 원문에 없는 인자 \(.n) 을 씁니다"
              elif $args[.n | tostring] != .type
              then "\($w) 의 인자 \(.n) 이 %\(.type) 입니다 (원문은 %\($args[.n | tostring]))"
              else empty
              end),
          (([$units[] | select(.unit.value != null) | tokens(.unit.value; $subs; .own)[] | .n | select(. != null)]
             | unique | map(tostring)) as $used
            | $args | keys[] | select(. as $n | $used | index($n) | not)
            | "원문의 인자 \(.) (%\($args[.])) 를 en 에서 쓰지 않습니다"),
          (if $en.variations.plural != null and ($args | length) != 1
           then "원문의 인자가 \($args | length)개인 키에 최상위 variations.plural 을 씁니다 (인자 하나만 복수형으로 고르려면 substitutions 를 쓰세요)"
           else empty end),
          (if $needs_plural and $en.variations.plural == null and $en.substitutions == null
           then "복수형 목록(xcstrings-plural-keys.txt)의 키인데 en 에 variations.plural 도 substitutions 도 없습니다"
           else empty end)
        ]
    end;

.strings as $strings
| ( ($strings | to_entries[]
      | select(.value.shouldTranslate != false)
      | .key as $key
      | entry_problems($key; .value; ($plural | index($key) != null))[]
      | "\($file)\t\($key | @json)\t\(.)"),
    ($plural[] | select(. as $k | $strings | has($k) | not)
      | "\($file)\t\(@json)\t복수형 목록(xcstrings-plural-keys.txt)의 키가 이 카탈로그에 없습니다") )
