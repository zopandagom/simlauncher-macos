#!/bin/bash
# 샘플 카탈로그 생성기 (.github/workflows/sample-catalog.yml, 규격 docs/CATALOG.md).
# 사용: sample-catalog.sh <releases.json>   결과 catalog.json(schemaVersion 2) 은 stdout
#   <releases.json>: gh api --paginate --slurp "repos/<owner>/<repo>/releases?per_page=100" 결과 (페이지 배열의 배열)
# 이전 catalog.json 을 읽지 않고 릴리스 목록에서 매번 처음부터 만든다.
# 앱은 둘이고 파일 순서는 iOS → Android 다 (같은 id·이름, platform 만 다르다).
#   iOS 앱 버전은 SampleApp.zip, Android 앱 버전은 SampleAndroidApp.apk 가 다 올라간(state=uploaded) 릴리스에서 만든다.
#   Android 빌드를 함께 올리기 전의 릴리스는 iOS 앱 버전에만 든다.
# 태그가 sample-build-<숫자> 이고 draft 가 아니며 그 앱의 자산이 다 올라간 릴리스마다 그 앱의 버전 하나:
#   id·tag = 태그, name = 릴리스 이름(없으면 태그), branch·buildNumber = 본문의 "key: value" 줄(없으면 생략),
#   createdAt = published_at (created_at 은 빌드 시각이 아니라 태그 커밋 시각), buildURL = 그 자산의 태그 고정 주소.
# 회귀 테스트: make catalog-test (.github/scripts/Fixtures)
set -euo pipefail

releases="${1:?releases.json 경로가 필요합니다}"
ios_asset="SampleApp.zip"
android_asset="SampleAndroidApp.apk"

jq --arg ios "$ios_asset" --arg android "$android_asset" '
  def field($key): (.body // "")
    | [scan("(?m)^" + $key + ": *(\\S[^\\r\\n]*?) *\\r?$")] | first
    | if . == null then null else .[0] end;
  (add // []) as $releases
  | def versions($asset): [
      $releases[]
      | select(.draft | not)
      | select(.tag_name | test("^sample-build-[0-9]+$"))
      | (.assets | map(select(.name == $asset and .state == "uploaded")) | first) as $file
      | select($file != null)
      | {
          id: .tag_name,
          name: (.name // .tag_name),
          branch: field("branch"),
          tag: .tag_name,
          buildNumber: field("buildNumber"),
          createdAt: .published_at,
          buildURL: $file.browser_download_url
        }
      | with_entries(select(.value != null))
    ] | sort_by(.createdAt) | reverse;
  def app($platform; $asset): {
    id: "com.zopandagom.simlauncher.sampleapp",
    name: "SimLauncher Sample",
    platform: $platform,
    versions: versions($asset)
  };
  {
    schemaVersion: 2,
    apps: [app("ios"; $ios), app("android"; $android)]
  }' "$releases"
