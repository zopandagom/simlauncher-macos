import Core
import DownloadInterface
import Foundation
import SwiftUI

/// 기기 한 줄: 종류 아이콘, 이름, 상태, 앱 설치 메뉴(파일에서 고르기… / URL 에서… / 카탈로그에서…)와 드롭, 링크 열기 버튼(시트),
/// 스크린샷 버튼(켜진 기기만, 찍는 중이면 작은 진행 표시), 녹화 표시(켜진 기기만: "녹화" 버튼, 녹화 중이면 경과 시간과 "중지",
/// 저장 중이면 작은 진행 표시), 켜기·끄기 버튼(받는 중이면 진행 막대와 받기 취소 버튼, 녹화 중이면 끄기 비활성),
/// 기기 작업 메뉴(… 버튼과 컨텍스트 메뉴: 초기화·삭제).
/// 여러 기기가 함께 받는 중(받기 묶음)이면 대상 행 모두에 같은 진행이 보이고, 취소 툴팁이 함께 멈추는 기기 수를 알린다.
/// 행의 버튼·메뉴·드롭·컨텍스트 메뉴는 목록 선택과 관계없이 이 기기 하나에만 동작한다.
/// 쓸 수 없는 기기는 흐리게 그리고 이유를 보인다. 막힌 메뉴 항목은 비활성으로 두고 이유를 메뉴 맨 위에 보인다 (녹화 중이면 녹화 이유를 먼저).
struct DeviceRow: View {
  let device: VirtualDevice
  /// 이 기기에서 진행 중인 작업. nil 이면 없다.
  let task: DeviceTask?
  /// URL 설치의 받기 단계. 있으면 상태 글자와 오른쪽 진행 표시가 `task` 보다 먼저 이것을 보인다.
  let downloadStage: DownloadStage?
  /// 이 기기와 같은 받기 묶음에서 받는 중인 기기 수 (`DeviceActivity.downloadGroupSize`). 2 이상이면 취소가 모두를 멈춘다.
  let downloadGroupSize: Int
  let installFromFileTapped: () -> Void
  let installFromURLTapped: () -> Void
  let installFromCatalogTapped: () -> Void
  let cancelDownloadTapped: () -> Void
  let appDropped: ([URL]) -> Void
  let openURLTapped: () -> Void
  /// 스크린샷 버튼을 누를 수 있다 (`ScreenshotActivity.canStart`: 켜진 기기, 찍는 중이 아님, 기기 작업이 없거나 앱 설치·링크 열기).
  let canTakeScreenshot: Bool
  /// 이 기기의 스크린샷을 찍는 중이다 (버튼 자리에 진행 표시).
  let isTakingScreenshot: Bool
  let screenshotTapped: () -> Void
  /// 이 기기의 녹화 단계. nil 이면 녹화 중이 아니다.
  let recordingPhase: RecordingPhase?
  /// 녹화 버튼을 누를 수 있다 (`RecordingActivity.canStart`: 스크린샷과 같은 기기·작업 규칙, 녹화 중이 아님).
  let canStartRecording: Bool
  let recordTapped: () -> Void
  let stopRecordingTapped: () -> Void
  let bootTapped: () -> Void
  let shutdownTapped: () -> Void
  let eraseTapped: () -> Void
  let deleteTapped: () -> Void
  /// 끌어다 놓는 항목이 이 줄 위에 있고 설치할 수 있다 (줄을 강조한다).
  @State private var isDropTargeted = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: self.iconName)
        .font(.title2)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: self.device.name)
        Text(self.statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
        if case let .unavailable(reason) = self.device.availability {
          Text(LauncherText.reason(for: reason))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer()
      Menu(LauncherText.installAppButton) {
        Button(LauncherText.installFromFileMenuItem, action: self.installFromFileTapped)
        Button(LauncherText.installFromURLMenuItem, action: self.installFromURLTapped)
        Button(LauncherText.installFromCatalogMenuItem, action: self.installFromCatalogTapped)
      }
      .menuStyle(.button)
      .fixedSize()
      .disabled(!self.canInstall)
      .help(self.installBlockReason ?? LauncherText.installAppHelp)
      // 링크 열기도 설치와 같은 규칙이다 (꺼져 있으면 켜고 연다).
      Button(LauncherText.openURLButton, action: self.openURLTapped)
        .disabled(!self.canInstall)
        .help(self.openURLBlockReason ?? LauncherText.openURLHelp)
      self.screenshot
      RecordingControl(
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
        Label(LauncherText.deviceActionsMenu, systemImage: "ellipsis.circle")
      }
      .labelStyle(.iconOnly)
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .disabled(self.isBusy)
      .help(self.blockReason ?? LauncherText.deviceActionsMenu)
    }
    .padding(.vertical, 4)
    .foregroundStyle(self.isAvailable ? .primary : .secondary)
    .listRowBackground(self.isDropTargeted ? Color.accentColor.opacity(0.15) : nil)
    .dropDestination(for: URL.self) { urls, _ in
      guard self.canInstall else { return false }
      self.appDropped(urls)
      return true
    } isTargeted: { isTargeted in
      self.isDropTargeted = isTargeted && self.canInstall
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
    Button(LauncherText.eraseMenuItem, action: self.eraseTapped)
      .disabled(self.device.eraseAvailability != .allowed || self.isRecording)
    Button(LauncherText.deleteMenuItem, role: .destructive, action: self.deleteTapped)
      .disabled(self.device.deleteAvailability != .allowed || self.isRecording)
  }

  /// 메뉴 맨 위에 보일 이유. 녹화 중이면 녹화 이유를 먼저 보인다. 켜져 있으면 삭제·초기화 모두, 쓸 수 없으면 초기화가 막힌다.
  private var blockReason: String? {
    if self.isRecording {
      return LauncherText.recordingBlocksDeviceActions
    }
    if case .blocked(.notShutdown) = self.device.deleteAvailability {
      return LauncherText.blockReason(.notShutdown)
    }
    if case .blocked(.unavailable) = self.device.eraseAvailability {
      return LauncherText.blockReason(.unavailable)
    }
    return nil
  }

  /// 찍는 중이면 작은 진행 표시, 아니면 스크린샷 버튼.
  @ViewBuilder
  private var screenshot: some View {
    if self.isTakingScreenshot {
      ProgressView()
        .controlSize(.small)
        .help(LauncherText.takingScreenshotLabel)
        .accessibilityLabel(LauncherText.takingScreenshotLabel)
    } else {
      Button(LauncherText.screenshotButton, action: self.screenshotTapped)
        .disabled(!self.canTakeScreenshot)
        .help(self.screenshotBlockReason ?? LauncherText.screenshotHelp)
    }
  }

  @ViewBuilder
  private var action: some View {
    if let stage = self.downloadStage {
      self.downloadProgress(stage)
    } else if self.isBusy {
      ProgressView()
        .controlSize(.small)
    } else if self.isAvailable, self.device.state == .shutdown {
      Button(LauncherText.bootButton, action: self.bootTapped)
    } else if self.device.state == .booted {
      let shutdown = Button(LauncherText.shutdownButton, action: self.shutdownTapped)
        .disabled(self.isRecording)
      if self.isRecording {
        shutdown.help(LauncherText.stopRecordingFirstHelp)
      } else {
        shutdown
      }
    }
  }

  /// 받는 중이면 진행(전체 크기를 알면 막대, 모르면 원형)과 받기 취소 버튼. 취소 중이면 원형 진행만.
  @ViewBuilder
  private func downloadProgress(_ stage: DownloadStage) -> some View {
    switch stage {
    case let .receiving(progress):
      if let progress, let expected = progress.expectedBytes, expected > 0 {
        ProgressView(value: Double(min(progress.receivedBytes, expected)), total: Double(expected))
          .frame(width: 80)
      } else {
        ProgressView()
          .controlSize(.small)
      }
      Button(LauncherText.cancelButton, action: self.cancelDownloadTapped)
        .accessibilityLabel(LauncherText.cancelDownloadAccessibilityLabel)
        .help(
          self.downloadGroupSize > 1
            ? LauncherText.batchCancelDownloadHelp(count: self.downloadGroupSize) : LauncherText.cancelDownloadHelp
        )
    case .cancelling:
      ProgressView()
        .controlSize(.small)
    }
  }

  private var isBusy: Bool {
    self.task != nil
  }

  /// 앱 설치 메뉴·드롭과 링크 열기 버튼을 받을 수 있다: 진행 중인 작업이 없고 설치할 수 있는 기기다.
  private var canInstall: Bool {
    !self.isBusy && self.device.appInstallAvailability == .allowed
  }

  /// 앱 설치 메뉴 툴팁에 보일 막힌 이유. 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var installBlockReason: String? {
    guard case let .blocked(reason) = self.device.appInstallAvailability else { return nil }
    return LauncherText.installBlockReason(reason)
  }

  /// 링크 열기 버튼 툴팁에 보일 막힌 이유. 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var openURLBlockReason: String? {
    guard case let .blocked(reason) = self.device.appInstallAvailability else { return nil }
    return LauncherText.openURLBlockReason(reason)
  }

  /// 스크린샷 버튼 툴팁에 보일 막힌 이유. 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var screenshotBlockReason: String? {
    guard case let .blocked(reason) = self.device.screenshotAvailability else { return nil }
    return LauncherText.screenshotBlockReason(reason)
  }

  /// 녹화 버튼 툴팁에 보일 막힌 이유. 기기 규칙은 스크린샷과 같다.
  private var recordBlockReason: String? {
    guard case let .blocked(reason) = self.device.screenshotAvailability else { return nil }
    return LauncherText.recordBlockReason(reason)
  }

  /// 이 기기가 녹화 중이다 (저장 중 포함). 끄기·초기화·삭제를 막는다 (`RecordingActivity.blocks`).
  private var isRecording: Bool {
    self.recordingPhase != nil
  }

  private var isAvailable: Bool {
    self.device.availability == .available
  }

  /// 받기 단계가 있으면 그것을, 아니면 진행 중인 작업을, 둘 다 없으면 기기 상태를 보인다.
  private var statusText: String {
    switch self.downloadStage {
    case let .receiving(progress):
      return LauncherText.downloadingLabel(progress)
    case .cancelling:
      return LauncherText.cancellingDownloadLabel
    case .none:
      break
    }
    switch self.task {
    case .installApp:
      return LauncherText.installingLabel
    case .openURL:
      return LauncherText.openingURLLabel
    case .boot, .shutdown, .delete, .erase, .none:
      break
    }
    return self.isAvailable ? LauncherText.stateLabel(for: self.device.state) : LauncherText.unavailableLabel
  }

  private var iconName: String {
    switch self.device.family {
    case .phone: "iphone"
    case .tablet: "ipad"
    case .watch, .tv, .vision, .other: "questionmark.square.dashed"
    }
  }
}

/// 행의 녹화 표시: 단계가 없으면 "녹화" 버튼, 시작 중이면 작은 진행 표시와 "중지", 녹화 중이면 빨간 점·경과 시간과 "중지",
/// 저장 중이면 작은 진행 표시. 경과 시간은 SwiftUI 가 스스로 다시 그리는 `Text(_:style: .timer)` 라 Model 은 시작 시각만 갖는다.
private struct RecordingControl: View {
  let phase: RecordingPhase?
  let canStart: Bool
  /// 버튼이 막힌 이유 (툴팁). nil 이면 도움말을 보인다.
  let blockReason: String?
  let recordTapped: () -> Void
  let stopTapped: () -> Void

  var body: some View {
    switch self.phase {
    case .none:
      Button(LauncherText.recordButton, action: self.recordTapped)
        .disabled(!self.canStart)
        .help(self.blockReason ?? LauncherText.recordHelp)
    case .starting:
      ProgressView()
        .controlSize(.small)
        .help(LauncherText.startingRecordingLabel)
        .accessibilityLabel(LauncherText.startingRecordingLabel)
      self.stopButton
    case let .recording(startedAt):
      HStack(spacing: 4) {
        Image(systemName: "record.circle.fill")
          .foregroundStyle(.red)
          .accessibilityLabel(LauncherText.recordingLabel)
        Text(startedAt, style: .timer)
          .monospacedDigit()
      }
      .accessibilityElement(children: .combine)
      .help(LauncherText.recordingLabel)
      self.stopButton
    case .stopping:
      ProgressView()
        .controlSize(.small)
        .help(LauncherText.stoppingRecordingLabel)
        .accessibilityLabel(LauncherText.stoppingRecordingLabel)
    }
  }

  private var stopButton: some View {
    Button(LauncherText.stopRecordingButton, action: self.stopTapped)
  }
}
