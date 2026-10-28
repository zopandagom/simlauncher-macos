import AndroidSDKInterface
import Core
import Foundation
import Observation
import PreferencesInterface
import WorkspaceInterface

/// Android 도구 화면의 상태와 로직. SDK 위치의 platform-tools·emulator·시스템 이미지를 파일만 읽어 확인하고(네트워크·명령 없음),
/// 사용자가 "Android 도구 설치" 를 누를 때만 Google 저장소 XML 로 계획을 만들어 없는 구성 요소를 설치한다.
/// 동의 기록(Preferences 의 원문 지문)에 없는 라이선스 원문이 있으면 동의 시트를 띄우고, 동의하면 지문을 기록한 뒤 설치한다.
/// 계획 받기·동의 대기·설치 중에는 확인을 무시하고, 설치가 끝나면 결과와 관계없이 다시 확인한다.
/// App 의 종료 요청은 `appTerminationRequested()` 로 받는다: 단계와 관계없이 설치를 취소하고 끝나기를 기다린다
/// (AndroidSDK Client 는 마무리 단계 안에서만 취소를 미루고 다음 패키지를 시작하지 않는다). 설치 중이 아니어도 종료 표시를 세워
/// App 이 다른 대기(녹화 저장·런타임 설치)를 기다리는 동안 확인·설치 버튼을 끈다.
/// 설정 창에서 SDK 위치가 바뀌면 App 이 `sdkLocationChanged()` 를 부른다.
@MainActor
@Observable
public final class AndroidSetupModel {
  public private(set) var checkState: AndroidSetupCheckState = .checking
  /// 확인이 진행 중 (첫 확인 포함). 확인을 시작하면 확인 Task 를 만들기 전에 세운다.
  public private(set) var isChecking = false
  /// 관리자가 SDK 위치를 강제했다 (설정 창에서 바꿀 수 없다). 확인할 때마다 다시 읽는다.
  public private(set) var isLocationLocked = false
  /// 계획 받기·동의 대기·계획 실패. nil 이면 그 어느 것도 아니다.
  public private(set) var plan: AndroidSetupPlanState?
  /// 진행 중인 설치. nil 이면 설치 중이 아니다.
  public private(set) var install: AndroidSetupInstall?
  /// 마지막으로 끝난 설치의 결과. 새 설치를 시작하면 지운다.
  public private(set) var lastResult: AndroidSetupInstallResult?
  /// 설치가 끝나고 그 뒤 다시 확인이 끝나기 전이다. 화면은 결과 줄 대신 "설치 결과를 확인하는 중…" 을 보인다.
  public private(set) var isVerifyingInstall = false
  /// 띄울 알림. 한 번에 하나.
  public private(set) var notice: AndroidSetupNotice?

  /// 계획을 받는 중이거나 동의를 기다리는 중이다 (확인·설치 버튼을 막는다).
  public var isPlanning: Bool {
    switch self.plan {
    case .fetching, .awaitingConsent: true
    case .failed, .none: false
    }
  }

  /// 확인 중이 아니고 계획·설치·종료 대기가 아니다.
  public var canRecheck: Bool {
    !self.isChecking && !self.isPlanning && self.install == nil && !self.isTerminating
  }

  /// 확인됐고, 위치에 쓸 수 있고, 없는 구성 요소가 있으며, 확인·계획·설치·종료 대기가 아니다.
  public var canInstall: Bool {
    guard case let .checked(status) = self.checkState, status.canInstallMissing else {
      return false
    }
    return !self.isChecking && !self.isPlanning && self.install == nil && !self.isVerifyingInstall
      && !self.isTerminating
  }

  public var canCancelInstall: Bool {
    self.install?.canCancel ?? false
  }

  /// App 이 종료 요청을 받았을 때 할 일.
  public var terminationAction: AndroidSetupTerminationAction {
    guard let install = self.install else {
      return .terminateNow
    }
    return install.canCancel && !self.isTerminating ? .confirmThenCancel : .waitForInstall
  }

  @ObservationIgnored private let androidSDK: any AndroidSDKClient
  @ObservationIgnored private let preferences: any PreferencesClient
  @ObservationIgnored private let workspace: any WorkspaceClient
  /// 진행 중인 확인. Model 이 소유해 View 의 `.task` 가 취소돼도 끝까지 돈다.
  @ObservationIgnored private var checkTask: Task<Void, Never>?
  /// 확인하는 동안 들어온 요청. 진행 중인 확인이 끝나면 한 번 더 확인한다.
  @ObservationIgnored private var recheckRequested = false
  /// 진행 중인 계획 받기. 취소는 이 Task 를 취소해 Client 에 전한다.
  @ObservationIgnored private var planTask: Task<Result<AndroidSDKInstallPlan, AndroidSDKPlanError>, Never>?
  /// 지금 계획 받기의 번호. 취소·위치 바뀜이 지우면 늦게 온 결과를 무시한다.
  @ObservationIgnored private var planID: UUID?
  /// 진행 중인 설치. Model 이 소유해 View 가 사라져도 끝까지 돈다.
  @ObservationIgnored private var installTask: Task<Void, Never>?
  /// 지금 설치의 번호. 끝난 설치에서 늦게 온 진행 알림을 무시한다.
  @ObservationIgnored private var installID: UUID?
  /// App 이 종료를 확정했다. 이후 확인·계획·설치를 시작하지 않고, 설치가 끝나도 다시 확인하지 않는다.
  /// 관찰되는 값이라 바뀌면 `canInstall`·`canRecheck` 를 쓰는 화면이 다시 그려진다 (바깥에는 그 둘로만 보인다).
  private var isTerminating = false

  /// `preferences` 는 라이선스 동의 기록과 위치 잠금 여부만 읽고 쓴다 (위치는 AndroidSDK Client 의 provider 가 정한다).
  public init(
    androidSDK: any AndroidSDKClient,
    preferences: any PreferencesClient,
    workspace: any WorkspaceClient
  ) {
    self.androidSDK = androidSDK
    self.preferences = preferences
    self.workspace = workspace
  }

  // MARK: - 확인

  /// 계획·설치 중이 아니면 남은 스테이징·받기 폴더를 지운 뒤 확인한다.
  public func onAppear() async {
    guard self.canStartCheck else { return }
    await self.androidSDK.removeLeftovers()
    await self.check()
  }

  public func recheckButtonTapped() async {
    await self.check()
  }

  /// Finder 에서 폴더를 치우고 돌아왔을 수 있어 다시 확인한다. 계획·설치 중에는 무시한다.
  public func appBecameActive() async {
    await self.check()
  }

  /// App 이 설정 창의 SDK 위치 변경을 넘긴다. 계획 받기·동의 대기·계획 실패는 버리고(받던 계획은 취소) 다시 확인한다.
  /// 설치 중이면 아무것도 하지 않는다 (원래 위치에 끝까지 설치하고, 끝나면 새 위치로 다시 확인한다).
  public func sdkLocationChanged() async {
    guard self.install == nil else { return }
    self.discardPlan()
    await self.check()
  }

  // MARK: - 계획·동의

  /// "Android 도구 설치". 계획을 받아, 빈 계획이면 다시 확인하고, 동의할 원문이 없으면 바로 설치하고, 있으면 동의 시트를 띄운다.
  /// 설치할 수 없으면(`canInstall`) 무시한다. 바로 설치하면 설치와 그 뒤 다시 확인까지 마치고 돌아온다.
  public func installButtonTapped() async {
    guard self.canInstall else { return }
    self.lastResult = nil
    self.plan = .fetching
    let id = UUID()
    self.planID = id
    let task = Task { () -> Result<AndroidSDKInstallPlan, AndroidSDKPlanError> in
      do throws(AndroidSDKPlanError) {
        let plan = try await self.androidSDK.fetchInstallPlan()
        return .success(plan)
      } catch {
        return .failure(error)
      }
    }
    self.planTask = task
    let result = await task.value
    // 취소·위치 바뀜·종료가 번호를 지웠으면 늦게 온 결과를 무시한다 (취소한 뒤 동의 시트가 뜨지 않는다).
    guard self.planID == id else { return }
    self.planID = nil
    self.planTask = nil
    switch result {
    case let .success(plan):
      await self.planReceived(plan)
    case .failure(.cancelled):
      self.plan = nil
    case let .failure(error):
      self.plan = .failed(error)
    }
  }

  /// 계획 받기를 취소하거나 동의 시트를 닫는다 (동의하지 않음). 계획 실패 줄은 그대로 둔다.
  public func planCancelButtonTapped() {
    guard self.isPlanning else { return }
    self.discardPlan()
  }

  /// 동의 시트의 "동의하고 설치". 원문 지문을 기록하고(관리자가 잠갔으면 알림 없이 건너뛴다) 설치한다.
  /// 설치에는 기록된 지문과 이 계획의 지문을 함께 넘긴다 (방금 동의했으므로 잠긴 Mac 에서도 막히지 않는다).
  public func licenseAccepted() async {
    guard case let .awaitingConsent(plan, toConfirm) = self.plan, !self.isTerminating else { return }
    self.plan = nil
    try? self.preferences.addAcceptedAndroidLicenses(Set(toConfirm.map(\.fingerprint)))
    let accepted = self.preferences.acceptedAndroidLicenses().union(plan.licenses.map(\.fingerprint))
    await self.startInstall(plan, acceptedLicenses: accepted)
  }

  // MARK: - 설치

  /// 받기·확인·풀기 중인 설치를 멈춘다. 마무리 단계이거나 이미 멈추는 중이면 무시한다.
  public func cancelInstallButtonTapped() {
    guard self.canCancelInstall else { return }
    self.install?.cancelling()
    self.installTask?.cancel()
  }

  /// App 이 종료를 확정했다. 계획 받기는 버리고, 설치 중이면 단계와 관계없이 설치 Task 를 취소하고 끝나기를 기다린다
  /// (마무리 단계 중이면 그 패키지의 마무리만 끝나고 다음 패키지는 시작하지 않는다). 끝난 뒤 다시 확인하지 않는다.
  /// 설치 중이 아니면 종료 표시만 세우고 바로 돌아온다. **첫 await 전에** 종료 표시·계획 버리기·설치 취소를 마친다
  /// (AppDelegate 가 다른 대기와 함께 시작해 겹치게 기다린다).
  public func appTerminationRequested() async {
    self.isTerminating = true
    self.discardPlan()
    guard let task = self.installTask, let install = self.install else { return }
    if install.canCancel {
      self.install?.cancelling()
    }
    self.install?.terminating()
    task.cancel()
    await task.value
  }

  // MARK: - Finder·알림

  /// 쓸 수 없는 SDK 위치·구성 요소 폴더·설치를 막는 폴더를 Finder 에서 보인다. 실패하면 알림을 띄운다.
  public func revealButtonTapped(_ target: AndroidSetupRevealTarget) async {
    guard let url = self.revealURL(target) else { return }
    do throws(WorkspaceError) {
      try await self.workspace.revealInFinder(url)
    } catch {
      self.notice = .revealFailed(error)
    }
  }

  public func noticeDismissed() {
    self.notice = nil
  }

  // MARK: - 내부

  private var canStartCheck: Bool {
    !self.isPlanning && self.install == nil && !self.isTerminating
  }

  private func revealURL(_ target: AndroidSetupRevealTarget) -> URL? {
    guard case let .checked(status) = self.checkState else { return nil }
    switch target {
    case .location:
      return status.location.root?.url
    case let .component(component):
      return status.location.root?.folder(for: component)
    case .blockedFolder:
      guard case let .notWritable(url) = status.installBlocker else { return nil }
      return url
    }
  }

  /// 받던 계획은 취소하고, 동의 대기·계획 실패를 지운다.
  private func discardPlan() {
    self.planID = nil
    self.planTask?.cancel()
    self.planTask = nil
    self.plan = nil
  }

  private func planReceived(_ plan: AndroidSDKInstallPlan) async {
    guard !plan.isEmpty else {
      // 그사이 Android Studio 가 설치했을 수 있다. 다시 확인해 지금 상태를 보인다.
      self.plan = nil
      await self.check()
      return
    }
    let accepted = self.preferences.acceptedAndroidLicenses()
    let toConfirm = plan.licensesToConfirm(accepted: accepted)
    guard toConfirm.isEmpty else {
      self.plan = .awaitingConsent(plan, toConfirm: toConfirm)
      return
    }
    self.plan = nil
    await self.startInstall(plan, acceptedLicenses: accepted)
  }

  private func startInstall(_ plan: AndroidSDKInstallPlan, acceptedLicenses: Set<String>) async {
    guard self.install == nil, !self.isTerminating else { return }
    self.lastResult = nil
    let id = UUID()
    self.installID = id
    self.install = AndroidSetupInstall(plan: plan)
    let task = Task {
      let kind: AndroidSetupInstallResult.Kind
      // Task 클로저 안에서는 catch 의 에러 타입이 any Error 로 추론되므로 명시한다.
      do throws(AndroidSDKInstallError) {
        let outcome = try await self.androidSDK.install(plan, acceptedLicenses: acceptedLicenses) { update in
          await self.installProgressed(update, id: id)
        }
        kind = .finished(outcome)
      } catch {
        kind = .failed(error)
      }
      self.installID = nil
      self.lastResult = AndroidSetupInstallResult(kind: kind, root: plan.root)
      // 진행 패널을 내리기 전에 세워 두 화면 사이에 옛 상태가 보이지 않게 한다. 확인 루프가 내린다.
      if !self.isTerminating {
        self.isVerifyingInstall = true
      }
      self.install = nil
      self.installTask = nil
      if !self.isTerminating {
        await self.check()
      }
    }
    self.installTask = task
    await task.value
  }

  private func installProgressed(_ update: AndroidSDKInstallProgress, id: UUID) {
    guard self.installID == id, self.install != nil else { return }
    self.install?.progressed(update)
  }

  /// 상태를 확인한다. 계획·설치 중·종료 대기 중이면 아무것도 하지 않는다 (설치가 끝나면 다시 확인한다).
  /// 확인 중이면 새로 시작하지 않고 그 확인을 기다리며, 끝난 뒤 한 번 더 확인하게 한다.
  private func check() async {
    guard self.canStartCheck else { return }
    if let checkTask = self.checkTask {
      self.recheckRequested = true
      await checkTask.value
      return
    }
    // Task 몸체가 돌기 전에 설치를 시작할 수 없게 먼저 세운다.
    self.isChecking = true
    let task = Task {
      repeat {
        self.recheckRequested = false
        let status = await self.androidSDK.checkSDK()
        self.isLocationLocked = self.preferences.androidSDKPath().isLocked
        self.checkState = .checked(status)
        self.lastResult?.locationChecked(status.location.root)
        self.isVerifyingInstall = false
      } while self.recheckRequested
      self.isChecking = false
      self.checkTask = nil
    }
    self.checkTask = task
    await task.value
  }
}
