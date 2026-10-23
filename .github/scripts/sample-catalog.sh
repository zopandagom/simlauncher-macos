#!/bin/bash
# 샘플 카탈로그 생성기 (.github/workflows/sample-catalog.yml, 규격 docs/CATALOG.md).
# 사용: sample-catalog.sh <releases.json>   결과 catalog.json 은 stdout
#   <releases.json>: gh api --paginate --slurp "repos/<owner>/<repo>/releases?per_page=100" 결과 (페이지 배열의 배열)
# 이전 catalog.json 을 읽지 않고 릴리스 목록에서 매번 처음부터 만든다.
# 태그가 sample-build-<숫자> 이고 draft 가 아니며 SampleApp.zip 이 다 올라간(state=uploaded) 릴리스마다 버전 하나:
#   id·tag = 태그, name = 릴리스 이름(없으면 태그), branch·buildNumber = 본문의 "key: value" 줄(없으면 생략),
#   createdAt = published_at (created_at 은 빌드 시각이 아니라 태그 커밋 시각), buildURL = 자산의 태그 고정 주소.
# 회귀 테스트: make catalog-test (.github/scripts/Fixtures)
set -euo pipefail

releases="${1:?releases.json 경로가 필요합니다}"

jq '
  def field($key): (.body // "")
    | [scan("(?m)^" + $key + ": *(\\S[^\\r\\n]*?) *\\r?$")] | first
    | if . == null then null else .[0] end;
  {
    schemaVersion: 1,
    apps: [{
      id: "com.zopandagom.simlauncher.sampleapp",
      name: "SimLauncher Sample",
      versions: [
        add // [] | .[]
        | select(.draft | not)
        | select(.tag_name | test("^sample-build-[0-9]+$"))
        | (.assets | map(select(.name == "SampleApp.zip" and .state == "uploaded")) | first) as $zip
        | select($zip != null)
        | {
            id: .tag_name,
            name: (.name // .tag_name),
            branch: field("branch"),
            tag: .tag_name,
            buildNumber: field("buildNumber"),
            createdAt: .published_at,
            buildURL: $zip.browser_download_url
          }
        | with_entries(select(.value != null))
      ] | sort_by(.createdAt) | reverse
    }]
  }' "$releases"
