import CommandInterface
import Foundation
import Synchronization

/// `launch` 가 띄운 프로세스 표. `CommandClientImpl` 은 복사되는 struct 라 표는 참조 타입에 두고 복사본끼리 같은 표를 쓴다.
/// 항목은 종료 뒤에도 종료 상태를 남긴다 (앱 수명 동안 작은 값). `Process` 는 끝날 때까지만 붙잡는다.
/// SIGINT 는 lock 안에서 종료 처리(`terminationHandler`)가 오기 전에만 보낸다. 종료 처리가 온 뒤에는 보내지 않지만,
/// Foundation 이 프로세스를 거둔 뒤 종료 처리가 오기 전의 짧은 틈(그 사이 pid 가 재사용될 수 있다)은 막지 못한다 (`ProcessControl` 과 같다).
final class LaunchedProcessTable: Sendable {
  private enum Phase {
    /// `run()` 전후, 프로세스를 아직 표에 넣지 않았다.
    case starting
    case running(Process)
    case exited(Int32)
  }

  private struct Entry {
    var phase: Phase = .starting
    /// `waitForExit` 로 기다리는 쪽. 키는 부를 때마다 새로 만든 값이라 취소된 쪽만 뺄 수 있다.
    var waiters: [UUID: CheckedContinuation<Int32?, Never>] = [:]
  }

  /// 모르는 값의 종료 상태 (끝난 것으로 본다).
  static let unknownStatus: Int32 = -1

  private let entries = Mutex<[UUID: Entry]>([:])

  /// 띄우기 전에 항목을 만든다. 종료 처리가 `launched` 보다 먼저 와도 받을 곳이 있다.
  func register(_ id: UUID) {
    self.entries.withLock { $0[id] = Entry() }
  }

  /// 시작하지 못했다. 항목을 지운다.
  func discard(_ id: UUID) {
    self.entries.withLock { _ = $0.removeValue(forKey: id) }
  }

  /// 시작했다. 이미 끝났으면(종료 처리가 먼저 옴) 프로세스를 붙잡지 않는다.
  func launched(_ id: UUID, process: sending Process) {
    self.entries.withLock { entries in
      guard var entry = entries[id], case .starting = entry.phase else {
        return
      }
      entry.phase = .running(process)
      entries[id] = entry
    }
  }

  /// 끝났다 (`terminationHandler`). 종료 상태를 남기고 기다리는 쪽을 깨운다.
  func exited(_ id: UUID, status: Int32) {
    let waiters = self.entries.withLock { entries -> [CheckedContinuation<Int32?, Never>] in
      guard var entry = entries[id] else {
        return []
      }
      entry.phase = .exited(status)
      let waiters = Array(entry.waiters.values)
      entry.waiters = [:]
      entries[id] = entry
      return waiters
    }
    for waiter in waiters {
      waiter.resume(returning: status)
    }
  }

  func status(_ id: UUID) -> Int32? {
    self.entries.withLock { entries in
      guard let entry = entries[id] else {
        return Self.unknownStatus
      }
      if case let .exited(status) = entry.phase {
        return status
      }
      return nil
    }
  }

  /// 끝날 때까지 기다린다. 부른 Task 가 취소되면 nil 로 돌아온다 (프로세스는 건드리지 않는다).
  func wait(_ id: UUID) async -> Int32? {
    let token = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Int32?, Never>) in
        let immediate: Int32?? = self.entries.withLock { entries in
          guard var entry = entries[id] else {
            return .some(Self.unknownStatus)
          }
          if case let .exited(status) = entry.phase {
            return .some(status)
          }
          // 취소 처리기가 등록보다 먼저 돌았으면 여기서 끝낸다 (취소 표시는 처리기보다 먼저 선다).
          if Task.isCancelled {
            return .some(nil)
          }
          entry.waiters[token] = continuation
          entries[id] = entry
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
        }
      }
    } onCancel: {
      let waiter = self.entries.withLock { entries -> CheckedContinuation<Int32?, Never>? in
        entries[id]?.waiters.removeValue(forKey: token)
      }
      waiter?.resume(returning: nil)
    }
  }

  /// 돌고 있으면 SIGINT 를 보낸다. 끝났거나 아직 표에 넣지 않았거나 모르는 값이면 아무것도 하지 않는다.
  func interrupt(_ id: UUID) {
    self.entries.withLock { entries in
      guard let entry = entries[id], case let .running(process) = entry.phase else {
        return
      }
      process.interrupt()
    }
  }
}
