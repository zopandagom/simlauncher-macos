import Core
import Foundation

/// 이 Mac 의 iOS 시뮬레이터가 실행하는 아키텍처.
enum HostArchitecture {
  /// `hw.optional.arm64` 가 있고 값이 1 이면 arm64 (Apple 실리콘. Rosetta 로 실행 중이어도 1 이다), 아니면 x86_64
  /// (Intel 에는 이 이름이 없어 실패한다. Rosetta·Intel 실기는 미확인).
  static func current() -> CPUArchitecture {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let status = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
    return status == 0 && value == 1 ? .arm64 : .x86_64
  }
}
