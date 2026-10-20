import Core
import DevEnvironmentInterface
import Foundation
import Observation

/// 개발 환경 준비 화면의 상태와 로직. 쓸 Xcode 의 준비 상태를 확인해 단계(Xcode 설치 → 라이선스 동의 →
/// 첫 실행 준비)를 안내하고, Xcode·App Store 를 연다. 시스템을 바꾸는 명령은 실행하지 않는다 (사용자가 Xcode 에서 마친다).
/// 앱 시작 뒤 첫 판정이 준비됨이면 `isFinished` 가 true 가 되어 App 이 기기 목록 화면을 보인다.
@MainActor
@Observable
public final class SetupModel {
  public private(set) var checkState: SetupCheckState = .checking
  /// 확인 명령이 진행 중 (첫 확인 포함).
  public private(set) var isChecking = false
  /// Xcode·App Store 를 여는 중. 여는 버튼을 비활성으로 보인다.
  public private(set) var isOpening = false
  /// 띄울 열기 실패 알림. 한 번에 하나 (알림이 창을 막아 다른 열기를 누를 수 없다).
  public private(set) var notice: SetupNotice?
  /// true 면 App 이 기기 목록 화면을 보인다.
  public private(set) var isFinished = false

  public var canRecheck: Bool {
    !self.isChecking
  }

  /// 준비됨으로 확인됐고 다시 확인 중이 아니다.
  public var canFinish: Bool {
    guard case .checked(.ready) = self.checkState else { return false }
    return !self.isChecking
  }

  /// 확인 결과가 있으면 세 단계, 아니면(첫 확인 중·확인 실패) 빈 배열.
  public var steps: [SetupStep] {
    guard case let .checked(status) = self.checkState else { return [] }
    return SetupStep.steps(for: status)
  }

  @ObservationIgnored private let devEnvironment: any DevEnvironmentClient
  /// 진행 중인 확인. Model 이 소유해 View 의 `.task` 가 취소돼도 끝까지 돈다.
  @ObservationIgnored private var checkTask: Task<Void, Never>?
  /// 확인하는 동안 들어온 요청. 진행 중인 확인이 끝나면 한 번 더 확인한다.
  @ObservationIgnored private var recheckRequested = false
  /// 앱 시작 뒤 첫 판정 전이다. 첫 판정이 준비됨일 때만 기기 목록으로 자동으로 넘어간다.
  @ObservationIgnored private var autoFinishPending = true

  public init(devEnvironment: any DevEnvironmentClient) {
    self.devEnvironment = devEnvironment
  }

  public func onAppear() async {
    await self.check()
  }

  public func recheckButtonTapped() async {
    await self.check()
  }

  /// 다른 앱(Xcode·App Store)에서 단계를 마치고 돌아왔을 수 있어 다시 확인한다.
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

  /// 준비됨 화면의 "기기 목록 열기".
  public func doneButtonTapped() {
    guard self.canFinish else { return }
    self.isFinished = true
  }

  public func noticeDismissed() {
    self.notice = nil
  }

  /// App 이 기기 목록 화면의 진입 요청을 받아 부른다. 확인은 다시 나타난 View 의 `onAppear()` 가 한다.
  public func reopened() {
    self.isFinished = false
  }

  /// 준비 상태를 확인한다. 확인 중이면 새로 시작하지 않고 그 확인을 기다리며, 끝난 뒤 한 번 더 확인하게 한다.
  private func check() async {
    if let checkTask = self.checkTask {
      self.recheckRequested = true
      await checkTask.value
      return
    }
    let task = Task {
      self.isChecking = true
      repeat {
        self.recheckRequested = false
        // Task 클로저 안에서는 catch 의 에러 타입이 any Error 로 추론되므로 명시한다.
        do throws(DevEnvironmentError) {
          self.checkState = try await .checked(self.devEnvironment.checkEnvironment())
        } catch {
          self.checkState = .failed(error)
        }
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
}
