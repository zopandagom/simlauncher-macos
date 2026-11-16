import Core
import DownloadInterface
import Foundation
import SwiftUI

/// 기기 한 줄: 종류 아이콘, 이름(두 줄까지, 툴팁에 전체 이름), 상태, 그리고 행에 남는 글자 버튼 넷과 진행 표시, 기기 작업 메뉴.
/// - 앱 설치 메뉴(파일에서 고르기… / URL 에서… / 카탈로그에서…)와 드롭, 앱 실행 버튼(설치한 앱을 고르는 시트),
///   로그 보기 버튼(늘 보이고, 이 기기에 앱 로그 세션이 있으면 기기 상태·작업과 관계없이 누를 수 있다. 없으면 비활성으로 두고
///   이유("앱 실행…" 안내)를 툴팁으로).
/// - 진행 표시: 스크린샷을 찍는 중이면 작은 진행, 녹화 중이면 경과 시간과 "중지"(시작·저장 중이면 작은 진행).
/// - 켜기·끄기 버튼(받는 중이면 진행 막대와 받기 취소 버튼, 녹화 중이면 끄기 비활성).
/// - 기기 작업 메뉴(⋯ 버튼과 컨텍스트 메뉴가 같은 항목, `LauncherText.deviceMenu(_:)`): 설치된 앱…(켜진 기기이고 진행 작업이
///   없을 때)·링크 열기… / 스크린샷·녹화·레이아웃 보기(러너의 최소 iOS 보다 낮은 기기는 막는다)·테스트 조건…(켜진 기기,
///   찍는 중·녹화 중·앱 작업 중에도 된다) / 초기화…·삭제…(진행 작업·녹화 중이면 막는다). 메뉴는 늘 열리고, 묶음마다 막힌 이유를
///   맨 위 줄에 보인다 (기기 묶음은 녹화 이유를 먼저). 항목 툴팁은 버튼이던 때와 같다.
/// 여러 기기가 함께 받는 중(받기 묶음)이면 대상 행 모두에 같은 진행이 보이고, 취소 툴팁이 함께 멈추는 기기 수를 알린다.
/// 행의 버튼·메뉴·드롭·컨텍스트 메뉴는 목록 선택과 관계없이 이 기기 하나에만 동작한다. 글자 버튼은 줄어들지 않고(`fixedSize`),
/// 폭이 모자라면 이름 열이 최소 폭까지 줄어든다. 쓸 수 없는 기기는 흐리게 그리고 이유를 보인다.
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
  let launchAppTapped: () -> Void
  /// "설치된 앱…" 을 누를 수 있다 (`InstalledAppsAvailability.canOpen`: 켜진 기기, 진행 작업 없음).
  let canOpenInstalledApps: Bool
  let installedAppsTapped: () -> Void
  let openURLTapped: () -> Void
  /// 이 기기에 앱 로그 세션(받는 중·끝남)이 있다 (`LauncherModel.logDevices`). 있으면 "로그 보기" 를 누를 수 있다.
  let hasLog: Bool
  /// 이 기기의 로그 창을 연다 (View 가 `openWindow` 로 연다).
  let logTapped: () -> Void
  /// 스크린샷 항목을 누를 수 있다 (`ScreenshotActivity.canStart`: 켜진 기기, 찍는 중이 아님, 기기 작업이 없거나 앱 설치·링크 열기·앱 실행).
  let canTakeScreenshot: Bool
  /// 이 기기의 스크린샷을 찍는 중이다 (행에 진행 표시).
  let isTakingScreenshot: Bool
  let screenshotTapped: () -> Void
  /// 이 기기의 녹화 단계. nil 이면 녹화 중이 아니다.
  let recordingPhase: RecordingPhase?
  /// 녹화 항목을 누를 수 있다 (`RecordingActivity.canStart`: 스크린샷과 같은 기기·작업 규칙, 녹화 중이 아님).
  let canStartRecording: Bool
  let recordTapped: () -> Void
  let stopRecordingTapped: () -> Void
  /// "레이아웃 보기" 를 누를 수 있다 (`IOSLayoutAvailability.canOpen`: 스크린샷과 같은 기기·작업 규칙).
  let canViewLayout: Bool
  /// 이 기기의 레이아웃 창을 연다 (View 가 `openWindow` 로 연다).
  let layoutTapped: () -> Void
  /// "테스트 조건…" 을 누를 수 있다 (`TestConditionsAvailability.canOpen`: 스크린샷과 같은 기기·작업 규칙).
  let canChangeTestConditions: Bool
  let testConditionsTapped: () -> Void
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
          .lineLimit(2)
          .help(Text(verbatim: self.device.name))
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
      .frame(minWidth: Self.nameMinWidth, alignment: .leading)
      .layoutPriority(1)
      Spacer(minLength: 0)
      Menu(LauncherText.installAppButton) {
        Button(LauncherText.installFromFileMenuItem, action: self.installFromFileTapped)
        Button(LauncherText.installFromURLMenuItem, action: self.installFromURLTapped)
        Button(LauncherText.installFromCatalogMenuItem, action: self.installFromCatalogTapped)
      }
      .menuStyle(.button)
      .fixedSize()
      .disabled(!self.canInstall)
      .help(self.installBlockReason ?? LauncherText.installAppHelp)
      // 앱 실행도 설치와 같은 규칙이다 (꺼져 있으면 켜고 실행한다).
      Button(LauncherText.launchAppButton, action: self.launchAppTapped)
        .fixedSize()
        .disabled(!self.canInstall)
        .help(self.launchAppBlockReason ?? LauncherText.launchAppHelp)
      Button(LauncherText.viewLogButton, action: self.logTapped)
        .fixedSize()
        .disabled(!self.hasLog)
        .help(self.hasLog ? LauncherText.viewLogHelp : LauncherText.viewLogUnavailableHelp)
      self.screenshotProgress
      RecordingControl(phase: self.recordingPhase, stopTapped: self.stopRecordingTapped)
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
      // 막힌 이유는 메뉴 안 묶음 줄로만 보인다 (한 묶음의 이유가 메뉴 전체의 툴팁이 되지 않게).
      .help(LauncherText.deviceActionsMenu)
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
      self.menuItems
    }
  }

  /// 이름·상태 열의 최소 폭. 글자 버튼은 줄어들지 않으므로 폭이 모자라면 이 열이 여기까지 줄어든다.
  private static let nameMinWidth: CGFloat = 120

  /// ⋯ 메뉴와 컨텍스트 메뉴의 항목 (`LauncherText.deviceMenu(_:)` 의 결과를 그린다).
  @ViewBuilder
  private var menuItems: some View {
    let menu = LauncherText.deviceMenu(
      DeviceRowMenu.Input(
        device: self.device,
        isBusy: self.isBusy,
        isRecording: self.isRecording,
        isTakingScreenshot: self.isTakingScreenshot,
        canOpenInstalledApps: self.canOpenInstalledApps,
        canTakeScreenshot: self.canTakeScreenshot,
        canStartRecording: self.canStartRecording,
        canViewLayout: self.canViewLayout,
        canChangeTestConditions: self.canChangeTestConditions
      )
    )
    if let reason = menu.appReason {
      Text(reason)
    }
    Button(LauncherText.installedAppsButton, action: self.installedAppsTapped)
      .disabled(!menu.canOpenInstalledApps)
      .help(self.installedAppsBlockReason ?? LauncherText.installedAppsHelp)
    Button(LauncherText.openURLButton, action: self.openURLTapped)
      .disabled(!menu.canOpenURL)
      .help(self.openURLBlockReason ?? LauncherText.openURLHelp)
    Divider()
    if let reason = menu.screenReason {
      Text(reason)
    }
    Button(LauncherText.screenshotButton, action: self.screenshotTapped)
      .disabled(!menu.canTakeScreenshot)
      .help(self.screenshotBlockReason ?? LauncherText.screenshotHelp)
    Button(LauncherText.recordButton, action: self.recordTapped)
      .disabled(!menu.canRecord)
      .help(self.recordBlockReason ?? LauncherText.recordHelp)
    Button(LauncherText.layoutButton, action: self.layoutTapped)
      .disabled(!menu.canViewLayout)
      .help(self.layoutBlockReason ?? LauncherText.layoutHelp)
    Button(LauncherText.testConditionsButton, action: self.testConditionsTapped)
      .disabled(!menu.canChangeTestConditions)
      .help(self.testConditionsBlockReason ?? LauncherText.testConditionsHelp)
    Divider()
    if let reason = menu.deviceReason {
      Text(reason)
    }
    Button(LauncherText.eraseMenuItem, action: self.eraseTapped)
      .disabled(!menu.canErase)
    Button(LauncherText.deleteMenuItem, role: .destructive, action: self.deleteTapped)
      .disabled(!menu.canDelete)
  }

  /// 스크린샷을 찍는 중이면 작은 진행 표시 (스크린샷은 ⋯ 메뉴 항목이다).
  @ViewBuilder
  private var screenshotProgress: some View {
    if self.isTakingScreenshot {
      ProgressView()
        .controlSize(.small)
        .help(LauncherText.takingScreenshotLabel)
        .accessibilityLabel(LauncherText.takingScreenshotLabel)
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
        .fixedSize()
    } else if self.device.state == .booted {
      let shutdown = Button(LauncherText.shutdownButton, action: self.shutdownTapped)
        .fixedSize()
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
        .fixedSize()
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

  /// 앱 설치 메뉴·드롭과 앱 실행 버튼을 받을 수 있다: 진행 중인 작업이 없고 설치할 수 있는 기기다.
  private var canInstall: Bool {
    !self.isBusy && self.device.appInstallAvailability == .allowed
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
    case .launchApp:
      return LauncherText.launchingAppLabel
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

// MARK: - 버튼·메뉴 항목 툴팁의 막힌 이유

extension DeviceRow {
  /// 앱 설치 메뉴 툴팁에 보일 막힌 이유. 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var installBlockReason: String? {
    guard case let .blocked(reason) = self.device.appInstallAvailability else { return nil }
    return LauncherText.installBlockReason(reason)
  }

  /// 링크 열기 항목 툴팁에 보일 막힌 이유. 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var openURLBlockReason: String? {
    guard case let .blocked(reason) = self.device.appInstallAvailability else { return nil }
    return LauncherText.openURLBlockReason(reason)
  }

  /// 앱 실행 버튼 툴팁에 보일 막힌 이유. 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var launchAppBlockReason: String? {
    guard case let .blocked(reason) = self.device.appInstallAvailability else { return nil }
    return LauncherText.launchAppBlockReason(reason)
  }

  /// 스크린샷 항목 툴팁에 보일 막힌 이유. 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var screenshotBlockReason: String? {
    guard case let .blocked(reason) = self.device.screenshotAvailability else { return nil }
    return LauncherText.screenshotBlockReason(reason)
  }

  /// "레이아웃 보기" 항목 툴팁에 보일 막힌 이유. 기기 규칙은 스크린샷과 같고, 러너보다 낮은 iOS 도 막는다.
  private var layoutBlockReason: String? {
    if case let .blocked(reason) = self.device.screenshotAvailability {
      return LauncherText.layoutBlockReason(reason)
    }
    return IOSLayoutAvailability.supportsRunner(self.device) ? nil : LauncherText.layoutUnsupportedOS
  }

  /// "설치된 앱…" 항목 툴팁에 보일 막힌 이유 (꺼짐·켜는 중·쓸 수 없음). 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var installedAppsBlockReason: String? {
    guard case let .blocked(reason) = self.device.screenshotAvailability else { return nil }
    return LauncherText.installedAppsBlockReason(reason)
  }

  /// "테스트 조건…" 항목 툴팁에 보일 막힌 이유 (꺼짐·켜는 중·쓸 수 없음). 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var testConditionsBlockReason: String? {
    guard case let .blocked(reason) = self.device.screenshotAvailability else { return nil }
    return LauncherText.testConditionsBlockReason(reason)
  }

  /// 녹화 항목 툴팁에 보일 막힌 이유. 기기 규칙은 스크린샷과 같다.
  private var recordBlockReason: String? {
    guard case let .blocked(reason) = self.device.screenshotAvailability else { return nil }
    return LauncherText.recordBlockReason(reason)
  }
}

/// 행의 녹화 진행 표시: 단계가 없으면 아무것도 없고("녹화" 는 ⋯ 메뉴 항목), 시작 중이면 작은 진행 표시와 "중지",
/// 녹화 중이면 빨간 점·경과 시간과 "중지", 저장 중이면 작은 진행 표시. 경과 시간은 SwiftUI 가 스스로 다시 그리는
/// `Text(_:style: .timer)` 라 Model 은 시작 시각만 갖는다.
private struct RecordingControl: View {
  let phase: RecordingPhase?
  let stopTapped: () -> Void

  var body: some View {
    switch self.phase {
    case .none:
      EmptyView()
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
      .fixedSize()
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
      .fixedSize()
  }
}
