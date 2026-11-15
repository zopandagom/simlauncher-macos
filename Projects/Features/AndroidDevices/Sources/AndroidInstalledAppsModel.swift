import AndroidEmulatorInterface
import Core
import Observation

/// Android 기기 행 "설치된 앱…" 시트의 상태와 로직: 켜진 에뮬레이터의 사용자 설치 패키지 목록(`installedPackages`,
/// `pm list packages -3`)을 읽어 보이고, 고른 패키지를 확인 대화상자를 거쳐 지운다(`uninstall`, `adb uninstall`: 실행 중이면 끝내고
/// 지운다). 기기 목록 상태를 함께 쓰지 않는 자기 비동기 흐름이고 `AndroidDevicesModel.swift` 가 600 줄에 닿아 따로 둔다 (App 소유,
/// iOS `InstalledAppsModel` 과 같은 모양). 쓰기와 읽기는 구조로 겹치지 않는다: 목록을 읽는 동안 삭제를 확인하지 않고
/// (`AndroidInstalledAppsDraft.canConfirm(_:)`), 삭제하는 동안 목록을 읽지 않으며(`loadPackages` 가드) 시트를 닫지 않는다
/// (`canClose`). 시트는 그 기기에 진행 작업이 없을 때만 열리고(`target`) 시트가 창을 막아 그 기기에 새 작업이 시작되지 않는다.
/// 서로 막기: 시트를 열 기기는 App 이 `AndroidDevicesModel.installedAppsTarget(_:)` 로 잇는 `target` 이 정하고,
/// `AndroidDevicesModel` 은 App 이 이 Model 의 `hasPresentedSheet` 를 다른 시트 Model 들과 OR 로 잇는 클로저로 이 시트가 떠 있는지 본다.
@MainActor
@Observable
public final class AndroidInstalledAppsModel {
  /// 시트 초안. nil 이면 시트가 닫혀 있다.
  public private(set) var draft: AndroidInstalledAppsDraft?

  @ObservationIgnored private let emulator: any AndroidEmulatorClient
  /// 시트를 열 수 있는 기기 (없으면 nil). App 이 `AndroidDevicesModel.installedAppsTarget(_:)` 로 잇는다.
  @ObservationIgnored private let target: @MainActor (AndroidVirtualDevice.ID) -> AndroidVirtualDevice?
  /// 기기 목록 다시 읽기. 명령이 기기 꺼짐·없어짐으로 실패하면 행 상태를 맞춘다. App 이 `AndroidDevicesModel.refreshButtonTapped()`
  /// 로 잇는다.
  @ObservationIgnored private let refreshRequested: @MainActor () async -> Void
  /// 마지막으로 연 시트의 번호.
  @ObservationIgnored private var nextSession = 0

  public init(
    emulator: any AndroidEmulatorClient,
    target: @escaping @MainActor (AndroidVirtualDevice.ID) -> AndroidVirtualDevice?,
    refreshRequested: @escaping @MainActor () async -> Void = {}
  ) {
    self.emulator = emulator
    self.target = target
    self.refreshRequested = refreshRequested
  }

  /// 설치된 앱 시트가 떠 있다. App 이 `AndroidDevicesModel` 의 `appSheetPresented` 에 OR 로 잇는다.
  public var hasPresentedSheet: Bool {
    self.draft != nil
  }

  // MARK: - 열기·닫기

  /// 시트를 첫 await 전에 열고(시트가 창을 막아 다른 시트·확인이 끼어들지 않는다) 설치된 패키지 목록을 읽는다.
  public func installedAppsTapped(_ id: AndroidVirtualDevice.ID) async {
    guard self.draft == nil, let device = self.target(id) else { return }
    self.nextSession += 1
    let session = self.nextSession
    self.draft = AndroidInstalledAppsDraft(deviceID: id, device: AndroidDeviceLabel(device), session: session)
    await self.loadPackages(session: session)
  }

  /// "앱 목록 다시 읽기"·실패 뒤 "다시 읽기". 읽는 중·확인 대기·삭제 중이면 무시한다 (`canRefresh`).
  public func refreshTapped() async {
    guard let draft = self.draft, draft.canRefresh else { return }
    await self.loadPackages(session: draft.session)
  }

  /// "닫기". 삭제 중이면 무시한다 (`canClose`).
  public func closeTapped() {
    guard self.draft?.canClose == true else { return }
    self.draft = nil
  }

  /// 시스템이 시트를 닫았다. 삭제 중이면 무시한다 (`canClose`. View 가 닫기를 막지만 Model 도 지킨다).
  public func sheetDismissed() {
    guard self.draft?.canClose == true else { return }
    self.draft = nil
  }

  // MARK: - 고르기·삭제

  /// 패키지를 고른다 (nil 이면 고르지 않음). 목록에 없는 패키지와 삭제 중의 고르기는 무시한다.
  public func selectionChanged(_ package: AndroidPackageName?) {
    self.draft?.selectionChanged(package)
  }

  /// "삭제…": 고른 패키지의 확인 대화상자를 띄운다 (`canRequestAction`).
  public func removeTapped() {
    guard let draft = self.draft, draft.canRequestAction, let package = draft.selectedPackage else { return }
    self.draft?.actionRequested(.remove(package))
  }

  /// 확인 대화상자의 "취소" (또는 대화상자가 닫힘).
  public func actionCancelled() {
    guard self.draft?.pendingAction != nil else { return }
    self.draft?.actionCancelled()
  }

  /// 확인 대화상자의 "삭제". SwiftUI 는 버튼 동작 뒤 곧바로 대화상자를 닫아(`actionCancelled()`) `pendingAction` 이 비므로 버튼이 받은
  /// 동작을 인자로 받는다. 목록을 읽는 중이거나 대상이 목록에서 빠졌으면 받지 않고 대화상자만 닫는다
  /// (`AndroidInstalledAppsDraft.canConfirm(_:)`). 첫 await 전에 진행 중으로 바꿔 연타한 두 번째 호출은 가드에서 끝난다. 성공하면
  /// 목록에서 그 패키지를 빼고 다시 읽고(남은 목록을 보인 채), 실패하면 결과 줄을 보인 뒤 기기 꺼짐·없어짐이면 목록 실패와 기기 목록
  /// 다시 읽기, 그 밖이면 목록을 다시 읽어 실제 상태를 맞춘다.
  public func actionConfirmed(_ action: AndroidInstalledAppsDraft.Action) async {
    guard let draft = self.draft, draft.runningAction == nil else { return }
    guard draft.canConfirm(action) else {
      self.draft?.actionCancelled()
      return
    }
    let session = draft.session
    self.draft?.actionStarted(action)
    let result: Result<Void, AndroidEmulatorError>
    do throws(AndroidEmulatorError) {
      switch action {
      case let .remove(package):
        try await self.emulator.uninstall(package, on: draft.deviceID)
      }
      result = .success(())
    } catch {
      result = .failure(error)
    }
    // 진행 중에는 닫을 수 없어 정상 흐름에서는 같은 시트다.
    guard self.draft?.session == session else { return }
    switch result {
    case .success:
      self.draft?.packageRemoved(action.package)
      await self.loadPackages(session: session)
    case let .failure(error):
      self.draft?.actionFailed(action, error)
      if error == .deviceNotBooted || error == .deviceNotFound {
        self.draft?.packagesFailed(error)
        await self.refreshRequested()
      } else {
        await self.loadPackages(session: session)
      }
    }
  }

  // MARK: - 내부

  /// 설치된 패키지 목록을 읽어 반영한다. 삭제 중이면 시작하지 않는다 (쓰기 뒤 읽기는 진행 중 표시를 지운 다음 부른다). 돌아왔을 때
  /// 시트가 닫혔거나 다시 열렸거나(번호) 그 뒤 다시 읽기를 시작했으면(요청 번호) 버린다.
  private func loadPackages(session: Int) async {
    guard let draft = self.draft, draft.session == session, draft.runningAction == nil else { return }
    self.draft?.packagesStarted()
    guard let request = self.draft?.packagesRequest else { return }
    let result: Result<[AndroidPackageName], AndroidEmulatorError>
    do throws(AndroidEmulatorError) {
      result = try await .success(self.emulator.installedPackages(on: draft.deviceID))
    } catch {
      result = .failure(error)
    }
    guard let current = self.draft, current.session == session, current.packagesRequest == request else { return }
    switch result {
    case let .success(packages):
      self.draft?.packagesLoaded(packages)
    case let .failure(error):
      self.draft?.packagesFailed(error)
      if error == .deviceNotBooted || error == .deviceNotFound {
        await self.refreshRequested()
      }
    }
  }
}
