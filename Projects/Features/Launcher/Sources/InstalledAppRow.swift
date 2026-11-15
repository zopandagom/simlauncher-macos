import Core
import SwiftUI

/// 설치된 앱 목록의 한 줄 ("앱 실행…" 시트·"설치된 앱…" 시트가 함께 쓴다). 표시 이름이 같은 앱이 있을 수 있어 번들 ID 를 함께
/// 보인다 (있으면 버전도). 앱이 정한 이름·버전·번들 ID 는 번역하지 않는 값이라 `Text(verbatim:)` 로 보인다.
struct InstalledAppRow: View {
  let app: InstalledApp

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: self.app.displayName)
        .lineLimit(1)
        .truncationMode(.middle)
      HStack(spacing: 8) {
        Text(verbatim: self.app.bundleID.rawValue)
          .lineLimit(1)
          .truncationMode(.middle)
        if let version = LauncherText.appVersionLabel(version: self.app.version, build: self.app.build) {
          Text(verbatim: version)
            .lineLimit(1)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}
