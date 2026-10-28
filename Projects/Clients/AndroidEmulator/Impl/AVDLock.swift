import Foundation

/// 실행 중 판정: 에뮬레이터(qemu)는 켜져 있는 동안 기기 폴더의 `multiinstance.lock` 에 잠금을 잡는다 (실측).
/// 잠그지 않는 `fcntl(F_GETLK)` 로 조회만 한다 → 그 순간 켜지는 emulator 를 막지 않는다.
/// 신호가 아니라 파일 잠금 조회라 프로세스 규칙(Command Impl)과 무관하다.
enum AVDLock {
  static let fileName = "multiinstance.lock"

  /// true = 누군가 잠금을 잡음(실행 중), false = 잠금 없음, nil = 파일 없음·열거나 조회하지 못함.
  static func isHeld(folder: URL) -> Bool? {
    let path = folder.appending(path: self.fileName, directoryHint: .notDirectory).path(percentEncoded: false)
    let descriptor = open(path, O_RDONLY | O_CLOEXEC)
    guard descriptor >= 0 else {
      return nil
    }
    defer { close(descriptor) }
    var query = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
    guard fcntl(descriptor, F_GETLK, &query) == 0 else {
      return nil
    }
    return query.l_type != Int16(F_UNLCK)
  }
}
