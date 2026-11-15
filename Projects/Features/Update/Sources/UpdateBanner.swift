import Core
import SwiftUI

/// 메인 창 위쪽의 새 버전 배너. `model.availableUpdate` 가 nil 이면 아무것도 그리지 않는다.
/// "다운로드 페이지 열기" 는 빌드 설정의 배포 저장소로 앱이 만든 고정 주소(`model.releasePageURL`)를 시스템 기본 브라우저로 연다
/// (화면 일이라 Model 이벤트가 없다, ARCHITECTURE §1 규칙 8). 닫기(×)는 그 버전을 하루 동안 숨긴다.
public struct UpdateBanner: View {
  let model: UpdateModel
  @Environment(\.openURL) private var openURL

  public init(model: UpdateModel) {
    self.model = model
  }

  public var body: some View {
    if let version = self.model.availableUpdate, let current = self.model.currentVersion {
      self.content(version, current: current)
    }
  }

  private func content(_ version: AppVersion, current: AppVersion) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "arrow.down.circle.fill")
        .foregroundStyle(.tint)
        .imageScale(.large)
      Text(UpdateText.banner(version, current: current))
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      Button(UpdateText.skipVersionButton) {
        self.model.skipVersionTapped(version)
      }
      if let url = self.model.releasePageURL {
        Button(UpdateText.openDownloadPageButton) {
          self.openURL(url)
        }
      }
      Button {
        self.model.bannerDismissed()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .help(UpdateText.dismissBannerLabel)
      .accessibilityLabel(UpdateText.dismissBannerLabel)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.bar)
    .overlay(alignment: .bottom) {
      Divider()
    }
  }
}
