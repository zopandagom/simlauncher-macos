import Core
import Synchronization

/// 설치 진행 알림의 바이트 계산과 같은 값 거르기. 부르는 쪽이 앞 알림이 끝난 뒤 다음을 부른다 (받기 진행 콜백도 차례로 온다).
final class InstallProgressReporter: Sendable {
  private struct State {
    var total: Int64
    /// 받기를 마친 패키지의 크기 합.
    var done: Int64 = 0
    var last: AndroidSDKInstallProgress?
  }

  private let packageCount: Int
  private let progress: @Sendable (AndroidSDKInstallProgress) async -> Void
  private let state: Mutex<State>

  /// - Parameter total: 이번 설치가 받을 패키지(시작 때 최종 경로가 없는 것)의 archive 크기 합.
  init(packageCount: Int, total: Int64, progress: @escaping @Sendable (AndroidSDKInstallProgress) async -> Void) {
    self.packageCount = packageCount
    self.progress = progress
    self.state = Mutex(State(total: total))
  }

  /// 받는 중: completed = 마친 크기 + `received`(그 패키지 크기까지). 앞 알림과 같으면 보내지 않는다.
  func downloading(_ package: AndroidSelectedPackage, index: Int, received: Int64) async {
    let size = package.archive.size
    let clamped = min(max(received, 0), size)
    await self.send(
      index: index,
      component: package.component,
      current: clamped,
      phase: .downloading(received: clamped, expected: size)
    )
  }

  /// 그 패키지의 받기를 마쳤다. 이후 단계의 completed 에 그 크기가 든다.
  func downloaded(_ package: AndroidSelectedPackage) {
    self.state.withLock { $0.done = $0.done.addingReportingOverflow(package.archive.size).partialValue }
  }

  /// 확인·풀기·마무리 단계.
  func phase(_ phase: AndroidSDKInstallProgress.Phase, _ package: AndroidSelectedPackage, index: Int) async {
    await self.send(index: index, component: package.component, current: 0, phase: phase)
  }

  /// 시작 때는 받을 예정이던 패키지가 그사이 생겨 건너뛰었다: 전체에서 빼고, 이미 알린 것이 있으면 새 전체로 다시 알린다.
  func skipped(_ package: AndroidSelectedPackage) async {
    let resend: AndroidSDKInstallProgress? = self.state.withLock { state in
      state.total = max(state.total - package.archive.size, 0)
      guard let last = state.last else {
        return nil
      }
      let updated = AndroidSDKInstallProgress(
        packageIndex: last.packageIndex,
        packageCount: last.packageCount,
        component: last.component,
        phase: last.phase,
        completedBytes: min(last.completedBytes, state.total),
        totalBytes: state.total
      )
      guard updated != last else {
        return nil
      }
      state.last = updated
      return updated
    }
    if let resend {
      await self.progress(resend)
    }
  }

  private func send(
    index: Int,
    component: AndroidSDKComponent,
    current: Int64,
    phase: AndroidSDKInstallProgress.Phase
  ) async {
    let value: AndroidSDKInstallProgress? = self.state.withLock { state in
      let completed = min(state.done.addingReportingOverflow(current).partialValue, state.total)
      let value = AndroidSDKInstallProgress(
        packageIndex: index,
        packageCount: self.packageCount,
        component: component,
        phase: phase,
        completedBytes: completed,
        totalBytes: state.total
      )
      guard value != state.last else {
        return nil
      }
      state.last = value
      return value
    }
    if let value {
      await self.progress(value)
    }
  }
}
