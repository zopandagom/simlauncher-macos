import Core
import SwiftUI
import UpdateCheckInterface

/// 업데이트 확인 창(메뉴 "업데이트 확인…" 이 여는 단일 창)의 내용. 창이 열리면 확인을 요청하고(진행 중이면 합류), 닫히면 창 상태만
/// 지운다 (요청은 취소하지 않는다). "다운로드 페이지 열기" 는 앱이 만든 고정 주소를 브라우저로 열고, 버튼을 누른 뒤 창을 닫는
/// 것(`dismissWindow`)도 View 가 맡는다 (ARCHITECTURE §1 규칙 8). 배포 저장소가 없는 빌드에는 이 창의 입구가 없고, 그래도 열리면
/// 안내와 "닫기" 만 보인다 (요청하지 않는다).
public struct UpdateCheckView: View {
  /// 창 씬 id (`Window(_:id:)`). 여는 곳은 메뉴 항목(`UpdateCommands`) 하나다.
  public static let windowID = "update-check"

  /// 창 제목.
  public static var windowTitle: String {
    UpdateText.windowTitle
  }

  let model: UpdateModel
  @Environment(\.openURL) private var openURL
  @Environment(\.dismissWindow) private var dismissWindow

  public init(model: UpdateModel) {
    self.model = model
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      self.content
    }
    .padding(20)
    .frame(width: 420, alignment: .leading)
    .onAppear {
      Task { await self.model.checkForUpdatesRequested() }
    }
    .onDisappear {
      self.model.checkWindowClosed()
    }
  }

  @ViewBuilder
  private var content: some View {
    if !self.model.isAvailable {
      Text(UpdateText.unavailable)
        .fixedSize(horizontal: false, vertical: true)
      self.buttons(download: false)
    } else {
      switch self.model.manualCheck {
      case nil, .checking:
        // nil 은 onAppear 직전 한순간이라 확인 중과 같게 그린다.
        self.checking
      case let .finished(report):
        self.finished(report)
      }
    }
  }

  private var checking: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text(UpdateText.checking)
      }
      Text(UpdateText.checkingCaption)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      self.buttons(download: false)
    }
  }

  @ViewBuilder
  private func finished(_ report: UpdateCheckReport) -> some View {
    switch report {
    case let .newer(version, current, skipped):
      self.message(symbol: "arrow.down.circle.fill", title: UpdateText.newerTitle(version)) {
        Text(UpdateText.currentLine(current))
        if skipped {
          Text(UpdateText.skippedNote)
            .foregroundStyle(.secondary)
        }
      }
      self.buttons(download: true, skip: skipped ? nil : version)
    case let .upToDate(current):
      self.message(symbol: "checkmark.circle.fill", title: UpdateText.upToDate(current)) {}
      self.buttons(download: false)
    case .currentUnknown:
      self.message(symbol: "questionmark.circle.fill", title: UpdateText.currentUnknown) {}
      self.buttons(download: true)
    case .latestUnrecognized:
      self.message(symbol: "questionmark.circle.fill", title: UpdateText.latestUnrecognized) {}
      self.buttons(download: true)
    case let .failed(error):
      self.message(symbol: "exclamationmark.triangle.fill", title: UpdateText.failedTitle) {
        Text(UpdateText.message(for: error))
      }
      self.buttons(download: true, retry: true)
    }
  }

  private func message(
    symbol: String,
    title: String,
    @ViewBuilder details: () -> some View
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.title)
        .foregroundStyle(.tint)
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.headline)
        details()
      }
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// 창 아래 버튼 줄. "닫기" 는 늘 있고 창만 닫는다 (확인 중이어도 요청은 끝까지 간다).
  private func buttons(download: Bool, skip version: AppVersion? = nil, retry: Bool = false) -> some View {
    HStack {
      Spacer()
      if let version {
        Button(UpdateText.skipVersionButton) {
          self.model.skipVersionTapped(version)
          self.dismissWindow()
        }
      }
      if retry {
        Button(UpdateText.retryButton) {
          Task { await self.model.checkForUpdatesRequested() }
        }
      }
      Button(UpdateText.closeButton) {
        self.dismissWindow()
      }
      .keyboardShortcut(.cancelAction)
      if download, let url = self.model.releasePageURL {
        Button(UpdateText.openDownloadPageButton) {
          self.openURL(url)
          self.dismissWindow()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
  }
}
