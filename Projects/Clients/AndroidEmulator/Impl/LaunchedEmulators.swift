import CommandInterface
import Foundation
import Synchronization

/// 이 앱이 띄운 에뮬레이터 프로세스 (AVD 이름 → 프로세스). 끝난 것은 조회할 때 지운다.
/// Impl 은 값 타입이라 복사본끼리 같은 표를 쓰도록 참조 타입에 둔다 (App 은 Impl 을 하나만 만든다).
final class LaunchedEmulators: Sendable {
  private let processes = Mutex<[String: LaunchedProcess]>([:])

  /// 아직 도는 프로세스. 끝났으면 표에서 지우고 nil.
  func running(_ name: String, command: any CommandClient) -> LaunchedProcess? {
    self.processes.withLock { processes in
      guard let process = processes[name] else {
        return nil
      }
      guard command.exitStatus(process) == nil else {
        processes[name] = nil
        return nil
      }
      return process
    }
  }

  func insert(_ process: LaunchedProcess, for name: String) {
    self.processes.withLock { $0[name] = process }
  }

  /// 표의 값이 `process` 일 때만 지운다 (그사이 다시 띄운 프로세스는 남긴다).
  func remove(_ process: LaunchedProcess, for name: String) {
    self.processes.withLock { processes in
      if processes[name] == process {
        processes[name] = nil
      }
    }
  }
}
