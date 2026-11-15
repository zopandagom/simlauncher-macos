import AndroidEmulatorInterface
import Core
import Foundation
import Observation

/// Android 기기 행 "테스트 조건…" 시트의 상태와 로직: 켜진 에뮬레이터의 외관(`cmd uimode night`)과 위치 서비스 켜짐
/// (`cmd location is-location-enabled`)을 읽어 보이고, 외관을 바꾸며 위치 한 점(`emu geo fix`)을 보낸다. 앱 단위 구역에서는 사용자
/// 설치 패키지 목록(`installedPackages`)을 읽어 앱을 고르고, 그 앱의 런타임 권한을 읽어(`dumpsys package`) 허용·거부한다
/// (`pm grant`·`pm revoke` + `pm clear-permission-flags`). 명령은 모두 짧게 끝나 이 Model 이 들고 있는 장기 작업은 없다.
/// 시트를 닫아도 진행 중 명령은 취소하지 않고, 결과는 기기별 `applying`·`sentLocations` 에 반영된다. 기기 목록 상태를 함께 쓰지
/// 않는 자기 비동기 흐름이고 `AndroidDevicesModel.swift` 가 600 줄에 닿아 따로 둔다 (App 소유, iOS `TestConditionsModel` 과 같은 모양).
/// 서로 막기: 시트를 열 기기는 App 이 `AndroidDevicesModel.testConditionsTarget(_:)` 로 잇는 `target` 이 정하고, `AndroidDevicesModel`
/// 은 App 이 이 Model 의 `hasPresentedSheet` 를 앱 실행·링크 열기·설치된 앱 시트와 OR 로 잇는 클로저로 이 시트가 떠 있는지 본다.
@MainActor
@Observable
public final class AndroidTestConditionsModel {
  /// 시트 초안. nil 이면 시트가 닫혀 있다.
  public private(set) var draft: AndroidTestConditionsDraft?
  /// 기기별 적용 중인 항목 (한 기기에 하나). 시트를 닫았다 다시 열어도 같은 기기의 두 번째 명령을 막도록 초안 밖에 둔다.
  public private(set) var applying: [AndroidVirtualDevice.ID: AndroidTestConditionItem] = [:]
  /// SimLauncher 가 켜져 있는 동안 기기별로 마지막으로 보낸 위치. 앱을 다시 켜면 비어 있다 (저장하지 않는다).
  public private(set) var sentLocations: [AndroidVirtualDevice.ID: AndroidSentLocation] = [:]

  @ObservationIgnored private let emulator: any AndroidEmulatorClient
  /// 시트를 열 수 있는 기기 (없으면 nil). App 이 `AndroidDevicesModel.testConditionsTarget(_:)` 로 잇는다.
  @ObservationIgnored private let target: @MainActor (AndroidVirtualDevice.ID) -> AndroidVirtualDevice?
  /// 기기 목록 다시 읽기. 명령이 기기 꺼짐·없어짐으로 실패하면 행 상태를 맞춘다. App 이 `AndroidDevicesModel.refreshButtonTapped()`
  /// 로 잇는다.
  @ObservationIgnored private let refreshRequested: @MainActor () async -> Void
  /// 보낸 위치의 시각.
  @ObservationIgnored private let now: @Sendable () -> Date
  /// 마지막으로 연 시트의 번호.
  @ObservationIgnored private var nextSession = 0
  /// 기기별로 끝난 외관 쓰기 횟수. 읽는 동안 쓰기가 끝났으면 그 읽기는 쓰기 전 값일 수 있어 다시 읽는다.
  @ObservationIgnored private var settingsEpoch: [AndroidVirtualDevice.ID: Int] = [:]
  /// 기기별로 사용자가 마지막으로 고른 패키지. 같은 기기의 시트를 다시 열면 그 패키지를 먼저 고른다 (SimLauncher 가 켜져 있는 동안).
  @ObservationIgnored private var lastSelectedPackage: [AndroidVirtualDevice.ID: AndroidPackageName] = [:]
  /// 기기별로 끝난 권한 쓰기 횟수. 권한을 읽는 동안 쓰기가 끝났으면 그 읽기는 쓰기 전 값일 수 있어 다시 읽는다.
  @ObservationIgnored private var permissionEpoch: [AndroidVirtualDevice.ID: Int] = [:]

  public init(
    emulator: any AndroidEmulatorClient,
    target: @escaping @MainActor (AndroidVirtualDevice.ID) -> AndroidVirtualDevice?,
    refreshRequested: @escaping @MainActor () async -> Void = {},
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.emulator = emulator
    self.target = target
    self.refreshRequested = refreshRequested
    self.now = now
  }

  /// 테스트 조건 시트가 떠 있다. App 이 `AndroidDevicesModel` 의 `appSheetPresented` 에 OR 로 잇는다.
  public var hasPresentedSheet: Bool {
    self.draft != nil
  }

  // MARK: - 열기·닫기

  /// 시트를 첫 await 전에 열고(시트가 창을 막아 다른 시트·확인이 끼어들지 않는다) 지금 값을 읽은 뒤 설치된 패키지 목록을 읽는다
  /// (고른 패키지가 생기면 그 권한도 읽는다). 지금 값 읽기가 기기 꺼짐·없어짐으로 실패했으면 목록은 읽지 않고 같은 실패를 보인다
  /// (목록 새로 고침은 지금 값 읽기에서 한 번).
  public func testConditionsTapped(_ id: AndroidVirtualDevice.ID) async {
    guard self.draft == nil, let device = self.target(id) else { return }
    self.nextSession += 1
    let session = self.nextSession
    self.draft = AndroidTestConditionsDraft(deviceID: id, device: AndroidDeviceLabel(device), session: session)
    await self.readConditions(on: id, session: session)
    guard let draft = self.draft, draft.session == session else { return }
    if case let .failed(error) = draft.conditions, error == .deviceNotBooted || error == .deviceNotFound {
      self.draft?.updateApp { $0.packagesFailed(error) }
      return
    }
    await self.loadPackages(on: id, session: session)
  }

  /// 읽기가 실패한 화면 구역의 "다시 읽기".
  public func conditionsRetryTapped() async {
    guard let draft = self.draft, case .failed = draft.conditions else { return }
    self.draft?.conditionsStarted()
    await self.readConditions(on: draft.deviceID, session: draft.session)
  }

  /// 진행 중 명령은 취소하지 않는다 (짧게 끝나고, 결과는 `applying`·`sentLocations` 에만 반영된다).
  public func closeTapped() {
    self.draft = nil
  }

  public func sheetDismissed() {
    self.draft = nil
  }

  // MARK: - 외관

  /// 외관을 보낸다. iOS 와 달리 자동·예약 모드나 읽지 못한 값에서도 보낸다 (쓰기 출력으로 확인한다). 지금 값과 같으면 보내지 않는다.
  public func appearanceSelected(_ appearance: DeviceAppearance) async {
    guard let draft = self.draft,
          case let .loaded(conditions) = draft.conditions,
          conditions.nightMode.appearance != appearance,
          self.applying[draft.deviceID] == nil
    else { return }
    let id = draft.deviceID
    // 첫 await 전에 채워 연타한 두 번째 호출은 위에서 끝난다.
    self.applying[id] = .appearance
    self.draft?.messageChanged(nil)
    let result: Result<AndroidConditionOutcome, AndroidEmulatorError>
    do throws(AndroidEmulatorError) {
      result = try await .success(self.emulator.setNightMode(appearance, on: id))
    } catch {
      result = .failure(error)
    }
    self.applying[id] = nil
    self.settingsEpoch[id, default: 0] += 1
    // 결과는 기기의 사실이라 같은 기기의 시트면(다시 열었어도) 반영한다.
    let isShown = self.draft?.deviceID == id
    switch result {
    case .success(.applied):
      if isShown {
        self.draft?.nightModeApplied(appearance)
      }
    case .success(.notApplied):
      if isShown {
        self.draft?.messageChanged(.notApplied(.appearance))
      }
    case let .failure(error):
      if isShown {
        self.draft?.messageChanged(.failed(.appearance, error))
      }
      await self.refreshIfDeviceChanged(error)
    }
  }

  // MARK: - 위치

  public func pointTextChanged(_ text: String) {
    self.draft?.pointTextChanged(text)
  }

  /// 프리셋은 입력란을 채우기만 한다 (곧바로 보내지 않는다).
  public func locationPresetSelected(_ preset: LocationPreset) {
    let coordinate = preset.coordinate
    self.draft?.pointTextChanged(
      "\(GeoCoordinate.decimalString(coordinate.latitude)), \(GeoCoordinate.decimalString(coordinate.longitude))"
    )
  }

  /// 위치는 외관 읽기 상태와 관계없이 보낼 수 있다 (읽는 중·읽기 실패에도). 성공하면 시트가 닫혔어도 기록한다.
  /// 입력란은 지우지 않는다 (같은 값으로 다시 보내기 쉽게).
  public func setPointTapped() async {
    guard let draft = self.draft, let coordinate = draft.pointCoordinate, self.applying[draft.deviceID] == nil else {
      return
    }
    let id = draft.deviceID
    self.applying[id] = .location
    self.draft?.messageChanged(nil)
    let result: Result<AndroidConditionOutcome, AndroidEmulatorError>
    do throws(AndroidEmulatorError) {
      result = try await .success(self.emulator.setLocation(coordinate, on: id))
    } catch {
      result = .failure(error)
    }
    self.applying[id] = nil
    let isShown = self.draft?.deviceID == id
    switch result {
    case .success(.applied):
      self.sentLocations[id] = AndroidSentLocation(coordinate: coordinate, sentAt: self.now())
    case .success(.notApplied):
      if isShown {
        self.draft?.messageChanged(.notApplied(.location))
      }
    case let .failure(error):
      if isShown {
        self.draft?.messageChanged(.failed(.location, error))
      }
      await self.refreshIfDeviceChanged(error)
    }
  }

  // MARK: - 내부

  /// 지금 값을 읽어 반영한다. 돌아왔을 때 시트가 닫혔거나 다시 열렸으면 버린다. 읽는 동안 그 기기의 외관 쓰기가 끝났으면 쓰기 전
  /// 값일 수 있어 한 번 더 읽는다. 읽는 동안에는 외관을 바꿀 수 없고(`.loaded` 가 아님) 쓰기 결과도 읽은 값(`.loaded`)이 있을 때만
  /// 반영되어(`nightModeApplied`) 읽는 동안 `.loaded` 가 되지 않으므로, 겹치는 쓰기는 읽기 전에 시작한 하나뿐이라 한 번이면 된다.
  private func readConditions(on id: AndroidVirtualDevice.ID, session: Int) async {
    var retried = false
    while true {
      let epoch = self.settingsEpoch[id, default: 0]
      let result: Result<AndroidTestConditions, AndroidEmulatorError>
      do throws(AndroidEmulatorError) {
        result = try await .success(self.emulator.testConditions(on: id))
      } catch {
        result = .failure(error)
      }
      guard self.draft?.session == session else { return }
      if self.settingsEpoch[id, default: 0] != epoch, !retried {
        retried = true
        continue
      }
      switch result {
      case let .success(conditions):
        self.draft?.conditionsLoaded(conditions)
      case let .failure(error):
        self.draft?.conditionsFailed(error)
        await self.refreshIfDeviceChanged(error)
      }
      return
    }
  }

  /// 기기가 꺼졌거나 없어진 실패면 기기 목록을 다시 읽어 행 상태를 맞춘다 (알림은 쌓지 않는다).
  private func refreshIfDeviceChanged(_ error: AndroidEmulatorError) async {
    if error == .deviceNotBooted || error == .deviceNotFound {
      await self.refreshRequested()
    }
  }
}

// MARK: - 앱 단위 (앱 고르기·권한)

// 타입 본문 길이(lint `type_body_length`)에 들지 않게 같은 파일의 extension 에 둔다 (같은 파일이라 `private` 상태에 닿는다).
public extension AndroidTestConditionsModel {
  /// "앱 목록 다시 읽기". 읽는 중(첫 읽기·다시 읽기)이 아니면(읽었거나 실패했으면) 다시 읽는다. 읽는 동안 마지막 목록·고른 패키지·
  /// 읽어 둔 권한 값(`.loaded` 일 때)을 그대로 보인다. 고른 패키지가 새 목록에 있으면 그대로 두고, 고른 패키지가 있으면 그 권한도 다시 읽는다 (다시 설치한
  /// 앱일 수 있다. 같은 패키지면 읽어 둔 권한 값(`.loaded`)이 있을 때 읽는 동안에도 그 값을 보인다).
  func packagesRefreshTapped() async {
    guard let draft = self.draft, !draft.app.isReadingPackages else { return }
    await self.loadPackages(on: draft.deviceID, session: draft.session)
  }

  /// 패키지를 고른다 (nil 이면 고르지 않음). 보이는 목록(다시 읽는 동안은 마지막 목록)에 없는 패키지는 무시한다. 고르면 그 권한을 읽는다.
  func packageSelected(_ package: AndroidPackageName?) async {
    guard let draft = self.draft else { return }
    var accepted = false
    self.draft?.updateApp { accepted = $0.packageSelected(package) }
    guard accepted else { return }
    self.lastSelectedPackage[draft.deviceID] = package
    if let package {
      await self.loadPermissions(of: package, on: draft.deviceID, session: draft.session)
    }
  }

  /// 권한 읽기가 실패한 권한 구역의 "다시 읽기". 앱이 없다고 읽은 상태도 받지만,
  /// 화면은 그 상태에서 이 버튼 대신 "앱 목록 다시 읽기"(`packagesRefreshTapped`, 앱 목록을 읽는 동안은 꺼 둔다)를 보인다.
  func permissionsRetryTapped() async {
    guard let draft = self.draft, let package = draft.app.selectedPackage else { return }
    switch draft.app.permissions {
    case .failed, .appNotInstalled:
      await self.loadPermissions(of: package, on: draft.deviceID, session: draft.session)
    case .idle, .loading, .loaded:
      return
    }
  }

  /// 고른 앱의 런타임 권한 하나를 허용(`granted`)하거나 거부한다. 지금 값을 읽었고 그 값과 다르며 그 기기에 적용 중인 것이 없을 때만.
  /// 허용된 권한을 거부하면 실행 중인 앱이 종료된다 (그 행이 늘 안내한다, 확인은 묻지 않는다). 결과는 같은 기기의 시트이고 같은 패키지를
  /// 고르고 있을 때만 반영한다 (다른 패키지를 골랐으면 그 읽기가 맞춘다. 쓰기 자체는 앞 앱에 적용된 채다).
  func permissionChanged(_ permission: AndroidRuntimePermission, granted: Bool) async {
    guard let draft = self.draft,
          let package = draft.app.selectedPackage,
          let current = draft.app.grant(of: permission),
          current.isGranted != granted,
          self.applying[draft.deviceID] == nil
    else { return }
    let id = draft.deviceID
    let item = AndroidTestConditionItem.permission(permission)
    // 첫 await 전에 채워 연타한 두 번째 호출은 위에서 끝난다.
    self.applying[id] = item
    self.draft?.messageChanged(nil)
    let result: Result<AndroidPermissionOutcome, AndroidEmulatorError>
    do throws(AndroidEmulatorError) {
      result = try await .success(self.emulator.setRuntimePermission(permission, granted: granted, of: package, on: id))
    } catch {
      result = .failure(error)
    }
    self.applying[id] = nil
    self.permissionEpoch[id, default: 0] += 1
    let isShown = self.draft?.deviceID == id && self.draft?.app.selectedPackage == package
    switch result {
    case let .success(.applied(grants)):
      if isShown {
        self.draft?.updateApp { $0.permissionsChanged(.loaded(grants)) }
      }
    case let .success(.notApplied(grants)):
      if isShown {
        self.draft?.updateApp { $0.permissionsChanged(.loaded(grants)) }
        self.draft?.messageChanged(.permissionNotApplied(permission, granted: granted))
      }
    case .success(.appNotInstalled):
      if isShown {
        self.draft?.updateApp { $0.permissionsChanged(.appNotInstalled) }
        self.draft?.messageChanged(.appNotInstalled(package))
      }
    case let .failure(error):
      if isShown {
        self.draft?.messageChanged(.failed(item, error))
      }
      await self.refreshIfDeviceChanged(error)
    }
  }

  /// 설치된 패키지 목록을 읽어 반영한다. 돌아왔을 때 시트가 닫혔거나 다시 열렸거나(번호) 그 뒤 다시 읽기를 시작했으면(요청 번호)
  /// 버린다. 반영 뒤 고른 패키지가 있으면 그 권한을 읽는다: 반영 전과 같은 패키지면 읽어 둔 권한 값(`.loaded`)이 있을 때 그 값을
  /// 그대로 보이며 읽고(`keepingShown`. 없으면 `.loading` 부터), 선택 규칙으로 다른 패키지가 골라졌으면 `.loading` 부터.
  private func loadPackages(on id: AndroidVirtualDevice.ID, session: Int) async {
    guard self.draft?.session == session else { return }
    self.draft?.updateApp { $0.packagesStarted() }
    guard let request = self.draft?.app.packagesRequest else { return }
    let result: Result<[AndroidPackageName], AndroidEmulatorError>
    do throws(AndroidEmulatorError) {
      result = try await .success(self.emulator.installedPackages(on: id))
    } catch {
      result = .failure(error)
    }
    guard let draft = self.draft, draft.session == session, draft.app.packagesRequest == request else { return }
    switch result {
    case let .success(packages):
      let remembered = self.lastSelectedPackage[id]
      let previous = draft.app.selectedPackage
      self.draft?.updateApp { $0.packagesLoaded(packages, remembered: remembered) }
      if let package = self.draft?.app.selectedPackage {
        await self.loadPermissions(of: package, on: id, session: session, keepingShown: package == previous)
      }
    case let .failure(error):
      self.draft?.updateApp { $0.packagesFailed(error) }
      await self.refreshIfDeviceChanged(error)
    }
  }

  /// 고른 패키지의 런타임 권한을 읽어 반영한다. 돌아왔을 때 시트·요청 번호·고른 패키지가 그대로일 때만 반영한다. 읽는 동안 그 기기의
  /// 권한 쓰기가 끝났으면 쓰기 전 값일 수 있어 다시 읽고, 쓰기가 끝나지 않은 읽기를 얻을 때까지 되풀이한다 (읽는 동안 끝난 쓰기는 자기
  /// 결과로 표시를 `.loaded` 로 고쳐(`keepingShown` 이고 읽어 둔 값(`.loaded`)이 있으면 처음부터 `.loaded`) 읽는 동안에도 토글을 쓸 수 있어 여러 번 겹칠 수 있다.
  /// 쓰기는 기기당 하나라 조작을 멈추면 끝난다). `keepingShown` 이고 읽어 둔 권한 값(`.loaded`)이 있으면 그 값을 읽는 동안 그대로 보인다 (같은 패키지를 다시
  /// 읽을 때만. `permissionsStarted(keepingShown:)`).
  private func loadPermissions(
    of package: AndroidPackageName,
    on id: AndroidVirtualDevice.ID,
    session: Int,
    keepingShown: Bool = false
  ) async {
    guard self.draft?.session == session else { return }
    self.draft?.updateApp { $0.permissionsStarted(keepingShown: keepingShown) }
    guard let request = self.draft?.app.permissionsRequest else { return }
    while true {
      let epoch = self.permissionEpoch[id, default: 0]
      let result: Result<AndroidAppPermissions, AndroidEmulatorError>
      do throws(AndroidEmulatorError) {
        result = try await .success(self.emulator.runtimePermissions(of: package, on: id))
      } catch {
        result = .failure(error)
      }
      guard let draft = self.draft,
            draft.session == session,
            draft.app.permissionsRequest == request,
            draft.app.selectedPackage == package
      else { return }
      if self.permissionEpoch[id, default: 0] != epoch {
        continue
      }
      switch result {
      case let .success(.runtime(grants)):
        self.draft?.updateApp { $0.permissionsChanged(.loaded(grants)) }
      case .success(.appNotInstalled):
        self.draft?.updateApp { $0.permissionsChanged(.appNotInstalled) }
      case let .failure(error):
        self.draft?.updateApp { $0.permissionsChanged(.failed(error)) }
        await self.refreshIfDeviceChanged(error)
      }
      return
    }
  }
}
