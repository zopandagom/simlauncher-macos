import Core
import DownloadInterface
import SwiftUI

/// 기기 한 줄: 모양 아이콘, 표시 이름(두 줄까지, 툴팁에 전체 이름), "API · 상태" 글자(쓸 수 없으면 이유 줄), 그리고 행에 남는
/// 글자 버튼 넷과 진행 표시, 기기 작업 메뉴.
/// - 앱 설치 메뉴(파일에서 고르기…·URL 에서…·카탈로그에서…)와 드롭, "앱 실행…" 버튼(시트), "로그 보기" 버튼(늘 보이고, 앱 로그
///   세션이 없으면 비활성 + 안내 툴팁. 기기 상태·작업과 관계없이 세션이 있으면 눌린다).
/// - 진행 표시: 스크린샷을 찍는 중이면 작은 진행, 녹화 중이면 경과 시간과 "중지"(시작·저장 중이면 작은 진행).
/// - 켜기·끄기 버튼(앱 작업 중이면 진행 표시).
/// - 기기 작업 메뉴(⋯ 버튼과 컨텍스트 메뉴가 같은 항목, `AndroidDevicesText.deviceMenu(_:)`): 설치된 앱…(켜진 기기이고
///   진행 작업이 없을 때)·링크 열기… / 스크린샷·녹화·레이아웃 보기·테스트 조건…(켜진 기기, 찍는 중·녹화 중·앱 작업 중에도 된다) /
///   초기화…·삭제…(진행 작업·녹화 중이면 막는다). 메뉴는 늘 열리고, 묶음마다 막힌 이유를 맨 위 줄에 보인다 (기기 묶음은 녹화 이유를
///   먼저). 항목 툴팁은 버튼이던 때와 같다.
/// 녹화 중(저장 중 포함)이면 끄기·초기화·삭제를 막고 이유를 보인다.
/// 앱 설치·실행·링크 열기는 켜진 기기만 된다 (꺼진·켜는 중·쓸 수 없는 행은 비활성이고 도움말에 이유를 보이며, 드롭을 거절한다).
/// 앱이 켜는 중인 행은 끄기를 포함한 모든 동작을 막는다. 앱 밖에서 켜는 중인 행은 끌 수 있다.
/// 쓸 수 없는 기기는 흐리게 그리고 이유를 보인다. 실행 중이면 상태도 함께 보이고 끌 수 있다.
/// URL·카탈로그에서 받는 중이면 진행(전체 크기를 알면 막대, 녹화 중인 행은 값이 있는 작은 원형, 모르면 원형)과 받기 취소 버튼을(여러 기기에 함께 받는 중이면 취소가
/// 모두를 멈춘다는 툴팁), 취소 중이면 원형 진행만 보인다. 받기가 끝나면 설치 중 표시로 돌아간다.
/// 글자 버튼은 줄어들지 않고(`fixedSize`), 폭이 모자라면 이름 열이 최소 폭까지 줄어든다.
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
  /// "설치된 앱…" 을 누를 수 있다 (`AndroidInstalledAppsAvailability.canOpen`: 켜진 기기, 진행 작업 없음).
  let canOpenInstalledApps: Bool
  let installedAppsTapped: () -> Void
  /// 이 기기에 앱 로그 세션(받는 중·끝남)이 있다 (`AndroidAppSheetsModel.logDevices`). 있으면 "로그 보기" 를 누를 수 있다.
  let hasLog: Bool
  /// 이 기기의 로그 창을 연다 (View 가 `openWindow` 로 연다).
  let logTapped: () -> Void
  /// 스크린샷 항목을 누를 수 있다 (`AndroidScreenshotActivity.canStart`: 켜진 기기, 찍는 중이 아님, 기기 작업이 없거나 앱 작업).
  let canTakeScreenshot: Bool
  /// 이 기기의 스크린샷을 찍는 중이다 (행에 진행 표시).
  let isTakingScreenshot: Bool
  let screenshotTapped: () -> Void
  /// 이 기기의 녹화 단계. nil 이면 녹화 중이 아니다.
  let recordingPhase: AndroidRecordingPhase?
  /// 녹화 항목을 누를 수 있다 (`AndroidRecordingActivity.canStart`: 스크린샷과 같은 기기·작업 규칙, 녹화 중이 아님).
  let canStartRecording: Bool
  let recordTapped: () -> Void
  let stopRecordingTapped: () -> Void
  /// "레이아웃 보기" 를 누를 수 있다 (`AndroidLayoutAvailability.canOpen`: 스크린샷과 같은 기기·작업 규칙).
  let canViewLayout: Bool
  /// 이 기기의 레이아웃 창을 연다 (View 가 `openWindow` 로 연다).
  let layoutTapped: () -> Void
  /// "테스트 조건…" 을 누를 수 있다 (`AndroidTestConditionsAvailability.canOpen`: 레이아웃 보기와 같은 기기·작업 규칙).
  let canChangeTestConditions: Bool
  let testConditionsTapped: () -> Void
  /// 끌어다 놓는 항목이 이 줄 위에 있고 설치할 수 있다 (줄을 강조한다).
  @State private var isDropTargeted = false

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: self.iconName)
        .font(.title2)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: self.device.displayName)
          .lineLimit(2)
          .help(Text(verbatim: self.device.displayName))
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
      .frame(minWidth: Self.nameMinWidth, alignment: .leading)
      .layoutPriority(1)
      Spacer(minLength: 0)
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
        .fixedSize()
        .disabled(!self.canAct)
        .help(self.appActionBlockReason ?? AndroidDevicesText.launchAppHelp)
      Button(AndroidDevicesText.viewLogButton, action: self.logTapped)
        .fixedSize()
        .disabled(!self.hasLog)
        .help(self.hasLog ? AndroidDevicesText.viewLogHelp : AndroidDevicesText.viewLogUnavailableHelp)
      self.screenshotProgress
      AndroidRecordingControl(phase: self.recordingPhase, stopTapped: self.stopRecordingTapped)
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
      // 막힌 이유는 메뉴 안 묶음 줄로만 보인다 (한 묶음의 이유가 메뉴 전체의 툴팁이 되지 않게).
      .help(AndroidDevicesText.deviceActionsMenu)
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
      self.menuItems
    }
  }

  /// 이름·상태 열의 최소 폭. 글자 버튼은 줄어들지 않으므로 폭이 모자라면 이 열이 여기까지 줄어든다.
  private static let nameMinWidth: CGFloat = 120

  /// 스크린샷을 찍는 중이면 작은 진행 표시 (스크린샷은 ⋯ 메뉴 항목이다).
  @ViewBuilder
  private var screenshotProgress: some View {
    if self.isTakingScreenshot {
      ProgressView()
        .controlSize(.small)
        .help(AndroidDevicesText.takingScreenshotLabel)
        .accessibilityLabel(AndroidDevicesText.takingScreenshotLabel)
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
        .fixedSize()
    } else if self.device.canShutdown {
      let shutdown = Button(AndroidDevicesText.shutdownButton, action: self.shutdownTapped)
        .fixedSize()
        .disabled(self.isRecording)
      if self.isRecording {
        shutdown.help(AndroidDevicesText.stopRecordingFirstHelp)
      } else {
        shutdown
      }
    }
  }

  /// 받는 중이면 진행(전체 크기를 알면 막대, 녹화 중인 행은 값이 있는 작은 원형, 모르면 원형)과 받기 취소 버튼.
  /// 취소 중이면 원형 진행만.
  @ViewBuilder
  private func downloadProgress(_ stage: AndroidDownloadStage) -> some View {
    switch stage {
    case let .receiving(progress):
      if let progress, let expected = progress.expectedBytes, expected > 0 {
        let bar = ProgressView(value: Double(min(progress.receivedBytes, expected)), total: Double(expected))
        if self.isRecording {
          // 녹화 중 행은 경과 시간·"중지" 가 더해져 80pt 막대면 영어에서 detail 최소 폭을 넘는다 (`MainWindow.detailMinWidth`).
          bar
            .progressViewStyle(.circular)
            .controlSize(.small)
        } else {
          bar
            .frame(width: 80)
        }
      } else {
        ProgressView()
          .controlSize(.small)
      }
      Button(AndroidDevicesText.cancelButton, action: self.cancelDownloadTapped)
        .fixedSize()
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

  /// 앱 설치 메뉴·드롭과 앱 실행 버튼을 받을 수 있다: 진행 중인 작업이 없고 켜진·쓸 수 있는 기기다.
  private var canAct: Bool {
    !self.isBusy && self.device.appActionAvailability == .allowed
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
    // 펼친 두 면 (macOS 11 이상). 기기 모양 SF Symbol 중 폴더블 전용은 없다.
    case .foldable: "rectangle.split.2x1"
    case .none: "questionmark.square.dashed"
    }
  }
}

// MARK: - 기기 작업 메뉴와 버튼·메뉴 항목 툴팁의 막힌 이유

// 타입 본문 길이(lint `type_body_length`)에 들지 않게 같은 파일의 extension 에 둔다 (같은 파일이라 `private` 에 닿는다).
extension AndroidDeviceRow {
  /// 앱 설치·실행·링크 열기 도움말에 보일 막힌 이유. 진행 중이면 행의 진행 표시가 이유라 따로 보이지 않는다.
  private var appActionBlockReason: String? {
    guard case let .blocked(reason) = self.device.appActionAvailability else { return nil }
    return AndroidDevicesText.appActionBlockReason(reason)
  }

  /// 스크린샷·녹화·레이아웃 보기·테스트 조건·설치된 앱 항목 툴팁에 보일 막힌 이유 (기기 규칙은 앱 작업과 같다). 진행 중이면 행의
  /// 진행 표시가 이유라 따로 보이지 않는다.
  private func captureBlockReason(_ text: (AndroidAppActionBlockReason) -> String) -> String? {
    guard case let .blocked(reason) = self.device.appActionAvailability else { return nil }
    return text(reason)
  }

  /// ⋯ 메뉴와 컨텍스트 메뉴의 항목 (`AndroidDevicesText.deviceMenu(_:)` 의 결과를 그린다).
  @ViewBuilder
  private var menuItems: some View {
    let menu = AndroidDevicesText.deviceMenu(
      AndroidDeviceRowMenu.Input(
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
    Button(AndroidDevicesText.installedAppsButton, action: self.installedAppsTapped)
      .disabled(!menu.canOpenInstalledApps)
      .help(
        self.captureBlockReason(AndroidDevicesText.installedAppsBlockReason) ?? AndroidDevicesText.installedAppsHelp
      )
    Button(AndroidDevicesText.openURLButton, action: self.openURLTapped)
      .disabled(!menu.canOpenURL)
      .help(self.appActionBlockReason ?? AndroidDevicesText.openURLHelp)
    Divider()
    if let reason = menu.screenReason {
      Text(reason)
    }
    Button(AndroidDevicesText.screenshotButton, action: self.screenshotTapped)
      .disabled(!menu.canTakeScreenshot)
      .help(self.captureBlockReason(AndroidDevicesText.screenshotBlockReason) ?? AndroidDevicesText.screenshotHelp)
    Button(AndroidDevicesText.recordButton, action: self.recordTapped)
      .disabled(!menu.canRecord)
      .help(self.captureBlockReason(AndroidDevicesText.recordBlockReason) ?? AndroidDevicesText.recordHelp)
    Button(AndroidDevicesText.layoutButton, action: self.layoutTapped)
      .disabled(!menu.canViewLayout)
      .help(self.captureBlockReason(AndroidDevicesText.layoutBlockReason) ?? AndroidDevicesText.layoutHelp)
    Button(AndroidDevicesText.testConditionsButton, action: self.testConditionsTapped)
      .disabled(!menu.canChangeTestConditions)
      .help(
        self.captureBlockReason(AndroidDevicesText.testConditionsBlockReason) ?? AndroidDevicesText.testConditionsHelp
      )
    Divider()
    if let reason = menu.deviceReason {
      Text(reason)
    }
    Button(AndroidDevicesText.eraseMenuItem, action: self.eraseTapped)
      .disabled(!menu.canErase)
    Button(AndroidDevicesText.deleteMenuItem, role: .destructive, action: self.deleteTapped)
      .disabled(!menu.canDelete)
  }
}
