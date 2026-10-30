import Core
import DownloadInterface
import SwiftUI

/// 기기 한 줄: 모양 아이콘, 표시 이름, "API · 상태" 글자(쓸 수 없으면 이유 줄), 앱 설치 메뉴(파일에서 고르기…·URL 에서…·
/// 카탈로그에서…)와 드롭,
/// "앱 실행…"·"링크 열기…" 버튼(시트), "스크린샷"·"녹화" 버튼(찍는 중·녹화 단계 표시), 켜기·끄기 버튼(앱 작업 중이면 진행 표시),
/// 기기 작업 메뉴(… 버튼과 컨텍스트 메뉴: 초기화·삭제).
/// 스크린샷·녹화는 켜진 기기만 되고 앱 작업 중에도 된다. 녹화 중(저장 중 포함)이면 끄기·초기화·삭제를 막고 이유를 보인다.
/// 앱 설치·실행·링크 열기는 켜진 기기만 된다 (꺼진·켜는 중·쓸 수 없는 행은 비활성이고 도움말에 이유를 보이며, 드롭을 거절한다).
/// 앱이 켜는 중인 행은 끄기를 포함한 모든 동작을 막는다. 앱 밖에서 켜는 중인 행은 끌 수 있다.
/// 쓸 수 없는 기기는 흐리게 그리고 이유를 보인다. 실행 중이면 상태도 함께 보이고 끌 수 있다.
/// 막힌 메뉴 항목은 비활성으로 두고 이유를 메뉴 맨 위에 보인다. URL·카탈로그에서 받는 중이면 진행(전체 크기를 알면 막대, 모르면
/// 원형)과 받기 취소 버튼을(여러 기기에 함께 받는 중이면 취소가 모두를 멈춘다는 툴팁), 취소 중이면 원형 진행만 보인다.
/// 받기가 끝나면 설치 중 표시로 돌아간다.
struct AndroidDeviceRow: View {
  let device: AndroidVirtualDevice
  /// 이 기기에서 앱이 진행 중인 작업. nil 이면 없다.
  let task: AndroidDeviceTask?
  /// URL·카탈로그에서 설치의 받기 단계. nil 이면 받는 중이 아니다.
  let downloadStage: AndroidDownloadStage?
  /// 이 기기와 같은 받기 묶음에서 받는 중인 기기 수 (`AndroidDeviceActivity.downloadGroupSize`). 2 이상이면 취소가 모두를 멈춘다.
  let downloadGroupSize: Int
  let bootTapped: () -> Void
  let shutdownTapped: () -> Void
  let eraseTapped: () -> Void
  let deleteTapped: () -> Void
  let installFromFileTapped: () -> Void
  let installFromURLTapped: () -> Void
  let installFromCatalogTapped: () -> Void
  let cancelDownloadTapped: () -> Void
  let appDropped: ([URL]) -> Void
  let launchAppTapped: () -> Void
  let openURLTapped: () -> Void
  /// 스크린샷 버튼을 누를 수 있다 (`AndroidScreenshotActivity.canStart`: 켜진 기기, 찍는 중이 아님, 기기 작업이 없거나 앱 작업).
  let canTakeScreenshot: Bool
  /// 이 기기의 스크린샷을 찍는 중이다 (버튼 자리에 진행 표시).
  let isTakingScreenshot: Bool
  let screenshotTapped: () -> Void
  /// 이 기기의 녹화 단계. nil 이면 녹화 중이 아니다.
  let recordingPhase: AndroidRecordingPhase?
  /// 녹화 버튼을 누를 수 있다 (`AndroidRecordingActivity.canStart`: 스크린샷과 같은 기기·작업 규칙, 녹화 중이 아님).
  let canStartRecording: Bool
  let recordTapped: () -> Void
  let stopRecordingTapped: () -> Void
  /// 끌어다 놓는 항목이 이 줄 위에 있고 설치할 수 있다 (줄을 강조한다).
  @State private var isDropTargeted = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: self.iconName)
        .font(.title2)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: self.device.displayName)
        Text(verbatim: self.statusLine)
          .font(.caption)
          .foregroundStyle(.secondary)
        if case let .unavailable(reason) = self.device.availability {
          Text(AndroidDevicesText.reason(for: reason))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer()
      Menu(AndroidDevicesText.installAppButton) {
        Button(AndroidDevicesText.installFromFileMenuItem, action: self.installFromFileTapped)
        Button(AndroidDevicesText.installFromURLMenuItem, action: self.installFromURLTapped)
        Button(AndroidDevicesText.installFromCatalogMenuItem, action: self.installFromCatalogTapped)
      }
      .menuStyle(.button)
      .fixedSize()
      .disabled(!self.canAct)
      .help(self.appActionBlockReason ?? AndroidDevicesText.installAppHelp)
      Button(AndroidDevicesText.launchAppButton, action: self.launchAppTapped)
        .disabled(!self.canAct)
        .help(self.appActionBlockReason ?? AndroidDevicesText.launchAppHelp)
      Button(AndroidDevicesText.openURLButton, action: self.openURLTapped)
        .disabled(!self.canAct)
        .help(self.appActionBlockReason ?? AndroidDevicesText.openURLHelp)
      self.screenshot
      AndroidRecordingControl(
        phase: self.recordingPhase,
        canStart: self.canStartRecording,
        blockReason: self.recordBlockReason,
        recordTapped: self.recordTapped,
        stopTapped: self.stopRecordingTapped
      )
      self.action
      Menu {
        self.menuItems
      } label: {
        Label(AndroidDevicesText.deviceActionsMenu, systemImage: "ellipsis.circle")
      }
      .labelStyle(.iconOnly)
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .disabled(self.isBusy)
      .help(self.blockReason ?? AndroidDevicesText.deviceActionsMenu)
    }
    .padding(.vertical, 4)
    .foregroundStyle(self.isAvailable ? .primary : .secondary)
    .listRowBackground(self.isDropTargeted ? Color.accentColor.opacity(0.15) : nil)
    .dropDestination(for: URL.self) { urls, _ in
      guard self.canAct else { return false }
      self.appDropped(urls)
      return true
    } isTargeted: { isTargeted in
      self.isDropTargeted = isTargeted && self.canAct
    }
    .contextMenu {
      if !self.isBusy {
        self.menuItems
      }
    }
  }

  @ViewBuilder
  private var menuItems: some View {
    if let reason = self.blockReason {
      Text(reason)
      Divider()
    }
    Button(AndroidDevicesText.eraseMenuItem, action: self.eraseTapped)
      .disabled(self.device.eraseAvailability != .allowed || self.isRecording)
    Button(AndroidDevicesText.deleteMenuItem, role: .destructive, action: self.deleteTapped)
      .disabled(self.device.deleteAvailability != .allowed || self.isRecording)
  }

  /// 메뉴 맨 위에 보일 이유. 녹화 중이면 녹화 이유를 먼저 보인다. 켜져 있으면 삭제·초기화 모두, 쓸 수 없으면 초기화가 막힌다.
  private var blockReason: String? {
    if self.isRecording {
      return AndroidDevicesText.recordingBlocksDeviceActions
    }
    if case .blocked(.notShutdown) = self.device.deleteAvailability {
      return AndroidDevicesText.blockReason(.notShutdown)
    }
    if case .blocked(.unavailable) = self.device.eraseAvailability {
      return AndroidDevicesText.blockReason(.unavailable)
    }
    return nil
  }

  /// 찍는 중이면 작은 진행 표시, 아니면 스크린샷 버튼.
  @ViewBuilder
  private var screenshot: some View {
    if self.isTakingScreenshot {
      ProgressView()
        .controlSize(.small)
        .help(AndroidDevicesText.takingScreenshotLabel)
        .accessibilityLabel(AndroidDevicesText.takingScreenshotLabel)
    } else {
      Button(AndroidDevicesText.screenshotButton, action: self.screenshotTapped)
        .disabled(!self.canTakeScreenshot)
        .help(self.captureBlockReason(AndroidDevicesText.screenshotBlockReason) ?? AndroidDevicesText.screenshotHelp)
    }
  }

  /// 받는 중이면 받기 진행, 앱 작업 중이면 진행 표시(켜는 중이면 오래 걸릴 수 있다는 도움말), 켤 수 있으면 "켜기",
  /// 켜는 중·켜짐이면 "끄기" (녹화 중이면 비활성이고 도움말에 이유).
  @ViewBuilder
  private var action: some View {
    if let stage = self.downloadStage {
      self.downloadProgress(stage)
    } else if let task = self.task {
      ProgressView()
        .controlSize(.small)
        .help(task == .boot ? AndroidDevicesText.bootingHelp : AndroidDevicesText.taskLabel(for: task))
        .accessibilityLabel(AndroidDevicesText.taskLabel(for: task))
    } else if self.device.canBoot {
      Button(AndroidDevicesText.bootButton, action: self.bootTapped)
    } else if self.device.canShutdown {
      let shutdown = Button(AndroidDevicesText.shutdownButton, action: self.shutdownTapped)
        .disabled(self.isRecording)
      if self.isRecording {
        shutdown.help(AndroidDevicesText.stopRecordingFirstHelp)
      } else {
        shutdown
      }
    }
  }

  /// 받는 중이면 진행(전체 크기를 알면 막대, 모르면 원형)과 받기 취소 버튼. 취소 중이면 원형 진행만.
  @ViewBuilder
  private func downloadProgress(_ stage: AndroidDownloadStage) -> some View {
    switch stage {
    case let .receiving(progress):
      if let progress, let expected = progress.expectedBytes, expected > 0 {
        ProgressView(value: Double(min(progress.receivedBytes, expected)), total: Double(expected))
          .frame(width: 80)
      } else {
        ProgressView()
          .controlSize(.small)
      }
      Button(AndroidDevicesText.cancelButton, action: self.cancelDownloadTapped)
        .accessibilityLabel(AndroidDevicesText.cancelDownloadAccessibilityLabel)
        .help(
          self.downloadGroupSize > 1
            ? AndroidDevicesText.batchCancelDownloadHelp(count: self.downloadGroupSize)
            : AndroidDevicesText.cancelDownloadHelp
        )
    case .cancelling:
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel(AndroidDevicesText.cancellingDownloadLabel)
    }
  }

  private var isBusy: Bool {
    self.task != nil
  }

  /// 앱 설치 메뉴·드롭과 앱 실행·링크 열기 버튼을 받을 수 있다: 진행 중인 작업이 없고 켜진·쓸 수 있는 기기다.
  private var canAct: Bool {
    !self.isBusy && self.device.appActionAvailability == .allowed
  }

  /// 앱 설치·실행·링크 열기 도움말에 보일 막힌 이유. 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var appActionBlockReason: String? {
    guard case let .blocked(reason) = self.device.appActionAvailability else { return nil }
    return AndroidDevicesText.appActionBlockReason(reason)
  }

  /// 스크린샷·녹화 버튼 툴팁에 보일 막힌 이유 (기기 규칙은 앱 작업과 같다). 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private func captureBlockReason(_ text: (AndroidAppActionBlockReason) -> String) -> String? {
    guard case let .blocked(reason) = self.device.appActionAvailability else { return nil }
    return text(reason)
  }

  private var recordBlockReason: String? {
    self.captureBlockReason(AndroidDevicesText.recordBlockReason)
  }

  /// 이 기기가 녹화 중이다 (저장 중 포함). 끄기·초기화·삭제를 막는다 (`AndroidRecordingActivity.blocks`).
  private var isRecording: Bool {
    self.recordingPhase != nil
  }

  private var isAvailable: Bool {
    self.device.availability == .available
  }

  /// "API 37.0 · 꺼짐". 받는 중이면 받기 글자, 앱 작업 중이면 작업 글자(켜는 중이면 오래 걸릴 수 있다는 안내도), 쓸 수 없으면
  /// "사용할 수 없음" (실행 중이면 상태도 함께).
  private var statusLine: String {
    var parts: [String] = []
    if let image = self.device.systemImage {
      parts.append(AndroidDevicesText.apiLabel(image))
    }
    if let stage = self.downloadStage {
      switch stage {
      case let .receiving(progress): parts.append(AndroidDevicesText.downloadingLabel(progress))
      case .cancelling: parts.append(AndroidDevicesText.cancellingDownloadLabel)
      }
    } else if let task = self.task {
      parts.append(AndroidDevicesText.taskLabel(for: task))
      if task == .boot {
        parts.append(AndroidDevicesText.bootingHelp)
      }
    } else if self.isAvailable {
      parts.append(AndroidDevicesText.stateLabel(for: self.device.state))
    } else {
      parts.append(AndroidDevicesText.unavailableLabel)
      if self.device.state != .shutdown {
        parts.append(AndroidDevicesText.stateLabel(for: self.device.state))
      }
    }
    return parts.joined(separator: " · ")
  }

  private var iconName: String {
    switch self.device.formFactor {
    case .phone: "smartphone"
    case .tablet: "ipad.landscape"
    case .none: "questionmark.square.dashed"
    }
  }
}
