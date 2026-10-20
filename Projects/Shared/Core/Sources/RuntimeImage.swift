/// `simctl runtime list -j` 의 런타임 디스크 이미지 하나 (설치됐거나 설치·삭제 중인 런타임).
public struct RuntimeImage: Identifiable, Hashable, Sendable {
  /// 디스크 이미지 UUID (`identifier`). 같은 런타임 식별자의 이미지가 여럿일 수 있다.
  public struct ID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  /// `state` 문자열을 묶은 값. "Ready" 만 실제 출력에서 확인했고, 나머지는 CoreSimulator 바이너리의 문자열 후보다.
  public enum State: Hashable, Sendable {
    /// "Ready"
    case ready
    /// "Copying"·"Verifying"·"Reading"·"Expanding"·"Mounting" (받은 뒤 확인·마운트 중)
    case preparing
    /// "Unusable"
    case unusable
    /// "Deleting"·"Unmounting"
    case removing
    /// 그 밖의 값
    case unknown
  }

  public let id: ID
  /// `runtimeIdentifier` (예: "com.apple.CoreSimulator.SimRuntime.iOS-27-0").
  public let runtimeID: DeviceRuntime.ID
  /// `platformIdentifier` 에서 만든 플랫폼.
  public let platform: DevicePlatform
  public let version: OSVersion
  /// OS build (예: "24A434").
  public let build: String
  public let state: State
  /// 디스크 이미지 크기. 출력에 없으면 nil.
  public let sizeBytes: Int64?

  /// 기본값을 두지 않는다: 값을 다시 만드는 경로가 필드를 빠뜨리지 않게 컴파일러가 잡는다.
  public init(
    id: ID,
    runtimeID: DeviceRuntime.ID,
    platform: DevicePlatform,
    version: OSVersion,
    build: String,
    state: State,
    sizeBytes: Int64?
  ) {
    self.id = id
    self.runtimeID = runtimeID
    self.platform = platform
    self.version = version
    self.build = build
    self.state = state
    self.sizeBytes = sizeBytes
  }
}
