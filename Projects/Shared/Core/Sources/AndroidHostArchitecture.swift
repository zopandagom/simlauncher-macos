/// Android 패키지를 고를 때 쓰는 이 Mac 의 아키텍처. App 이 `AppBundleClientImpl.hostArchitecture` 를 넘긴다
/// (Rosetta 로 돌아도 Apple 실리콘이면 arm64).
public enum AndroidHostArchitecture: Hashable, Sendable {
  case aarch64, x64

  /// arm64 → aarch64, x86_64 → x64.
  public init(_ cpu: CPUArchitecture) {
    switch cpu {
    case .arm64: self = .aarch64
    case .x86_64: self = .x64
    }
  }

  /// 저장소 XML archive 의 `<host-arch>` 값.
  public var archiveHostArch: String {
    switch self {
    case .aarch64: "aarch64"
    case .x64: "x64"
    }
  }

  /// 시스템 이미지의 `<abi>` 값이자 SDK 안 폴더 이름.
  public var systemImageABI: String {
    switch self {
    case .aarch64: "arm64-v8a"
    case .x64: "x86_64"
    }
  }
}
