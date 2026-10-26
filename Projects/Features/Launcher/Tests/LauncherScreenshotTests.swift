import AppBundleTesting
import Core
import DownloadTesting
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
import WorkspaceInterface
import WorkspaceTesting
@testable import LauncherFeature

@MainActor
struct LauncherScreenshotTests: LauncherModelTesting {
  /// 파일 이름 시각으로 쓰는 고정 시각.
  static let takenAt = Date(timeIntervalSince1970: 1_793_000_000)

  /// 켜진 iPhone 17 Pro (iOS 27.0) 를 고정 시각에 찍은 파일 이름.
  static var name: ScreenshotFileName {
    ScreenshotFileName(deviceName: "iPhone 17 Pro", runtimeName: "iOS 27.0", takenAt: takenAt, timeZone: .current)
  }

  /// Workspace Fake 가 `name` 의 attempt 번호로 예약하는 파일.
  static func reserved(_ attempt: Int = 1) -> URL {
    WorkspaceClientFake.folder.appending(path: self.name.fileName(attempt: attempt)!, directoryHint: .notDirectory)
  }

  static func model(
    workspace: WorkspaceClientFake = WorkspaceClientFake(),
    _ configure: (SimulatorClientFake) -> Void = { _ in }
  ) async -> (LauncherModel, SimulatorClientFake) {
    await loadedModel(workspace: workspace, now: self.takenAt, configure)
  }

  static func fetchCount(in simulator: SimulatorClientFake) -> Int {
    simulator.calls.filter { $0 == .fetchInventory }.count
  }

  static func screenshotCalls(in simulator: SimulatorClientFake) -> [SimulatorClientFake.Call] {
    simulator.calls.filter {
      if case .screenshot = $0 {
        true
      } else {
        false
      }
    }
  }

  // MARK: - 성공

  @Test("켜진 기기: 예약 → 촬영 → Finder 순서로 부르고, 알림 없이 목록을 다시 읽지 않으며 끝나면 촬영 중이 풀린다")
  func takesScreenshotOfBootedDevice() async {
    let workspace = WorkspaceClientFake()
    workspace.suspendReserves()
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let fetches = Self.fetchCount(in: simulator)

    let tap = Task { await model.screenshotButtonTapped(id) }
    await Self.waitUntil { !workspace.calls.isEmpty }
    // 예약이 끝나기 전에는 촬영하지 않는다.
    #expect(model.screenshots.isTaking(on: id))
    #expect(Self.screenshotCalls(in: simulator).isEmpty)

    workspace.resumeReserves()
    await tap.value
    let file = Self.reserved()
    #expect(workspace.calls == [.reserveScreenshotFile(stem: Self.name.stem), .revealInFinder(file)])
    #expect(Self.screenshotCalls(in: simulator) == [.screenshot(id, file)])
    #expect(model.notices.isEmpty)
    #expect(Self.fetchCount(in: simulator) == fetches)
    #expect(!model.screenshots.isTaking(on: id))
  }

  @Test("예약 이름은 기기 이름·런타임 이름과 주입한 시각(지금 시간대)으로 만든다")
  func reservedNameUsesDeviceAndNow() async {
    let workspace = WorkspaceClientFake()
    let (model, _) = await Self.model(workspace: workspace)

    await model.screenshotButtonTapped(SampleID.iPhoneOn)

    let expected = ScreenshotFileName(
      deviceName: "iPhone 17 Pro", runtimeName: "iOS 27.0", takenAt: Self.takenAt, timeZone: .current
    )
    #expect(workspace.calls.first == .reserveScreenshotFile(stem: expected.stem))
  }

  // MARK: - 막힘

  @Test(
    "꺼진·쓸 수 없는·목록에 없는 기기는 아무것도 부르지 않는다",
    arguments: [
      SampleID.iPhoneOff,
      SampleID.unavailableIPhone,
      VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF")
    ]
  )
  func blockedDeviceCallsNothing(id: VirtualDevice.ID) async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace)
    let before = simulator.calls

    await model.screenshotButtonTapped(id)

    #expect(workspace.calls.isEmpty)
    #expect(simulator.calls == before)
    #expect(model.notices.isEmpty)
    #expect(model.screenshots == ScreenshotActivity())
  }

  @Test("목록을 읽기 전에는 아무것도 부르지 않는다")
  func beforeLoadCallsNothing() async {
    let workspace = WorkspaceClientFake()
    let simulator = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(
      simulator: simulator,
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake(),
      workspace: workspace
    )

    await model.screenshotButtonTapped(SampleID.iPhoneOn)

    #expect(workspace.calls.isEmpty)
    #expect(simulator.calls.isEmpty)
  }

  // MARK: - 겹침

  @Test("찍는 중 같은 기기를 다시 누르면 아무것도 부르지 않고, 끝나면 한 번만 저장한다")
  func secondTapOnSameDeviceIsIgnored() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace) { $0.suspendScreenshots() }
    let id = SampleID.iPhoneOn
    let first = Task { await model.screenshotButtonTapped(id) }
    await Self.waitUntil { Self.screenshotCalls(in: simulator).count == 1 }

    let again = Self.start { await model.screenshotButtonTapped(id) }
    await Self.waitUntil { again.isFinished || workspace.calls.count > 1 }
    #expect(again.isFinished)
    #expect(workspace.calls == [.reserveScreenshotFile(stem: Self.name.stem)])
    #expect(model.screenshots.isTaking(on: id))
    // 촬영이 끝나기 전에는 Finder 를 열지 않는다.
    #expect(!workspace.calls.contains(.revealInFinder(Self.reserved())))

    simulator.resumeScreenshots()
    await first.value
    #expect(Self.screenshotCalls(in: simulator).count == 1)
    #expect(workspace.calls == [.reserveScreenshotFile(stem: Self.name.stem), .revealInFinder(Self.reserved())])
    #expect(!model.screenshots.isTaking(on: id))
  }

  @Test("켜진 두 기기를 함께 찍으면 둘 다 찍는 중이 되고, 둘 다 저장해 Finder 에서 보인다")
  func twoDevicesConcurrently() async {
    let workspace = WorkspaceClientFake()
    let inventory = Self.inventory(SampleID.iPadOff, state: .booted)
    let (model, simulator) = await Self.model(workspace: workspace) { simulator in
      simulator.setInventory(inventory)
      simulator.suspendScreenshots()
    }
    let phone = Task { await model.screenshotButtonTapped(SampleID.iPhoneOn) }
    let pad = Task { await model.screenshotButtonTapped(SampleID.iPadOff) }
    await Self.waitUntil { Self.screenshotCalls(in: simulator).count == 2 }
    #expect(model.screenshots.deviceIDs == [SampleID.iPhoneOn, SampleID.iPadOff])

    simulator.resumeScreenshots()
    await phone.value
    await pad.value
    #expect(model.screenshots.deviceIDs.isEmpty)
    let revealed = workspace.calls.filter {
      if case .revealInFinder = $0 {
        true
      } else {
        false
      }
    }
    #expect(revealed.count == 2)
    #expect(workspace.reservedFiles.count == 2)
    #expect(model.notices.isEmpty)
  }

  @Test("같은 기기에 앱을 설치하는 중에도 찍고, 기기 작업은 앱 설치 그대로다")
  func screenshotDuringInstall() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace) { $0.suspendInstalls() }
    let id = SampleID.iPhoneOn
    let picked = LauncherInstallTests.picked
    let install = Task { await model.appFileSelected(picked, for: id) }
    await Self.waitUntil { LauncherInstallTests.installCount(in: simulator) == 1 }

    await model.screenshotButtonTapped(id)

    #expect(Self.screenshotCalls(in: simulator) == [.screenshot(id, Self.reserved())])
    #expect(workspace.calls.last == .revealInFinder(Self.reserved()))
    #expect(model.activity.task(on: id) == .installApp)
    #expect(!model.screenshots.isTaking(on: id))

    simulator.resumeInstalls()
    await install.value
    #expect(model.notices.isEmpty)
  }

  // MARK: - 실패

  @Test("예약 실패: 저장 폴더 알림, 촬영·Finder·지우기 없음, 다시 읽지 않고 촬영 중이 풀린다")
  func reserveFailure() async {
    let workspace = WorkspaceClientFake()
    workspace.setReserveError(.folderUnavailable)
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let fetches = Self.fetchCount(in: simulator)

    await model.screenshotButtonTapped(id)

    #expect(workspace.calls == [.reserveScreenshotFile(stem: Self.name.stem)])
    #expect(Self.screenshotCalls(in: simulator).isEmpty)
    #expect(model.notices.map(\.notice) == [.screenshotFailed(Self.label(id), .workspace(.folderUnavailable))])
    #expect(Self.fetchCount(in: simulator) == fetches)
    #expect(!model.screenshots.isTaking(on: id))
  }

  @Test("바깥에서 꺼진 기기: 예약 파일을 지우고 꺼짐 알림 뒤 한 번 다시 읽어, 행이 꺼짐으로 바뀐다")
  func deviceTurnedOffOutside() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    // 목록 값은 켜짐 그대로이고, Client 의 실행 전 확인이 꺼짐을 본다.
    simulator.setInventory(Self.inventory(id, state: .shutdown))
    let fetches = Self.fetchCount(in: simulator)

    await model.screenshotButtonTapped(id)

    let file = Self.reserved()
    #expect(workspace.calls == [.reserveScreenshotFile(stem: Self.name.stem), .removeReservedFile(file)])
    #expect(workspace.reservedFiles.isEmpty)
    #expect(model.notices.map(\.notice) == [.screenshotFailed(Self.label(id), .simulator(.deviceNotBooted))])
    #expect(Self.fetchCount(in: simulator) == fetches + 1)
    #expect(Self.device(id, in: model)?.state == .shutdown)
    #expect(!model.screenshots.isTaking(on: id))
  }

  @Test("촬영 명령 실패: 예약 파일을 지우고 명령 실패 알림 뒤 한 번 다시 읽는다")
  func commandFailure() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace) { $0.setScreenshotError(.commandFailed) }
    let id = SampleID.iPhoneOn
    let fetches = Self.fetchCount(in: simulator)

    await model.screenshotButtonTapped(id)

    let file = Self.reserved()
    #expect(Self.screenshotCalls(in: simulator) == [.screenshot(id, file)])
    #expect(workspace.calls == [.reserveScreenshotFile(stem: Self.name.stem), .removeReservedFile(file)])
    #expect(model.notices.map(\.notice) == [.screenshotFailed(Self.label(id), .simulator(.commandFailed))])
    #expect(Self.fetchCount(in: simulator) == fetches + 1)
    #expect(!model.screenshots.isTaking(on: id))
  }

  @Test("Finder 실패: 저장한 파일은 지우지 않고 Finder 실패 알림만 띄운다")
  func revealFailure() async {
    let workspace = WorkspaceClientFake()
    workspace.setRevealError(.fileNotFound)
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let fetches = Self.fetchCount(in: simulator)

    await model.screenshotButtonTapped(id)

    let file = Self.reserved()
    #expect(workspace.calls == [.reserveScreenshotFile(stem: Self.name.stem), .revealInFinder(file)])
    #expect(workspace.reservedFiles == [file])
    #expect(model.notices.map(\.notice) == [.screenshotRevealFailed(Self.label(id), .fileNotFound)])
    #expect(Self.fetchCount(in: simulator) == fetches)
    #expect(!model.screenshots.isTaking(on: id))
  }
}

/// 스크린샷 문구.
struct ScreenshotTextTests {
  static let device = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 26.0")

  @Test("스크린샷 실패 제목에 기기 이름과 런타임 이름이 들어간다")
  func noticeTitlesContainDeviceName() {
    #expect(
      LauncherText.title(for: .screenshotFailed(Self.device, .workspace(.folderUnavailable)))
        == "“iPhone 17” (iOS 26.0) 기기의 스크린샷을 저장하지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .screenshotFailed(Self.device, .simulator(.deviceNotBooted)))
        == "“iPhone 17” (iOS 26.0) 기기의 스크린샷을 저장하지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .screenshotRevealFailed(Self.device, .fileNotFound))
        == "“iPhone 17” (iOS 26.0) 기기의 스크린샷을 저장했지만 Finder 에서 보여 주지 못했습니다"
    )
  }

  @Test("꺼진 기기 본문은 설치 문구가 아니라 스크린샷 문구이고, 그 밖의 명령 실패는 오류 분류 문구다")
  func simulatorFailureMessages() {
    let notBooted = LauncherText.message(for: ScreenshotFailure.simulator(.deviceNotBooted))
    #expect(notBooted == "기기가 켜져 있지 않아 스크린샷을 찍지 못했습니다. 기기를 켠 뒤 다시 시도하세요.")
    #expect(notBooted != LauncherText.message(for: SimulatorError.deviceNotBooted))
    for error in LauncherTextCatalog.errors where error != .deviceNotBooted {
      #expect(
        LauncherText.message(for: ScreenshotFailure.simulator(error)) == LauncherText.message(for: error),
        "\(error)"
      )
    }
    #expect(
      LauncherText.message(for: ScreenshotFailure.simulator(.deviceNotFound))
        == LauncherText.message(for: SimulatorError.deviceNotFound)
    )
  }

  @Test("저장 실패 본문은 Workspace 오류 문구이고, 알림 본문도 같다")
  func workspaceFailureMessages() {
    for error in LauncherTextCatalog.workspaceErrors {
      let message = LauncherText.message(for: error)
      #expect(LauncherText.message(for: ScreenshotFailure.workspace(error)) == message)
      #expect(LauncherText.message(for: .screenshotFailed(Self.device, .workspace(error))) == message)
      #expect(LauncherText.message(for: .screenshotRevealFailed(Self.device, error)) == message)
      #expect(message.contains("SimLauncher"), "\(error)")
    }
  }

  @Test("버튼·도움말·진행·막힌 이유가 서로 다르고 비어 있지 않다")
  func rowTexts() {
    let texts = [LauncherText.screenshotButton, LauncherText.screenshotHelp, LauncherText.takingScreenshotLabel]
      + LauncherTextCatalog.screenshotBlockReasons.map { LauncherText.screenshotBlockReason($0) }
    #expect(Set(texts).count == texts.count)
    for text in texts {
      #expect(!text.isEmpty)
    }
  }
}
