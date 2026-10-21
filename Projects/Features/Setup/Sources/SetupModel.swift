import Core
import DevEnvironmentInterface
import Foundation
import Observation
import SimulatorInterface

/// 개발 환경 준비 화면의 상태와 로직. 쓸 Xcode 의 준비 상태와, 준비됨이면 그 Xcode 의 기본 iOS 런타임 설치 여부를 확인해
/// 네 단계(Xcode 설치 → 라이선스 동의 → 첫 실행 준비 → iOS 시뮬레이터 설치)를 안내하고, Xcode·App Store 를 연다.
/// 앞 세 단계는 사용자가 Xcode 에서 마치고(시스템을 바꾸는 명령은 실행하지 않는다), 기본 iOS 런타임 설치는 사용자가 설치를
/// 누를 때만 Client 로 실행한다(Apple 서버에서 내려받음). 설치 중에는 확인과 기기 목록 이동을 막고, 끝나면 결과와 관계없이
/// 다시 확인한다. App 의 종료 요청은 `appTerminationRequested()` 로 받는다: 준비·내려받기 중인 설치는 멈추고,
/// 설치 단계이거나 이미 멈추는 중이면 멈추지 않으며, 어느 쪽이든 설치가 끝날 때까지 기다린 뒤 돌려준다.
/// 앱 시작 뒤 첫 판정이 준비됨이면(기본 iOS 설치 여부와 관계없이) `isFinished` 가 true 가 되어 App 이 기기 목록 화면을 보인다.
@MainActor
@Observable
public final class SetupModel {
  /// 진행 알림 없이 이만큼 지나면 연결 확인 안내를 보인다.
  static let installStallTimeout: Duration = .seconds(60)

  public private(set) var checkState: SetupCheckState = .checking
  /// 기본 iOS 런타임 확인 결과. 확인 루프가 `checkState` 와 함께 대입한다.
  public private(set) var runtimeState: SetupRuntimeState = .notChecked
  /// 확인이 진행 중 (첫 확인 포함). 확인을 시작하면 확인 Task 를 만들기 전에 세운다.
  public private(set) var isChecking = false
  /// 진행 중인 기본 iOS 런타임 설치. nil 이면 설치 중이 아니다.
  public private(set) var runtimeInstall: SetupRuntimeInstall?
  /// 마지막으로 끝난 설치의 결과. 새 설치를 시작하거나 Setup 을 다시 열면 지운다.
  public private(set) var lastInstallResult: SetupInstallResult?
  /// 설치가 끝나고 그 뒤 다시 확인이 끝나기 전이다. 화면은 런타임 상태·결과 줄 대신 "설치 결과를 확인하는 중…"을 보인다.
  public private(set) var isVerifyingInstall = false
  /// Xcode·App Store 를 여는 중. 여는 버튼을 비활성으로 보인다.
  public private(set) var isOpening = false
  /// 띄울 열기 실패 알림. 한 번에 하나 (알림이 창을 막아 다른 열기를 누를 수 없다).
  public private(set) var notice: SetupNotice?
  /// true 면 App 이 기기 목록 화면을 보인다.
  public private(set) var isFinished = false

  public var isInstallingRuntime: Bool {
    self.runtimeInstall != nil
  }

  /// 확인 중이 아니고 설치 중이 아니다.
  public var canRecheck: Bool {
    !self.isChecking && self.runtimeInstall == nil
  }

  /// Xcode 가 준비됨으로 확인됐고, 다시 확인 중·설치 중이 아니다 (기본 iOS 설치 여부는 보지 않는다:
  /// 다른 iOS 버전의 기기만 쓸 수도 있다).
  public var canFinish: Bool {
    guard case .checked(.ready) = self.checkState else { return false }
    return !self.isChecking && self.runtimeInstall == nil
  }

  /// Xcode 가 준비됨이고 기본 iOS 가 설치되지 않았으며, 확인 중·설치 중·종료 대기가 아니다.
  public var canInstallRuntime: Bool {
    guard case .checked(.ready) = self.checkState, case .checked(_, .notInstalled) = self.runtimeState else {
      return false
    }
    return !self.isChecking && self.runtimeInstall == nil && !self.isTerminating
  }

  public var canCancelRuntimeInstall: Bool {
    self.runtimeInstall?.canCancel ?? false
  }

  /// App 이 종료 요청을 받았을 때 할 일.
  public var terminationAction: SetupTerminationAction {
    guard let install = self.runtimeInstall else { return .terminateNow }
    return install.canCancel && !self.isTerminating ? .confirmThenCancel : .waitForInstall
  }

  /// 확인 결과가 있으면 네 단계, 아니면(첫 확인 중·확인 실패) 빈 배열.
  public var steps: [SetupStep] {
    guard case let .checked(status) = self.checkState else { return [] }
    return SetupStep.steps(for: status, runtime: self.runtimeState)
  }

  @ObservationIgnored private let devEnvironment: any DevEnvironmentClient
  @ObservationIgnored private let simulator: any SimulatorClient
  /// 무진행 시계가 기다리는 방법. 테스트가 시계를 대신한다.
  @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
  /// 진행 중인 확인. Model 이 소유해 View 의 `.task` 가 취소돼도 끝까지 돈다.
  @ObservationIgnored private var checkTask: Task<Void, Never>?
  /// 확인하는 동안 들어온 요청. 진행 중인 확인이 끝나면 한 번 더 확인한다.
  @ObservationIgnored private var recheckRequested = false
  /// 앱 시작 뒤 첫 판정 전이다. 첫 판정이 준비됨일 때만 기기 목록으로 자동으로 넘어간다.
  @ObservationIgnored private var autoFinishPending = true
  /// 진행 중인 설치. Model 이 소유해 View 의 Task 가 없어져도 끝까지 돌고, 취소는 이 Task 를 취소해 Client 에 전한다.
  @ObservationIgnored private var installTask: Task<Void, Never>?
  /// 무진행 시계. 진행 알림·취소·설치 끝마다 취소하고 새로 건다.
  @ObservationIgnored private var stallTask: Task<Void, Never>?
  /// 지금 설치의 식별자. 끝난 설치에서 늦게 온 진행 알림을 무시한다.
  @ObservationIgnored private var installID: UUID?
  /// App 이 종료를 확정했다. 이후 확인·설치를 시작하지 않고, 설치가 끝나도 다시 확인하지 않는다.
  @ObservationIgnored private var isTerminating = false
  /// 테스트용: 끝난 무진행 시계 Task 수. 화면·동작에 쓰지 않는다.
  @ObservationIgnored private(set) var stallTimerEndCount = 0

  public init(
    devEnvironment: any DevEnvironmentClient,
    simulator: any SimulatorClient,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.devEnvironment = devEnvironment
    self.simulator = simulator
    self.sleep = sleep
  }

  /// 확인한다. 설치 중·종료 대기 중에는 확인하지 않는다 (`recheckButtonTapped`·`appBecameActive` 도 같다).
  public func onAppear() async {
    await self.check()
  }

  public func recheckButtonTapped() async {
    await self.check()
  }

  /// 다른 앱(Xcode·App Store)에서 단계를 마치고 돌아왔을 수 있어 다시 확인한다. 설치 중·종료 대기 중에는 확인하지 않는다.
  public func appBecameActive() async {
    await self.check()
  }

  /// App Store 의 Xcode 페이지를 연다. 실패하면 알림만 띄운다 (설치는 오래 걸려 돌아온 뒤 활성화 때 다시 확인한다).
  public func openAppStoreButtonTapped() async {
    guard !self.isOpening else { return }
    self.isOpening = true
    defer { self.isOpening = false }
    do throws(DevEnvironmentError) {
      try await self.devEnvironment.openXcodeInAppStore()
    } catch {
      self.notice = .openAppStoreFailed(error)
    }
  }

  /// 쓸 Xcode 를 연다. 실패하면 알림을 띄우고, Xcode 가 없어졌으면 단계를 갱신하려고 다시 확인한다.
  public func openXcodeButtonTapped() async {
    guard !self.isOpening else { return }
    self.isOpening = true
    let failure: DevEnvironmentError?
    do throws(DevEnvironmentError) {
      try await self.devEnvironment.openXcode()
      failure = nil
    } catch {
      failure = error
    }
    // 다시 확인하는 동안 여는 버튼이 비활성으로 남지 않게 여는 구간만 표시한다.
    self.isOpening = false
    guard let failure else { return }
    self.notice = .openXcodeFailed(failure)
    if failure == .xcodeNotFound {
      await self.check()
    }
  }

  /// Xcode 준비됨 화면(기본 iOS 가 없어도)의 "기기 목록 열기". 확인 중·설치 중이면 무시한다.
  public func doneButtonTapped() {
    guard self.canFinish else { return }
    self.isFinished = true
  }

  public func noticeDismissed() {
    self.notice = nil
  }

  /// App 이 기기 목록 화면의 진입 요청을 받아 부른다. 지난 설치 결과를 지운다.
  /// 확인은 다시 나타난 View 의 `onAppear()` 가 한다.
  public func reopened() {
    self.isFinished = false
    self.lastInstallResult = nil
  }

  /// "iOS 시뮬레이터 설치". 설치할 수 없으면(`canInstallRuntime`) 무시한다. 설치가 끝나고 다시 확인까지 마치면 돌아온다.
  public func installRuntimeButtonTapped() async {
    guard self.canInstallRuntime else { return }
    self.lastInstallResult = nil
    let id = UUID()
    self.installID = id
    self.runtimeInstall = SetupRuntimeInstall()
    self.restartStallTimer()
    let task = Task {
      let result: SetupInstallResult
      // Task 클로저 안에서는 catch 의 에러 타입이 any Error 로 추론되므로 명시한다.
      do throws(RuntimeInstallError) {
        let outcome = try await self.devEnvironment.installDefaultIOSRuntime { update in
          await self.installProgressed(update, id: id)
        }
        result = .finished(outcome)
      } catch {
        result = .failed(error)
      }
      self.stallTask?.cancel()
      self.stallTask = nil
      self.installID = nil
      self.lastInstallResult = result
      // 진행 패널을 내리기 전에 세워 두 화면 사이에 옛 런타임 상태가 보이지 않게 한다. 확인 루프가 내린다.
      if !self.isTerminating {
        self.isVerifyingInstall = true
      }
      self.runtimeInstall = nil
      self.installTask = nil
      // 결과와 관계없이 다시 확인한다 (설치됐어도 바로 Ready 가 아닐 수 있고, Xcode 가 없어졌으면 환경 단계가 바뀐다).
      if !self.isTerminating {
        await self.check()
      }
    }
    self.installTask = task
    await task.value
  }

  /// 준비·내려받기 중인 설치를 멈춘다. 설치 단계이거나 이미 멈추는 중이면 무시한다.
  public func cancelInstallButtonTapped() {
    guard self.runtimeInstall?.canCancel == true else { return }
    self.cancelInstall()
  }

  /// App 이 종료를 확정했다 (준비·내려받기 중이면 사용자가 대화상자에서 "종료"를 골랐다). 진행 중인 설치가
  /// 준비·내려받기 중이면 멈추고, 설치 단계이거나 이미 멈추는 중이면 멈추지 않고, 끝나기를 기다린다.
  /// 끝난 뒤 다시 확인하지 않는다. 설치 중이 아니면 바로 돌아온다.
  public func appTerminationRequested() async {
    self.isTerminating = true
    guard let task = self.installTask, self.runtimeInstall != nil else { return }
    if self.runtimeInstall?.canCancel == true {
      self.cancelInstall()
    }
    self.runtimeInstall?.terminating()
    await task.value
  }

  private func cancelInstall() {
    self.runtimeInstall?.cancelling()
    self.stallTask?.cancel()
    self.stallTask = nil
    self.installTask?.cancel()
  }

  private func installProgressed(_ update: RuntimeInstallProgress, id: UUID) {
    guard self.installID == id, self.runtimeInstall != nil else { return }
    self.runtimeInstall?.progressed(update)
    self.restartStallTimer()
  }

  /// 무진행 시계를 다시 건다. 설치 단계·멈추는 중이면 시계를 걸지 않는다 (진행 알림이 없는 것이 정상이다).
  private func restartStallTimer() {
    self.stallTask?.cancel()
    self.stallTask = nil
    guard let install = self.runtimeInstall, install.progress.phase != .installing, !install.isCancelling else {
      return
    }
    self.stallTask = Task { [sleep] in
      defer { self.stallTimerEndCount += 1 }
      do {
        try await sleep(Self.installStallTimeout)
      } catch {
        return
      }
      // 잠이 끝난 뒤 취소가 온 시계(새 진행·설치 끝·취소가 먼저 처리됨)는 안내를 붙이지 않는다.
      guard !Task.isCancelled else { return }
      self.runtimeInstall?.stalled()
    }
  }

  /// 준비 상태를 확인한다. 설치 중·종료 대기 중이면 아무것도 하지 않는다 (설치가 끝나면 다시 확인한다).
  /// 확인 중이면 새로 시작하지 않고 그 확인을 기다리며, 끝난 뒤 한 번 더 확인하게 한다.
  /// Xcode 가 준비됨이면 기본 iOS 와 런타임 목록도 읽어 `checkState`·`runtimeState` 를 함께 대입하고 `isVerifyingInstall` 을 내린다.
  private func check() async {
    guard self.runtimeInstall == nil else { return }
    guard !self.isTerminating else { return }
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
        let state: SetupCheckState
        let runtime: SetupRuntimeState
        // Task 클로저 안에서는 catch 의 에러 타입이 any Error 로 추론되므로 명시한다.
        do throws(DevEnvironmentError) {
          let status = try await self.devEnvironment.checkEnvironment()
          state = .checked(status)
          if case .ready = status {
            runtime = await self.checkRuntime()
          } else {
            runtime = .notChecked
          }
        } catch {
          state = .failed(error)
          runtime = .notChecked
        }
        // 환경만 바뀌고 런타임이 확인 전인 중간 화면이 보이지 않게 함께 대입한다.
        self.checkState = state
        self.runtimeState = runtime
        self.isVerifyingInstall = false
      } while self.recheckRequested
      if self.autoFinishPending, case .checked(.ready) = self.checkState {
        self.isFinished = true
      }
      self.autoFinishPending = false
      self.isChecking = false
      self.checkTask = nil
    }
    self.checkTask = task
    await task.value
  }

  /// 기본 iOS 버전을 읽지 못하면 이미지는 읽지 않는다.
  private func checkRuntime() async -> SetupRuntimeState {
    guard let defaultRuntime = await self.devEnvironment.defaultIOSRuntime() else {
      return .defaultRuntimeUnknown
    }
    do throws(SimulatorError) {
      let images = try await self.simulator.fetchRuntimeImages()
      return .checked(defaultRuntime, DefaultIOSRuntimeStatus(defaultRuntime: defaultRuntime, images: images))
    } catch {
      return .failed(error)
    }
  }
}
